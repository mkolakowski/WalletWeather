"""Bank sync through Teller and Plaid, next to SimpleFIN (bank-providers
phase 1, #254).

Every call goes to a stand-in Teller or Plaid (an httpx MockTransport put on
app.teller._transport or app.plaid._transport), never the network. Covers
which providers an instance offers, connecting each one on its own page,
syncing posted lines (Teller's pages, Plaid's cursor), a bank that needs the
person again, many connections per user, one bank account per account across
connections, disconnecting and deleting a user (the provider is told), and
the connections in backups.
"""
import base64
import json
from datetime import timedelta

import httpx
import pytest

from test_bank_sync import (FakeSimpleFIN, PASSWORD, TODAY, lines, make_account, register,
                            set_switch)

BACKUP_PASSPHRASE = "a long passphrase"
TELLER_TOKEN = "teller_tok_one"
PLAID_ACCESS = "access-sandbox-1"


def day(n: int) -> str:
    """The date n days ago, as the providers write it."""
    return (TODAY - timedelta(days=n)).isoformat()


# ---------- Stand-in Teller ----------

class FakeTeller:
    """Answers /accounts, /accounts/{id}/transactions (newest first, paged
    with count and from_id), /balances and DELETE /accounts the way Teller
    does, checking the access token sent as the Basic user name."""

    def __init__(self):
        self.requests: list[httpx.Request] = []
        self.mode = "ok"        # ok | revoked | refused | down
        self.token = TELLER_TOKEN
        self.accounts = [{"id": "acc_1", "name": "Teller Checking", "last_four": "1234",
                          "type": "depository", "status": "open",
                          "institution": {"id": "teller_bank", "name": "Teller Bank"}}]
        self.transactions = [
            {"id": "txn_1", "date": day(1), "amount": "2500.00", "status": "posted",
             "description": "PAYROLL ACME"},
            {"id": "txn_2", "date": day(2), "amount": "-42.50", "status": "posted",
             "description": "CORNER GROCERY"},
            {"id": "txn_3", "date": day(0), "amount": "-9.99", "status": "pending",
             "description": "PENDING THING"},
            {"id": "txn_4", "date": day(40), "amount": "-5.00", "status": "posted",
             "description": "OLD COFFEE"},
        ]

    def calls(self, method: str, path_part: str) -> list[httpx.Request]:
        return [r for r in self.requests if r.method == method and path_part in r.url.path]

    def handler(self, request: httpx.Request) -> httpx.Response:
        self.requests.append(request)
        if self.mode == "down":
            raise httpx.ConnectError("down", request=request)
        if self.mode == "refused":
            return httpx.Response(403, json={"error": {"code": "forbidden", "message": "no"}})
        if self.mode == "revoked":
            return httpx.Response(404, json={"error": {
                "code": "enrollment.disconnected.user_action.mfa_required",
                "message": "The user must sign in to their bank again."}})
        user = base64.b64decode(request.headers["authorization"].split()[1]).decode().split(":")[0]
        if user != self.token:
            return httpx.Response(401, json={"error": {"code": "unauthorized", "message": "no"}})
        path = request.url.path
        if request.method == "DELETE" and path == "/accounts":
            return httpx.Response(204)
        if request.method == "GET" and path == "/accounts":
            return httpx.Response(200, json=self.accounts)
        if request.method == "GET" and path.endswith("/transactions"):
            return httpx.Response(200, json=self._page(request.url.params))
        if request.method == "GET" and path.endswith("/balances"):
            return httpx.Response(200, json={"ledger": "1200.00", "available": "1200.00"})
        return httpx.Response(404, json={"error": {"code": "not_found", "message": "?"}})

    def _page(self, params) -> list[dict]:
        rows = self.transactions
        from_id = params.get("from_id")
        if from_id:
            ids = [t["id"] for t in rows]
            rows = rows[ids.index(from_id) + 1:] if from_id in ids else []
        return rows[:int(params.get("count", 100))]


# ---------- Stand-in Plaid ----------

