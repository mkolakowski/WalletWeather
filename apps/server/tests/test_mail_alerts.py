"""Email alerts from a Microsoft 365 mailbox (bank-alert-emails phase 1, #206).

Every call goes to a stand-in Microsoft (an httpx MockTransport put on
app.mailbox._transport), never the network. Covers signing in both ways,
picking the folder, teaching a sender from a sample, Check now, the
couldn't-read list, the sender check, the guards on mail text and on where
the server may go, the admin switch, who may, disconnecting, and the
mailbox in encrypted backups. The reader itself is tested at the end on
alerts worded in different ways.
"""
import json
from datetime import date, datetime, timedelta, timezone
from urllib.parse import parse_qs, urlsplit

import httpx
import pytest
from fastapi.testclient import TestClient

from conftest import unique_email

PASSWORD = "correct-horse-battery"
TODAY = date.today()
BANK = "alerts@bank.example"
GOOD_AUTH = ("spf=pass (sender IP is 192.0.2.1) smtp.mailfrom=bank.example; "
             "dkim=pass (signature was verified) header.d=bank.example;"
             "dmarc=pass action=none header.from=bank.example;compauth=pass reason=100")
BAD_AUTH = "spf=fail smtp.mailfrom=bank.example; dkim=none; dmarc=fail action=quarantine header.from=bank.example"


def purchase_html(amount: str, merchant: str, when: str, card: str = "1234") -> str:
    return (f"<html><head><style>p{{color:red}}</style><script>alert(1)</script></head><body>"
            f"<table><tr><td>Hi there,</td></tr><tr><td>You made a purchase of <b>${amount}</b> at "
            f"{merchant} on {when} with your card ending in {card}.</td></tr></table>"
            f"<p>Questions? <a href='https://phish.example/x'>Call us</a></p>"
            f"<img src='https://tracker.example/pixel.gif'></body></html>")


class FakeMicrosoft:
    """Answers the identity platform and Graph the way Microsoft does."""

    def __init__(self):
        self.requests: list[httpx.Request] = []
        self.approved = False
        self.declined = False
        self.revoked = False
        self.down = False
        self.n = 0
        self.access = "access-0"
        self.refresh = "refresh-0"
        # Everything issued stays good, so two users can be signed in at once.
        self.valid_access = {"access-0"}
        self.valid_refresh = {"refresh-0"}
        self.messages: list[dict] = []
        self.next_link_host = None

    def _tokens(self):
        self.n += 1
        self.access, self.refresh = f"access-{self.n}", f"refresh-{self.n}"
        self.valid_access.add(self.access)
        self.valid_refresh.add(self.refresh)
        return httpx.Response(200, json={"token_type": "Bearer", "scope": "Mail.Read User.Read",
                                         "expires_in": 3599, "access_token": self.access,
                                         "refresh_token": self.refresh})

    def add(self, mid, subject, html, sender=BANK, auth=GOOD_AUTH, folder="ALERTS",
            received: datetime | None = None):
        received = received or datetime.now(timezone.utc) - timedelta(minutes=30 - len(self.messages) % 30)
        self.messages.append({"id": f"graph-{mid}", "internetMessageId": f"<{mid}@bank.example>",
                              "receivedDateTime": received.strftime("%Y-%m-%dT%H:%M:%SZ"),
                              "from": {"emailAddress": {"name": "Bank", "address": sender}},
                              "subject": subject, "folder": folder,
                              "body": {"contentType": "html", "content": html},
                              "internetMessageHeaders": [
                                  {"name": "Received", "value": "from x"},
                                  {"name": "Authentication-Results", "value": auth},
                                  # A header further down, as a sender could write it.
                                  {"name": "Authentication-Results", "value": GOOD_AUTH}]})

    def alert(self, mid, amount="4.50", merchant="STARBUCKS #123", when="Nov 16, 2026", card="1234", **kw):
        self.add(mid, f"You made a ${amount} purchase", purchase_html(amount, merchant, when, card), **kw)

    def handler(self, request: httpx.Request) -> httpx.Response:
        self.requests.append(request)
        if self.down:
            raise httpx.ConnectError("down", request=request)
        host, path = request.url.host, request.url.path
        if host == "login.microsoftonline.com":
            form = parse_qs(request.content.decode())
            grant = (form.get("grant_type") or [""])[0]
            if path.endswith("/devicecode"):
                return httpx.Response(200, json={"device_code": "DEV-123", "user_code": "ABCD-EFGH",
                                                 "verification_uri": "https://microsoft.com/devicelogin",
                                                 "expires_in": 900, "interval": 5,
                                                 "message": "To sign in, use a web browser"})
            if grant == "urn:ietf:params:oauth:grant-type:device_code":
                if self.declined:
                    return httpx.Response(400, json={"error": "authorization_declined"})
                if not self.approved:
                    return httpx.Response(400, json={"error": "authorization_pending"})
                return self._tokens()
            if grant == "refresh_token":
                if self.revoked or (form.get("refresh_token") or [""])[0] not in self.valid_refresh:
                    return httpx.Response(400, json={"error": "invalid_grant"})
                return self._tokens()
            if grant == "authorization_code":
                if form.get("code") == ["good-code"] and form.get("code_verifier") and form.get("client_secret"):
                    return self._tokens()
                return httpx.Response(400, json={"error": "invalid_grant"})
            return httpx.Response(400, json={"error": "unsupported_grant_type"})
        if host != "graph.microsoft.com":
            return httpx.Response(404)
        if request.headers.get("authorization", "").removeprefix("Bearer ") not in self.valid_access:
            return httpx.Response(401)
        p = path.removeprefix("/v1.0")
        if p == "/me":
            return httpx.Response(200, json={"mail": "me@outlook.example", "userPrincipalName": "me@outlook.example"})
        if p == "/me/mailFolders":
            return httpx.Response(200, json={"value": [
                {"id": "INBOX", "displayName": "Inbox", "childFolderCount": 1},
                {"id": "ARCHIVE", "displayName": "Archive", "childFolderCount": 0}]})
        if p == "/me/mailFolders/INBOX/childFolders":
            return httpx.Response(200, json={"value": [
                {"id": "ALERTS", "displayName": "Bank alerts", "childFolderCount": 0}]})
        if p.startswith("/me/mailFolders/") and p.endswith("/messages"):
            folder = p.split("/")[3]
            q = request.url.params
            rows = [m for m in self.messages if m["folder"] == folder]
            flt = q.get("$filter", "")
            if flt.startswith("receivedDateTime ge "):
                rows = [m for m in rows if m["receivedDateTime"] >= flt.removeprefix("receivedDateTime ge ")]
            rows.sort(key=lambda m: m["receivedDateTime"], reverse="desc" in q.get("$orderby", ""))
            skip = int(q.get("$skip", "0"))
            top = int(q.get("$top", "10"))
            page = rows[skip:skip + top]
            out = {"value": [{k: m[k] for k in ("id", "internetMessageId", "receivedDateTime", "from", "subject")}
                             for m in page]}
            if skip + top < len(rows):
                nxt = request.url.copy_merge_params({"$skip": str(skip + top)})
                if self.next_link_host:
                    nxt = nxt.copy_with(host=self.next_link_host)
                out["@odata.nextLink"] = str(nxt)
            return httpx.Response(200, json=out)
        if p.startswith("/me/messages/"):
            mid = p.split("/", 3)[3]
            m = next((m for m in self.messages if m["id"] == mid), None)
            if m is None:
                return httpx.Response(404)
            return httpx.Response(200, json={k: v for k, v in m.items() if k != "folder"})
        return httpx.Response(404)


