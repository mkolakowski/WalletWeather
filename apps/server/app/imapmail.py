"""Reads email alerts from a mailbox over IMAP with an app password
(bank-alert-emails phase 3, #208).

Gmail gives an app password to an account with 2-Step Verification on; any
other IMAP mailbox works the same way with its own password. What guards it
(decided 2026-11-27):

  - The server connects only to hosts on IMAP_HOSTS in .env (exact names,
    default imap.gmail.com), checked before any connection is made.
  - Port 993 with TLS from the first byte, the certificate and its name
    checked; no STARTTLS, no plain text, no other port.
  - The folder is opened read-only (EXAMINE) and every fetch is a PEEK, so
    nothing is marked read, moved or deleted.
  - The sender check trusts the topmost Authentication-Results header only
    when the host's own server wrote it: mx.google.com for imap.gmail.com,
    or the id an IMAP_HOSTS entry gives (`imap.fastmail.com=fastmail.com`).

Errors come back as mailbox.MailboxError with a plain message; the password
never appears in one. Mail text is data: see alerts.py for how it's read.
"""
import base64
import email
import email.policy
import email.utils
import imaplib
import os
import re
import ssl
from datetime import datetime, timedelta, timezone

from .alerts import trusted_results
from .mailbox import MailboxError

PORT = 993
TIMEOUT = 30.0
DEFAULT_HOSTS = "imap.gmail.com"
GMAIL_HOST = "imap.gmail.com"
# The server id each well-known host stamps on Authentication-Results.
KNOWN_AUTHSERV = {GMAIL_HOST: "mx.google.com"}
MAX_RAW = 2_000_000          # bytes of one mail read at most
_HOST = re.compile(r"^(?=.{1,253}$)[a-z0-9](?:[a-z0-9\-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9\-]{0,61}[a-z0-9])?)*$")
_FOLDER = re.compile(r"^[\x20-\x7e]{1,400}$")
_MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
_INTERNALDATE = re.compile(rb'INTERNALDATE "\s?(\d{1,2})-(\w{3})-(\d{4}) (\d\d):(\d\d):(\d\d) ([+-])(\d\d)(\d\d)"')

# Tests replace these: the stand-in server's factory (called as
# _factory(host, port, ssl_context, timeout)), the port, and a TLS context.
_factory = None
_port = PORT
_ssl_context: ssl.SSLContext | None = None


# ---------- Which hosts ----------

def host_list() -> dict[str, str | None]:
    """IMAP_HOSTS as {host: the server id it stamps, or None}."""
    raw = os.environ.get("IMAP_HOSTS", "").strip() or DEFAULT_HOSTS
    out: dict[str, str | None] = {}
    for entry in raw.split(","):
        host, _, authserv = entry.strip().partition("=")
        host, authserv = host.strip().lower().rstrip("."), authserv.strip().lower()
        if host and _HOST.fullmatch(host):
            out[host] = authserv or KNOWN_AUTHSERV.get(host)
    return out


def allowed_hosts() -> list[str]:
    return sorted(host_list())


def checked_host(host: str) -> str:
    """The host as it's connected to, if it's on the list. Raises before any
    connection is made when it isn't."""
    h = (host or "").strip().lower().rstrip(".")
    if not h or not _HOST.fullmatch(h):
        raise MailboxError("That isn't a mail server name.", status=400)
    if h not in host_list():
        raise MailboxError(f"This server isn't set up to connect to {h[:80]}. An admin can add it "
                           "to IMAP_HOSTS in the server's .env (see the email alerts guide). "
                           "Nothing was sent to it.", status=400)
    return h


def default_host(address: str) -> str | None:
    dom = (address or "").rsplit("@", 1)[-1].strip().lower()
    return GMAIL_HOST if dom in ("gmail.com", "googlemail.com") else None


def clean_password(host: str, password: str) -> str:
    """Google shows an app password in groups of four; the spaces aren't
    part of it."""
    return "".join(password.split()) if host == GMAIL_HOST else password.strip()


# ---------- Reading a mail ----------

def _clean(value, limit: int) -> str:
    return re.sub(r"[\x00-\x1f\x7f]", " ", str(value if value is not None else "")).strip()[:limit]


