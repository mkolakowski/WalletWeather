"""Email alerts from Gmail and other mailboxes (bank-alert-emails phase 3, #208).

Two ways in besides Microsoft 365: an IMAP mailbox with an app password
(app/imapmail.py) and Gmail with Google sign-in (app/gmail.py). No test
reaches the network: IMAP goes to a stand-in server put on
imapmail._factory (it records every command, so the tests can show nothing in
the mailbox was changed), Gmail to a stand-in Google (an httpx MockTransport
on gmail._transport), and the one test of "no TLS" talks to a plain TCP
server on 127.0.0.1. Covers connecting each way, the host guard, folders,
teaching, Check now, the sender check (the topmost Authentication-Results
counts only when the mailbox's own server wrote it), a sign-in that stops
working, and who may.
"""
import base64
import email.message
import imaplib
import json
import re
import socket
import threading
from contextlib import contextmanager
from datetime import date, datetime, timedelta, timezone
from urllib.parse import parse_qs, urlsplit

import httpx
import pytest
from fastapi.testclient import TestClient

from test_mail_alerts import (BANK, TODAY, _age_last_check, allow_mail, connection_row, lines,  # noqa: F401
                              make_account, purchase_html, register, set_switch, switched_on)

APP_PASSWORD = "abcd efgh ijkl mnop"      # as Google shows it
CLEAN_PASSWORD = "abcdefghijklmnop"
ME = "me@gmail.com"
GMAIL_AUTH = ("mx.google.com; dkim=pass header.i=@bank.example header.d=bank.example; spf=pass; "
              "dmarc=pass (p=REJECT) header.from=bank.example")
# What a sender can write for itself, claiming to be a mail server's own check.
FORGED_AUTH = ("mail.example.net; dkim=pass header.i=@bank.example header.d=bank.example; spf=pass; "
               "dmarc=pass (p=REJECT) header.from=bank.example")
YESTERDAY = (TODAY - timedelta(days=1)).isoformat()


def build_mail(mid, subject, html, sender=BANK, auth=GMAIL_AUTH, extra_auth=(), received=None) -> bytes:
    """A whole mail as the mailbox's server holds it: its own
    Authentication-Results as the topmost header, then the sender's."""
    m = email.message.EmailMessage()
    m["Authentication-Results"] = auth
    for more in extra_auth:
        m["Authentication-Results"] = more
    m["From"] = f"Bank <{sender}>"
    m["To"] = ME
    m["Subject"] = subject
    m["Message-ID"] = f"<{mid}@bank.example>"
    m["Date"] = (received or datetime.now(timezone.utc)).strftime("%a, %d %b %Y %H:%M:%S +0000")
    m.set_content(html, subtype="html")
    return m.as_bytes()


def alert_mail(mid, amount="4.50", merchant="STARBUCKS #123", when="Nov 16, 2026", card="1234", **kw):
    return build_mail(mid, f"You made a ${amount} purchase", purchase_html(amount, merchant, when, card), **kw)


def a_moment_ago(n: int) -> datetime:
    """Seconds, not minutes, ago and never reaching back past midnight UTC,
    where a mail would be dated before a connection's start day."""
    return datetime.now(timezone.utc) - timedelta(seconds=30 - n % 30)


# ---------- The stand-in IMAP server ----------

class FakeImap:
    """Answers IMAP the way imaplib hands it back. Records every command; a
    FETCH without PEEK marks the mail \\Seen, so a changed mailbox shows."""

    def __init__(self):
        self.mail: dict[str, list[dict]] = {"INBOX": [], "Alerts": []}
        self.noselect = ["[Gmail]"]
        self.password = CLEAN_PASSWORD
        self.next_uid = 11
        self.commands: list[tuple] = []
        self.factory_calls: list[tuple] = []

    # -- the mailbox --

    def add(self, mid, raw=None, folder="Alerts", received=None, **kw):
        received = received or a_moment_ago(sum(len(v) for v in self.mail.values()))
        raw = raw or alert_mail(mid, received=received, **kw)
        uid = self.next_uid
        self.next_uid += 1
        self.mail[folder].append({"uid": uid, "received": received, "raw": raw, "flags": set()})
        return f"777:{uid}"

    def snapshot(self):
        return {f: [(m["uid"], m["raw"], frozenset(m["flags"])) for m in ms] for f, ms in self.mail.items()}

    def factory(self, host, port, ssl_context, timeout):
        self.factory_calls.append((host, port))
        return _Conn(self)

    def verbs(self) -> set[str]:
        return {c[0] for c in self.commands}


