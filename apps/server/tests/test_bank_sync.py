"""Bank sync with SimpleFIN (bank-sync phase 2, #194).

Every call goes to a stand-in SimpleFIN (an httpx MockTransport put on
app.simplefin._transport), never the network. Covers connecting, matching
bank accounts to the user's own, Sync now, disconnecting, the admin switch,
the guard on where a token may point, the daily call limit, and the bank
connection in encrypted backups.
"""
import base64
import json
import uuid
from datetime import date, datetime, timedelta, timezone

import httpx
import pytest
from fastapi.testclient import TestClient

from conftest import share_account, unique_email

PASSWORD = "correct-horse-battery"
ACCESS = "https://user1:s3cret-pass@bridge.simplefin.org/simplefin"
TODAY = date.today()


def epoch(d: date) -> int:
    return int(datetime(d.year, d.month, d.day, 15, tzinfo=timezone.utc).timestamp())


class FakeSimpleFIN:
    """Answers claims and /accounts the way SimpleFIN Bridge does."""

    def __init__(self):
        self.claimed: set[str] = set()
        self.requests: list[httpx.Request] = []
        self.status = 200
        self.access = ACCESS
        self.down = False
        self.accounts = [
            {"id": "ACT-1", "name": "Everyday Checking", "conn_id": "CON-1", "currency": "USD",
             "balance": "1200.00", "balance-date": epoch(TODAY), "transactions": [
                 {"id": "T-1", "posted": epoch(TODAY - timedelta(days=2)), "amount": "-42.50",
                  "description": "CORNER GROCERY"},
                 {"id": "T-2", "posted": epoch(TODAY - timedelta(days=1)), "amount": "2500.00",
                  "description": "PAYROLL ACME"},
                 {"id": "T-3", "posted": 0, "amount": "-9.99", "description": "PENDING THING",
                  "pending": True},
                 {"id": "T-OLD", "posted": epoch(TODAY - timedelta(days=40)), "amount": "-5.00",
                  "description": "OLD COFFEE"},
             ]},
            {"id": "ACT-2", "name": "Savings", "conn_id": "CON-1", "currency": "USD",
             "balance": "5000.00", "balance-date": epoch(TODAY), "transactions": []},
        ]

    def token(self, host="bridge.simplefin.org") -> str:
        return base64.b64encode(f"https://{host}/simplefin/claim/{uuid.uuid4().hex}".encode()).decode()

    def handler(self, request: httpx.Request) -> httpx.Response:
        self.requests.append(request)
        if self.down:
            raise httpx.ConnectError("down", request=request)
        path = request.url.path
        if request.method == "POST" and path.startswith("/simplefin/claim/"):
            tok = path.rsplit("/", 1)[-1]
            if tok in self.claimed:
                return httpx.Response(403)
            self.claimed.add(tok)
            return httpx.Response(200, text=self.access)
        if request.method == "GET" and path == "/simplefin/accounts":
            want = "Basic " + base64.b64encode(b"user1:s3cret-pass").decode()
            if request.headers.get("authorization") != want:
                return httpx.Response(403)
            if self.status != 200:
                return httpx.Response(self.status)
            start = int(request.url.params.get("start-date", "0"))
            only = request.url.params.get("balances-only") == "1"
            out = []
            for a in self.accounts:
                a = {k: v for k, v in a.items() if k != "transactions"} | (
                    {} if only else {"transactions": [t for t in a["transactions"]
                                                      if t["posted"] == 0 or t["posted"] >= start]})
                out.append(a)
            return httpx.Response(200, json={
                "errlist": [], "connections": [{"conn_id": "CON-1", "name": "Test Bank",
                                                "org_id": "o1", "sfin_url": "https://x"}],
                "accounts": out})
        return httpx.Response(404)


@pytest.fixture
def fake(monkeypatch):
    from app import simplefin
    f = FakeSimpleFIN()
    monkeypatch.setattr(simplefin, "_transport", httpx.MockTransport(f.handler))
    monkeypatch.delenv("SIMPLEFIN_HOSTS", raising=False)
    return f


