"""Reads email alerts from Gmail with Google sign-in and read-only access
(bank-alert-emails phase 3, #208).

Offered only when GMAIL_API_ENABLED is set, a Google project is configured
and the instance is on https:// (Google wants an https:// return address and
has no code-on-another-device sign-in for Gmail; checked 2026-11-27, see
docs/dev/decisions/bank-alert-emails.md). The project is GMAIL_CLIENT_ID and
GMAIL_CLIENT_SECRET when set, so it can be in Personal mode, otherwise the
instance's Google sign-in project (GOOGLE_CLIENT_ID).

Signing in is OAuth 2.0 for web server apps with PKCE, asking for
gmail.readonly (a restricted scope) with offline access. Mail is read with
the Gmail API v1: labels as folders, messages.list with `after:` and the
taught senders, and each alert fetched whole (format=raw) and read as IMAP's
are. The server only talks to the two hosts below, over https, without
following redirects. Errors come back as mailbox.MailboxError with a plain
message; no token ever appears in one.
"""
import base64
import email.utils
import hashlib
import os
import re
import secrets
from datetime import datetime, timezone
from urllib.parse import quote, urlencode, urlsplit

import httpx

from .alerts import trusted_results
from .imapmail import parse_raw, MAX_RAW
from .mailbox import MailboxError

AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth"
TOKEN_HOST = "oauth2.googleapis.com"
API_HOST = "gmail.googleapis.com"
TOKEN_URL = f"https://{TOKEN_HOST}/token"
API = f"https://{API_HOST}/gmail/v1/users/me"
SCOPE = "https://www.googleapis.com/auth/gmail.readonly"
# The server id Gmail stamps on Authentication-Results (decided 2026-11-27).
AUTHSERV = "mx.google.com"
TIMEOUT = 30.0
_ID = re.compile(r"^[A-Za-z0-9_\-]{1,200}$")

# Tests put an httpx.MockTransport here as the stand-in Google.
_transport: httpx.BaseTransport | None = None


def _on(name: str) -> bool:
    return os.environ.get(name, "").strip().lower() in ("1", "true", "yes", "on")


def _project() -> tuple[str, str]:
    """(client id, client secret): Gmail's own project when it's set,
    otherwise the instance's Google sign-in project."""
    gid = os.environ.get("GMAIL_CLIENT_ID", "").strip()
    if gid:
        return gid, os.environ.get("GMAIL_CLIENT_SECRET", "").strip()
    return (os.environ.get("GOOGLE_CLIENT_ID", "").strip(),
            os.environ.get("GOOGLE_CLIENT_SECRET", "").strip())


def own_project() -> bool:
    return bool(os.environ.get("GMAIL_CLIENT_ID", "").strip())


def enabled() -> bool:
    return _on("GMAIL_API_ENABLED")


def available() -> bool:
    cid, secret = _project()
    return enabled() and bool(cid and secret)


def web_available(redirect_uri: str) -> bool:
    parts = urlsplit(redirect_uri)
    secure = parts.scheme == "https" or (parts.scheme == "http" and parts.hostname == "localhost")
    return available() and secure


def _client() -> httpx.Client:
    return httpx.Client(timeout=TIMEOUT, follow_redirects=False, transport=_transport)


# ---------- Signing in ----------

def start_web(redirect_uri: str) -> dict:
    """The address to send the browser to, with the state and the PKCE
    verifier the callback needs (kept in the user's own session)."""
    state = secrets.token_urlsafe(24)
    verifier = secrets.token_urlsafe(48)
    challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).decode().rstrip("=")
    query = urlencode({"client_id": _project()[0], "response_type": "code",
                       "redirect_uri": redirect_uri, "scope": SCOPE, "state": state,
                       "access_type": "offline", "prompt": "consent select_account",
                       "code_challenge": challenge, "code_challenge_method": "S256"})
    return {"url": AUTH_URL + "?" + query, "state": state, "verifier": verifier}


def _error(r: httpx.Response) -> str:
    try:
        data = r.json()
    except ValueError:
        return ""
    return str(data.get("error") or "") if isinstance(data, dict) else ""


def _post_token(form: dict) -> httpx.Response:
    cid, secret = _project()
    try:
        with _client() as c:
            return c.post(TOKEN_URL, data={**form, "client_id": cid, "client_secret": secret})
    except httpx.HTTPError:
        raise MailboxError("Couldn't reach Google. Try again in a while.")