class _Conn:
    def __init__(self, server: FakeImap):
        self.s = server
        self.folder = None

    def login(self, user, password):
        self.s.commands.append(("LOGIN", user))
        if password != self.s.password:
            raise imaplib.IMAP4.error("[AUTHENTICATIONFAILED] Invalid credentials (Failure)")
        return "OK", [b"logged in"]

    def logout(self):
        self.s.commands.append(("LOGOUT",))
        return "BYE", [b"bye"]

    def list(self, *a):
        self.s.commands.append(("LIST",))
        rows = [b'(\\HasNoChildren) "/" "' + n.encode() + b'"' for n in self.s.mail]
        rows += [b'(\\Noselect \\HasChildren) "/" "' + n.encode() + b'"' for n in self.s.noselect]
        return "OK", rows

    def select(self, mailbox, readonly=False):
        self.s.commands.append(("SELECT", mailbox, readonly))
        name = re.sub(r'\\(.)', r'\1', mailbox[1:-1]) if mailbox.startswith('"') else mailbox
        if name not in self.s.mail:
            return "NO", [b"no such folder"]
        self.folder = name
        return "OK", [str(len(self.s.mail[name])).encode()]

    def response(self, code):
        self.s.commands.append(("RESPONSE", code))
        return code, [b"777"]

    def _fetched(self, uids, spec):
        by_uid = {m["uid"]: m for m in self.s.mail[self.folder]}
        out = []
        for u in uids:
            m = by_uid.get(u)
            if m is None:
                continue
            if "BODY.PEEK" not in spec:
                m["flags"].add("\\Seen")
            stamp = m["received"].strftime("%d-%b-%Y %H:%M:%S +0000")
            if "HEADER.FIELDS" in spec:
                msg = email.message_from_bytes(m["raw"])
                lit = "".join(f"{h}: {msg[h]}\r\n" for h in ("From", "Subject", "Message-ID")).encode() + b"\r\n"
                label = "BODY[HEADER.FIELDS (FROM SUBJECT MESSAGE-ID)]"
            else:
                size = int(re.search(r"<0\.(\d+)>", spec).group(1))
                lit = m["raw"][:size]
                label = "BODY[]<0>"
            out.append((f'1 (UID {u} INTERNALDATE "{stamp}" {label} {{{len(lit)}}}'.encode(), lit))
            out.append(b")")
        return out

    def uid(self, command, *args):
        self.s.commands.append(("UID " + command.upper(),) + tuple(args))
        if self.folder is None:
            return "BAD", [b"no folder selected"]
        if command.upper() == "SEARCH":
            msgs = self.s.mail[self.folder]
            if args and args[0] == "SINCE":
                day = datetime.strptime(args[1], "%d-%b-%Y").date()
                msgs = [m for m in msgs if m["received"].date() >= day]
            return "OK", [" ".join(str(m["uid"]) for m in msgs).encode()]
        if command.upper() == "FETCH":
            return "OK", self._fetched([int(x) for x in args[0].split(",")], args[1])
        return "OK", []

    def __getattr__(self, name):   # store, copy, expunge, append, delete ...: only recorded
        def other(*a, **k):
            self.s.commands.append((name.upper(),) + a)
            return "OK", []
        return other


@pytest.fixture
def imap(monkeypatch):
    from app import imapmail
    f = FakeImap()
    monkeypatch.setattr(imapmail, "_factory", f.factory)
    monkeypatch.setattr(imapmail, "_ssl_context", None)
    monkeypatch.delenv("IMAP_HOSTS", raising=False)
    return f


def an_imap_user(app, providers=("imap",)):
    c, u = register(app, mail=False)
    allow_mail(u["id"], providers)
    return c, u


def connect_imap(c, **over):
    body = {"address": ME, "password": APP_PASSWORD, "utc_offset_minutes": 0}
    body.update(over)
    return c.post("/api/mail/imap", json=body)


@pytest.fixture
def imap_connected(app_started, imap, switched_on):
    """A user with an account and an IMAP mailbox reading the Alerts folder."""
    c, u = an_imap_user(app_started)
    acc = make_account(c)
    r = connect_imap(c)
    assert r.status_code == 200, r.text
    r = c.put("/api/mail/settings", json={"folder_id": "Alerts", "start_date": YESTERDAY})
    assert r.status_code == 200, r.text
    return c, u, acc


def teach_mail(c, acc, message_id, direction="out", fields=("amount", "merchant", "date", "card"),
               label="Test Bank", **over):
    pv = c.post("/api/mail/preview", json={"message_id": message_id})
    assert pv.status_code == 200, pv.text
    pv = pv.json()
    body = {"message_id": message_id, "label": label, "direction": direction,
            "subject_key": pv["subject_key"], "account_id": acc}
    body.update({f: pv["guess"]["fields"][f] for f in fields})
    body.update(over)
    r = c.post("/api/mail/senders", json=body)
    assert r.status_code == 200, r.text
    return pv


# ---------- IMAP: connecting ----------

def test_imap_connects_with_a_gmail_address_and_app_password(app_started, imap, switched_on):
    from app.db import decrypt_str
    c, u = an_imap_user(app_started)
    r = connect_imap(c)
    assert r.status_code == 200, r.text
    st = r.json()
    assert st["connected"] and st["provider"] == "imap" and st["address"] == ME
    assert st["folder"] == {"id": "INBOX", "name": "Inbox"}
    # No host given for a Gmail address: imap.gmail.com, on the TLS port.
    assert imap.factory_calls and {h for h, _ in imap.factory_calls} == {"imap.gmail.com"}
    # The app password's spaces are dropped, and it's what the server was given.
    stored = json.loads(decrypt_str(connection_row(u["id"]).tokens_enc))
    assert stored == {"host": "imap.gmail.com", "user": ME, "password": CLEAN_PASSWORD}


def test_the_app_password_is_stored_encrypted_and_never_sent_back(app_started, imap, switched_on):
    c, u = an_imap_user(app_started)
    r = connect_imap(c)
    assert r.status_code == 200
    row = connection_row(u["id"])
    assert b"abcdefghijklmnop" not in row.tokens_enc and b"abcd" not in row.tokens_enc
    for text in (r.text, c.get("/api/mail").text, c.get("/api/mail/status").text,
                 c.get("/api/mail/folders").text):
        assert CLEAN_PASSWORD not in text and APP_PASSWORD not in text and "abcd" not in text


def test_imap_a_wrong_password_is_a_plain_error_and_nothing_is_kept(app_started, imap, switched_on):
    c, u = an_imap_user(app_started)
    r = connect_imap(c, password="not the one")
    assert r.status_code == 400
    assert "didn't accept the address and app password" in r.json()["detail"]
    assert "not the one" not in r.text and "notstheone" not in r.text
    assert connection_row(u["id"]) is None
    assert c.get("/api/mail").json()["connected"] is False


def test_imap_a_host_off_the_list_is_refused_before_any_connection(app_started, imap, switched_on):
    c, u = an_imap_user(app_started)
    r = connect_imap(c, host="evil.example")
    assert r.status_code == 400 and "isn't set up to connect to evil.example" in r.json()["detail"]
    r = connect_imap(c, host="imap.gmail.com.evil.example")
    assert r.status_code == 400
    r = connect_imap(c, host="10.0.0.5")   # an address is no host name on the list either
    assert r.status_code == 400
    assert imap.factory_calls == [] and imap.commands == []
    assert connection_row(u["id"]) is None


