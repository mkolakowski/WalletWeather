"""The open findings of the 2026-11-16 security review (#178, #179), one test
each, written as the behaviour the fix should give.

Every test here is marked `xfail(strict=True)`: it fails today, which is the
finding, and the run stays green. When a fix lands, its test starts passing,
strict mode turns that into a failure, and the marker comes off in the same
commit. From then on the test guards the fix like any other.

The ids (WW-SEC-01 ...) are the review's; Plans/security-fixes.md says which
phase closes each. A fixed finding's tests move to test_security_fixes.py. A test marked "design" assumes an answer to one of the
plan's open questions and is rewritten if the answer differs.

Run them as they'd run once fixed, to see each finding fail for its own
reason:  ... run --rm tests tests/test_security_findings.py --runxfail
"""
import os
import subprocess
import sys
import uuid
from datetime import date
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from conftest import unique_email

PASSWORD = "correct-horse-battery"
TODAY = date.today().isoformat()
SERVER_DIR = Path(__file__).resolve().parent.parent


def finding(ref, why, design=False):
    return pytest.mark.xfail(strict=True, reason=f"{ref}{' (design)' if design else ''}: {why}")


def register(app, email=None, **extra):
    # A server error is an answer here (500), not an exception in the test.
    c = TestClient(app, raise_server_exceptions=False)
    email = email or unique_email()
    r = c.post("/api/auth/register", json={"email": email, "password": PASSWORD, **extra})
    assert r.status_code == 200, r.text
    return c, {"email": email, "id": r.json()["id"]}


def make_account(c, name="Checking"):
    r = c.post("/api/accounts", json={"name": name, "starting_balance": 100,
                                      "starting_date": TODAY})
    assert r.status_code == 200, r.text
    return r.json()["id"]


REFUSED = (400, 403, 404, 409, 413, 422)
# What a colour field could carry into a page that puts it inside an
# attribute: 20 characters, the column's size.
NOT_A_COLOUR = '"onclick=eval(name) '


# ---------- WW-SEC-03: sessions can't be ended from elsewhere ----------

@finding("WW-SEC-03", "a password change leaves the user's other sessions signed in")
def test_changing_the_password_signs_out_other_browsers(app_started):
    here, user = register(app_started)
    there = TestClient(app_started)
    r = there.post("/api/auth/login", json={"email": user["email"], "password": PASSWORD})
    assert r.status_code == 200 and there.get("/api/me").status_code == 200
    r = here.post("/api/me/password", json={"current_password": PASSWORD,
                                            "new_password": "a-brand-new-password"})
    assert r.status_code == 200, r.text
    assert there.get("/api/me").status_code == 401


@finding("WW-SEC-03", "an admin's password reset leaves the user's sessions signed in")
def test_an_admins_password_reset_signs_the_user_out(app_started):
    from app import main
    admin, admin_user = register(app_started)
    stolen, user = register(app_started)       # a session someone else holds
    main.ADMIN_EMAILS.add(admin_user["email"])
    try:
        r = admin.patch(f"/api/admin/users/{user['id']}", json={"new_password": "reset-by-admin-1"})
        assert r.status_code == 200, r.text
    finally:
        main.ADMIN_EMAILS.discard(admin_user["email"])
    assert stolen.get("/api/me").status_code == 401


# ---------- WW-SEC-06: everyone's address ----------

@finding("WW-SEC-06", "the Permissions panel lists every user's email and name", design=True)
def test_you_dont_see_the_addresses_of_people_you_share_nothing_with(app_started):
    _, stranger = register(app_started)
    c, _ = register(app_started)
    make_account(c)
    assert stranger["email"] not in c.get("/api/permissions").text


# ---------- WW-SEC-07 and -08: the browser's side ----------

@finding("WW-SEC-07", "a write from another site's page is only stopped by the cookie's SameSite")
def test_a_write_that_says_it_comes_from_another_site_is_refused(app_started):
    c, _ = register(app_started)
    r = c.post("/api/accounts", headers={"Origin": "https://evil.example"},
               json={"name": "x", "starting_balance": 0, "starting_date": TODAY})
    assert r.status_code == 403
    # The app's own page still works.
    r = c.post("/api/accounts", headers={"Origin": "http://testserver"},
               json={"name": "x", "starting_balance": 0, "starting_date": TODAY})
    assert r.status_code == 200


@finding("WW-SEC-08", "no security headers are sent")
def test_pages_and_answers_carry_the_security_headers(app_started):
    c, _ = register(app_started)
    for path in ("/", "/app-sign-in", "/api/me"):
        h = c.get(path).headers
        assert h.get("x-content-type-options") == "nosniff", path
        assert (h.get("x-frame-options", "").upper() in ("DENY", "SAMEORIGIN")
                or "frame-ancestors" in h.get("content-security-policy", "")), path
        assert h.get("referrer-policy"), path
    assert "no-store" in c.get("/api/me").headers.get("cache-control", "")