def _tokens(r: httpx.Response, refresh: str | None = None) -> dict:
    try:
        data = r.json()
    except ValueError:
        data = None
    if not isinstance(data, dict) or not isinstance(data.get("access_token"), str):
        raise MailboxError("Google sent something this server can't read. Try again in a while.")
    granted = str(data.get("scope") or SCOPE).split()
    if SCOPE not in granted:
        raise MailboxError("Google didn't allow reading your mail: the box for it was left unticked. "
                           "Connect again and tick \"View your email messages and settings\".",
                           status=400)
    expires = data.get("expires_in")
    expires = int(expires) if isinstance(expires, (int, str)) and str(expires).isdigit() else 3600
    new_refresh = data.get("refresh_token") if isinstance(data.get("refresh_token"), str) else refresh
    if not new_refresh:
        raise MailboxError("Google didn't allow staying signed in. Remove WalletWeather's access in "
                           "your Google Account, then connect again.", status=400)
    return {"access": data["access_token"], "refresh": new_refresh,
            "expires_at": int(datetime.now(timezone.utc).timestamp()) + max(60, expires) - 60}


def finish_web(code: str, verifier: str, redirect_uri: str) -> dict:
    r = _post_token({"grant_type": "authorization_code", "code": code,
                     "redirect_uri": redirect_uri, "code_verifier": verifier})
    if r.status_code != 200:
        raise MailboxError(f"Google didn't finish the sign-in "
                           f"({_error(r) or 'HTTP ' + str(r.status_code)}). Try again.", status=400)
    return _tokens(r)


def fresh(tokens: dict) -> dict:
    """The tokens with an access token good for at least a minute, renewed
    with the refresh token when needed; the same dict when nothing changed."""
    if tokens.get("access") and int(tokens.get("expires_at") or 0) > datetime.now(timezone.utc).timestamp():
        return tokens
    r = _post_token({"grant_type": "refresh_token", "refresh_token": tokens.get("refresh") or ""})
    if r.status_code != 200:
        if _error(r) in ("invalid_grant", "unauthorized_client", "invalid_client"):
            raise MailboxError("Google no longer accepts this sign-in: in a project set to \"Testing\" "
                               "it lapses after 7 days; it also ends when access is removed, the "
                               "Google password changes or it's unused for six months. Disconnect, "
                               "then connect again.", status=409, revoked=True)
        raise MailboxError(f"Google didn't renew the sign-in (HTTP {r.status_code}). "
                           "Try again in a while.")
    return _tokens(r, tokens.get("refresh"))


# ---------- Reading mail (Gmail API) ----------

def _clean(value, limit: int) -> str:
    return re.sub(r"[\x00-\x1f\x7f]", " ", str(value if value is not None else "")).strip()[:limit]


def _received(m: dict) -> datetime | None:
    raw = m.get("internalDate")
    if not isinstance(raw, (str, int)) or not str(raw).isdigit():
        return None
    return datetime.fromtimestamp(int(raw) / 1000, tz=timezone.utc).replace(tzinfo=None)


def _sender(value: str) -> str:
    return _clean(email.utils.parseaddr(value or "")[1], 320).lower()