def test_imap_a_non_gmail_address_with_no_host_asks_for_the_server(app_started, imap, switched_on):
    c, u = an_imap_user(app_started)
    r = connect_imap(c, address="me@example.net")
    assert r.status_code == 400 and "mail server's name" in r.json()["detail"]
    assert imap.factory_calls == []


def test_imap_hosts_can_be_added_in_the_env(app_started, imap, switched_on, monkeypatch):
    c, u = an_imap_user(app_started)
    assert c.get("/api/mail").json()["imap_hosts"] == ["imap.gmail.com"]
    monkeypatch.setenv("IMAP_HOSTS", "imap.gmail.com,mail.example.net=mail.example.net")
    assert c.get("/api/mail").json()["imap_hosts"] == ["imap.gmail.com", "mail.example.net"]
    r = connect_imap(c, address="me@example.net", host="mail.example.net", password="pw ok")
    assert r.status_code == 400   # the stand-in only knows the Gmail one
    imap.password = "pw ok"       # only Gmail's app passwords lose their spaces
    r = connect_imap(c, address="me@example.net", host="Mail.Example.net.", password="pw ok")
    assert r.status_code == 200, r.text
    assert r.json()["provider"] == "imap" and r.json()["address"] == "me@example.net"
    assert imap.factory_calls[-1][0] == "mail.example.net"


@contextmanager
def plain_tcp_server():
    """A server that says hello in plain text and never speaks TLS."""
    srv = socket.socket()
    srv.bind(("127.0.0.1", 0))
    srv.listen(5)
    srv.settimeout(0.2)
    stop = threading.Event()

    def handle(conn):
        try:
            conn.sendall(b"* OK IMAP4rev1 ready\r\n")
            conn.settimeout(5)
            while conn.recv(4096):
                pass
        except OSError:
            pass
        finally:
            conn.close()

    def run():
        while not stop.is_set():
            try:
                conn, _ = srv.accept()
            except socket.timeout:
                continue
            except OSError:
                break
            threading.Thread(target=handle, args=(conn,), daemon=True).start()

    t = threading.Thread(target=run, daemon=True)
    t.start()
    try:
        yield srv.getsockname()[1]
    finally:
        stop.set()
        srv.close()
        t.join(timeout=3)


def test_imap_a_server_without_tls_is_refused(app_started, switched_on, monkeypatch):
    from app import imapmail
    monkeypatch.setattr(imapmail, "_factory", None)
    monkeypatch.setattr(imapmail, "_ssl_context", None)
    monkeypatch.setenv("IMAP_HOSTS", "localhost")
    c, u = an_imap_user(app_started)
    with plain_tcp_server() as port:
        monkeypatch.setattr(imapmail, "_port", port)
        r = connect_imap(c, address="me@example.net", host="localhost", password="pw")
    assert r.status_code >= 400
    assert "didn't offer a secure connection" in r.json()["detail"]
    assert connection_row(u["id"]) is None


# ---------- IMAP: folders, teaching, Check now ----------

def test_imap_folders_leave_out_the_ones_that_cant_be_opened(imap_connected, imap):
    c, u, acc = imap_connected
    folders = c.get("/api/mail/folders").json()
    assert [f["id"] for f in folders] == ["INBOX", "Alerts"]     # not "[Gmail]" (\Noselect), Inbox first
    assert all(set(f) == {"id", "name", "parent"} for f in folders)
    st = c.get("/api/mail").json()
    assert st["folder"] == {"id": "Alerts", "name": "Alerts"} and st["start_date"] == YESTERDAY
    assert c.put("/api/mail/settings", json={"folder_id": "[Gmail]"}).status_code == 404
    assert c.put("/api/mail/settings", json={"folder_id": "Nope"}).status_code == 404
    assert c.put("/api/mail/settings", json={"folder_id": "INBOX"}).status_code == 200
    assert c.get("/api/mail").json()["folder"]["id"] == "INBOX"


def test_imap_recent_mail_and_the_preview(imap_connected, imap):
    c, u, acc = imap_connected
    mid = imap.add("a1")
    imap.add("friend", raw=build_mail("f1", "Hello", "<p>Not a bank</p>", sender="friend@example.org"))
    msgs = c.get("/api/mail/messages").json()
    assert {m["sender"] for m in msgs} == {BANK, "friend@example.org"}
    assert all(set(m) == {"id", "sender", "subject", "received_at", "taught"} for m in msgs)
    pv = c.post("/api/mail/preview", json={"message_id": mid}).json()
    got = {f: pv["text"][s:e] for f, (s, e) in pv["guess"]["fields"].items()}
    assert got == {"amount": "$4.50", "merchant": "STARBUCKS #123", "date": "Nov 16, 2026", "card": "1234"}
    assert pv["verified"] is True and pv["subject_key"] == "you made a"
    for gone in ("alert(1)", "phish.example", "tracker.example", "<"):
        assert gone not in pv["text"]
    assert c.post("/api/mail/preview", json={"message_id": "777:9999"}).status_code == 404
    assert c.post("/api/mail/preview", json={"message_id": "1:11"}).status_code == 404   # another UIDVALIDITY