class FakePlaid:
    """Answers Hosted Link, the token swap, accounts, /transactions/sync
    pages keyed by the incoming cursor, and /item/remove the way Plaid does,
    checking the client id and secret headers."""

    def __init__(self):
        self.requests: list[httpx.Request] = []
        self.bodies: list[tuple[str, dict]] = []
        self.sessions: list[dict] = []   # what /link/token/get answers with
        self.error: dict | None = None   # a 400 body to answer every call with
        self.access = PLAID_ACCESS
        self.accounts = [{"account_id": "pa_1", "name": "Plaid Checking", "mask": "0000",
                          "type": "depository", "balances": {"current": 900.0}}]
        self.pages: dict[str, dict] = {}
        self.pages[""] = {"accounts": self.accounts, "has_more": True, "next_cursor": "c1",
                          "transactions_update_status": "HISTORICAL_UPDATE_COMPLETE",
                          "added": [self.txn("p1", 42.50, 2, "CORNER GROCERY"),
                                    self.txn("p2", 9.99, 0, "PENDING THING", pending=True)]}
        self.pages["c1"] = {"accounts": self.accounts, "has_more": False, "next_cursor": "c2",
                            "transactions_update_status": "HISTORICAL_UPDATE_COMPLETE",
                            "added": [self.txn("p3", -2500.00, 1, "PAYROLL ACME"),
                                      self.txn("p4", 5.00, 40, "OLD COFFEE")]}
        self.pages["c2"] = {"accounts": self.accounts, "has_more": False, "next_cursor": "c3",
                            "transactions_update_status": "HISTORICAL_UPDATE_COMPLETE",
                            "added": [self.txn("p5", 12.00, 0, "NEW SANDWICH")]}

    @staticmethod
    def txn(tid, amount, days_ago, name, pending=False):
        return {"transaction_id": tid, "account_id": "pa_1", "amount": amount,
                "date": day(days_ago), "name": name, "pending": pending}

    def bodies_for(self, path: str) -> list[dict]:
        return [b for p, b in self.bodies if p == path]

    def handler(self, request: httpx.Request) -> httpx.Response:
        self.requests.append(request)
        path, body = request.url.path, json.loads(request.content or b"{}")
        self.bodies.append((path, body))
        assert request.headers["plaid-client-id"] == "plaid_client"
        assert request.headers["plaid-secret"] == "plaid_secret"
        if self.error:
            return httpx.Response(400, json=self.error)
        if path == "/link/token/create":
            return httpx.Response(200, json={"link_token": "link-sandbox-1",
                                             "hosted_link_url": "https://secure.plaid.com/hl/abc"})
        if path == "/link/token/get":
            return httpx.Response(200, json={"link_sessions": self.sessions})
        if path == "/item/public_token/exchange":
            return httpx.Response(200, json={"access_token": self.access, "item_id": "item_1"})
        if path == "/accounts/get":
            return httpx.Response(200, json={"accounts": self.accounts,
                                             "item": {"institution_name": "Plaid Bank"}})
        if path == "/transactions/sync":
            page = self.pages.get(body.get("cursor", ""))
            if page is None:
                return httpx.Response(400, json={"error_type": "INVALID_REQUEST",
                                                 "error_code": "INVALID_FIELD"})
            return httpx.Response(200, json=page)
        if path == "/item/remove":
            return httpx.Response(200, json={"request_id": "r"})
        return httpx.Response(404, json={})


def plaid_login_required():
    return {"error_type": "ITEM_ERROR", "error_code": "ITEM_LOGIN_REQUIRED",
            "error_message": "the login details of this item have changed"}


def plaid_done_session(public_token="public-sandbox-1", bank="Plaid Bank"):
    return {"finished_at": "2026-11-20T12:00:00Z", "results": {"item_add_results": [
        {"public_token": public_token, "institution": {"name": bank}}]}}


# ---------- Fixtures ----------

@pytest.fixture(autouse=True)
def no_provider_keys(monkeypatch):
    """No test sees keys from the machine's own environment."""
    for name in ("TELLER_APP_ID", "TELLER_ENV", "TELLER_CERT_FILE", "TELLER_KEY_FILE",
                 "PLAID_CLIENT_ID", "PLAID_SECRET", "PLAID_ENV", "SIMPLEFIN_HOSTS"):
        monkeypatch.delenv(name, raising=False)


@pytest.fixture
def teller_fake(monkeypatch):
    from app import teller
    f = FakeTeller()
    monkeypatch.setenv("TELLER_APP_ID", "app_test")
    monkeypatch.setenv("TELLER_ENV", "sandbox")
    monkeypatch.setattr(teller, "_transport", httpx.MockTransport(f.handler))
    return f


@pytest.fixture
def plaid_fake(monkeypatch):
    from app import plaid
    f = FakePlaid()
    monkeypatch.setenv("PLAID_CLIENT_ID", "plaid_client")
    monkeypatch.setenv("PLAID_SECRET", "plaid_secret")
    monkeypatch.setenv("PLAID_ENV", "sandbox")
    monkeypatch.setattr(plaid, "_transport", httpx.MockTransport(f.handler))
    return f


