"""Connecting a bank from the iPhone app (bank-providers phase 5, #258).

The app opens /app-connect-bank in the phone's sign-in sheet, which shares
Safari's sign-in. The page starts Teller or Plaid with {app: true}: Teller's
page gets ?app=1, and Plaid's Hosted Link is told to come back to
/app-connect-bank?attempt=<id> on this server (completion_redirect_uri), where
the page checks how it went and hands the app only the connection's number.
Connecting stays browser-only (test_security_guards.py). Uses the stand-in
Teller and Plaid from test_bank_providers.py.
"""
import pytest
from fastapi.testclient import TestClient

from test_bank_providers import (TELLER_TOKEN, no_provider_keys, plaid_done_session, plaid_fake,  # noqa: F401
                                 start, switched_on, teller_fake)
from test_bank_sync import register


def start_app(c, provider, **headers):
    return c.post("/api/bank/connect/start", json={"provider": provider, "app": True}, headers=headers)


def hosted_link(fake):
    return fake.bodies_for("/link/token/create")[-1]["hosted_link"]


# ---------- The page ----------

def test_the_page_is_served_with_its_own_strict_policy(app_started):
    c = TestClient(app_started)
    r = c.get("/app-connect-bank")
    assert r.status_code == 200 and r.headers["content-type"].startswith("text/html")
    assert r.headers["cache-control"] == "no-cache"
    csp = r.headers["content-security-policy"]
    assert "script-src 'self';" in csp and "frame-ancestors 'none'" in csp
    assert "teller" not in csp and "unsafe-inline' " not in csp.split("script-src")[1].split(";")[0]
    assert '<script src="/static/app-connect-bank.js"></script>' in r.text
    assert "<script>" not in r.text          # nothing inline, which the policy would block
    js = c.get("/static/app-connect-bank.js")
    assert js.status_code == 200 and "walletweather://bank-connected?" in js.text


def test_google_sign_in_may_return_to_the_page_and_nowhere_else():
    from app.main import _safe_next
    assert _safe_next("/app-connect-bank") == "/app-connect-bank"
    assert _safe_next("/app-connect-bank?attempt=abc") == "/app-connect-bank?attempt=abc"
    for bad in ("/app-connect-bankx", "//evil.example/app-connect-bank", "/app-connect-bank\\@evil.example",
                "https://evil.example/app-connect-bank"):
        assert _safe_next(bad) is None, bad


# ---------- Starting from the app ----------

def test_plaid_started_from_the_app_comes_back_to_the_page_on_this_server(app_started, plaid_fake, switched_on):
    from app import main
    c, _ = register(app_started)
    r = start_app(c, "plaid")
    assert r.status_code == 200, r.text
    attempt = r.json()["attempt"]
    base = main.APP_BASE_URL.strip().rstrip("/")
    assert hosted_link(plaid_fake)["completion_redirect_uri"] == f"{base}/app-connect-bank?attempt={attempt}"
    # Not as a mobile app: that would need a registered Universal Link (decided 2026-11-21).
    assert "is_mobile_app" not in hosted_link(plaid_fake)
    assert "redirect_uri" not in plaid_fake.bodies_for("/link/token/create")[-1]


def test_the_page_address_follows_the_address_the_browser_used(app_started, plaid_fake, switched_on):
    c, _ = register(app_started)
    # The test client's own host, as a browser on this server would send it.
    r = start_app(c, "plaid", origin="http://testserver")
    assert r.status_code == 200, r.text
    assert hosted_link(plaid_fake)["completion_redirect_uri"] == \
        f"http://testserver/app-connect-bank?attempt={r.json()['attempt']}"


def test_another_sites_page_cant_start_one_or_choose_where_plaid_returns(app_started, plaid_fake, switched_on):
    c, _ = register(app_started)
    r = start_app(c, "plaid", origin="https://evil.example")
    assert r.status_code == 403
    assert plaid_fake.bodies_for("/link/token/create") == []


def test_plaid_started_from_settings_is_unchanged(app_started, plaid_fake, switched_on):
    c, _ = register(app_started)
    assert start(c, "plaid").status_code == 200
    assert "completion_redirect_uri" not in hosted_link(plaid_fake)


def test_teller_started_from_the_app_tells_its_page_so(app_started, teller_fake, switched_on):
    c, _ = register(app_started)
    r = start_app(c, "teller")
    assert r.status_code == 200, r.text
    assert r.json()["url"] == f"/bank/teller?attempt={r.json()['attempt']}&app=1"


def test_a_plaid_connection_from_the_app_finishes_when_the_page_checks_back(app_started, plaid_fake, switched_on):
    c, _ = register(app_started)
    attempt = start_app(c, "plaid").json()["attempt"]
    plaid_fake.sessions = [plaid_done_session()]
    r = c.post("/api/bank/connect/check", json={"attempt": attempt})
    assert r.status_code == 200 and r.json()["state"] == "done", r.text
    conn = r.json()["connection_id"]
    status = c.get("/api/bank/status").json()
    assert [x["id"] for x in status["connections"]] == [conn]
    assert status["connections"][0]["provider"] == "plaid"


def test_leaving_plaid_without_a_bank_reads_as_exited(app_started, plaid_fake, switched_on):
    c, _ = register(app_started)
    attempt = start_app(c, "plaid").json()["attempt"]
    plaid_fake.sessions = [{"finished_at": "2026-11-21T12:00:00Z", "results": {}}]
    assert c.post("/api/bank/connect/check", json={"attempt": attempt}).json()["state"] == "exited"


def test_a_teller_connection_from_the_app_is_saved_as_from_settings(app_started, teller_fake, switched_on):
    c, _ = register(app_started)
    attempt = start_app(c, "teller").json()["attempt"]
    r = c.post("/api/bank/teller/enroll", json={"attempt": attempt, "access_token": TELLER_TOKEN})
    assert r.status_code == 200, r.text
    assert c.post("/api/bank/connect/check", json={"attempt": attempt}).json()["state"] == "done"


@pytest.mark.parametrize("provider", ["teller", "plaid"])
def test_the_apps_token_still_cant_start_a_connection(app_started, teller_fake, plaid_fake, switched_on, provider):
    c, _ = register(app_started)
    token = c.post("/api/tokens", json={"name": "phone", "access": "full"}).json()["token"]
    phone = TestClient(app_started)
    r = phone.post("/api/bank/connect/start", json={"provider": provider, "app": True},
                   headers={"Authorization": f"Bearer {token}"})
    assert r.status_code == 403