@pytest.fixture
def ms(monkeypatch):
    from app import mailbox
    f = FakeMicrosoft()
    monkeypatch.setattr(mailbox, "_transport", httpx.MockTransport(f.handler))
    monkeypatch.setenv("MS_CLIENT_ID", "00001111-aaaa-2222-bbbb-3333cccc4444")
    monkeypatch.delenv("MS_CLIENT_SECRET", raising=False)
    monkeypatch.delenv("MS_TENANT", raising=False)
    return f


def set_switch(on: bool):
    from app.db import AdminSetting, SessionLocal
    db = SessionLocal()
    try:
        row = db.get(AdminSetting, "mail_alerts_enabled")
        if on and not row:
            db.add(AdminSetting(key="mail_alerts_enabled", value="true"))
        elif not on and row:
            db.delete(row)
        db.commit()
    finally:
        db.close()


@pytest.fixture
def switched_on():
    set_switch(True)
    yield
    set_switch(False)


def register(app):
    c = TestClient(app)
    email = unique_email()
    r = c.post("/api/auth/register", json={"email": email, "password": PASSWORD})
    assert r.status_code == 200, r.text
    return c, {"email": email, "id": r.json()["id"], "password": PASSWORD}


def make_account(c, name="Checking"):
    r = c.post("/api/accounts", json={"name": name, "starting_balance": 100.0,
                                      "starting_date": (TODAY - timedelta(days=100)).isoformat()})
    assert r.status_code == 200, r.text
    return r.json()["id"]


def lines(c, acc):
    r = c.get(f"/api/accounts/{acc}/transactions")
    assert r.status_code == 200, r.text
    return r.json()


def connection_row(user_id):
    from app.db import MailConnection, SessionLocal
    db = SessionLocal()
    try:
        return db.query(MailConnection).filter_by(user_id=user_id).first()
    finally:
        db.close()


def connect_with_code(c, ms):
    r = c.post("/api/mail/microsoft/device", json={})
    assert r.status_code == 200, r.text
    ms.approved = True
    r = c.post("/api/mail/microsoft/device/poll")
    assert r.status_code == 200, r.text
    assert r.json()["status"] == "connected"
    return r.json()


@pytest.fixture
def connected(app_started, ms, switched_on):
    """A user with an account and a mailbox, reading the Bank alerts folder."""
    c, u = register(app_started)
    acc = make_account(c)
    connect_with_code(c, ms)
    r = c.put("/api/mail/settings", json={"folder_id": "ALERTS", "utc_offset_minutes": -300,
                                          "start_date": (TODAY - timedelta(days=1)).isoformat()})
    assert r.status_code == 200, r.text
    return c, u, acc


def teach(c, ms, acc, mid="sample", direction="out", fields=("amount", "merchant", "date", "card"),
          label="Test Bank", **over):
    """Teach from a message with the reader's own guess."""
    pv = c.post("/api/mail/preview", json={"message_id": f"graph-{mid}"})
    assert pv.status_code == 200, pv.text
    pv = pv.json()
    body = {"message_id": f"graph-{mid}", "label": label, "direction": direction,
            "subject_key": pv["subject_key"], "account_id": acc}
    body.update({f: pv["guess"]["fields"][f] for f in fields})
    body.update(over)
    r = c.post("/api/mail/senders", json=body)
    assert r.status_code == 200, r.text
    return r.json(), pv