def test_imap_check_lands_an_alert_once_and_the_mailbox_is_unchanged(imap_connected, imap):
    c, u, acc = imap_connected
    sample = imap.add("sample")
    teach_mail(c, acc, sample)
    imap.add("a1", amount="1,212.00", merchant="SHELL OIL 5566", when="Nov 15, 2026")
    imap.add("statement", raw=build_mail("st", "Your statement is ready", "<p>See your statement.</p>"))
    imap.add("other", raw=alert_mail("o1", amount="9.99", sender="other@example.org"))   # untaught sender
    before = imap.snapshot()
    r = c.post("/api/mail/check", json={})
    assert r.status_code == 200, r.text
    assert (r.json()["added"], r.json()["skipped"], r.json()["unread"]) == (2, 0, 0)
    got = sorted((t["description"], t["amount"], t["actual_date"], t["is_actual"]) for t in lines(c, acc))
    assert got == [("SHELL OIL 5566", -1212.0, "2026-11-15", True),
                   ("STARBUCKS #123", -4.5, "2026-11-16", True)]
    st = c.get("/api/mail").json()
    assert st["last_check_ok"] is True and st["last_check_status"].startswith("2 new lines")
    # A second check adds nothing and recognises both.
    _age_last_check(u["id"])
    r = c.post("/api/mail/check", json={})
    assert (r.json()["added"], r.json()["skipped"]) == (0, 2)
    assert len(lines(c, acc)) == 2
    # Nothing in the mailbox changed: read-only SELECT, PEEK-only FETCH, no writes.
    assert imap.snapshot() == before
    assert imap.verbs() <= {"LOGIN", "LOGOUT", "LIST", "SELECT", "RESPONSE", "UID SEARCH", "UID FETCH"}
    selects = [cmd for cmd in imap.commands if cmd[0] == "SELECT"]
    assert selects and all(cmd[2] is True for cmd in selects)
    fetches = [cmd for cmd in imap.commands if cmd[0] == "UID FETCH"]
    assert fetches
    for cmd in fetches:
        spec = cmd[2]
        assert "BODY.PEEK[" in spec and "BODY[" not in spec.replace("BODY.PEEK[", "")
        assert "RFC822" not in spec
    assert not any(v in imap.verbs() for v in ("STORE", "COPY", "MOVE", "EXPUNGE", "APPEND", "DELETE"))


def test_imap_only_asks_for_recent_days_not_the_whole_mailbox(imap_connected, imap):
    c, u, acc = imap_connected
    imap.add("old", received=datetime.now(timezone.utc) - timedelta(days=20))
    sample = imap.add("sample")
    teach_mail(c, acc, sample)
    r = c.post("/api/mail/check", json={})
    assert r.json()["added"] == 1       # not the mail from before the start day
    searches = [cmd for cmd in imap.commands if cmd[0] == "UID SEARCH"]
    assert any(cmd[1:2] == ("SINCE",) for cmd in searches)


# ---------- IMAP: the sender check ----------

def test_imap_on_a_host_without_a_server_id_an_alert_is_unverified(app_started, imap, switched_on, monkeypatch):
    monkeypatch.setenv("IMAP_HOSTS", "mail.example.net")
    imap.password = "pw"
    c, u = an_imap_user(app_started)
    acc = make_account(c)
    r = connect_imap(c, address="me@example.net", host="mail.example.net", password="pw")
    assert r.status_code == 200, r.text
    c.put("/api/mail/settings", json={"folder_id": "Alerts", "start_date": YESTERDAY})
    sample = imap.add("sample")        # topmost header says mx.google.com; this host has no id to trust
    pv = c.post("/api/mail/preview", json={"message_id": sample}).json()
    assert pv["verified"] is False
    teach_mail(c, acc, sample)
    r = c.post("/api/mail/check", json={})
    assert r.status_code == 200, r.text
    assert (r.json()["added"], r.json()["unread"]) == (0, 1)
    assert lines(c, acc) == []
    (item,) = c.get("/api/mail/unread").json()
    assert item["reason"] == "unverified" and item["sender"] == BANK
    assert "May not be from your bank" in item["reason_text"]


def test_imap_a_header_not_written_by_the_hosts_own_server_is_unverified(imap_connected, imap):
    c, u, acc = imap_connected
    teach_mail(c, acc, imap.add("sample"))
    imap.add("forged", amount="999.00", auth=FORGED_AUTH)                          # topmost is not Gmail's
    imap.add("buried", amount="888.00", auth=FORGED_AUTH, extra_auth=[GMAIL_AUTH])  # Gmail's is further down
    r = c.post("/api/mail/check", json={})
    assert r.status_code == 200, r.text
    assert (r.json()["added"], r.json()["unread"]) == (1, 2)    # the sample, and both kept aside
    assert [t["amount"] for t in lines(c, acc)] == [-4.5]
    items = c.get("/api/mail/unread").json()
    assert len(items) == 2 and {i["reason"] for i in items} == {"unverified"}
    _age_last_check(u["id"])
    c.post("/api/mail/check", json={})
    assert [t["amount"] for t in lines(c, acc)] == [-4.5]       # never becomes a line later


def test_the_server_id_of_an_authentication_results_header():
    from app import alerts
    assert alerts.authserv_id("mx.google.com; dkim=pass header.d=bank.example") == "mx.google.com"
    assert alerts.authserv_id("MX.Google.COM 1; spf=pass") == "mx.google.com"      # with a version
    assert alerts.authserv_id("(a comment) mail.example.net (another); dkim=none") == "mail.example.net"
    assert alerts.authserv_id("  mail.example.net  ;dkim=none") == "mail.example.net"
    assert alerts.authserv_id("") == "" and alerts.authserv_id(None) == ""
    assert alerts.authserv_id("; dkim=pass") == ""
    assert alerts.authserv_id("dkim=pass; spf=pass") == "dkim=pass"                 # a header with no id


def test_trusted_results_keeps_the_headers_only_when_the_hosts_own_server_wrote_the_top_one():
    from app import alerts
    mine, theirs = "mx.google.com; dkim=pass", "bank.example; dkim=pass"
    assert alerts.trusted_results([mine, theirs], "mx.google.com") == [mine, theirs]
    assert alerts.trusted_results([mine], "MX.GOOGLE.COM") == [mine]                # case doesn't matter
    assert alerts.trusted_results([theirs, mine], "mx.google.com") == []            # not on top
    assert alerts.trusted_results([mine], None) == []                               # no id to trust
    assert alerts.trusted_results([mine], "") == []
    assert alerts.trusted_results([], "mx.google.com") == []
    assert alerts.trusted_results([FORGED_AUTH], "mx.google.com") == []
    # And what that gives the sender check.
    good = GMAIL_AUTH
    assert alerts.sender_verified(BANK, alerts.trusted_results([good], "mx.google.com"))
    assert not alerts.sender_verified(BANK, alerts.trusted_results([good], "mail.example.net"))