@finding("WW-SEC-08", "the API's own documentation pages are public")
@pytest.mark.parametrize("path", ["/docs", "/redoc", "/openapi.json"])
def test_the_api_docs_arent_served_to_strangers(app_started, path):
    assert TestClient(app_started).get(path).status_code in (401, 403, 404)


# ---------- WW-SEC-09: no upper limits ----------

@finding("WW-SEC-09", "the forecast window has no upper limit")
def test_a_forecast_window_has_an_upper_limit(app_started):
    # Checked with a signed-in user who has no such account, so today's
    # answer (404, after the window was accepted) costs nothing to get.
    c, _ = register(app_started)
    assert c.get("/api/accounts/999999999/forecast", params={"days": 4_000_000}).status_code in (400, 422)
    r = c.get("/api/accounts/999999999/forecast", params={"start": "0001-01-01", "end": "9999-12-31"})
    assert r.status_code in (400, 422)


@finding("WW-SEC-09", "names and descriptions have no length limit (a long one is a 500 or is stored)")
@pytest.mark.parametrize("what", ["user name", "account name", "category name", "description",
                                  "recurring description"])
def test_a_very_long_name_is_refused_politely(app_started, what):
    long = "x" * 5000
    c, _ = register(app_started)
    acc = make_account(c)
    if what == "user name":
        r = TestClient(app_started, raise_server_exceptions=False).post(
            "/api/auth/register", json={"email": unique_email(), "password": PASSWORD, "name": long})
    elif what == "account name":
        r = c.post("/api/accounts", json={"name": long, "starting_balance": 0, "starting_date": TODAY})
    elif what == "category name":
        r = c.post("/api/categories", json={"name": long})
    elif what == "description":
        r = c.post(f"/api/accounts/{acc}/transactions", json={"description": long, "amount": -1})
    else:
        r = c.post(f"/api/accounts/{acc}/recurring", json={
            "description": long, "amount": -1, "frequency": "weekly", "anchor_date": TODAY})
    assert r.status_code in (400, 413, 422), r.status_code


@finding("WW-SEC-09", "a request body can be any size")
def test_a_huge_request_is_refused(app_started):
    body = '{"email": "a@example.test", "password": "' + "x" * (32 * 1024 * 1024) + '"}'
    r = TestClient(app_started, raise_server_exceptions=False).post(
        "/api/auth/login", content=body, headers={"Content-Type": "application/json"})
    assert r.status_code == 413


# ---------- WW-SEC-11: values that break the pages that show them ----------

@finding("WW-SEC-11", "NaN and Infinity are accepted as amounts")
@pytest.mark.parametrize("amount", ["NaN", "Infinity", "-Infinity", "1e400"])
def test_an_amount_must_be_a_real_number(app_started, amount):
    c, _ = register(app_started)
    acc = make_account(c)
    r = c.post(f"/api/accounts/{acc}/transactions",
               content='{"description": "x", "amount": %s}' % amount,
               headers={"Content-Type": "application/json"})
    listing = c.get(f"/api/accounts/{acc}/transactions")
    assert r.status_code in (400, 422)
    assert listing.status_code == 200


@finding("WW-SEC-11", "a recurring item's frequency and day of the month aren't checked")
@pytest.mark.parametrize("fields", [
    {"frequency": "hourly", "anchor_date": TODAY},
    {"frequency": "monthly_day", "day_of_month": 99},
    {"frequency": "monthly_day", "day_of_month": 0},
    {"frequency": "monthly_day"},
    {"frequency": "weekly"},
])
def test_a_recurring_item_must_be_one_the_forecast_can_run(app_started, fields):
    c, _ = register(app_started)
    acc = make_account(c)
    r = c.post(f"/api/accounts/{acc}/recurring",
               json={"description": "x", "amount": -1, **fields})
    forecast = c.get(f"/api/accounts/{acc}/forecast")
    assert r.status_code in (400, 422)
    assert forecast.status_code == 200


# ---------- WW-SEC-12: secrets left as the template has them ----------

@finding("WW-SEC-12", "the server starts with the template's placeholder SESSION_SECRET")
@pytest.mark.parametrize("secret", ["replace_with_random_string", "short", ""])
def test_the_server_wont_start_with_a_guessable_session_secret(secret):
    env = {**os.environ, "SESSION_SECRET": secret}
    done = subprocess.run([sys.executable, "-c", "import app.main"], cwd=SERVER_DIR, env=env,
                          capture_output=True, text=True, timeout=60)
    assert done.returncode != 0
    assert "SESSION_SECRET" in done.stderr