def set_switch(on: bool):
    from app.db import AdminSetting, SessionLocal
    db = SessionLocal()
    try:
        row = db.get(AdminSetting, "bank_sync_enabled")
        if on and not row:
            db.add(AdminSetting(key="bank_sync_enabled", value="true"))
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
    from app.db import BankConnection, SessionLocal
    db = SessionLocal()
    try:
        return db.query(BankConnection).filter_by(user_id=user_id).first()
    finally:
        db.close()


@pytest.fixture
def connected(app_started, fake, switched_on):
    """A user with an account, connected to the stand-in SimpleFIN."""
    c, u = register(app_started)
    acc = make_account(c)
    r = c.post("/api/bank/connect", json={"token": fake.token()})
    assert r.status_code == 200, r.text
    return c, u, acc, r.json()


def ref_of(status, name):
    return next(a["ref"] for a in status["accounts"] if a["name"] == name)


def link(c, status, acc, start=None, name="Everyday Checking"):
    body = {"links": [{"ref": ref_of(status, name), "account_id": acc,
                       "start_date": (start or TODAY - timedelta(days=10)).isoformat()}]}
    r = c.put("/api/bank/links", json=body)
    assert r.status_code == 200, r.text
    return r.json()


# ---------- Connecting ----------

def test_connect_lists_the_bank_accounts_and_hides_the_address(connected, fake):
    c, u, _, status = connected
    assert status["enabled"] is True and status["connected"] is True
    assert [(a["name"], a["org"], a["account_id"]) for a in status["accounts"]] == [
        ("Everyday Checking", "Test Bank", None), ("Savings", "Test Bank", None)]
    assert all(len(a["ref"]) == 64 for a in status["accounts"])
    assert status["start_max_days"] == 90
    text = json.dumps(status) + c.get("/api/bank").text
    for secret in ("s3cret-pass", "user1", "ACT-1"):
        assert secret not in text
    # The listing asked for balances only, and the address is stored encrypted.
    assert fake.requests[-1].url.params.get("balances-only") == "1"
    row = connection_row(u["id"])
    assert b"s3cret" not in row.access_url_enc


def test_a_token_works_once(app_started, fake, switched_on):
    c, _ = register(app_started)
    token = fake.token()
    assert c.post("/api/bank/connect", json={"token": token}).status_code == 200
    c2, _ = register(app_started)
    r = c2.post("/api/bank/connect", json={"token": token})
    assert r.status_code == 400 and "already used" in r.json()["detail"]


def test_connecting_twice_is_refused(connected, fake):
    c, *_ = connected
    r = c.post("/api/bank/connect", json={"token": fake.token()})
    assert r.status_code == 409


@pytest.mark.parametrize("bad", [
    "not base64 !!",
    base64.b64encode(b"https://evil.example/simplefin/claim/abc").decode(),
    base64.b64encode(b"http://bridge.simplefin.org/simplefin/claim/abc").decode(),
    base64.b64encode(b"https://bridge.simplefin.org:8443/simplefin/claim/abc").decode(),
    base64.b64encode(b"https://u:p@bridge.simplefin.org/simplefin/claim/abc").decode(),
    base64.b64encode(b"https://bridge.simplefin.org.evil.example/claim/abc").decode(),
])
def test_a_token_pointing_anywhere_else_is_refused_before_any_call(app_started, fake, switched_on, bad):
    c, u = register(app_started)
    r = c.post("/api/bank/connect", json={"token": bad})
    assert r.status_code == 400
    assert fake.requests == []
    assert connection_row(u["id"]) is None


def test_an_access_address_pointing_elsewhere_is_refused(app_started, fake, switched_on):
    fake.access = "https://user1:s3cret-pass@evil.example/simplefin"
    c, u = register(app_started)
    r = c.post("/api/bank/connect", json={"token": fake.token()})
    assert r.status_code == 400 and "isn't SimpleFIN" in r.json()["detail"]
    assert [q.method for q in fake.requests] == ["POST"]   # the claim only
    assert connection_row(u["id"]) is None


def test_the_allowed_hosts_come_from_the_setting(app_started, fake, switched_on, monkeypatch):
    monkeypatch.setenv("SIMPLEFIN_HOSTS", "sfin.example.org")
    c, _ = register(app_started)
    r = c.post("/api/bank/connect", json={"token": fake.token()})
    assert r.status_code == 400 and fake.requests == []