# ---------- IMAP: a password that stops working ----------

def test_imap_a_password_that_stops_working_is_recorded_and_the_schedule_stops(imap_connected, imap):
    c, u, acc = imap_connected
    teach_mail(c, acc, imap.add("sample"))
    st = c.get("/api/mail/status").json()
    assert st["needs_reconnect"] is False and st["next_check_at"] is not None
    imap.password = "rotated-by-google"     # the app password was revoked
    r = c.post("/api/mail/check", json={})
    assert r.status_code == 409
    assert "didn't accept the address and app password" in r.json()["detail"]
    assert CLEAN_PASSWORD not in r.text
    assert lines(c, acc) == []
    st = c.get("/api/mail/status").json()
    assert st["needs_reconnect"] is True and st["last_check_ok"] is False
    assert st["next_check_at"] is None
    assert c.get("/api/mail").json()["needs_reconnect"] is True


# ---------- The stand-in Google ----------

class FakeGoogle:
    """Answers Google's token endpoint and the Gmail API the way Google does."""

    def __init__(self):
        self.requests: list[httpx.Request] = []
        self.token_forms: list[dict] = []
        self.queries: list[str] = []
        self.fetched: list[tuple[str, str]] = []
        self.scope = "openid email https://www.googleapis.com/auth/gmail.readonly"
        self.invalid_grant = False
        self.n = 0
        self.access = None
        self.valid_access: set[str] = set()
        self.mail: list[dict] = []
        self.labels = [{"id": "INBOX", "name": "INBOX", "type": "system"},
                       {"id": "SENT", "name": "SENT", "type": "system"},
                       {"id": "SPAM", "name": "SPAM", "type": "system"},
                       {"id": "Label_7", "name": "Receipts", "type": "user"},
                       {"id": "Label_12", "name": "Bank/Alerts", "type": "user"}]

    def add(self, mid, raw=None, label="Label_12", received=None, **kw):
        received = received or a_moment_ago(len(self.mail))
        raw = raw or alert_mail(mid, received=received, **kw)
        self.mail.append({"id": f"msg-{mid}", "label": label, "raw": raw, "received": received})
        return f"msg-{mid}"

    def _token(self, refresh_too: bool):
        self.n += 1
        self.access = f"gaccess-{self.n}"
        self.valid_access.add(self.access)
        out = {"access_token": self.access, "expires_in": 3599, "scope": self.scope, "token_type": "Bearer"}
        if refresh_too:
            out["refresh_token"] = "grefresh-0"
        return httpx.Response(200, json=out)

    def handler(self, request: httpx.Request) -> httpx.Response:
        self.requests.append(request)
        host, path = request.url.host, request.url.path
        if host == "oauth2.googleapis.com" and path == "/token":
            form = {k: v[0] for k, v in parse_qs(request.content.decode()).items()}
            self.token_forms.append(form)
            if form.get("grant_type") == "authorization_code":
                if form.get("code") == "good-code" and form.get("code_verifier") and form.get("client_secret"):
                    return self._token(True)
                return httpx.Response(400, json={"error": "invalid_grant"})
            if form.get("grant_type") == "refresh_token":
                if self.invalid_grant or form.get("refresh_token") != "grefresh-0":
                    return httpx.Response(400, json={"error": "invalid_grant",
                                                     "error_description": "Token has been expired or revoked."})
                return self._token(False)     # Google doesn't send the refresh token again
            return httpx.Response(400, json={"error": "unsupported_grant_type"})
        if host != "gmail.googleapis.com":
            return httpx.Response(404)
        if request.headers.get("authorization", "").removeprefix("Bearer ") not in self.valid_access:
            return httpx.Response(401, json={"error": {"code": 401}})
        p = path.removeprefix("/gmail/v1/users/me")
        q = request.url.params
        if p == "/profile":
            return httpx.Response(200, json={"emailAddress": "me@gmail.example", "messagesTotal": 5})
        if p == "/labels":
            return httpx.Response(200, json={"labels": self.labels})
        if p == "/messages":
            query = q.get("q", "")
            self.queries.append(query)
            rows = [m for m in self.mail if m["label"] == q.get("labelIds")]
            after = re.search(r"after:(\d+)", query)
            if after:
                rows = [m for m in rows if m["received"].timestamp() >= int(after.group(1))]
            senders = re.findall(r"from:([^\s}]+)", query)
            if senders:
                rows = [m for m in rows if re.search(r"<([^>]+)>", m["raw"].decode().split("From: ", 1)[1]).group(1)
                        in senders]
            rows.sort(key=lambda m: m["received"], reverse=True)    # newest first, as Gmail lists
            return httpx.Response(200, json={"messages": [{"id": m["id"], "threadId": m["id"]} for m in rows]}
                                  if rows else {"resultSizeEstimate": 0})
        if p.startswith("/messages/"):
            m = next((m for m in self.mail if m["id"] == p.split("/", 2)[2]), None)
            if m is None:
                return httpx.Response(404, json={"error": {"code": 404}})
            fmt = q.get("format", "full")
            self.fetched.append((m["id"], fmt))
            internal = str(int(m["received"].timestamp() * 1000))
            if fmt == "raw":
                return httpx.Response(200, json={"id": m["id"], "internalDate": internal,
                                                 "raw": base64.urlsafe_b64encode(m["raw"]).decode().rstrip("=")})
            msg = email.message_from_bytes(m["raw"])
            return httpx.Response(200, json={"id": m["id"], "internalDate": internal, "payload": {"headers": [
                {"name": h, "value": msg[h]} for h in ("From", "Subject", "Message-ID")]}})
        return httpx.Response(404)