@pytest.fixture
def taught(connected, ms):
    c, u, acc = connected
    ms.alert("sample")
    status, pv = teach(c, ms, acc)
    return c, u, acc


# ---------- Signing in ----------

def test_signing_in_with_a_code(app_started, ms, switched_on):
    c, u = register(app_started)
    st = c.get("/api/mail").json()
    assert st["enabled"] and st["available"] and not st["connected"] and not st["web_available"]
    r = c.post("/api/mail/microsoft/device", json={})
    assert r.status_code == 200, r.text
    assert r.json() == {"user_code": "ABCD-EFGH", "verification_uri": "https://microsoft.com/devicelogin",
                        "expires_in": 900, "interval": 5}
    assert "DEV-123" not in r.text
    # Waiting: the code is shown again on reload, and polling says pending.
    assert c.get("/api/mail").json()["pending"]["user_code"] == "ABCD-EFGH"
    assert c.post("/api/mail/microsoft/device/poll").json() == {"status": "pending"}
    ms.approved = True
    # Asked again before the interval: still pending, without asking Microsoft.
    before = len(ms.requests)
    assert c.post("/api/mail/microsoft/device/poll").json() == {"status": "pending"}
    assert len(ms.requests) == before
    import app.main as main
    main._mail_pending[u["id"]]["next"] = 0
    r = c.post("/api/mail/microsoft/device/poll")
    assert r.json()["status"] == "connected" and r.json()["address"] == "me@outlook.example"
    assert r.json()["auth_mode"] == "device" and r.json()["folder"] is None
    # The sign-in is stored encrypted and never sent to the browser.
    text = r.text + c.get("/api/mail").text
    assert "access-1" not in text and "refresh-1" not in text
    row = connection_row(u["id"])
    assert b"refresh-1" not in row.tokens_enc


def test_a_declined_sign_in_and_no_microsoft_app(app_started, ms, switched_on, monkeypatch):
    c, u = register(app_started)
    c.post("/api/mail/microsoft/device", json={})
    ms.declined = True
    r = c.post("/api/mail/microsoft/device/poll")
    assert r.status_code == 400 and "declined" in r.json()["detail"]
    assert c.post("/api/mail/microsoft/device/poll").status_code == 410
    monkeypatch.setenv("MS_CLIENT_ID", "")
    assert c.get("/api/mail").json()["available"] is False
    r = c.post("/api/mail/microsoft/device", json={})
    assert r.status_code == 400 and "MS_CLIENT_ID" in r.json()["detail"]


def test_the_connect_button(app_started, ms, switched_on, monkeypatch):
    c, u = register(app_started)
    r = c.post("/api/mail/microsoft/web", json={})
    assert r.status_code == 400 and "MS_CLIENT_SECRET" in r.json()["detail"]
    monkeypatch.setenv("MS_CLIENT_SECRET", "test-secret")
    assert c.get("/api/mail").json()["web_available"] is True
    r = c.post("/api/mail/microsoft/web", json={})
    assert r.status_code == 200, r.text
    url = urlsplit(r.json()["url"])
    q = parse_qs(url.query)
    assert url.hostname == "login.microsoftonline.com" and url.path == "/common/oauth2/v2.0/authorize"
    assert q["code_challenge_method"] == ["S256"] and q["redirect_uri"][0].endswith("/api/mail/microsoft/callback")
    assert "test-secret" not in r.text
    # A return that doesn't match the state started here is refused.
    r = c.get("/api/mail/microsoft/callback", params={"code": "good-code", "state": "forged"},
              follow_redirects=False)
    assert r.status_code == 303 and r.headers["location"] == "/#settings/mail"
    st = c.get("/api/mail").json()
    assert not st["connected"] and "didn't match" in st["connect_error"]
    assert "connect_error" not in c.get("/api/mail").json()   # said once
    # A real one connects.
    state = parse_qs(urlsplit(c.post("/api/mail/microsoft/web", json={}).json()["url"]).query)["state"][0]
    r = c.get("/api/mail/microsoft/callback", params={"code": "good-code", "state": state},
              follow_redirects=False)
    assert r.status_code == 303
    st = c.get("/api/mail").json()
    assert st["connected"] and st["auth_mode"] == "web" and "connect_error" not in st
    # The state works once.
    r = c.get("/api/mail/microsoft/callback", params={"code": "good-code", "state": state},
              follow_redirects=False)
    assert "didn't match" in c.get("/api/mail").json()["connect_error"]


def test_connecting_twice_is_refused(connected, ms):
    c, *_ = connected
    r = c.post("/api/mail/microsoft/device", json={})
    assert r.status_code == 409


def test_with_two_factor_on_connecting_and_disconnecting_need_a_code(app_started, ms, switched_on):
    from test_two_factor_actions import fresh_code, turn_on
    c, u = register(app_started)
    secret, _ = turn_on(c, u)
    r = c.post("/api/mail/microsoft/device", json={})
    assert r.status_code == 403 and ms.requests == []
    r = c.post("/api/mail/microsoft/device", json={"code": fresh_code(u["email"], secret)})
    assert r.status_code == 200, r.text
    ms.approved = True
    assert c.post("/api/mail/microsoft/device/poll").json()["status"] == "connected"
    assert c.post("/api/mail/disconnect", json={}).status_code == 403
    r = c.post("/api/mail/disconnect", json={"code": fresh_code(u["email"], secret)})
    assert r.status_code == 200 and r.json()["connected"] is False