def test_simplefin_down_while_connecting_changes_nothing(app_started, fake, switched_on):
    fake.down = True
    c, u = register(app_started)
    r = c.post("/api/bank/connect", json={"token": fake.token()})
    assert r.status_code == 502 and "Couldn't reach SimpleFIN" in r.json()["detail"]
    assert connection_row(u["id"]) is None


# ---------- Matching and Sync now ----------

def test_sync_lands_posted_lines_once(connected, fake):
    c, u, acc, status = connected
    link(c, status, acc)
    r = c.post("/api/bank/sync")
    assert r.status_code == 200, r.text
    assert (r.json()["added"], r.json()["skipped"]) == (2, 0)
    got = sorted((t["description"], t["amount"], t["is_actual"]) for t in lines(c, acc))
    # Posted only, and nothing before the start date.
    assert got == [("CORNER GROCERY", -42.5, True), ("PAYROLL ACME", 2500.0, True)]
    st = r.json()["status"]
    assert st["last_sync_ok"] is True and st["last_sync_status"].startswith("2 new lines")
    again = c.post("/api/bank/sync")
    assert (again.json()["added"], again.json()["skipped"]) == (0, 2)
    assert len(lines(c, acc)) == 2


def test_a_later_start_date_leaves_older_lines_out(connected, fake):
    c, u, acc, status = connected
    link(c, status, acc, start=TODAY - timedelta(days=1))
    assert c.post("/api/bank/sync").json()["added"] == 1


def test_a_line_already_imported_by_csv_is_not_doubled(connected, fake):
    c, u, acc, status = connected
    day = (TODAY - timedelta(days=2)).isoformat()
    r = c.post(f"/api/accounts/{acc}/import/commit", json={
        "csv_text": f"Date,Description,Amount\n{day},Corner Grocery,-42.50\n",
        "mapping": {"date": 0, "description": 1, "amount": 2}})
    assert r.status_code == 200, r.text
    link(c, status, acc)
    r = c.post("/api/bank/sync")
    assert (r.json()["added"], r.json()["skipped"]) == (1, 1)
    assert len(lines(c, acc)) == 2


def test_the_tag_rules_run_on_synced_lines(connected, fake):
    c, u, acc, status = connected
    tag = c.post("/api/tags", json={"name": "Groceries"}).json()["id"]
    assert c.post("/api/tag-rules", json={"description_pattern": "grocery", "tag_id": tag}).status_code == 200
    link(c, status, acc)
    c.post("/api/bank/sync")
    grocery = next(t for t in lines(c, acc) if t["description"] == "CORNER GROCERY")
    assert tag in [x["id"] for x in grocery["tags"]]


def test_new_lines_arrive_on_the_next_sync(connected, fake):
    c, u, acc, status = connected
    link(c, status, acc)
    c.post("/api/bank/sync")
    fake.accounts[0]["transactions"].append(
        {"id": "T-9", "posted": epoch(TODAY), "amount": "-3.00", "description": "BUS FARE"})
    r = c.post("/api/bank/sync")
    assert (r.json()["added"], r.json()["skipped"]) == (1, 2)


def test_only_an_accounts_owner_can_link_it(app_started, connected):
    c, u, acc, status = connected
    other, ou = register(app_started)
    theirs = make_account(other, "Theirs")
    share_account(other, theirs, "edit", invitee_client=c)
    r = c.put("/api/bank/links", json={"links": [{"ref": ref_of(status, "Savings"), "account_id": theirs}]})
    assert r.status_code == 404


def test_link_checks(connected):
    c, u, acc, status = connected
    checking, savings = ref_of(status, "Everyday Checking"), ref_of(status, "Savings")
    too_old = (TODAY - timedelta(days=91)).isoformat()
    for body, code in [
        ({"links": [{"ref": checking, "account_id": acc, "start_date": too_old}]}, 400),
        ({"links": [{"ref": checking, "account_id": acc,
                     "start_date": (TODAY + timedelta(days=1)).isoformat()}]}, 400),
        ({"links": [{"ref": checking, "account_id": acc}, {"ref": savings, "account_id": acc}]}, 400),
        ({"links": [{"ref": "0" * 64, "account_id": acc}]}, 404),
        ({"links": [{"ref": checking, "account_id": 999999999}]}, 404),
    ]:
        assert c.put("/api/bank/links", json=body).status_code == code, body
    # Defaults to today; leaving it out removes the match; moving it works.
    st = c.put("/api/bank/links", json={"links": [{"ref": checking, "account_id": acc}]}).json()
    assert next(a for a in st["accounts"] if a["ref"] == checking)["start_date"] == TODAY.isoformat()
    st = c.put("/api/bank/links", json={"links": [{"ref": checking, "account_id": None},
                                                  {"ref": savings, "account_id": acc}]}).json()
    assert [(a["name"], a["account_id"]) for a in st["accounts"]] == [
        ("Everyday Checking", None), ("Savings", acc)]