@pytest.fixture
def google(monkeypatch):
    from app import gmail, main
    g = FakeGoogle()
    monkeypatch.setattr(gmail, "_transport", httpx.MockTransport(g.handler))
    monkeypatch.setattr(main, "APP_BASE_URL", "https://ww.example.test")
    monkeypatch.setenv("GMAIL_API_ENABLED", "true")
    monkeypatch.setenv("GOOGLE_CLIENT_ID", "shared-id.apps.example")
    monkeypatch.setenv("GOOGLE_CLIENT_SECRET", "shared-secret")
    monkeypatch.delenv("GMAIL_CLIENT_ID", raising=False)
    monkeypatch.delenv("GMAIL_CLIENT_SECRET", raising=False)
    return g


def start_gmail(c):
    r = c.post("/api/mail/gmail/web", json={})
    assert r.status_code == 200, r.text
    return r.json()["url"], parse_qs(urlsplit(r.json()["url"]).query)


def connect_gmail(c, g):
    _, q = start_gmail(c)
    r = c.get("/api/mail/gmail/callback", params={"code": "good-code", "state": q["state"][0]},
              follow_redirects=False)
    assert r.status_code == 303 and r.headers["location"] == "/#settings/mail", r.text
    return r


def a_gmail_user(app, providers=("gmail",)):
    c, u = register(app, mail=False)
    allow_mail(u["id"], providers)
    return c, u


@pytest.fixture
def gmail_connected(app_started, google, switched_on):
    """A user with an account and Gmail, reading the Bank/Alerts label."""
    c, u = a_gmail_user(app_started)
    acc = make_account(c)
    connect_gmail(c, google)
    r = c.put("/api/mail/settings", json={"folder_id": "Label_12", "start_date": YESTERDAY})
    assert r.status_code == 200, r.text
    return c, u, acc


def set_tokens(user_id, tokens: dict):
    from app.db import MailConnection, SessionLocal, encrypt_str
    db = SessionLocal()
    try:
        db.query(MailConnection).filter_by(user_id=user_id).update(
            {MailConnection.tokens_enc: encrypt_str(json.dumps(tokens))})
        db.commit()
    finally:
        db.close()


# ---------- Gmail: when it's offered ----------

def test_gmail_is_refused_when_not_switched_on(app_started, google, switched_on, monkeypatch):
    c, u = a_gmail_user(app_started)
    assert c.get("/api/mail").json()["gmail_available"] is True
    monkeypatch.delenv("GMAIL_API_ENABLED")
    assert c.get("/api/mail").json()["gmail_available"] is False
    r = c.post("/api/mail/gmail/web", json={})
    assert r.status_code == 400 and "GMAIL_API_ENABLED" in r.json()["detail"]
    assert google.requests == [] and connection_row(u["id"]) is None
    # Switched on, but with no Google project at all.
    monkeypatch.setenv("GMAIL_API_ENABLED", "true")
    monkeypatch.delenv("GOOGLE_CLIENT_ID")
    assert c.get("/api/mail").json()["gmail_available"] is False
    assert c.post("/api/mail/gmail/web", json={}).status_code == 400


def test_gmail_needs_an_https_address(app_started, google, switched_on, monkeypatch):
    from app import main
    c, u = a_gmail_user(app_started)
    monkeypatch.setattr(main, "APP_BASE_URL", "http://ww.example.test")
    assert c.get("/api/mail").json()["gmail_available"] is False
    r = c.post("/api/mail/gmail/web", json={})
    assert r.status_code == 400 and "https://" in r.json()["detail"]
    monkeypatch.setattr(main, "APP_BASE_URL", "http://localhost:8300")     # the one http address Google allows
    assert c.get("/api/mail").json()["gmail_available"] is True
    assert c.post("/api/mail/gmail/web", json={}).status_code == 200


def test_gmail_is_refused_for_someone_not_ticked_for_it(app_started, google, switched_on):
    c, u = a_gmail_user(app_started, providers=("microsoft", "imap"))
    st = c.get("/api/mail").json()
    assert st["gmail_available"] is True and "gmail" not in st["providers_allowed"]
    r = c.post("/api/mail/gmail/web", json={})
    assert r.status_code == 403 and "Gmail" in r.json()["detail"]
    allow_mail(u["id"], ("gmail",))
    assert c.get("/api/mail").json()["providers_allowed"] == ["gmail"]
    assert c.post("/api/mail/gmail/web", json={}).status_code == 200


# ---------- Gmail: connecting ----------

def test_gmail_the_connect_button(app_started, google, switched_on):
    c, u = a_gmail_user(app_started)
    url, q = start_gmail(c)
    parts = urlsplit(url)
    assert parts.hostname == "accounts.google.com" and parts.path == "/o/oauth2/v2/auth"
    assert q["scope"] == ["https://www.googleapis.com/auth/gmail.readonly"]
    assert q["access_type"] == ["offline"] and q["code_challenge_method"] == ["S256"]
    assert q["redirect_uri"] == ["https://ww.example.test/api/mail/gmail/callback"]
    assert "shared-secret" not in url
    # A return that doesn't match the state started here is refused, and nothing is sent to Google.
    r = c.get("/api/mail/gmail/callback", params={"code": "good-code", "state": "forged"},
              follow_redirects=False)
    assert r.status_code == 303 and r.headers["location"] == "/#settings/mail"
    st = c.get("/api/mail").json()
    assert not st["connected"] and "didn't match" in st["connect_error"]
    assert "connect_error" not in c.get("/api/mail").json()          # said once
    assert google.token_forms == [] and connection_row(u["id"]) is None
    # A real one connects, and Google was given the PKCE verifier and the secret.
    connect_gmail(c, google)
    form = google.token_forms[-1]
    assert form["grant_type"] == "authorization_code" and form["code_verifier"]
    assert form["redirect_uri"] == "https://ww.example.test/api/mail/gmail/callback"
    st = c.get("/api/mail").json()
    assert st["connected"] and st["provider"] == "gmail" and st["auth_mode"] == "web"
    assert st["address"] == "me@gmail.example" and st["folder"] is None and "connect_error" not in st
    # The sign-in is stored encrypted and never sent to the browser.
    row = connection_row(u["id"])
    assert b"grefresh-0" not in row.tokens_enc and b"gaccess-1" not in row.tokens_enc
    assert "grefresh-0" not in c.get("/api/mail").text and "gaccess-1" not in c.get("/api/mail").text
    # The state works once.
    state = q["state"][0]
    c.get("/api/mail/gmail/callback", params={"code": "good-code", "state": state}, follow_redirects=False)
    assert "didn't match" in c.get("/api/mail").json()["connect_error"]
    # And a second mailbox isn't started.
    assert c.post("/api/mail/gmail/web", json={}).status_code == 409