class Reader:
    """Gmail through its API for the length of a `with` block. `cred` is the
    access token; `folder` a label id (INBOX, Label_12, ...)."""

    def __init__(self, access: str, folder: str | None = None):
        self.access = access
        self.folder = folder

    def open(self) -> "Reader":
        return self

    def close(self) -> None:
        pass

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False

    def _get(self, path: str, params=None) -> dict:
        url = f"{API}{path}"
        parts = urlsplit(url)
        if parts.scheme != "https" or (parts.hostname or "").lower() != API_HOST:
            raise MailboxError("Google pointed this server somewhere it doesn't go. Nothing was sent.")
        try:
            with _client() as c:
                r = c.get(url, params=params, headers={"Authorization": f"Bearer {self.access}"})
        except httpx.HTTPError:
            raise MailboxError("Couldn't reach Google. Try again in a while.")
        if r.status_code == 401:
            raise MailboxError("Google no longer accepts this sign-in. Disconnect, then connect again.",
                               status=409, revoked=True)
        if r.status_code == 403:
            text = r.text[:2000].lower()
            if "ratelimit" in text or "quota" in text:
                raise MailboxError("Gmail is busy. Try again in a few minutes.", status=503)
            raise MailboxError("Google won't let this sign-in read mail. Disconnect, then connect again "
                               "and allow reading your mail.", status=409, revoked=True)
        if r.status_code == 404:
            raise MailboxError("That folder or message isn't in the mailbox any more.", status=404)
        if r.status_code in (429, 500, 503, 504):
            raise MailboxError("Gmail is busy. Try again in a few minutes.", status=503)
        if r.status_code != 200:
            raise MailboxError(f"Gmail answered with an error (HTTP {r.status_code}). "
                               "Try again in a while.")
        try:
            data = r.json()
        except ValueError:
            data = None
        if not isinstance(data, dict):
            raise MailboxError("Gmail sent something this server can't read. Try again in a while.")
        return data

    def _label(self) -> str:
        if not self.folder or not _ID.fullmatch(self.folder):
            raise MailboxError("That folder isn't in the mailbox.", status=404)
        return self.folder

    def address(self) -> str:
        return _clean(self._get("/profile").get("emailAddress"), 320)

    def folders(self) -> list[dict]:
        out = []
        for lab in (self._get("/labels").get("labels") or [])[:500]:
            if not isinstance(lab, dict) or not isinstance(lab.get("id"), str) or not _ID.fullmatch(lab["id"]):
                continue
            if lab.get("type") == "system" and lab["id"] not in ("INBOX", "IMPORTANT", "STARRED",
                                                                 "CATEGORY_UPDATES", "CATEGORY_PERSONAL"):
                continue
            name = _clean(lab.get("name"), 200) or "Folder"
            parent, _, leaf = name.rpartition("/")
            out.append({"id": lab["id"], "name": leaf or name, "parent": parent or None})
            if len(out) >= 300:
                break
        out.sort(key=lambda f: (f["id"] != "INBOX", (f["parent"] or "").lower(), f["name"].lower()))
        return out

    def _summary(self, mid: str) -> dict | None:
        m = self._get(f"/messages/{quote(mid, safe='')}",
                      [("format", "metadata"), ("metadataHeaders", "From"),
                       ("metadataHeaders", "Subject"), ("metadataHeaders", "Message-ID")])
        received = _received(m)
        if received is None or not isinstance(m.get("id"), str):
            return None
        heads = {}
        for h in ((m.get("payload") or {}).get("headers") or []) if isinstance(m.get("payload"), dict) else []:
            if isinstance(h, dict) and isinstance(h.get("name"), str):
                heads.setdefault(h["name"].lower(), str(h.get("value") or ""))
        return {"id": m["id"][:200], "sender": _sender(heads.get("from", "")),
                "subject": _clean(heads.get("subject"), 300),
                "message_id": _clean(heads.get("message-id") or f"gmail:{m['id']}", 400),
                "received": received}

    def _ids(self, q: str | None, cap: int) -> list[str]:
        ids: list[str] = []
        page = None
        while len(ids) < cap:
            params = {"labelIds": self._label(), "maxResults": "100"}
            if q:
                params["q"] = q
            if page:
                params["pageToken"] = page
            data = self._get("/messages", params)
            ids.extend(m["id"] for m in data.get("messages") or []
                       if isinstance(m, dict) and isinstance(m.get("id"), str) and _ID.fullmatch(m["id"]))
            page = data.get("nextPageToken") if isinstance(data.get("nextPageToken"), str) else None
            if not page:
                break
        return ids[:cap]

    def recent(self, count: int = 25) -> list[dict]:
        rows = [s for s in (self._summary(i) for i in self._ids(None, count)) if s]
        rows.sort(key=lambda m: m["received"], reverse=True)
        return rows[:count]

    def since(self, after: datetime, limit: int, senders=None) -> list[dict]:
        """Mail at or after `after` (UTC), oldest first, at most `limit`,
        without bodies. Only mail from the taught senders is asked for, as
        Gmail needs a call per mail to say who sent it."""
        stamp = int(after.replace(tzinfo=timezone.utc).timestamp())
        q = f"after:{stamp}"
        wanted = sorted({s for s in (senders or []) if isinstance(s, str) and re.fullmatch(r"[^\s()\"]{3,320}", s)})
        if wanted:
            q += " {" + " ".join(f"from:{s}" for s in wanted[:50]) + "}"
        ids = list(reversed(self._ids(q, 5000)))   # Gmail lists newest first
        out = []
        for i in ids:
            s = self._summary(i)
            if s and s["received"] >= after:
                out.append(s)
            if len(out) >= limit:
                break
        out.sort(key=lambda m: m["received"])
        return out[:limit]

    def message(self, message_id: str) -> dict:
        if not _ID.fullmatch(message_id or ""):
            raise MailboxError("That message isn't in the mailbox any more.", status=404)
        m = self._get(f"/messages/{quote(message_id, safe='')}", {"format": "raw"})
        received = _received(m)
        raw = m.get("raw")
        if received is None or not isinstance(raw, str):
            raise MailboxError("Gmail sent something this server can't read. Try again in a while.")
        chunk = raw.strip()[: (MAX_RAW // 3 + 1) * 4]   # what decodes to MAX_RAW bytes or so
        chunk = chunk if len(chunk) == len(raw.strip()) else chunk[: len(chunk) // 4 * 4]
        try:
            data = base64.urlsafe_b64decode(chunk + "=" * (-len(chunk) % 4))
        except (ValueError, TypeError):
            raise MailboxError("Gmail sent something this server can't read. Try again in a while.")
        p = parse_raw(data)
        return {"id": message_id, "message_id": p["message_id"] or f"gmail:{message_id}",
                "sender": p["sender"], "subject": p["subject"], "received": received,
                "html": p["html"], "body": p["body"],
                "auth_results": trusted_results(p["auth_results"], AUTHSERV)}