def test_sync_needs_a_match(connected):
    c, *_ = connected
    r = c.post("/api/bank/sync")
    assert r.status_code == 400 and "Match at least one" in r.json()["detail"]


def test_a_revoked_connection_says_so_and_changes_nothing(connected, fake):
    c, u, acc, status = connected
    link(c, status, acc)
    fake.status = 403
    r = c.post("/api/bank/sync")
    assert r.status_code == 409 and "connect again" in r.json()["detail"]
    st = c.get("/api/bank").json()
    assert st["last_sync_ok"] is False and "connect again" in st["last_sync_status"]
    assert lines(c, acc) == []


@pytest.mark.parametrize("status_code,words", [(402, "subscription"), (500, "Try again")])
def test_simplefin_errors_are_plain_and_change_nothing(connected, fake, status_code, words):
    c, u, acc, status = connected
    link(c, status, acc)
    fake.status = status_code
    r = c.post("/api/bank/sync")
    assert r.status_code in (402, 502) and words in r.json()["detail"]
    assert "s3cret" not in r.text
    assert lines(c, acc) == []


def test_simplefin_down_during_sync(connected, fake):
    c, u, acc, status = connected
    link(c, status, acc)
    fake.down = True
    r = c.post("/api/bank/sync")
    assert r.status_code == 502 and lines(c, acc) == []


def test_the_daily_call_limit(connected, fake):
    from app.db import BankConnection, SessionLocal
    c, u, acc, status = connected
    link(c, status, acc)
    db = SessionLocal()
    try:
        row = db.query(BankConnection).filter_by(user_id=u["id"]).first()
        now = datetime.utcnow()
        row.calls_json = json.dumps([(now - timedelta(hours=1, minutes=i)).isoformat() for i in range(20)])
        db.commit()
    finally:
        db.close()
    before = len(fake.requests)
    r = c.post("/api/bank/sync")
    assert r.status_code == 429 and "run again in" in r.json()["detail"]
    assert int(r.headers["retry-after"]) > 0
    assert len(fake.requests) == before
    assert c.get("/api/bank").json()["syncs_left_today"] == 0


# ---------- Disconnecting ----------

def test_disconnect_removes_the_address_and_keeps_the_lines(connected, fake):
    c, u, acc, status = connected
    link(c, status, acc)
    c.post("/api/bank/sync")
    r = c.post("/api/bank/disconnect", json={})
    assert r.status_code == 200 and r.json()["connected"] is False
    assert connection_row(u["id"]) is None
    assert len(lines(c, acc)) == 2
    assert c.post("/api/bank/disconnect", json={}).status_code == 404


def test_deleting_the_user_removes_the_connection(connected):
    c, u, acc, status = connected
    r = c.request("DELETE", "/api/me", json={"password": PASSWORD})
    assert r.status_code == 200, r.text
    assert connection_row(u["id"]) is None


def test_with_two_factor_on_connecting_and_disconnecting_need_a_code(app_started, fake, switched_on):
    from test_two_factor_actions import fresh_code, turn_on
    c, u = register(app_started)
    secret, _ = turn_on(c, u)
    r = c.post("/api/bank/connect", json={"token": fake.token()})
    assert r.status_code == 403 and fake.requests == []
    r = c.post("/api/bank/connect", json={"token": fake.token(), "code": fresh_code(u["email"], secret)})
    assert r.status_code == 200, r.text
    assert c.post("/api/bank/disconnect", json={}).status_code == 403
    r = c.post("/api/bank/disconnect", json={"code": fresh_code(u["email"], secret)})
    assert r.status_code == 200


# ---------- Who may ----------