def _address(msg) -> str:
    try:
        raw = str(msg.get("From") or "")
    except Exception:
        return ""
    return _clean(email.utils.parseaddr(raw)[1], 320).lower()


def _header(msg, name: str, limit: int) -> str:
    try:
        return _clean(msg.get(name), limit)
    except Exception:
        return ""


def _body(msg) -> tuple[str, bool]:
    """The HTML part if there is one, else the plain text, as text."""
    part = None
    try:
        part = msg.get_body(preferencelist=("html", "plain"))
    except Exception:
        part = None
    if part is None:
        return "", False
    html = part.get_content_subtype() == "html"
    try:
        content = part.get_content()
    except Exception:
        payload = part.get_payload(decode=True) or b""
        content = payload.decode("utf-8", "replace") if isinstance(payload, bytes) else ""
    return (content if isinstance(content, str) else "")[:400_000], html


def parse_raw(raw: bytes) -> dict:
    """A whole mail (RFC 5322 bytes) as the parts the reader needs: who it's
    from, the subject, its Message-ID, the body (HTML or text) and its
    Authentication-Results headers, topmost first. Used for Gmail too."""
    msg = email.message_from_bytes(raw[:MAX_RAW], policy=email.policy.default)
    try:
        results = [_clean(h, 2000) for h in (msg.get_all("Authentication-Results") or [])]
    except Exception:
        results = []
    body, html = _body(msg)
    return {"sender": _address(msg), "subject": _header(msg, "Subject", 300),
            "message_id": _header(msg, "Message-ID", 400), "body": body, "html": html,
            "auth_results": results[:10]}


def _headers_only(raw: bytes) -> dict:
    msg = email.message_from_bytes(raw[:20_000], policy=email.policy.default)
    return {"sender": _address(msg), "subject": _header(msg, "Subject", 300),
            "message_id": _header(msg, "Message-ID", 400)}


def _internaldate(meta: bytes) -> datetime | None:
    m = _INTERNALDATE.search(meta)
    if not m or m.group(2).decode().title() not in _MONTHS:
        return None
    day, mon, year, hh, mm, ss = (int(m.group(1)), _MONTHS.index(m.group(2).decode().title()) + 1,
                                  int(m.group(3)), int(m.group(4)), int(m.group(5)), int(m.group(6)))
    offset = timedelta(hours=int(m.group(8)), minutes=int(m.group(9)))
    try:
        local = datetime(year, mon, day, hh, mm, ss)
    except ValueError:
        return None
    return local - offset if m.group(7) == b"+" else local + offset


def _records(data) -> list[tuple[bytes, bytes]]:
    """A FETCH answer as (everything but the literal, the literal) per mail.
    Servers put UID and INTERNALDATE before or after the literal."""
    out: list[list] = []
    for item in data or []:
        if isinstance(item, tuple) and len(item) >= 2:
            out.append([bytes(item[0] or b""), bytes(item[1] or b"")])
        elif isinstance(item, bytes) and out:
            out[-1][0] += b" " + item
    return [(a, b) for a, b in out]


def _uid(meta: bytes) -> int | None:
    m = re.search(rb"\bUID (\d+)", meta)
    return int(m.group(1)) if m else None


def _quote(name: str) -> str:
    return '"' + name.replace("\\", "\\\\").replace('"', '\\"') + '"'


def _unquote(raw: str) -> str:
    raw = raw.strip()
    if len(raw) >= 2 and raw[0] == raw[-1] == '"':
        return re.sub(r'\\(.)', r'\1', raw[1:-1])
    return raw


def _mutf7(name: str) -> str:
    """A folder name as people read it (IMAP's modified UTF-7)."""
    def part(m):
        s = m.group(1)
        if not s:
            return "&"
        b64 = s.replace(",", "/")
        b64 += "=" * (-len(b64) % 4)
        try:
            return base64.b64decode(b64).decode("utf-16-be")
        except Exception:
            return m.group(0)
    return re.sub(r"&([A-Za-z0-9+,]*)-", part, name)


_LIST = re.compile(r'^\((?P<flags>[^)]*)\)\s+(?P<delim>"(?:[^"\\]|\\.)*"|NIL)\s+(?P<name>.*)$', re.S)