@pytest.fixture
def simplefin_fake(monkeypatch):
    from app import simplefin
    f = FakeSimpleFIN()
    monkeypatch.setattr(simplefin, "_transport", httpx.MockTransport(f.handler))
    return f


@pytest.fixture
def switched_on():
    set_switch(True)
    yield
    set_switch(False)


@pytest.fixture
def admin(app_started):
    from app import main
    c, u = register(app_started)
    main.ADMIN_EMAILS.add(u["email"])
    yield c, u
    main.ADMIN_EMAILS.discard(u["email"])
    set_switch(False)


# ---------- Helpers ----------

def start(c, provider):
    return c.post("/api/bank/connect/start", json={"provider": provider})


def connect_teller(c, token=TELLER_TOKEN) -> int:
    """Start on Teller and hand over an access token, as /bank/teller does."""
    attempt = start(c, "teller").json()["attempt"]
    r = c.post("/api/bank/teller/enroll", json={"attempt": attempt, "access_token": token})
    assert r.status_code == 200, r.text
    return r.json()["connection_id"]


def connect_plaid(c, fake) -> int:
    """Start on Plaid, with the person finishing Hosted Link, then check back."""
    fake.sessions = [plaid_done_session()]
    attempt = start(c, "plaid").json()["attempt"]
    r = c.post("/api/bank/connect/check", json={"attempt": attempt})
    assert r.status_code == 200 and r.json()["state"] == "done", r.text
    return r.json()["connection_id"]


def connect_simplefin(c, fake) -> int:
    r = c.post("/api/bank/connect", json={"token": fake.token()})
    assert r.status_code == 200, r.text
    return r.json()["connections"][-1]["id"]


def bank_account(c, connection_id, starts_with):
    st = c.get("/api/bank").json()
    return next(a for a in st["accounts"]
                if a["connection_id"] == connection_id and a["name"].startswith(starts_with))


def link_to(c, connection_id, bank_name, account_id, days_back=10):
    ref = bank_account(c, connection_id, bank_name)["ref"]
    return c.put("/api/bank/links", json={"links": [{
        "ref": ref, "account_id": account_id, "start_date": day(days_back)}]})


def linked(c, connection_id, bank_name, name="Checking"):
    """A new account matched to one of a connection's bank accounts."""
    acc = make_account(c, name)
    r = link_to(c, connection_id, bank_name, acc)
    assert r.status_code == 200, r.text
    return acc


def descriptions(c, acc):
    return sorted((t["description"], t["amount"]) for t in lines(c, acc))


def connection_in(c, connection_id):
    return next((x for x in c.get("/api/bank").json()["connections"] if x["id"] == connection_id), None)


@pytest.fixture
def teller_user(app_started, teller_fake, switched_on):
    c, u = register(app_started)
    return c, u, connect_teller(c)


@pytest.fixture
def plaid_user(app_started, plaid_fake, switched_on):
    c, u = register(app_started)
    return c, u, connect_plaid(c, plaid_fake)


@pytest.fixture
def mixed_user(app_started, teller_fake, simplefin_fake, switched_on):
    """A user with a SimpleFIN connection and a Teller one, each matched to
    an account of their own."""
    c, u = register(app_started)
    sf = connect_simplefin(c, simplefin_fake)
    tl = connect_teller(c)
    sf_acc = linked(c, sf, "Everyday Checking", "SimpleFIN checking")
    tl_acc = linked(c, tl, "Teller Checking", "Teller checking")
    return c, u, {"sf": sf, "tl": tl, "sf_acc": sf_acc, "tl_acc": tl_acc}


# ---------- What an instance offers ----------

def test_admin_shows_which_providers_the_instance_offers(admin, monkeypatch):
    ac, _ = admin
    assert ac.get("/api/admin/bank-sync").json()["providers"] == {
        "simplefin": True, "teller": False, "plaid": False}
    monkeypatch.setenv("TELLER_APP_ID", "app_test")
    monkeypatch.setenv("TELLER_ENV", "sandbox")
    monkeypatch.setenv("PLAID_CLIENT_ID", "plaid_client")
    monkeypatch.setenv("PLAID_SECRET", "plaid_secret")
    assert ac.get("/api/admin/bank-sync").json()["providers"] == {
        "simplefin": True, "teller": True, "plaid": True}