def test_with_the_switch_off_everything_but_disconnect_is_refused(connected, fake):
    c, u, acc, status = connected
    set_switch(False)
    assert c.get("/api/bank").json()["enabled"] is False
    assert c.post("/api/bank/connect", json={"token": fake.token()}).status_code == 403
    assert c.put("/api/bank/links", json={"links": []}).status_code == 403
    assert c.post("/api/bank/sync").status_code == 403
    assert c.post("/api/bank/disconnect", json={}).status_code == 200


def test_an_api_token_cannot_use_bank_sync(app_started, fake, switched_on):
    c, u = register(app_started)
    tok = c.post("/api/tokens", json={"name": "t", "access": "full", "expires_in_days": 30}).json()["token"]
    bearer = TestClient(app_started, headers={"Authorization": f"Bearer {tok}"})
    assert bearer.get("/api/bank").status_code == 403
    assert bearer.post("/api/bank/connect", json={"token": fake.token()}).status_code == 403
    assert bearer.post("/api/bank/sync").status_code == 403
    assert fake.requests == []


def test_the_demo_user_cannot_connect(app_started, switched_on):
    from fastapi import HTTPException
    from app import main
    from app.db import SessionLocal, User
    db = SessionLocal()
    try:
        with pytest.raises(HTTPException) as e:
            main._bank_allowed(db, User(email="admin@demo.walletweather.local"))
        assert e.value.status_code == 403
    finally:
        db.close()


def test_signed_out_is_refused(app_started):
    anon = TestClient(app_started)
    for method, path in [("GET", "/api/bank"), ("POST", "/api/bank/connect"), ("PUT", "/api/bank/links"),
                         ("POST", "/api/bank/sync"), ("POST", "/api/bank/disconnect")]:
        assert anon.request(method, path, json={}).status_code == 401, path


# ---------- Admin ----------

@pytest.fixture
def admin(app_started):
    from app import main
    c, u = register(app_started)
    main.ADMIN_EMAILS.add(u["email"])
    yield c, u
    main.ADMIN_EMAILS.discard(u["email"])
    set_switch(False)


def test_the_admin_switch(admin, connected):
    ac, _ = admin
    c, u, *_ = connected
    r = ac.put("/api/admin/bank-sync", json={"enabled": False})
    assert r.status_code == 200 and r.json()["enabled"] is False
    assert ac.get("/api/admin/bank-sync").json()["connected_users"] >= 1
    r = ac.put("/api/admin/bank-sync", json={"enabled": True})
    assert r.json()["enabled"] is True
    users = {x["id"]: x for x in ac.get("/api/admin/users").json()}
    assert users[u["id"]]["bank_connected"] is True
    assert users[admin[1]["id"]]["bank_connected"] is False
    assert c.put("/api/admin/bank-sync", json={"enabled": False}).status_code == 403
    assert c.get("/api/admin/bank-sync").status_code == 403


# ---------- Backups ----------

def test_the_connection_goes_into_encrypted_backups_only(app_started, connected, fake):
    from app.backup import open_sealed
    c, u, acc, status = connected
    link(c, status, acc)
    c.post("/api/bank/sync")
    plain = c.get("/api/backup/export")
    assert "bank_connection" not in plain.json() and "s3cret" not in plain.text
    sealed = c.post("/api/backup/export", json={"passphrase": "a long passphrase"}).json()
    inside = open_sealed(sealed, "a long passphrase")
    assert inside["bank_connection"]["access_url"] == ACCESS
    assert [l["account_name"] for l in inside["bank_connection"]["links"]] == ["Checking"]

    # Restored into another user: the connection and its match come back, and
    # the lines keep their bank ids, so the next sync adds nothing.
    other, ou = register(app_started)
    r = other.post("/api/backup/import", json={"payload": sealed, "passphrase": "a long passphrase"})
    assert r.status_code == 200, r.text
    assert r.json()["imported"]["bank_connection"] == 1
    st = other.get("/api/bank").json()
    new_acc = next(a for a in other.get("/api/accounts").json() if a["name"] == "Checking")["id"]
    assert next(a for a in st["accounts"] if a["name"] == "Everyday Checking")["account_id"] == new_acc
    r = other.post("/api/bank/sync")
    assert (r.json()["added"], r.json()["skipped"]) == (0, 2)