class Reader:
    """One connection to an IMAP mailbox for the length of a `with` block.
    `cred` is {"host", "user", "password"}; `folder` is the folder's name as
    the server gives it (its id here)."""

    def __init__(self, cred: dict, folder: str | None = None):
        self.host = checked_host(str(cred.get("host") or ""))
        self.authserv = host_list().get(self.host)
        self.user = str(cred.get("user") or "")
        self.password = str(cred.get("password") or "")
        self.folder = folder
        self._c = None
        self._validity: str | None = None

    # -- the connection --

    def open(self) -> "Reader":
        context = _ssl_context or ssl.create_default_context()
        context.check_hostname = True
        context.verify_mode = ssl.CERT_REQUIRED
        try:
            if _factory is not None:
                self._c = _factory(self.host, _port, context, TIMEOUT)
            else:
                self._c = imaplib.IMAP4_SSL(self.host, _port, ssl_context=context, timeout=TIMEOUT)
        except ssl.SSLError:
            raise MailboxError(f"{self.host} didn't offer a secure connection that checks out, so "
                               "nothing was sent to it.")
        except (OSError, imaplib.IMAP4.error):
            raise MailboxError(f"Couldn't reach {self.host}. Try again in a while.")
        try:
            self._c.login(self.user, self.password)
        except imaplib.IMAP4.abort:
            self.close()
            raise MailboxError(f"{self.host} closed the connection. Try again in a while.")
        except imaplib.IMAP4.error as e:
            self.close()
            text = str(e).upper()
            if "UNAVAILABLE" in text or "INUSE" in text or "LIMIT" in text:
                raise MailboxError(f"{self.host} is busy. Try again in a few minutes.", status=503)
            raise MailboxError("The mail server didn't accept the address and app password. If it's "
                               "Gmail, the app password may have been removed, or revoked when the "
                               "Google password changed. Disconnect, then connect again with a new "
                               "one.", status=409, revoked=True)
        except (OSError, ssl.SSLError):
            self.close()
            raise MailboxError(f"Couldn't reach {self.host}. Try again in a while.")
        return self

    def close(self) -> None:
        c, self._c = self._c, None
        if c is None:
            return
        try:
            c.logout()
        except Exception:
            pass

    def __enter__(self):
        return self.open()

    def __exit__(self, *exc):
        self.close()
        return False

    def _run(self, fn, *args):
        """An IMAP command; a NO or BAD answer as a plain error."""
        if self._c is None:
            raise MailboxError("The mailbox isn't open.")
        try:
            typ, data = fn(*args)
        except imaplib.IMAP4.abort:
            raise MailboxError(f"{self.host} closed the connection. Try again in a while.")
        except imaplib.IMAP4.error:
            raise MailboxError(f"{self.host} answered with an error. Try again in a while.")
        except (OSError, ssl.SSLError):
            raise MailboxError(f"Lost the connection to {self.host}. Try again in a while.")
        if typ != "OK":
            raise MailboxError(f"{self.host} answered with an error. Try again in a while.")
        return data

    def _examine(self, folder: str) -> None:
        """Open the folder read-only (EXAMINE): nothing in it changes."""
        if not folder or not _FOLDER.fullmatch(folder):
            raise MailboxError("That folder isn't in the mailbox.", status=404)
        try:
            typ, _ = self._c.select(_quote(folder), readonly=True)
        except imaplib.IMAP4.abort:
            raise MailboxError(f"{self.host} closed the connection. Try again in a while.")
        except (imaplib.IMAP4.error, OSError):
            typ = "NO"
        if typ != "OK":
            raise MailboxError("That folder isn't in the mailbox any more.", status=404)
        _, v = self._c.response("UIDVALIDITY")
        self._validity = (v[0].decode() if v and isinstance(v[0], bytes) else str(v[0] if v else "0"))[:20]

    def _opened(self) -> None:
        if self._validity is None:
            self._examine(self.folder or "")

    # -- what main.py asks for --

    def address(self) -> str:
        return _clean(self.user, 320)

    def folders(self) -> list[dict]:
        out = []
        for line in self._run(self._c.list)[:2000]:
            if isinstance(line, tuple):   # a name sent as a literal
                head, name = line[0].decode("utf-8", "replace"), line[1].decode("utf-8", "replace")
                m = _LIST.match(head.rsplit("{", 1)[0] + '""')
            else:
                m = _LIST.match((line or b"").decode("utf-8", "replace"))
                name = _unquote(m.group("name")) if m else ""
            if not m or "\\noselect" in m.group("flags").lower() or "\\nonexistent" in m.group("flags").lower():
                continue
            if not name or not _FOLDER.fullmatch(name):
                continue
            delim = _unquote(m.group("delim")) if m.group("delim") != "NIL" else ""
            shown = _mutf7(name)
            parent = shown.rsplit(delim, 1)[0] if delim and delim in shown else None
            leaf = "Inbox" if name.upper() == "INBOX" else (shown.rsplit(delim, 1)[-1] if parent else shown)
            out.append({"id": name, "name": _clean(leaf, 200) or "Folder",
                        "parent": _clean(parent, 200) if parent else None})
            if len(out) >= 300:
                break
        out.sort(key=lambda f: (f["id"].upper() != "INBOX", f["id"].lower()))
        return out

    def _summaries(self, uids: list[int]) -> list[dict]:
        out = []
        for i in range(0, len(uids), 100):
            chunk = ",".join(str(u) for u in uids[i:i + 100])
            data = self._run(self._c.uid, "FETCH", chunk,
                             "(UID INTERNALDATE BODY.PEEK[HEADER.FIELDS (FROM SUBJECT MESSAGE-ID)])")
            for meta, lit in _records(data):
                uid, received = _uid(meta), _internaldate(meta)
                if uid is None or received is None:
                    continue
                h = _headers_only(lit)
                mid = f"{self._validity}:{uid}"
                out.append({"id": mid, "sender": h["sender"], "subject": h["subject"],
                            "message_id": h["message_id"] or f"imap:{self.host}:{self.user}:{self.folder}:{mid}",
                            "received": received})
        return out

    def _search(self, *criteria: str) -> list[int]:
        data = self._run(self._c.uid, "SEARCH", *criteria)
        raw = b" ".join(d for d in data if isinstance(d, bytes))
        return sorted({int(x) for x in raw.split() if x.isdigit()})

    def recent(self, count: int = 25) -> list[dict]:
        self._opened()
        uids = self._search("ALL")[-count:]
        rows = self._summaries(uids)
        rows.sort(key=lambda m: m["received"], reverse=True)
        return rows[:count]

    def since(self, after: datetime, limit: int, senders=None) -> list[dict]:
        """Mail that arrived at or after `after` (UTC), oldest first, at most
        `limit`, without bodies. SINCE only knows days, so a day earlier is
        asked for and the rest is left out here."""
        self._opened()
        day = after - timedelta(days=1)
        uids = self._search("SINCE", f"{day.day:02d}-{_MONTHS[day.month - 1]}-{day.year}")
        out: list[dict] = []
        for i in range(0, len(uids), 200):
            got = [m for m in self._summaries(uids[i:i + 200]) if m["received"] >= after]
            out.extend(got)
            if len(out) >= limit:
                break
        out.sort(key=lambda m: m["received"])
        return out[:limit]

    def message(self, message_id: str) -> dict:
        self._opened()
        validity, _, uid = (message_id or "").partition(":")
        if validity != self._validity or not uid.isdigit():
            raise MailboxError("That message isn't in the mailbox any more.", status=404)
        data = self._run(self._c.uid, "FETCH", uid, f"(UID INTERNALDATE BODY.PEEK[]<0.{MAX_RAW}>)")
        recs = [(m, lit) for m, lit in _records(data) if _uid(m) == int(uid)]
        if not recs:
            raise MailboxError("That message isn't in the mailbox any more.", status=404)
        meta, raw = recs[0]
        received = _internaldate(meta) or datetime.now(timezone.utc).replace(tzinfo=None)
        p = parse_raw(raw)
        return {"id": message_id, "message_id": p["message_id"] or
                f"imap:{self.host}:{self.user}:{self.folder}:{message_id}",
                "sender": p["sender"], "subject": p["subject"], "received": received,
                "html": p["html"], "body": p["body"],
                "auth_results": trusted_results(p["auth_results"], self.authserv)}


def try_connect(cred: dict) -> list[dict]:
    """Sign in and list the folders, to check an address and password before
    they're kept."""
    with Reader(cred) as r:
        return r.folders()