# ---------- The folder ----------

def test_folders_and_settings(connected, ms):
    c, u, acc = connected
    folders = c.get("/api/mail/folders").json()
    assert {(f["name"], f["parent"]) for f in folders} == {("Inbox", None), ("Archive", None),
                                                          ("Bank alerts", "Inbox")}
    st = c.get("/api/mail").json()
    assert st["folder"] == {"id": "ALERTS", "name": "Inbox / Bank alerts"}
    assert st["start_date"] == (TODAY - timedelta(days=1)).isoformat()
    assert c.put("/api/mail/settings", json={"folder_id": "NOPE"}).status_code == 404
    # "Today" is the user's own (five hours behind UTC here), not the server's.
    today = (datetime.utcnow() - timedelta(minutes=300)).date()
    r = c.put("/api/mail/settings", json={"start_date": (today - timedelta(days=31)).isoformat()})
    assert r.status_code == 400
    r = c.put("/api/mail/settings", json={"start_date": (today + timedelta(days=1)).isoformat()})
    assert r.status_code == 400
    r = c.put("/api/mail/settings", json={"start_date": (today - timedelta(days=30)).isoformat()})
    assert r.status_code == 200
    assert c.put("/api/mail/settings", json={"utc_offset_minutes": 2000}).status_code == 422


def test_check_needs_a_folder_and_a_sender(app_started, ms, switched_on):
    c, u = register(app_started)
    make_account(c)
    connect_with_code(c, ms)
    r = c.post("/api/mail/check", json={})
    assert r.status_code == 400 and "folder" in r.json()["detail"]
    c.put("/api/mail/settings", json={"folder_id": "ALERTS"})
    r = c.post("/api/mail/check", json={})
    assert r.status_code == 400 and "Teach" in r.json()["detail"]


# ---------- Teaching ----------

def test_recent_mail_and_the_preview(connected, ms):
    c, u, acc = connected
    ms.alert("a1")
    ms.add("other", "Hello", "<p>Not a bank</p>", sender="friend@example.org")
    msgs = c.get("/api/mail/messages").json()
    assert {m["sender"] for m in msgs} == {BANK, "friend@example.org"}
    assert all(set(m) == {"id", "sender", "subject", "received_at", "taught"} for m in msgs)
    pv = c.post("/api/mail/preview", json={"message_id": "graph-a1"}).json()
    text = pv["text"]
    # Read as text: no script, no style, no link address, no image.
    for gone in ("alert(1)", "color:red", "phish.example", "tracker.example", "<"):
        assert gone not in text
    got = {f: text[s:e] for f, (s, e) in pv["guess"]["fields"].items()}
    assert got == {"amount": "$4.50", "merchant": "STARBUCKS #123", "date": "Nov 16, 2026", "card": "1234"}
    assert pv["guess"]["direction"] == "out" and pv["subject_key"] == "you made a"
    assert pv["verified"] is True and pv["known_sender"] is None
    r = c.post("/api/mail/preview", json={"message_id": "graph-missing"})
    assert r.status_code == 404
    assert c.post("/api/mail/preview", json={}).status_code == 400


def test_teaching_checks_what_was_marked(connected, ms):
    c, u, acc = connected
    ms.alert("s1")
    pv = c.post("/api/mail/preview", json={"message_id": "graph-s1"}).json()
    f = pv["guess"]["fields"]
    base = {"message_id": "graph-s1", "label": "Test Bank", "direction": "out",
            "subject_key": "you made a", "account_id": acc, "amount": f["amount"]}
    r = c.post("/api/mail/senders", json=base | {"amount": f["merchant"]})
    assert r.status_code == 400 and "isn't an amount" in r.json()["detail"]
    r = c.post("/api/mail/senders", json=base | {"amount": [0, 99999]})
    assert r.status_code == 400
    r = c.post("/api/mail/senders", json=base | {"subject_key": "your statement"})
    assert r.status_code == 400 and "subject" in r.json()["detail"]
    other = make_account(c, "Other")
    c2, _ = register(c.app)
    theirs = make_account(c2, "Theirs")
    assert c.post("/api/mail/senders", json=base | {"account_id": theirs}).status_code == 404
    r = c.post("/api/mail/senders", json=base | {"card": f["card"], "account_id": other})
    assert r.status_code == 200, r.text
    s = r.json()["senders"][0]
    assert s["address"] == BANK and s["cards"] == [{"last4": "1234", "account_id": other}]
    assert s["kinds"][0]["fields"] == ["amount", "card"]
    # Taught again with the same subject start: replaced, not added.
    r = c.post("/api/mail/senders", json=base)
    assert len(r.json()["senders"][0]["kinds"]) == 1
    assert r.json()["senders"][0]["kinds"][0]["fields"] == ["amount"]


def test_teaching_refuses_an_account_linked_to_bank_sync(connected, ms):
    from app.db import BankAccountLink, BankConnection, SessionLocal, encrypt_str
    c, u, acc = connected
    db = SessionLocal()
    try:
        bc = BankConnection(user_id=u["id"], access_url_enc=encrypt_str("https://x"), calls_json="[]")
        db.add(bc)
        db.flush()
        db.add(BankAccountLink(connection_id=bc.id, bank_account_ref="a" * 64, account_id=acc,
                               start_date=TODAY))
        db.commit()
    finally:
        db.close()
    ms.alert("s1")
    pv = c.post("/api/mail/preview", json={"message_id": "graph-s1"}).json()
    r = c.post("/api/mail/senders", json={"message_id": "graph-s1", "label": "B", "direction": "out",
                                          "subject_key": "you made a", "account_id": acc,
                                          "amount": pv["guess"]["fields"]["amount"]})
    assert r.status_code == 400 and "bank sync" in r.json()["detail"]
    assert c.get("/api/mail").json()["bank_linked_account_ids"] == [acc]