def test_gmail_the_cancelled_and_the_refused_sign_in(app_started, google, switched_on):
    c, u = a_gmail_user(app_started)
    _, q = start_gmail(c)
    r = c.get("/api/mail/gmail/callback", params={"error": "access_denied", "state": q["state"][0]},
              follow_redirects=False)
    assert r.status_code == 303
    assert "cancelled or declined" in c.get("/api/mail").json()["connect_error"]
    _, q = start_gmail(c)
    c.get("/api/mail/gmail/callback", params={"code": "bad-code", "state": q["state"][0]}, follow_redirects=False)
    st = c.get("/api/mail").json()
    assert "didn't finish the sign-in" in st["connect_error"] and not st["connected"]


def test_gmail_the_project_of_its_own_wins_over_the_sign_in_project(app_started, google, switched_on, monkeypatch):
    c, u = a_gmail_user(app_started)
    _, q = start_gmail(c)
    assert q["client_id"] == ["shared-id.apps.example"]
    assert c.get("/api/mail").json()["gmail_own_project"] is False
    monkeypatch.setenv("GMAIL_CLIENT_ID", "own-id.apps.example")
    monkeypatch.setenv("GMAIL_CLIENT_SECRET", "own-secret")
    assert c.get("/api/mail").json()["gmail_own_project"] is True
    url, q = start_gmail(c)
    assert q["client_id"] == ["own-id.apps.example"] and "own-secret" not in url
    r = c.get("/api/mail/gmail/callback", params={"code": "good-code", "state": q["state"][0]},
              follow_redirects=False)
    assert r.status_code == 303 and c.get("/api/mail").json()["connected"] is True
    assert google.token_forms[-1]["client_id"] == "own-id.apps.example"
    assert google.token_forms[-1]["client_secret"] == "own-secret"


def test_gmail_leaving_the_read_box_unticked_is_a_plain_error(app_started, google, switched_on):
    c, u = a_gmail_user(app_started)
    google.scope = "openid email"          # the person unticked "View your email messages"
    _, q = start_gmail(c)
    r = c.get("/api/mail/gmail/callback", params={"code": "good-code", "state": q["state"][0]},
              follow_redirects=False)
    assert r.status_code == 303
    st = c.get("/api/mail").json()
    assert not st["connected"] and "didn't allow reading your mail" in st["connect_error"]
    assert "gaccess" not in st["connect_error"]
    assert connection_row(u["id"]) is None


# ---------- Gmail: folders, teaching, Check now ----------

def test_gmail_folders_are_the_labels(gmail_connected, google):
    c, u, acc = gmail_connected
    folders = c.get("/api/mail/folders").json()
    assert [f["id"] for f in folders][0] == "INBOX"
    assert {f["id"] for f in folders} == {"INBOX", "Label_7", "Label_12"}    # not Sent or Spam
    nested = next(f for f in folders if f["id"] == "Label_12")
    assert (nested["name"], nested["parent"]) == ("Alerts", "Bank")
    assert c.get("/api/mail").json()["folder"] == {"id": "Label_12", "name": "Bank / Alerts"}
    assert c.put("/api/mail/settings", json={"folder_id": "SENT"}).status_code == 404
    assert c.put("/api/mail/settings", json={"folder_id": "Label_7"}).status_code == 200


def test_gmail_teach_and_check_lands_an_alert_once(gmail_connected, google):
    c, u, acc = gmail_connected
    sample = google.add("sample")
    msgs = c.get("/api/mail/messages").json()
    assert [m["sender"] for m in msgs] == [BANK]
    pv = teach_mail(c, acc, sample)
    assert pv["verified"] is True
    google.add("a1", amount="1,212.00", merchant="SHELL OIL 5566", when="Nov 15, 2026")
    friend = google.add("friend", raw=build_mail("f1", "Hello", "<p>Not a bank</p>", sender="friend@example.org"))
    google.queries.clear()
    google.fetched.clear()
    r = c.post("/api/mail/check", json={})
    assert r.status_code == 200, r.text
    assert (r.json()["added"], r.json()["skipped"], r.json()["unread"]) == (2, 0, 0)
    got = sorted((t["description"], t["amount"], t["actual_date"]) for t in lines(c, acc))
    assert got == [("SHELL OIL 5566", -1212.0, "2026-11-15"), ("STARBUCKS #123", -4.5, "2026-11-16")]
    # Only the taught sender was asked for, and mail from anyone else wasn't fetched at all.
    assert google.queries and all(f"from:{BANK}" in q and "after:" in q for q in google.queries)
    assert friend not in {i for i, _ in google.fetched}
    # A second check adds nothing.
    _age_last_check(u["id"])
    r = c.post("/api/mail/check", json={})
    assert (r.json()["added"], r.json()["skipped"]) == (0, 2)
    assert len(lines(c, acc)) == 2
    # Mail was only read: GETs to Gmail, and the only POST went to the token endpoint.
    api = [q for q in google.requests if q.url.host == "gmail.googleapis.com"]
    assert api and {q.method for q in api} == {"GET"}
    assert {q.url.path for q in google.requests if q.method == "POST"} == {"/token"}


def test_gmail_an_alert_not_from_gmails_own_server_is_unverified(gmail_connected, google):
    c, u, acc = gmail_connected
    teach_mail(c, acc, google.add("sample"))
    google.add("forged", amount="999.00", auth=FORGED_AUTH)
    r = c.post("/api/mail/check", json={})
    assert (r.json()["added"], r.json()["unread"]) == (1, 1)
    assert [t["amount"] for t in lines(c, acc)] == [-4.5]
    (item,) = c.get("/api/mail/unread").json()
    assert item["reason"] == "unverified"


