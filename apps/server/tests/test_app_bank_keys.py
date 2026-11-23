"""Your own Teller and Plaid keys from the iPhone app (own-bank-keys phase 3, #278).

Decided 2026-11-23: the app opens /app-bank-keys in the phone's sign-in
sheet, which shares Safari's sign-in; the page saves, replaces or removes
keys through the browser-only routes of phase 1 (a fresh two-factor code,
never the app's token) and hands back only walletweather://bank-keys?state=.
GET /api/bank/status, which the app reads with its token, says which
services the person is ticked for (`providers_ticked`) and which of Teller
and Plaid have their own keys (`own_keys`: the environment only, never the
id or the secret). Every call goes to the stand-in Plaid, never the network.
"""
import httpx
import pytest
from fastapi.testclient import TestClient

from test_bank_providers import FakePlaid, no_provider_keys  # noqa: F401
from test_bank_sync import allow_bank, register, set_switch

PLAID_SECRET = "plaid_secret"


@pytest.fixture
def plaid_stand_in(monkeypatch):
    """The stand-in Plaid without handing anyone keys."""
    from app import plaid
    f = FakePlaid()
    monkeypatch.setattr(plaid, "_transport", httpx.MockTransport(f.handler))
    return f


@pytest.fixture
def fresh(app_started):
    """A signed-in person ticked for every provider, with no keys, and bank
    sync switched on."""
    set_switch(True)
    yield register(app_started)
    set_switch(False)


def save_plaid(c, **extra):
    return c.put("/api/bank/keys/plaid", json={"client_id": "plaid_client", "secret": PLAID_SECRET,
                                               "environment": "sandbox", **extra})


def token_client(app, c, access="full"):
    r = c.post("/api/tokens", json={"name": "iPhone", "access": access, "expires_in_days": 30})
    assert r.status_code == 200, r.text
    return TestClient(app, headers={"Authorization": f"Bearer {r.json()['token']}"})


# ---------- The page ----------

def test_the_page_is_served_with_its_own_strict_policy(app_started):
    c = TestClient(app_started)
    r = c.get("/app-bank-keys")
    assert r.status_code == 200 and r.headers["content-type"].startswith("text/html")
    assert r.headers["cache-control"] == "no-cache"
    csp = r.headers["content-security-policy"]
    assert "script-src 'self';" in csp and "frame-ancestors 'none'" in csp and "form-action 'self'" in csp
    assert "teller" not in csp and "plaid" not in csp
    assert '<script src="/static/app-bank-keys.js"></script>' in r.text
    assert "<script>" not in r.text          # nothing inline, which the policy would block
    js = c.get("/static/app-bank-keys.js")
    assert js.status_code == 200
    assert "walletweather://bank-keys?" in js.text
    # It saves through the browser-only routes, and never with a token.
    for route in ("/api/bank/keys/", "/api/bank/keys/remove"):
        assert route in js.text
    assert "Bearer" not in js.text and "Authorization" not in js.text


def test_google_sign_in_may_return_to_the_page_and_nowhere_else():
    from app.main import _safe_next
    assert _safe_next("/app-bank-keys") == "/app-bank-keys"
    for bad in ("/app-bank-keysx", "//evil.example/app-bank-keys", "/app-bank-keys\\@evil.example",
                "https://evil.example/app-bank-keys"):
        assert _safe_next(bad) is None, bad


# ---------- What the app reads ----------

def test_the_status_says_who_is_ticked_and_which_services_have_keys(app_started, fresh, plaid_stand_in):
    c, u = fresh
    st = c.get("/api/bank/status").json()
    assert st["providers_ticked"] == ["simplefin", "teller", "plaid"]
    assert st["own_keys"] == {"teller": None, "plaid": None}
    assert "plaid" not in st["providers_allowed"]           # ticked, but no keys yet
    assert save_plaid(c).status_code == 200
    # The app reads it with its token: the environment only.
    app_client = token_client(app_started, c, access="read")
    r = app_client.get("/api/bank/status")
    assert r.status_code == 200, r.text
    assert r.json()["own_keys"] == {"teller": None, "plaid": {"environment": "sandbox"}}
    assert "plaid" in r.json()["providers_allowed"]
    assert "plaid_client" not in r.text and PLAID_SECRET not in r.text


def test_an_unticked_person_is_ticked_for_nothing_and_an_admin_for_everything(app_started, fresh):
    from app import main
    c, u = fresh
    allow_bank(u["id"], [])
    st = c.get("/api/bank/status").json()
    assert st["providers_ticked"] == [] and st["own_keys"] == {"teller": None, "plaid": None}
    main.ADMIN_EMAILS.add(u["email"])
    try:
        assert c.get("/api/bank/status").json()["providers_ticked"] == ["simplefin", "teller", "plaid"]
    finally:
        main.ADMIN_EMAILS.discard(u["email"])


def test_removing_keys_shows_in_the_status(app_started, fresh, plaid_stand_in):
    c, _ = fresh
    assert save_plaid(c).status_code == 200
    r = c.post("/api/bank/keys/remove", json={"provider": "plaid"})
    assert r.status_code == 200, r.text
    assert c.get("/api/bank/status").json()["own_keys"]["plaid"] is None


# ---------- Keys never go with the app's token ----------

def test_the_apps_token_cant_save_or_remove_keys(app_started, fresh, plaid_stand_in):
    c, u = fresh
    app_client = token_client(app_started, c)
    r = save_plaid(app_client)
    assert r.status_code in (401, 403), r.text
    assert plaid_stand_in.requests == []                    # not even checked with Plaid
    assert save_plaid(c).status_code == 200                 # the browser's session can
    r = app_client.post("/api/bank/keys/remove", json={"provider": "plaid"})
    assert r.status_code in (401, 403), r.text
    assert c.get("/api/bank/status").json()["own_keys"]["plaid"] == {"environment": "sandbox"}


def test_the_status_without_a_sign_in_is_refused(app_started):
    assert TestClient(app_started).get("/api/bank/status").status_code == 401