def test_bank_status_lists_each_provider_as_available_or_not(app_started, switched_on, monkeypatch):
    c, _ = register(app_started)
    got = {p["key"]: p["available"] for p in c.get("/api/bank").json()["providers"]}
    assert got == {"simplefin": True, "teller": False, "plaid": False}
    monkeypatch.setenv("PLAID_CLIENT_ID", "plaid_client")
    monkeypatch.setenv("PLAID_SECRET", "plaid_secret")
    got = {p["key"]: p["available"] for p in c.get("/api/bank").json()["providers"]}
    assert got == {"simplefin": True, "teller": False, "plaid": True}


# ---------- Connecting Teller ----------

def test_teller_cannot_be_started_when_not_configured(app_started, switched_on):
    c, _ = register(app_started)
    r = start(c, "teller")
    assert r.status_code == 400 and "isn't set up" in r.json()["detail"]


def test_starting_teller_gives_its_page_with_the_attempt(app_started, teller_fake, switched_on):
    c, _ = register(app_started)
    r = start(c, "teller")
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["provider"] == "teller" and body["attempt"] and body["expires_at"].endswith("Z")
    assert body["url"] == f"/bank/teller?attempt={body['attempt']}"


def test_teller_setup_gives_what_connect_needs(app_started, teller_fake, switched_on):
    c, _ = register(app_started)
    attempt = start(c, "teller").json()["attempt"]
    r = c.get("/api/bank/teller/setup", params={"attempt": attempt})
    assert r.status_code == 200, r.text
    got = r.json()
    assert got["application_id"] == "app_test" and got["environment"] == "sandbox"
    assert len(got["nonce"]) >= 16


def test_enrolling_makes_a_teller_connection_and_the_check_says_done(app_started, teller_fake, switched_on):
    c, _ = register(app_started)
    attempt = start(c, "teller").json()["attempt"]
    r = c.post("/api/bank/teller/enroll", json={"attempt": attempt, "access_token": TELLER_TOKEN})
    assert r.status_code == 200, r.text
    assert r.json()["name"] == "Teller Bank" and r.json()["accounts"] == 1
    [conn] = c.get("/api/bank").json()["connections"]
    assert conn["id"] == r.json()["connection_id"]
    assert (conn["provider"], conn["name"]) == ("teller", "Teller Bank")
    [acc] = [a for a in c.get("/api/bank").json()["accounts"] if a["connection_id"] == conn["id"]]
    assert acc["name"] == "Teller Checking ··1234" and acc["org"] == "Teller Bank"
    check = c.post("/api/bank/connect/check", json={"attempt": attempt}).json()
    assert check["state"] == "done" and check["connection_id"] == conn["id"]
    # The token is sent as the Basic user name, and never shown back.
    assert teller_fake.requests[0].headers["authorization"] == \
        "Basic " + base64.b64encode(f"{TELLER_TOKEN}:".encode()).decode()
    assert TELLER_TOKEN not in c.get("/api/bank").text


def test_the_check_says_waiting_until_teller_has_handed_over(app_started, teller_fake, switched_on):
    c, _ = register(app_started)
    attempt = start(c, "teller").json()["attempt"]
    assert c.post("/api/bank/connect/check", json={"attempt": attempt}).json() == {"state": "waiting"}


def test_enrolling_twice_on_one_attempt_is_a_conflict(app_started, teller_fake, switched_on):
    c, _ = register(app_started)
    attempt = start(c, "teller").json()["attempt"]
    body = {"attempt": attempt, "access_token": TELLER_TOKEN}
    assert c.post("/api/bank/teller/enroll", json=body).status_code == 200
    assert c.post("/api/bank/teller/enroll", json=body).status_code == 409
    assert len(c.get("/api/bank").json()["connections"]) == 1


def test_another_users_attempt_is_not_found(app_started, teller_fake, switched_on):
    c, _ = register(app_started)
    other, _ = register(app_started)
    attempt = start(c, "teller").json()["attempt"]
    assert other.get("/api/bank/teller/setup", params={"attempt": attempt}).status_code == 404
    r = other.post("/api/bank/teller/enroll", json={"attempt": attempt, "access_token": TELLER_TOKEN})
    assert r.status_code == 404
    assert other.post("/api/bank/connect/check", json={"attempt": attempt}).status_code == 404
    assert other.get("/api/bank").json()["connections"] == []