# ---------- Check now ----------

def test_check_lands_alerts_once(taught, ms):
    c, u, acc = taught
    ms.alert("a1", amount="1,212.00", merchant="SHELL OIL 5566", when="Nov 15, 2026")
    ms.add("statement", "Your statement is ready", "<p>See your statement.</p>")   # untaught kind
    ms.add("spam", "You made a $9.99 purchase", purchase_html("9.99", "X", "Nov 15, 2026"),
           sender="other@example.org")                                             # untaught sender
    r = c.post("/api/mail/check", json={})
    assert r.status_code == 200, r.text
    assert (r.json()["added"], r.json()["skipped"], r.json()["unread"]) == (2, 0, 0)
    got = sorted((t["description"], t["amount"], t["actual_date"], t["is_actual"]) for t in lines(c, acc))
    assert got == [("SHELL OIL 5566", -1212.0, "2026-11-15", True),
                   ("STARBUCKS #123", -4.5, "2026-11-16", True)]
    st = r.json()["status"]
    assert st["last_check_ok"] is True and st["last_check_status"].startswith("2 new lines")
    # Again: nothing new, and both recognised.
    import app.main as main
    from app.db import MailConnection, SessionLocal
    db = SessionLocal()
    db.query(MailConnection).filter_by(user_id=u["id"]).update(
        {MailConnection.last_check_at: datetime.utcnow() - timedelta(minutes=5),
         MailConnection.scanned_through: None})
    db.commit()
    db.close()
    r = c.post("/api/mail/check", json={})
    assert (r.json()["added"], r.json()["skipped"]) == (0, 2)
    assert len(lines(c, acc)) == 2
    # The mailbox is never changed: only GETs went to Graph.
    assert {q.method for q in ms.requests if q.url.host == "graph.microsoft.com"} == {"GET"}


def test_check_too_soon_is_refused(taught, ms):
    c, u, acc = taught
    assert c.post("/api/mail/check", json={}).status_code == 200
    r = c.post("/api/mail/check", json={})
    assert r.status_code == 429 and r.headers["Retry-After"]


def _age_last_check(user_id):
    from app.db import MailConnection, SessionLocal
    db = SessionLocal()
    db.query(MailConnection).filter_by(user_id=user_id).update(
        {MailConnection.last_check_at: datetime.utcnow() - timedelta(minutes=5)})
    db.commit()
    db.close()


def test_a_deposit_and_the_tag_rules(connected, ms):
    c, u, acc = connected
    tag = c.post("/api/tags", json={"name": "Pay"}).json()["id"]
    r = c.post("/api/tag-rules", json={"description_pattern": "payroll", "tag_id": tag})
    assert r.status_code == 200, r.text
    ms.add("d1", "Deposit received: $2,500.00",
           "<p>We've deposited $2,500.00 from ACME PAYROLL into your account ending in 7777 on 11/15.</p>")
    pv = c.post("/api/mail/preview", json={"message_id": "graph-d1"}).json()
    assert pv["guess"]["direction"] == "in" and pv["subject_key"] == "deposit received"
    text = pv["text"]
    start = text.index("ACME PAYROLL")
    teach(c, ms, acc, mid="d1", direction="in", fields=("amount",),
          merchant=[start, start + len("ACME PAYROLL")])
    r = c.post("/api/mail/check", json={})
    assert r.json()["added"] == 1
    (t,) = lines(c, acc)
    assert (t["description"], t["amount"]) == ("ACME PAYROLL", 2500.0)
    assert [x["name"] for x in t.get("tags", [])] == ["Pay"]


def test_an_alert_failing_the_sender_check_never_becomes_a_line(taught, ms):
    c, u, acc = taught
    ms.alert("forged", amount="999.00", auth=BAD_AUTH)
    r = c.post("/api/mail/check", json={})
    assert (r.json()["added"], r.json()["unread"]) == (1, 1)    # the sample, and the forgery kept aside
    assert all(t["amount"] != -999.0 for t in lines(c, acc))
    (u1,) = c.get("/api/mail/unread").json()
    assert u1["reason"] == "unverified" and "May not be from your bank" in u1["reason_text"]
    # Matching cards or teaching again never brings it in.
    _age_last_check(u["id"])
    c.post("/api/mail/check", json={})
    assert all(t["amount"] != -999.0 for t in lines(c, acc))


def test_a_card_not_matched_waits_until_it_is(taught, ms):
    c, u, acc = taught
    ms.alert("c1", amount="20.00", card="9876")
    r = c.post("/api/mail/check", json={})
    assert (r.json()["added"], r.json()["unread"]) == (1, 1)
    (item,) = c.get("/api/mail/unread").json()
    assert item["reason"] == "card" and "9876" in item["reason_text"]
    sender = c.get("/api/mail").json()["senders"][0]
    other = make_account(c, "Card 9876")
    r = c.put(f"/api/mail/senders/{sender['id']}", json={"cards": {"9876": other}})
    assert r.status_code == 200
    assert c.put(f"/api/mail/senders/{sender['id']}", json={"cards": {"98x6": other}}).status_code == 400
    _age_last_check(u["id"])
    r = c.post("/api/mail/check", json={})
    assert r.json()["added"] == 1
    assert [t["amount"] for t in lines(c, other)] == [-20.0]
    assert c.get("/api/mail/unread").json() == []