def test_gmail_the_sign_in_is_renewed_with_the_refresh_token_and_stored(gmail_connected, google):
    from app.db import decrypt_str
    c, u, acc = gmail_connected
    teach_mail(c, acc, google.add("sample"))
    set_tokens(u["id"], {"access": "stale", "refresh": "grefresh-0", "expires_at": 0})
    r = c.post("/api/mail/check", json={})
    assert r.status_code == 200, r.text
    form = google.token_forms[-1]
    assert form["grant_type"] == "refresh_token" and form["refresh_token"] == "grefresh-0"
    stored = json.loads(decrypt_str(connection_row(u["id"]).tokens_enc))
    assert stored["access"] == google.access and stored["access"] != "stale"
    assert stored["refresh"] == "grefresh-0"                       # kept: Google doesn't send it again
    assert stored["expires_at"] > datetime.now(timezone.utc).timestamp()
    last_api = [q for q in google.requests if q.url.host == "gmail.googleapis.com"][-1]
    assert last_api.headers["authorization"] == f"Bearer {google.access}"
    # Still good a minute later: no second renewal.
    n = len(google.token_forms)
    _age_last_check(u["id"])
    assert c.post("/api/mail/check", json={}).status_code == 200
    assert len(google.token_forms) == n


def test_gmail_a_lapsed_sign_in_is_recorded_and_the_schedule_stops(gmail_connected, google):
    c, u, acc = gmail_connected
    teach_mail(c, acc, google.add("sample"))
    assert c.get("/api/mail/status").json()["next_check_at"] is not None
    set_tokens(u["id"], {"access": "stale", "refresh": "grefresh-0", "expires_at": 0})
    google.invalid_grant = True      # a project in Testing mode: the refresh token lapsed after 7 days
    r = c.post("/api/mail/check", json={})
    assert r.status_code == 409 and "no longer accepts this sign-in" in r.json()["detail"]
    assert "grefresh-0" not in r.text
    assert lines(c, acc) == []
    st = c.get("/api/mail/status").json()
    assert st["needs_reconnect"] is True and st["last_check_ok"] is False and st["next_check_at"] is None
    assert c.get("/api/mail").json()["needs_reconnect"] is True
    _age_last_check(u["id"])
    assert c.post("/api/mail/check", json={}).status_code == 409


def test_gmail_a_rejected_access_token_is_a_lapsed_sign_in_too(gmail_connected, google):
    c, u, acc = gmail_connected
    teach_mail(c, acc, google.add("sample"))
    google.valid_access.clear()      # Google no longer knows the token, though it looks fresh
    r = c.post("/api/mail/check", json={})
    assert r.status_code == 409
    assert c.get("/api/mail/status").json()["needs_reconnect"] is True


# ---------- Who may ----------

@pytest.mark.parametrize("path, body", [
    ("/api/mail/imap", {"address": ME, "password": CLEAN_PASSWORD}),
    ("/api/mail/gmail/web", {}),
])
def test_an_api_token_cannot_connect_a_mailbox(app_started, imap, google, switched_on, path, body):
    c, u = register(app_started, mail=False)
    allow_mail(u["id"], ("imap", "gmail"))
    tok = c.post("/api/tokens", json={"name": "t", "access": "full", "expires_in_days": 30}).json()["token"]
    bearer = TestClient(app_started, headers={"Authorization": f"Bearer {tok}"})
    assert bearer.post(path, json=body).status_code == 403
    assert imap.factory_calls == [] and google.requests == [] and connection_row(u["id"]) is None
    assert TestClient(app_started).post(path, json=body).status_code in (401, 403)   # nobody signed in


@pytest.mark.parametrize("path, body", [
    ("/api/mail/imap", {"address": ME, "password": CLEAN_PASSWORD}),
    ("/api/mail/gmail/web", {}),
])
def test_the_demo_user_cannot_connect_a_mailbox(app_started, imap, google, switched_on, monkeypatch, path, body):
    import app.main as main
    c, u = register(app_started, mail=False)
    allow_mail(u["id"], ("imap", "gmail"))
    monkeypatch.setattr(main, "is_demo_email", lambda e: e == u["email"])
    r = c.post(path, json=body)
    assert r.status_code == 403 and "demo" in r.json()["detail"]
    assert imap.factory_calls == [] and google.requests == [] and connection_row(u["id"]) is None


@pytest.mark.parametrize("path, body", [
    ("/api/mail/imap", {"address": ME, "password": CLEAN_PASSWORD}),
    ("/api/mail/gmail/web", {}),
])
def test_with_the_switch_off_connecting_a_mailbox_is_refused(app_started, imap, google, path, body):
    set_switch(False)
    c, u = register(app_started, mail=False)
    allow_mail(u["id"], ("imap", "gmail"))
    r = c.post(path, json=body)
    assert r.status_code == 403 and "switched off" in r.json()["detail"]
    assert imap.factory_calls == [] and google.requests == [] and connection_row(u["id"]) is None


def test_imap_is_refused_for_someone_not_ticked_for_it(app_started, imap, switched_on):
    c, u = an_imap_user(app_started, providers=("microsoft", "gmail"))
    r = connect_imap(c)
    assert r.status_code == 403
    assert imap.factory_calls == []
    allow_mail(u["id"], ("imap",))
    assert connect_imap(c).status_code == 200


def test_imap_connecting_twice_is_refused(imap_connected, imap):
    c, u, acc = imap_connected
    n = len(imap.factory_calls)
    r = connect_imap(c)
    assert r.status_code == 409 and len(imap.factory_calls) == n


def test_disconnecting_an_imap_mailbox_forgets_the_password(imap_connected, imap):
    c, u, acc = imap_connected
    r = c.post("/api/mail/disconnect", json={})
    assert r.status_code == 200 and r.json()["connected"] is False
    assert connection_row(u["id"]) is None