def test_a_token_teller_refuses_makes_no_connection(app_started, teller_fake, switched_on):
    teller_fake.mode = "refused"
    c, _ = register(app_started)
    attempt = start(c, "teller").json()["attempt"]
    r = c.post("/api/bank/teller/enroll", json={"attempt": attempt, "access_token": "refused_token_1"})
    assert r.status_code == 400
    assert c.get("/api/bank").json()["connections"] == []
    assert c.post("/api/bank/connect/check", json={"attempt": attempt}).json()["state"] == "waiting"


def test_starting_with_bank_sync_off_is_refused(app_started, teller_fake):
    set_switch(False)
    c, _ = register(app_started)
    assert start(c, "teller").status_code == 403
    assert teller_fake.requests == []


# ---------- The Teller Connect page ----------

def test_the_teller_page_alone_may_load_tellers_script(app_started):
    c, _ = register(app_started)
    home = c.get("/")
    if home.status_code != 200:
        pytest.skip("the web client isn't in this image")
    page = c.get("/bank/teller")
    assert page.status_code == 200
    csp = page.headers["content-security-policy"]
    script_src = next(p for p in csp.split(";") if p.strip().startswith("script-src"))
    assert "https://cdn.teller.io" in script_src
    assert "cdn.teller.io" not in home.headers.get("content-security-policy", "")


# ---------- Teller sync ----------

def test_teller_sync_lands_posted_lines_once(teller_user, teller_fake):
    c, _, conn = teller_user
    acc = linked(c, conn, "Teller Checking")
    r = c.post("/api/bank/sync")
    assert r.status_code == 200, r.text
    assert (r.json()["added"], r.json()["skipped"]) == (2, 0)
    # Posted only, amounts as Teller gives them, nothing before the start date.
    assert descriptions(c, acc) == [("CORNER GROCERY", -42.5), ("PAYROLL ACME", 2500.0)]
    sent = teller_fake.calls("GET", "/transactions")[0].url.params
    assert sent["start_date"] == day(10) and sent["count"]
    again = c.post("/api/bank/sync").json()
    assert (again["added"], again["skipped"]) == (0, 2)
    assert len(lines(c, acc)) == 2


def test_teller_sync_follows_pages_with_from_id(teller_user, teller_fake, monkeypatch):
    from app import teller
    monkeypatch.setattr(teller, "PAGE", 2)
    teller_fake.transactions = [
        {"id": f"txn_{n}", "date": day(n), "amount": f"-{n}.00", "status": "posted",
         "description": f"SHOP {n}"} for n in range(1, 6)]
    c, _, conn = teller_user
    acc = linked(c, conn, "Teller Checking")
    assert c.post("/api/bank/sync").json()["added"] == 5
    assert len(lines(c, acc)) == 5
    asked = teller_fake.calls("GET", "/transactions")
    assert "from_id" not in asked[0].url.params
    assert [q.url.params["from_id"] for q in asked[1:]] == ["txn_2", "txn_4"]


def test_a_teller_bank_asking_for_a_new_sign_in_needs_a_reconnect(teller_user, teller_fake):
    c, _, conn = teller_user
    linked(c, conn, "Teller Checking")
    teller_fake.mode = "revoked"
    r = c.post("/api/bank/sync")
    assert r.status_code == 409 and "sign in again" in r.json()["detail"]
    status = c.get("/api/bank/status").json()
    assert status["needs_reconnect"] is True and status["last_sync_ok"] is False


# ---------- Connecting Plaid ----------

def test_plaid_start_gives_the_hosted_link(app_started, plaid_fake, switched_on):
    c, _ = register(app_started)
    r = start(c, "plaid")
    assert r.status_code == 200, r.text
    assert r.json()["url"] == "https://secure.plaid.com/hl/abc" and r.json()["attempt"]
    [body] = plaid_fake.bodies_for("/link/token/create")
    assert isinstance(body["hosted_link"], dict) and body["products"] == ["transactions"]


def test_plaid_cannot_be_started_when_not_configured(app_started, switched_on):
    c, _ = register(app_started)
    assert start(c, "plaid").status_code == 400


def test_plaid_check_waits_then_reports_exited(app_started, plaid_fake, switched_on):
    c, _ = register(app_started)
    attempt = start(c, "plaid").json()["attempt"]
    assert c.post("/api/bank/connect/check", json={"attempt": attempt}).json() == {"state": "waiting"}
    plaid_fake.sessions = [{"finished_at": "2026-11-20T12:00:00Z"}]
    assert c.post("/api/bank/connect/check", json={"attempt": attempt}).json() == {"state": "exited"}
    assert c.get("/api/bank").json()["connections"] == []
    assert plaid_fake.bodies_for("/item/public_token/exchange") == []