def test_an_unreadable_alert_can_be_taught_from_the_list(taught, ms):
    c, u, acc = taught
    ms.add("odd", "You made a $7.00 purchase", "<p>Charge: 7.00 USD by CAFE LUNA</p>")
    r = c.post("/api/mail/check", json={})
    assert r.json()["unread"] == 1
    (item,) = c.get("/api/mail/unread").json()
    assert item["reason"] == "unreadable"
    pv = c.post("/api/mail/preview", json={"unread_id": item["id"]}).json()
    assert pv["known_sender"]["address"] == BANK and pv["text"] == "Charge: 7.00 USD by CAFE LUNA"
    s = pv["text"].index("CAFE LUNA")
    r = c.post("/api/mail/senders", json={
        "unread_id": item["id"], "label": "Test Bank", "direction": "out",
        "subject_key": "you made a purchase" if False else "you made a", "account_id": acc,
        "amount": pv["guess"]["fields"]["amount"], "merchant": [s, s + len("CAFE LUNA")]})
    assert r.status_code == 200, r.text
    _age_last_check(u["id"])
    c.post("/api/mail/check", json={})
    assert ("CAFE LUNA", -7.0) in [(t["description"], t["amount"]) for t in lines(c, acc)]


def test_dismissing_an_item(taught, ms):
    c, u, acc = taught
    ms.alert("forged", auth=BAD_AUTH)
    c.post("/api/mail/check", json={})
    (item,) = c.get("/api/mail/unread").json()
    assert c.delete(f"/api/mail/unread/{item['id']}").status_code == 200
    assert c.get("/api/mail/unread").json() == []
    assert c.get("/api/mail").json()["unread_count"] == 0
    assert c.post("/api/mail/preview", json={"unread_id": item["id"]}).status_code == 404
    _age_last_check(u["id"])
    c.post("/api/mail/check", json={})
    assert c.get("/api/mail/unread").json() == []


def test_a_long_mail_with_markup_is_read_as_text_and_cut_off(taught, ms):
    c, u, acc = taught
    junk = "<div>" + ("filler " * 20000) + "</div>"
    ms.add("long", "You made a $3.00 purchase",
           purchase_html("3.00", "BAKERY", "Nov 16, 2026").replace("</body>", junk + "</body>"))
    c.post("/api/mail/check", json={})
    assert ("BAKERY", -3.0) in [(t["description"], t["amount"]) for t in lines(c, acc)]
    from app import alerts
    assert len(alerts.to_text(junk * 3, True)) == alerts.MAX_TEXT


def test_one_check_lands_at_most_fifty_lines(taught, ms):
    c, u, acc = taught
    base = datetime.now(timezone.utc) - timedelta(hours=3)
    for i in range(60):
        ms.alert(f"bulk{i}", amount=f"{i + 1}.00", received=base + timedelta(minutes=i))
    r = c.post("/api/mail/check", json={})
    assert r.json()["added"] == 50 and r.json()["more"] is True
    _age_last_check(u["id"])
    r = c.post("/api/mail/check", json={})
    assert r.json()["added"] == 11 and r.json()["more"] is False   # the other ten, and the sample
    assert len(lines(c, acc)) == 61


def test_microsoft_down_or_the_sign_in_lapsed(taught, ms):
    c, u, acc = taught
    ms.alert("a1")
    ms.down = True
    from app.db import MailConnection, SessionLocal
    db = SessionLocal()
    db.query(MailConnection).filter_by(user_id=u["id"]).update(
        {MailConnection.tokens_enc: __import__("app.db", fromlist=["encrypt_str"]).encrypt_str(
            json.dumps({"access": ms.access, "refresh": ms.refresh, "expires_at": 0}))})
    db.commit()
    db.close()
    r = c.post("/api/mail/check", json={})
    assert r.status_code == 502 and "Couldn't reach Microsoft" in r.json()["detail"]
    assert lines(c, acc) == []
    st = c.get("/api/mail").json()
    assert st["last_check_ok"] is False and st["needs_reconnect"] is False
    ms.down, ms.revoked = False, True
    _age_last_check(u["id"])
    r = c.post("/api/mail/check", json={})
    assert r.status_code == 409 and "Disconnect" in r.json()["detail"]
    assert c.get("/api/mail").json()["needs_reconnect"] is True
    assert lines(c, acc) == []


def test_the_sign_in_is_renewed_and_stored(taught, ms):
    c, u, acc = taught
    from app.db import MailConnection, SessionLocal, encrypt_str
    db = SessionLocal()
    db.query(MailConnection).filter_by(user_id=u["id"]).update(
        {MailConnection.tokens_enc: encrypt_str(json.dumps(
            {"access": ms.access, "refresh": ms.refresh, "expires_at": 0}))})
    db.commit()
    db.close()
    old_refresh = ms.refresh
    assert c.post("/api/mail/check", json={}).status_code == 200
    assert ms.refresh != old_refresh
    row = connection_row(u["id"])
    from app.db import decrypt_str
    assert json.loads(decrypt_str(row.tokens_enc))["refresh"] == ms.refresh