def test_plaid_check_with_a_public_token_makes_the_connection_once(app_started, plaid_fake, switched_on):
    c, _ = register(app_started)
    plaid_fake.sessions = [plaid_done_session()]
    attempt = start(c, "plaid").json()["attempt"]
    first = c.post("/api/bank/connect/check", json={"attempt": attempt}).json()
    assert first["state"] == "done"
    for _ in range(2):
        again = c.post("/api/bank/connect/check", json={"attempt": attempt}).json()
        assert again["state"] == "done" and again["connection_id"] == first["connection_id"]
    [conn] = c.get("/api/bank").json()["connections"]
    assert (conn["provider"], conn["name"]) == ("plaid", "Plaid Bank")
    assert [a["name"] for a in c.get("/api/bank").json()["accounts"]] == ["Plaid Checking ··0000"]
    assert plaid_fake.bodies_for("/item/public_token/exchange") == [{"public_token": "public-sandbox-1"}]
    assert PLAID_ACCESS not in c.get("/api/bank").text


# ---------- Plaid sync ----------

def test_plaid_first_sync_follows_has_more_and_turns_the_sign_round(plaid_user, plaid_fake):
    c, _, conn = plaid_user
    acc = linked(c, conn, "Plaid Checking")
    r = c.post("/api/bank/sync")
    assert r.status_code == 200, r.text
    assert r.json()["added"] == 2
    # Plaid's money out is positive; here it's negative. Pending and old ones stay out.
    assert descriptions(c, acc) == [("CORNER GROCERY", -42.5), ("PAYROLL ACME", 2500.0)]
    sent = plaid_fake.bodies_for("/transactions/sync")
    assert "cursor" not in sent[0] and sent[1]["cursor"] == "c1"


def test_plaid_next_sync_sends_the_stored_cursor_and_adds_only_new_lines(plaid_user, plaid_fake):
    c, _, conn = plaid_user
    acc = linked(c, conn, "Plaid Checking")
    c.post("/api/bank/sync")
    plaid_fake.bodies.clear()
    r = c.post("/api/bank/sync")
    assert r.status_code == 200, r.text
    assert r.json()["added"] == 1
    assert [b.get("cursor") for b in plaid_fake.bodies_for("/transactions/sync")] == ["c2"]
    assert ("NEW SANDWICH", -12.0) in descriptions(c, acc)
    assert len(lines(c, acc)) == 3


def test_plaid_still_gathering_history_asks_to_try_later(plaid_user, plaid_fake):
    plaid_fake.pages[""] = {"accounts": plaid_fake.accounts, "added": [], "has_more": False,
                            "next_cursor": "", "transactions_update_status": "NOT_READY"}
    c, _, conn = plaid_user
    linked(c, conn, "Plaid Checking")
    r = c.post("/api/bank/sync")
    assert r.status_code == 409 and "still gathering" in r.json()["detail"]


def test_plaid_needing_the_login_again_needs_a_reconnect(plaid_user, plaid_fake):
    c, _, conn = plaid_user
    linked(c, conn, "Plaid Checking")
    plaid_fake.error = plaid_login_required()
    r = c.post("/api/bank/sync")
    assert r.status_code == 409
    assert c.get("/api/bank/status").json()["needs_reconnect"] is True


# ---------- Many connections ----------

def test_both_connections_are_listed_and_the_status_keeps_its_old_keys(mixed_user):
    c, _, ids = mixed_user
    listed = c.get("/api/bank").json()["connections"]
    assert [(x["id"], x["provider"]) for x in listed] == [(ids["sf"], "simplefin"), (ids["tl"], "teller")]
    status = c.get("/api/bank/status").json()
    for key in ("enabled", "connected", "linked_account_ids", "last_sync_at", "last_sync_ok",
                "last_sync_status", "needs_reconnect", "failing_over_a_day", "next_sync_at",
                "syncs_left_today", "sync_wait_seconds"):
        assert key in status, key
    assert len(status["connections"]) == 2
    assert sorted(status["linked_account_ids"]) == sorted([ids["sf_acc"], ids["tl_acc"]])


def test_sync_with_no_body_syncs_every_connection_and_sums_them(mixed_user):
    c, _, ids = mixed_user
    r = c.post("/api/bank/sync")
    assert r.status_code == 200, r.text
    assert r.json()["added"] == 4
    assert len(lines(c, ids["sf_acc"])) == 2 and len(lines(c, ids["tl_acc"])) == 2
    assert len(r.json()["status"]["connections"]) == 2


def test_sync_with_a_connection_id_syncs_only_that_one(mixed_user, simplefin_fake):
    c, _, ids = mixed_user
    r = c.post("/api/bank/sync", json={"connection_id": ids["tl"]})
    assert r.status_code == 200, r.text
    assert r.json()["added"] == 2
    assert len(lines(c, ids["tl_acc"])) == 2 and lines(c, ids["sf_acc"]) == []
    assert connection_in(c, ids["sf"])["last_sync_at"] is None
    assert simplefin_fake.requests[-1].url.params.get("balances-only") == "1"   # only the listing


def test_one_connection_failing_leaves_the_other_synced(mixed_user, teller_fake):
    c, _, ids = mixed_user
    teller_fake.mode = "down"
    r = c.post("/api/bank/sync")
    assert r.status_code == 200, r.text
    assert r.json()["added"] == 2
    assert any("Couldn't reach Teller" in m for m in r.json()["messages"])
    assert len(lines(c, ids["sf_acc"])) == 2 and lines(c, ids["tl_acc"]) == []
    assert connection_in(c, ids["tl"])["last_sync_ok"] is False
    assert connection_in(c, ids["sf"])["last_sync_ok"] is True


def test_every_connection_failing_is_an_error(mixed_user, teller_fake, simplefin_fake):
    c, _, _ = mixed_user
    teller_fake.mode = "down"
    simplefin_fake.down = True
    assert c.post("/api/bank/sync").status_code == 502


# ---------- One link per account ----------

def test_an_account_cannot_take_lines_from_two_bank_accounts(mixed_user):
    c, _, ids = mixed_user
    before = bank_account(c, ids["tl"], "Teller Checking")
    assert before["account_id"] == ids["tl_acc"]
    r = link_to(c, ids["sf"], "Savings", ids["tl_acc"])
    assert r.status_code == 400
    assert "Teller Bank" in r.json()["detail"]
    after = bank_account(c, ids["tl"], "Teller Checking")
    assert after["account_id"] == ids["tl_acc"] and after["start_date"] == before["start_date"]
    assert bank_account(c, ids["sf"], "Savings")["account_id"] is None


# ---------- Disconnecting ----------

def test_disconnect_must_say_which_connection_when_there_are_two(mixed_user):
    c, _, _ = mixed_user
    assert c.post("/api/bank/disconnect", json={}).status_code == 400
    assert len(c.get("/api/bank").json()["connections"]) == 2


def test_disconnecting_another_users_connection_is_not_found(mixed_user, app_started):
    c, _, ids = mixed_user
    other, _ = register(app_started)
    assert other.post("/api/bank/disconnect", json={"connection_id": ids["tl"]}).status_code == 404
    assert len(c.get("/api/bank").json()["connections"]) == 2


def test_disconnecting_teller_ends_it_at_teller(mixed_user, teller_fake):
    c, _, ids = mixed_user
    r = c.post("/api/bank/disconnect", json={"connection_id": ids["tl"]})
    assert r.status_code == 200, r.text
    assert "warning" not in r.json()
    assert [x["id"] for x in r.json()["connections"]] == [ids["sf"]]
    [gone] = teller_fake.calls("DELETE", "/accounts")
    assert gone.headers["authorization"] == "Basic " + base64.b64encode(f"{TELLER_TOKEN}:".encode()).decode()


def test_disconnecting_plaid_removes_the_item(app_started, plaid_fake, simplefin_fake, switched_on):
    c, _ = register(app_started)
    sf = connect_simplefin(c, simplefin_fake)
    pl = connect_plaid(c, plaid_fake)
    r = c.post("/api/bank/disconnect", json={"connection_id": pl})
    assert r.status_code == 200, r.text
    assert [x["id"] for x in r.json()["connections"]] == [sf]
    assert plaid_fake.bodies_for("/item/remove") == [{"access_token": PLAID_ACCESS}]


def test_teller_unreachable_on_disconnect_still_disconnects_with_a_warning(mixed_user, teller_fake):
    c, _, ids = mixed_user
    teller_fake.mode = "down"
    r = c.post("/api/bank/disconnect", json={"connection_id": ids["tl"]})
    assert r.status_code == 200, r.text
    assert "Teller" in r.json()["warning"]
    assert [x["id"] for x in r.json()["connections"]] == [ids["sf"]]