def test_a_next_page_pointing_elsewhere_is_refused(taught, ms):
    c, u, acc = taught
    for i in range(120):
        ms.add(f"x{i}", "Hello", "<p>hi</p>", sender="friend@example.org")
    ms.next_link_host = "evil.example"
    r = c.post("/api/mail/check", json={})
    assert r.status_code == 502 and "somewhere it doesn't go" in r.json()["detail"]
    assert not any(q.url.host == "evil.example" for q in ms.requests)


# ---------- Who may ----------

def test_with_the_switch_off_everything_but_disconnect_is_refused(taught, ms):
    c, u, acc = taught
    set_switch(False)
    st = c.get("/api/mail").json()
    assert st["enabled"] is False and st["connected"] is True
    assert c.post("/api/mail/microsoft/device", json={}).status_code == 403
    assert c.get("/api/mail/folders").status_code == 403
    assert c.post("/api/mail/check", json={}).status_code == 403
    assert c.get("/api/mail/messages").status_code == 403
    assert c.post("/api/mail/disconnect", json={}).status_code == 200


def test_an_api_token_and_the_demo_user_cannot(app_started, ms, switched_on, monkeypatch):
    c, u = register(app_started)
    tok = c.post("/api/tokens", json={"name": "t", "access": "full", "expires_in_days": 30}).json()["token"]
    bearer = TestClient(app_started, headers={"Authorization": f"Bearer {tok}"})
    for method, path in [("GET", "/api/mail"), ("POST", "/api/mail/microsoft/device"),
                         ("GET", "/api/mail/unread"), ("GET", "/api/mail/checks")]:
        assert bearer.request(method, path, json={}).status_code == 403, path
    import app.main as main
    monkeypatch.setattr(main, "is_demo_email", lambda e: e == u["email"])
    r = c.post("/api/mail/microsoft/device", json={})
    assert r.status_code == 403 and "demo" in r.json()["detail"]


def test_another_users_mailbox_is_out_of_reach(taught, ms, app_started):
    c, u, acc = taught
    ms.alert("forged", auth=BAD_AUTH)
    c.post("/api/mail/check", json={})
    sender = c.get("/api/mail").json()["senders"][0]
    (item,) = c.get("/api/mail/unread").json()
    c2, _ = register(app_started)
    make_account(c2)
    connect_with_code(c2, ms)
    assert c2.put(f"/api/mail/senders/{sender['id']}", json={"label": "x"}).status_code == 404
    assert c2.delete(f"/api/mail/senders/{sender['id']}").status_code == 404
    assert c2.delete(f"/api/mail/unread/{item['id']}").status_code == 404
    assert c2.post("/api/mail/preview", json={"unread_id": item["id"]}).status_code == 404
    assert c2.get("/api/mail/unread").json() == []


def test_forgetting_senders_and_disconnecting(taught, ms):
    c, u, acc = taught
    c.post("/api/mail/check", json={})
    st = c.get("/api/mail").json()
    s = st["senders"][0]
    r = c.delete(f"/api/mail/senders/{s['id']}/kinds/{s['kinds'][0]['id']}")
    assert r.json()["senders"][0]["kinds"] == []
    assert c.delete(f"/api/mail/senders/{s['id']}").json()["senders"] == []
    r = c.post("/api/mail/disconnect", json={})
    assert r.status_code == 200 and r.json()["connected"] is False
    assert connection_row(u["id"]) is None
    assert len(lines(c, acc)) == 1     # lines already brought in stay
    assert c.post("/api/mail/disconnect", json={}).status_code == 404


def test_deleting_the_user_removes_the_mailbox(connected):
    c, u, acc = connected
    r = c.request("DELETE", "/api/me", json={"password": PASSWORD})
    assert r.status_code == 200, r.text
    assert connection_row(u["id"]) is None


@pytest.fixture
def admin(app_started):
    import app.main as main
    c, u = register(app_started)
    main.ADMIN_EMAILS.add(u["email"])
    yield c, u
    main.ADMIN_EMAILS.discard(u["email"])


def test_the_admin_switch(admin, ms, app_started):
    c, u = admin
    assert c.get("/api/admin/mail-alerts").json() == {
        "enabled": False, "connected_users": c.get("/api/admin/mail-alerts").json()["connected_users"],
        "microsoft_configured": True}
    r = c.put("/api/admin/mail-alerts", json={"enabled": True})
    assert r.status_code == 200 and r.json()["enabled"] is True
    plain, pu = register(app_started)
    assert plain.get("/api/admin/mail-alerts").status_code == 403
    assert plain.put("/api/admin/mail-alerts", json={"enabled": False}).status_code == 403
    connect_with_code(plain, ms)
    row = next(x for x in c.get("/api/admin/users").json() if x["email"] == pu["email"])
    assert row["mail_connected"] is True
    events = [e["event"] for e in c.get("/api/admin/audit", params={"email": pu["email"]}).json()["events"]]
    assert "mail_connected" in events
    assert c.put("/api/admin/mail-alerts", json={"enabled": False}).json()["enabled"] is False


# ---------- Backups ----------