def test_deleting_the_user_ends_their_connections_at_the_providers(app_started, teller_fake, plaid_fake,
                                                                  switched_on):
    c, u = register(app_started)
    connect_teller(c)
    connect_plaid(c, plaid_fake)
    r = c.request("DELETE", "/api/me", json={"password": PASSWORD})
    assert r.status_code == 200, r.text
    assert len(teller_fake.calls("DELETE", "/accounts")) == 1
    assert plaid_fake.bodies_for("/item/remove") == [{"access_token": PLAID_ACCESS}]


# ---------- Backups ----------

@pytest.fixture
def two_providers(app_started, teller_fake, plaid_fake, switched_on):
    """A user with a synced Teller connection and a synced Plaid one."""
    c, u = register(app_started)
    tl, pl = connect_teller(c), connect_plaid(c, plaid_fake)
    linked(c, tl, "Teller Checking", "Checking")
    linked(c, pl, "Plaid Checking", "Savings")
    assert c.post("/api/bank/sync").status_code == 200
    return c, u


def test_sealed_backup_holds_the_tokens_and_the_plain_one_does_not(two_providers):
    from app.backup import open_sealed
    c, _ = two_providers
    plain = c.get("/api/backup/export")
    assert "bank_connections" not in plain.json()
    assert TELLER_TOKEN not in plain.text and PLAID_ACCESS not in plain.text
    sealed = c.post("/api/backup/export", json={"passphrase": BACKUP_PASSPHRASE}).json()
    banks = {b["provider"]: b for b in open_sealed(sealed, BACKUP_PASSPHRASE)["bank_connections"]}
    assert set(banks) == {"teller", "plaid"}
    assert banks["teller"]["access_token"] == TELLER_TOKEN
    assert banks["plaid"]["access_token"] == PLAID_ACCESS and banks["plaid"]["cursor"] == "c2"
    assert [l["account_name"] for l in banks["teller"]["links"]] == ["Checking"]


def test_importing_the_sealed_backup_restores_both_connections(app_started, two_providers, plaid_fake):
    c, _ = two_providers
    sealed = c.post("/api/backup/export", json={"passphrase": BACKUP_PASSPHRASE}).json()
    other, _ = register(app_started)
    r = other.post("/api/backup/import", json={"payload": sealed, "passphrase": BACKUP_PASSPHRASE})
    assert r.status_code == 200, r.text
    assert r.json()["imported"]["bank_connection"] == 2
    conns = other.get("/api/bank").json()["connections"]
    assert sorted(x["provider"] for x in conns) == ["plaid", "teller"]
    assert sorted(x["name"] for x in conns) == ["Plaid Bank", "Teller Bank"]
    # The matches came back with their accounts. Teller's lines keep their
    # bank ids, so its sync adds nothing; Plaid's cursor came back too, so its
    # sync asks from "c2" and gets only the newer line.
    assert all(x["linked_account_ids"] for x in conns)
    by = {x["provider"]: x["id"] for x in conns}
    assert other.post("/api/bank/sync", json={"connection_id": by["teller"]}).json()["added"] == 0
    assert other.post("/api/bank/sync", json={"connection_id": by["plaid"]}).json()["added"] == 1
    assert plaid_fake.bodies_for("/transactions/sync")[-1].get("cursor") == "c2"


def test_an_old_backup_with_one_simplefin_connection_still_imports(app_started, simplefin_fake, switched_on):
    from app.backup import open_sealed, seal
    c, _ = register(app_started)
    sf = connect_simplefin(c, simplefin_fake)
    linked(c, sf, "Everyday Checking")
    sealed = c.post("/api/backup/export", json={"passphrase": BACKUP_PASSPHRASE}).json()
    inside = open_sealed(sealed, BACKUP_PASSPHRASE)
    [only] = inside.pop("bank_connections")
    assert "access_url" in only and only["links"]
    inside["bank_connection"] = only   # the shape from before many connections
    legacy = seal(inside, BACKUP_PASSPHRASE)
    other, _ = register(app_started)
    r = other.post("/api/backup/import", json={"payload": legacy, "passphrase": BACKUP_PASSPHRASE})
    assert r.status_code == 200, r.text
    assert r.json()["imported"]["bank_connection"] == 1
    [conn] = other.get("/api/bank").json()["connections"]
    assert conn["provider"] == "simplefin" and conn["linked_account_ids"]