def test_the_mailbox_goes_into_encrypted_backups_only(app_started, taught, ms):
    from app.backup import open_sealed
    c, u, acc = taught
    c.post("/api/mail/check", json={})
    plain = c.get("/api/backup/export")
    assert "mail_connection" not in plain.json() and ms.refresh not in plain.text
    sealed = c.post("/api/backup/export", json={"passphrase": "a long passphrase"}).json()
    inside = open_sealed(sealed, "a long passphrase")
    mc = inside["mail_connection"]
    assert mc["tokens"]["refresh"] == ms.refresh and mc["folder_id"] == "ALERTS"
    assert mc["senders"][0]["account_name"] == "Checking" and mc["senders"][0]["cards"] == {"1234": "Checking"}
    other, ou = register(app_started)
    r = other.post("/api/backup/import", json={"payload": sealed, "passphrase": "a long passphrase"})
    assert r.status_code == 200, r.text
    assert r.json()["imported"]["mail_connection"] == 1
    st = other.get("/api/mail").json()
    new_acc = next(a for a in other.get("/api/accounts").json() if a["name"] == "Checking")["id"]
    assert st["senders"][0]["account_id"] == new_acc and st["folder"]["id"] == "ALERTS"
    # The restored line keeps its mail id, so checking again adds nothing.
    from app.db import MailConnection, SessionLocal
    db = SessionLocal()
    db.query(MailConnection).filter_by(user_id=ou["id"]).update({MailConnection.scanned_through: None})
    db.commit()
    db.close()
    r = other.post("/api/mail/check", json={})
    assert (r.json()["added"], r.json()["skipped"]) == (0, 1)


# ---------- The reader ----------

def test_reading_alerts_worded_in_different_ways():
    from app import alerts
    day = date(2026, 11, 17)
    cases = [
        # A table of labels and values.
        ("<table><tr><td>Merchant</td><td>CORNER GROCERY</td></tr><tr><td>Amount</td><td>$42.10</td></tr>"
         "<tr><td>Date</td><td>11/16/2026</td></tr><tr><td>Card</td><td>****4321</td></tr></table>",
         True, "Transaction alert",
         lambda h: h.replace("CORNER GROCERY", "AMAZON MKTPLACE").replace("42.10", "1,007.99")
                    .replace("11/16/2026", "11/14/2026"),
         {"amount": "1007.99", "merchant": "AMAZON MKTPLACE", "date": "2026-11-14", "card": "4321"}),
        # Plain text, the amount after the merchant.
        ("A charge of 12.00 USD was made at PIZZA PLACE on 16 Nov 2026 using card x5555.",
         False, "Charge alert",
         lambda h: h.replace("12.00", "8.25").replace("PIZZA PLACE", "TACO TRUCK").replace("16 Nov", "17 Nov"),
         {"amount": "8.25", "merchant": "TACO TRUCK", "date": "2026-11-17", "card": "5555"}),
    ]
    for sample, html, subject, change, want in cases:
        text = alerts.to_text(sample, html)
        g = alerts.guess(text, subject)
        anchors = {f: alerts.anchor(text, s, e) for f, (s, e) in g["fields"].items()}
        assert set(anchors) == set(want), (text, g)
        got = alerts.read(alerts.to_text(change(sample), html), anchors, day)
        assert {k: str(v) for k, v in got.items()} == want, (text, got)


def test_a_year_left_out_and_the_subject_key():
    from app import alerts
    assert alerts.parse_date("on Dec 30", date(2027, 1, 2)) == date(2026, 12, 30)
    assert alerts.parse_date("on Nov 16", date(2026, 11, 17)) == date(2026, 11, 16)
    assert alerts.parse_amount("$0.00") is None and alerts.parse_amount("$1,000,000,000.00") is None
    assert alerts.subject_key("You made a $4.50 purchase at Starbucks") == "you made a"
    assert alerts.subject_key("$4.50 charge") == "charge"
    assert alerts.subject_matches("you made a", "You made a $9 purchase")
    assert not alerts.subject_matches("you made a", "Your statement is ready")


def test_the_sender_check_trusts_the_top_header_only():
    from app import alerts
    assert alerts.sender_verified(BANK, [GOOD_AUTH])
    assert alerts.sender_verified("alerts@mail.bank.example", [GOOD_AUTH])     # a subdomain
    assert not alerts.sender_verified(BANK, [BAD_AUTH, GOOD_AUTH])
    assert not alerts.sender_verified(BANK, [GOOD_AUTH.replace("bank.example", "evil.example")])
    assert not alerts.sender_verified(BANK, [])
    only_dkim = "spf=none; dkim=pass header.d=bank.example; dmarc=none header.from=bank.example"
    assert alerts.sender_verified(BANK, [only_dkim])


def test_a_merchant_marked_short_still_reads_the_whole_name():
    """Taught with "STARBUCKS" marked (not "#123"), a later alert still gives
    the whole merchant: the word after the mark is allowed to vary."""
    from app import alerts
    text = alerts.to_text(purchase_html("4.50", "STARBUCKS #123", "Nov 16, 2026"), True)
    s = text.index("STARBUCKS")
    anchors = {"merchant": alerts.anchor(text, s, s + len("STARBUCKS"))}
    anchors["amount"] = alerts.anchor(text, text.index("$4.50"), text.index("$4.50") + 5)
    later = alerts.to_text(purchase_html("12.00", "SHELL OIL 5566", "Nov 17, 2026"), True)
    got = alerts.read(later, anchors, date(2026, 11, 17))
    assert got["merchant"] == "SHELL OIL 5566" and str(got["amount"]) == "12.00"


def test_crafted_anchors_stay_fast():
    import time
    from app import alerts
    text = ("1" * 5000 + " ") * 4
    a = {"before": "1" * 40, "after": "x" * 16}
    t0 = time.monotonic()
    alerts.find(text, a, "amount", date(2026, 11, 16))
    assert time.monotonic() - t0 < 2
