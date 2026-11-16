"""Fixes from the 2026-11-16 security review (#178), each guarded by the test
that failed before it (#183 in 1.62.0, #185 in 1.63.0, #187 in 1.64.0, #186 in 1.66.0, #189 in 1.67.0). The ids (WW-SEC-01 ...) are the
review's.
"""
import os
import subprocess
import sys
import uuid
from datetime import date
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from conftest import share_account, unique_email

PASSWORD = "correct-horse-battery"
TODAY = date.today().isoformat()
SERVER_DIR = Path(__file__).resolve().parent.parent
REFUSED = (400, 403, 404, 409, 413, 422)
# What a colour field could carry into a page that puts it inside an
# attribute: 20 characters, the column's size.
NOT_A_COLOUR = '"onclick=eval(name) '


def register(app, email=None, **extra):
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


@pytest.fixture
def admin(app_started):
    from app import main
    c, user = register(app_started)
    main.ADMIN_EMAILS.add(user["email"])
    yield c, user
    main.ADMIN_EMAILS.discard(user["email"])


# ---------- WW-SEC-01: a colour is any text ----------

@pytest.mark.parametrize("kind", ["categories", "tags"])
def test_a_colour_must_be_a_hex_colour(app_started, kind):
    c, _ = register(app_started)
    r = c.post(f"/api/{kind}", json={"name": "Odd", "color": NOT_A_COLOUR})
    assert r.status_code in REFUSED, r.text
    made = c.post(f"/api/{kind}", json={"name": "Fine", "color": "#58a6ff"})
    assert made.status_code == 200, made.text
    r = c.patch(f"/api/{kind}/{made.json()['id']}", json={"name": "Fine", "color": NOT_A_COLOUR})
    assert r.status_code in REFUSED, r.text


def test_an_imported_backup_cant_bring_in_a_colour_that_isnt_one(app_started):
    c, _ = register(app_started)
    payload = {"version": 4, "accounts": [],
               "categories": [{"name": "Imported", "color": NOT_A_COLOUR}],
               "tags": [{"name": "imported", "color": NOT_A_COLOUR}]}
    c.post("/api/backup/import", json={"mode": "merge", "payload": payload})
    colours = [x.get("color") for path in ("/api/categories", "/api/tags")
               for x in c.get(path).json()]
    assert NOT_A_COLOUR not in colours


# ---------- WW-SEC-02: an address belongs to whoever registers it first ----------

def test_an_admin_address_cant_be_claimed_by_registering_it(app_started):
    from app import main
    register(app_started)                      # the instance already has a user
    address = unique_email()
    main.ADMIN_EMAILS.add(address)
    try:
        c = TestClient(app_started)
        r = c.post("/api/auth/register", json={"email": address, "password": PASSWORD})
        became_admin = r.status_code == 200 and c.get("/api/me").json()["is_admin"]
    finally:
        main.ADMIN_EMAILS.discard(address)
    assert not became_admin


# ---------- WW-SEC-04 and -05: pointing at someone else's rows ----------

def _victim_with_a_bill(app):
    v, victim = register(app)
    acc = make_account(v)
    cat = v.post("/api/categories", json={"name": "Private " + uuid.uuid4().hex[:8]})
    rec = v.post(f"/api/accounts/{acc}/recurring", json={
        "description": "Rent", "amount": -500, "frequency": "weekly", "anchor_date": TODAY})
    assert cat.status_code == 200 and rec.status_code == 200
    return v, {**victim, "acc": acc, "cat": cat.json(), "rec": rec.json()["id"]}


def test_a_line_cant_be_tied_to_someone_elses_bill(app_started):
    v, victim = _victim_with_a_bill(app_started)
    x, _ = register(app_started)
    own = make_account(x)
    r = x.post(f"/api/accounts/{own}/transactions", json={
        "description": "x", "amount": -1, "forecast_date": TODAY, "actual_date": TODAY,
        "is_actual": True, "recurring_id": victim["rec"]})
    if r.status_code == 200:
        # What it's good for: deleting the line strikes that date from the
        # victim's bill, and while it exists the date counts as paid.
        x.delete(f"/api/transactions/{r.json()['id']}")
    bill = next(i for i in v.get("/api/recurring").json()["items"] if i["id"] == victim["rec"])
    assert r.status_code in REFUSED
    assert bill["skipped_count"] == 0 and bill["next_date"] == TODAY


def test_marking_a_bill_paid_cant_use_someone_elses_category(app_started):
    _, victim = _victim_with_a_bill(app_started)
    x, _ = register(app_started)
    own = make_account(x)
    rec = x.post(f"/api/accounts/{own}/recurring", json={
        "description": "Mine", "amount": -1, "frequency": "weekly", "anchor_date": TODAY})
    r = x.post(f"/api/accounts/{own}/forecast/actual", json={
        "recurring_id": rec.json()["id"], "forecast_date": TODAY,
        "category_id": victim["cat"]["id"]})
    assert victim["cat"]["name"] not in x.get(f"/api/accounts/{own}/transactions").text
    assert r.status_code in REFUSED


# ---------- WW-SEC-10: the reserved demo address ----------

def test_the_demo_domain_cant_be_registered_outside_demo_mode(app_started):
    r = TestClient(app_started).post("/api/auth/register", json={
        "email": f"x-{uuid.uuid4().hex[:10]}@demo.walletweather.local", "password": PASSWORD})
    assert r.status_code in REFUSED


# ---------- WW-SEC-13: Google's word on an address ----------

def test_google_sign_in_refuses_an_address_google_hasnt_verified(app_started, monkeypatch):
    from app import main
    _, victim = register(app_started)

    class FakeGoogle:
        async def authorize_access_token(self, request):
            return {"userinfo": {"sub": "sub-" + uuid.uuid4().hex, "email": victim["email"],
                                 "email_verified": False, "name": "Someone else"}}

    class FakeOAuth:
        google = FakeGoogle()

    monkeypatch.setattr(main, "GOOGLE_ENABLED", True)
    monkeypatch.setattr(main, "oauth", FakeOAuth())
    c = TestClient(app_started, raise_server_exceptions=False)
    r = c.get("/auth/callback", follow_redirects=False)
    signed_in_as_victim = c.get("/api/me").status_code == 200
    assert r.status_code in (400, 403) and not signed_in_as_victim


# ---------- WW-SEC-14: the two-factor hold reads the address the caller wrote ----------

def test_the_two_factor_hold_cant_be_slipped_with_a_host_header(app_started):
    from app.db import AdminSetting, SessionLocal
    from app.main import REQUIRE_TWO_FACTOR_KEY
    c, _ = register(app_started)
    db = SessionLocal()
    try:
        db.merge(AdminSetting(key=REQUIRE_TWO_FACTOR_KEY, value="true"))
        db.commit()
        held = c.get("/api/accounts")
        slipped = c.get("/api/accounts", headers={"Host": "testserver/api/me?x="})
    finally:
        db.query(AdminSetting).filter_by(key=REQUIRE_TWO_FACTOR_KEY).delete()
        db.commit()
        db.close()
    assert held.status_code == 403
    assert slipped.status_code in (400, 403)


# ---------- More on WW-SEC-01: what a colour may be ----------

@pytest.mark.parametrize("colour,stored", [("#58a6ff", "#58a6ff"), ("#ABC", "#ABC"),
                                           (" #58a6ff ", "#58a6ff"), ("", None), (None, None)])
def test_hex_colours_and_no_colour_are_accepted(app_started, colour, stored):
    c, _ = register(app_started)
    r = c.post("/api/categories", json={"name": "Fine", "color": colour})
    assert r.status_code == 200 and r.json()["color"] == stored


@pytest.mark.parametrize("colour", ["red", "#12345", "#1234567", "58a6ff", "rgb(1,2,3)",
                                    "var(--bad)", "#58a6ff;x", "#58a6ff\"", "url(//x.example)"])
def test_anything_else_is_refused_as_a_colour(app_started, colour):
    c, _ = register(app_started)
    for kind in ("categories", "tags"):
        r = c.post(f"/api/{kind}", json={"name": "Odd", "color": colour})
        assert r.status_code == 400 and "hex colour" in r.json()["detail"], (kind, colour)


def test_colours_already_stored_are_blanked_at_start_up(app_started):
    """The v22 migration: a row from before the check loses its colour, a hex
    one keeps it."""
    from sqlalchemy import text
    from app.db import SessionLocal, init_db
    c, _ = register(app_started)
    bad = c.post("/api/categories", json={"name": "Old", "color": "#111111"}).json()["id"]
    good = c.post("/api/tags", json={"name": "old", "color": "#222222"}).json()["id"]
    db = SessionLocal()
    try:
        db.execute(text("UPDATE categories SET color = :c WHERE id = :i"),
                   {"c": NOT_A_COLOUR, "i": bad})
        db.commit()
        init_db()
        assert db.execute(text("SELECT color FROM categories WHERE id = :i"), {"i": bad}).scalar() is None
        assert db.execute(text("SELECT color FROM tags WHERE id = :i"), {"i": good}).scalar() == "#222222"
    finally:
        db.close()


# ---------- More on WW-SEC-02: the registration code, and adding a user ----------

@pytest.fixture
def code(monkeypatch):
    from app import main
    monkeypatch.setattr(main, "REGISTRATION_CODE", "let-me-in-please")
    return "let-me-in-please"


def test_the_sign_in_page_is_told_whether_a_code_is_needed(app_started, monkeypatch):
    from app import main
    c = TestClient(app_started)
    assert c.get("/api/auth/config").json()["registration_code_required"] is False
    monkeypatch.setattr(main, "REGISTRATION_CODE", "x")
    assert c.get("/api/auth/config").json()["registration_code_required"] is True


@pytest.mark.parametrize("given", [None, "", "wrong", "let-me-in-pleas", "LET-ME-IN-PLEASE"])
def test_registering_needs_the_code_when_one_is_set(app_started, code, given):
    body = {"email": unique_email(), "password": PASSWORD}
    if given is not None:
        body["registration_code"] = given
    c = TestClient(app_started)
    r = c.post("/api/auth/register", json=body)
    assert r.status_code == 403 and "registration code" in r.json()["detail"]
    assert c.get("/api/me").status_code == 401
    # Nothing was made: the same address registers with the right code.
    r = c.post("/api/auth/register", json={**body, "registration_code": f" {code} "})
    assert r.status_code == 200, r.text


def test_an_admin_adds_a_user_who_can_then_sign_in(app_started, admin, code):
    """Works with a registration code set, and for another admin's address."""
    from app import main
    c, me = admin
    address = unique_email()
    main.ADMIN_EMAILS.add(address)
    try:
        r = c.post("/api/admin/users", json={"email": f" {address.upper()} ",
                                             "password": PASSWORD, "name": "Second Admin"})
        assert r.status_code == 200, r.text
        made = r.json()
        assert set(made) == {"id", "email", "name", "is_admin"}
        assert made["email"] == address and made["name"] == "Second Admin" and made["is_admin"] is True
        listed = {u["id"]: u for u in c.get("/api/admin/users").json()}
        assert listed[made["id"]]["has_password"] is True
        new = TestClient(app_started)
        r = new.post("/api/auth/login", json={"email": address, "password": PASSWORD})
        assert r.status_code == 200 and new.get("/api/me").json()["is_admin"] is True
        assert len(new.get("/api/categories").json()) > 0      # the default categories
    finally:
        main.ADMIN_EMAILS.discard(address)
    events = c.get("/api/admin/audit", params={"event": "user_created", "email": me["email"]}).json()
    assert events["events"][0]["detail"] == f"user #{made['id']}"
    assert "user_created" in events["event_types"]


def test_adding_a_user_refuses_bad_input(app_started, admin):
    c, me = admin
    ok = {"email": unique_email(), "password": PASSWORD}
    assert c.post("/api/admin/users", json={**ok, "email": "not-an-address"}).status_code == 400
    assert c.post("/api/admin/users", json={**ok, "password": "short"}).status_code == 422
    assert c.post("/api/admin/users", json={"email": ok["email"]}).status_code == 422
    assert c.post("/api/admin/users", json={**ok, "email": me["email"]}).status_code == 409
    assert c.post("/api/admin/users",
                  json={**ok, "email": "x@demo.walletweather.local"}).status_code == 400


def test_adding_a_user_keeps_to_the_allow_list(app_started, admin, monkeypatch):
    from app import main
    c, _ = admin
    monkeypatch.setattr(main, "ALLOWED_EMAILS", {"someone-else@example.test"})
    r = c.post("/api/admin/users", json={"email": unique_email(), "password": PASSWORD})
    assert r.status_code == 400 and "ALLOWED_EMAILS" in r.json()["detail"]


def test_only_an_admin_adds_users(app_started):
    c, _ = register(app_started)
    body = {"email": unique_email(), "password": PASSWORD}
    assert c.post("/api/admin/users", json=body).status_code == 403
    assert TestClient(app_started).post("/api/admin/users", json=body).status_code == 401


# ---------- More on WW-SEC-13: Google sign-in ----------

def _google(monkeypatch, userinfo):
    from app import main

    class FakeGoogle:
        async def authorize_access_token(self, request):
            return {"userinfo": userinfo}

    class FakeOAuth:
        google = FakeGoogle()

    monkeypatch.setattr(main, "GOOGLE_ENABLED", True)
    monkeypatch.setattr(main, "oauth", FakeOAuth())


def test_google_sign_in_with_a_verified_address_still_works(app_started, monkeypatch):
    address = unique_email()
    _google(monkeypatch, {"sub": "sub-" + uuid.uuid4().hex, "email": address,
                          "email_verified": True, "name": "New Person"})
    c = TestClient(app_started)
    r = c.get("/auth/callback", follow_redirects=False)
    assert r.status_code in (302, 307) and r.headers["location"] == "/"
    assert c.get("/api/me").json()["email"] == address


def test_with_a_code_set_google_makes_new_users_only_from_the_allow_list(
        app_started, monkeypatch, code):
    from app import main
    address = unique_email()
    info = {"sub": "sub-" + uuid.uuid4().hex, "email": address, "email_verified": True}
    _google(monkeypatch, info)
    c = TestClient(app_started)
    r = c.get("/auth/callback", follow_redirects=False)
    assert r.status_code == 403 and c.get("/api/me").status_code == 401
    monkeypatch.setattr(main, "ALLOWED_EMAILS", {address})
    r = c.get("/auth/callback", follow_redirects=False)
    assert r.status_code in (302, 307) and c.get("/api/me").json()["email"] == address


# ---------- WW-SEC-09: no upper limits ----------

def test_a_forecast_window_has_an_upper_limit(app_started):
    # Checked with a signed-in user who has no such account, so today's
    # answer (404, after the window was accepted) costs nothing to get.
    c, _ = register(app_started)
    assert c.get("/api/accounts/999999999/forecast", params={"days": 4_000_000}).status_code in (400, 422)
    r = c.get("/api/accounts/999999999/forecast", params={"start": "0001-01-01", "end": "9999-12-31"})
    assert r.status_code in (400, 422)


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


def test_a_huge_request_is_refused(app_started):
    body = '{"email": "a@example.test", "password": "' + "x" * (32 * 1024 * 1024) + '"}'
    r = TestClient(app_started, raise_server_exceptions=False).post(
        "/api/auth/login", content=body, headers={"Content-Type": "application/json"})
    assert r.status_code == 413


# ---------- WW-SEC-11: values that break the pages that show them ----------

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

@pytest.mark.parametrize("secret", ["replace_with_random_string", "short", ""])
def test_the_server_wont_start_with_a_guessable_session_secret(secret):
    env = {**os.environ, "SESSION_SECRET": secret}
    done = subprocess.run([sys.executable, "-c", "import app.main"], cwd=SERVER_DIR, env=env,
                          capture_output=True, text=True, timeout=60)
    assert done.returncode != 0
    assert "SESSION_SECRET" in done.stderr


# ---------- More on WW-SEC-09 and -11: the limits themselves ----------

def test_a_request_without_a_length_is_counted_and_refused(app_started, monkeypatch):
    """A body sent in pieces has no Content-Length to go by."""
    from app import main
    limiter = next(m for m in app_started.user_middleware if m.cls is main.BodyLimitMiddleware)
    assert limiter.kwargs["max_bytes"] == main.MAX_BODY_BYTES == 25 * 1024 * 1024

    def pieces():
        yield b'{"email": "a@example.test", "password": "'
        for _ in range(27):
            yield b"x" * (1024 * 1024)
        yield b'"}'
    r = TestClient(app_started, raise_server_exceptions=False).post(
        "/api/auth/login", content=pieces(), headers={"Content-Type": "application/json"})
    assert r.status_code == 413 and "too large" in r.json()["detail"]


def test_an_ordinary_import_is_well_under_the_limit(app_started):
    c, _ = register(app_started)
    acc = make_account(c)
    rows = "".join(f"2026-01-{d:02d},Shop {d},-{d}.50\n" for d in range(1, 29)) * 40
    r = c.post(f"/api/accounts/{acc}/import/preview",
               json={"csv_text": "Date,Description,Amount\n" + rows})
    assert r.status_code == 200 and r.json()["row_count"] == 28 * 40


@pytest.mark.parametrize("params,status", [
    ({"days": 3660}, 200), ({"days": 0}, 200), ({"days": 3661}, 400), ({"days": -1}, 400),
    ({"start": "2026-01-01", "end": "2025-12-31"}, 400),
    ({"start": "2026-01-01", "end": "2036-01-08"}, 200),
    ({"start": "2026-01-01", "end": "2036-01-10"}, 400),
])
def test_the_forecast_window_stops_at_ten_years(app_started, params, status):
    c, _ = register(app_started)
    acc = make_account(c)
    assert c.get(f"/api/accounts/{acc}/forecast", params=params).status_code == status


def test_a_report_over_too_long_a_window_is_refused_or_falls_back(app_started):
    c, _ = register(app_started)
    make_account(c)
    assert c.get("/api/report", params={"start": "0001-01-01", "end": "9999-12-31"}).status_code == 400
    r = c.post("/api/report/run", json={"range_mode": "custom", "start": "0001-01-01",
                                        "end": "9999-12-31"})
    assert r.status_code == 200 and r.json()["start"].startswith(TODAY[:8])   # this month


@pytest.mark.parametrize("amount", ["1e13", "-1e13"])
def test_an_amount_past_a_trillion_is_refused(app_started, amount):
    c, _ = register(app_started)
    acc = make_account(c)
    r = c.post(f"/api/accounts/{acc}/transactions",
               content='{"description": "x", "amount": %s}' % amount,
               headers={"Content-Type": "application/json"})
    assert r.status_code == 422


@pytest.mark.parametrize("path,body", [
    ("/api/accounts", {"name": "x", "starting_balance": "NaN", "starting_date": TODAY}),
    ("/api/budgets", {"category_id": 1, "amount": "Infinity"}),
    ("/api/transfers", {"from_account_id": 1, "to_account_id": 2, "amount": "Infinity",
                        "transfer_date": TODAY}),
])
def test_other_amounts_must_be_real_numbers_too(app_started, path, body):
    c, _ = register(app_started)
    raw = "{" + ", ".join(
        f'"{k}": {v if k in ("amount", "starting_balance") else repr(v).replace(chr(39), chr(34))}'
        for k, v in body.items()) + "}"
    r = c.post(path, content=raw, headers={"Content-Type": "application/json"})
    assert r.status_code == 422, r.text


def test_a_csv_cant_bring_in_an_amount_that_isnt_a_number(app_started):
    c, _ = register(app_started)
    acc = make_account(c)
    csv_text = "Date,Description,Amount\n2026-01-01,a,nan\n2026-01-02,b,inf\n2026-01-03,c,-4.50\n"
    r = c.post(f"/api/accounts/{acc}/import/commit", json={
        "csv_text": csv_text, "mapping": {"date": 0, "description": 1, "amount": 2}})
    assert r.status_code == 200 and r.json()["inserted"] == 1
    assert c.get(f"/api/accounts/{acc}/transactions").status_code == 200
    # An empty file, and a mapping that isn't column numbers, are answers, not errors.
    r = c.post(f"/api/accounts/{acc}/import/commit", json={"csv_text": "", "mapping": {}})
    assert r.status_code == 200 and r.json()["inserted"] == 0
    r = c.post(f"/api/accounts/{acc}/import/commit",
               json={"csv_text": csv_text, "mapping": {"date": "first"}})
    assert r.status_code == 422


def test_a_backup_cant_bring_in_an_amount_that_isnt_a_number(app_started):
    c, _ = register(app_started)
    account = {"name": "Imported", "starting_balance": 0, "starting_date": TODAY,
               "recurring": [{"description": "odd", "amount": -1, "frequency": "hourly",
                              "day_of_month": 0}],
               "transactions": [{"description": "x", "amount": "NaN", "actual_date": TODAY}]}
    r = c.post("/api/backup/import", json={"mode": "merge",
                                           "payload": {"version": 4, "accounts": [account]}})
    assert r.status_code == 400 and "Not an amount" in r.json()["detail"]
    assert c.get("/api/accounts").json() == []          # nothing was half-imported
    # An old backup's odd recurring item still restores, and the forecast runs.
    account["transactions"][0]["amount"] = -2
    r = c.post("/api/backup/import", json={"mode": "merge",
                                           "payload": {"version": 4, "accounts": [account]}})
    assert r.status_code == 200, r.text
    acc = c.get("/api/accounts").json()[0]["id"]
    assert c.get(f"/api/accounts/{acc}/forecast").status_code == 200


def test_a_long_enough_session_secret_starts_the_server():
    env = {**os.environ, "SESSION_SECRET": "x" * 16}
    done = subprocess.run([sys.executable, "-c", "import app.main"], cwd=SERVER_DIR, env=env,
                          capture_output=True, text=True, timeout=60)
    assert done.returncode == 0, done.stderr[-300:]


# ---------- WW-SEC-07 and -08: the browser's side ----------

def test_a_write_that_says_it_comes_from_another_site_is_refused(app_started):
    c, _ = register(app_started)
    r = c.post("/api/accounts", headers={"Origin": "https://evil.example"},
               json={"name": "x", "starting_balance": 0, "starting_date": TODAY})
    assert r.status_code == 403
    # The app's own page still works.
    r = c.post("/api/accounts", headers={"Origin": "http://testserver"},
               json={"name": "x", "starting_balance": 0, "starting_date": TODAY})
    assert r.status_code == 200


def test_pages_and_answers_carry_the_security_headers(app_started):
    c, _ = register(app_started)
    for path in ("/", "/app-sign-in", "/api/me"):
        h = c.get(path).headers
        assert h.get("x-content-type-options") == "nosniff", path
        assert (h.get("x-frame-options", "").upper() in ("DENY", "SAMEORIGIN")
                or "frame-ancestors" in h.get("content-security-policy", "")), path
        assert h.get("referrer-policy"), path
    assert "no-store" in c.get("/api/me").headers.get("cache-control", "")


@pytest.mark.parametrize("path", ["/docs", "/redoc", "/openapi.json"])
def test_the_api_docs_arent_served_to_strangers(app_started, path):
    assert TestClient(app_started).get(path).status_code in (401, 403, 404)


# ---------- More on WW-SEC-07: which writes are refused ----------

ACCOUNT = {"name": "x", "starting_balance": 0, "starting_date": TODAY}


@pytest.mark.parametrize("headers,status", [
    ({}, 200),                                                    # scripts, the native app
    ({"Origin": "http://testserver"}, 200),
    ({"Origin": "HTTP://TESTSERVER/"}, 200),
    ({"Origin": "https://testserver"}, 200),                      # HTTPS ends at a proxy
    ({"Origin": "http://localhost:8300"}, 200),                   # APP_BASE_URL
    ({"Origin": "https://wallet.example.test", "X-Forwarded-Host": "wallet.example.test"}, 200),
    ({"Origin": "https://evil.example"}, 403),
    ({"Origin": "http://testserver.evil.example"}, 403),
    ({"Origin": "http://other.testserver"}, 403),                 # another app on the domain
    ({"Origin": "null"}, 403),
    ({"Sec-Fetch-Site": "cross-site"}, 403),
    ({"Sec-Fetch-Site": "same-site"}, 403),
    ({"Sec-Fetch-Site": "same-origin"}, 200),
    ({"Sec-Fetch-Site": "none"}, 200),
])
def test_which_writes_count_as_another_sites(app_started, headers, status):
    c, _ = register(app_started)
    r = c.post("/api/accounts", json=ACCOUNT, headers=headers)
    assert r.status_code == status, r.text
    if status == 403:
        assert "another site" in r.json()["detail"]
        assert c.get("/api/accounts").json() == []


def test_a_trusted_origin_from_the_settings_is_let_through(app_started, monkeypatch):
    from app import main
    c, _ = register(app_started)
    headers = {"Origin": "https://wallet.example.test"}
    assert c.post("/api/accounts", json=ACCOUNT, headers=headers).status_code == 403
    monkeypatch.setattr(main, "TRUSTED_ORIGINS", {"https://wallet.example.test"})
    assert c.post("/api/accounts", json=ACCOUNT, headers=headers).status_code == 200


def test_reads_and_api_tokens_arent_judged_by_origin(app_started):
    c, _ = register(app_started)
    evil = {"Origin": "https://evil.example"}
    assert c.get("/api/accounts", headers=evil).status_code == 200
    token = c.post("/api/tokens", json={"name": "t", "access": "full"}).json()["token"]
    r = TestClient(app_started).post("/api/accounts", json=ACCOUNT,
                                     headers={**evil, "Authorization": "Bearer " + token})
    assert r.status_code == 200


@pytest.mark.parametrize("method,path", [("POST", "/auth/logout"), ("DELETE", "/api/me"),
                                         ("PUT", "/api/admin/two-factor"),
                                         ("PATCH", "/api/me/preferences"),
                                         ("POST", "/api/admin/backups/restore/x")])
def test_every_kind_of_write_is_covered(app_started, method, path):
    c, _ = register(app_started)
    r = c.request(method, path, json={}, headers={"Origin": "https://evil.example"})
    assert r.status_code == 403 and "another site" in r.json()["detail"]
    assert c.get("/api/me").status_code == 200           # still signed in


def test_the_headers_are_on_errors_and_static_files_too(app_started):
    c = TestClient(app_started)
    for path in ("/api/me", "/nope", "/static/sw.js", "/api/auth/config", "/manifest.webmanifest"):
        h = c.get(path).headers
        assert h["x-content-type-options"] == "nosniff", path
        assert h["x-frame-options"] == "DENY", path
        assert "frame-ancestors 'none'" in h["content-security-policy"], path
    # The page and the service worker keep their own caching rule.
    assert c.get("/").headers["cache-control"] == "no-cache"
    assert "no-store" in c.get("/api/auth/config").headers["cache-control"]


# ---------- WW-SEC-03: sessions can't be ended from elsewhere ----------

def test_changing_the_password_signs_out_other_browsers(app_started):
    here, user = register(app_started)
    there = TestClient(app_started)
    r = there.post("/api/auth/login", json={"email": user["email"], "password": PASSWORD})
    assert r.status_code == 200 and there.get("/api/me").status_code == 200
    r = here.post("/api/me/password", json={"current_password": PASSWORD,
                                            "new_password": "a-brand-new-password"})
    assert r.status_code == 200, r.text
    assert there.get("/api/me").status_code == 401


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


# ---------- More on WW-SEC-03: what ends, and what doesn't ----------

def _second_browser(app, user):
    c = TestClient(app)
    r = c.post("/api/auth/login", json={"email": user["email"], "password": PASSWORD})
    assert r.status_code == 200 and c.get("/api/me").status_code == 200
    return c


def test_the_browser_that_changed_the_password_stays_in_and_tokens_keep_working(app_started):
    here, user = register(app_started)
    token = here.post("/api/tokens", json={"name": "app", "access": "read"}).json()["token"]
    r = here.post("/api/me/password", json={"current_password": PASSWORD,
                                            "new_password": "a-brand-new-password"})
    assert r.status_code == 200
    assert here.get("/api/me").status_code == 200
    bearer = {"Authorization": "Bearer " + token}
    assert TestClient(app_started).get("/api/me", headers=bearer).status_code == 200
    # And a new sign-in with the new password is a good session.
    again = TestClient(app_started)
    assert again.post("/api/auth/login", json={"email": user["email"],
                                               "password": "a-brand-new-password"}).status_code == 200
    assert again.get("/api/me").status_code == 200


def test_sign_out_my_other_browsers(app_started):
    here, user = register(app_started)
    there = _second_browser(app_started, user)
    token = here.post("/api/tokens", json={"name": "app", "access": "read"}).json()["token"]
    r = here.post("/api/me/sessions/end-others")
    assert r.status_code == 200 and r.json() == {"ok": True}
    assert there.get("/api/me").status_code == 401
    assert there.get("/api/accounts").status_code == 401
    assert here.get("/api/me").status_code == 200
    bearer = {"Authorization": "Bearer " + token}
    assert TestClient(app_started).get("/api/me", headers=bearer).status_code == 200


def test_ending_other_sessions_needs_a_browser_session(app_started):
    c, _ = register(app_started)
    assert TestClient(app_started).post("/api/me/sessions/end-others").status_code == 401
    token = c.post("/api/tokens", json={"name": "app", "access": "full"}).json()["token"]
    r = TestClient(app_started).post("/api/me/sessions/end-others",
                                     headers={"Authorization": "Bearer " + token})
    assert r.status_code == 403


def test_an_admins_reset_also_ends_the_users_tokens(app_started, admin):
    c, _ = admin
    theirs, user = register(app_started)
    token = theirs.post("/api/tokens", json={"name": "app", "access": "full"}).json()["token"]
    bearer = {"Authorization": "Bearer " + token}
    assert TestClient(app_started).get("/api/me", headers=bearer).status_code == 200
    r = c.patch(f"/api/admin/users/{user['id']}", json={"new_password": "reset-by-admin-1"})
    assert r.status_code == 200
    assert TestClient(app_started).get("/api/me", headers=bearer).status_code == 401
    assert theirs.get("/api/me").status_code == 401
    assert c.get("/api/me").status_code == 200           # the admin is untouched


def test_switching_two_factor_on_signs_out_browsers_that_never_gave_a_code(app_started):
    import time
    from app import twofactor
    here, user = register(app_started)
    there = _second_browser(app_started, user)
    secret = here.post("/api/me/two-factor/setup", json={"password": PASSWORD}).json()["secret"]
    code = twofactor.code_at(secret, twofactor.current_step(time.time()))
    assert here.post("/api/me/two-factor/enable", json={"code": code}).status_code == 200
    assert there.get("/api/me").status_code == 401
    assert here.get("/api/me").json()["two_factor_enabled"] is True


def test_a_session_from_before_the_update_still_works(app_started):
    """A cookie with no number counts as 0, so updating signs nobody out."""
    import base64, json
    import itsdangerous
    from app import main
    _, user = register(app_started)
    signer = itsdangerous.TimestampSigner(main.SECRET_KEY)
    old = signer.sign(base64.b64encode(json.dumps({"uid": user["id"]}).encode())).decode()
    c = TestClient(app_started)
    c.cookies.set("session", old)
    assert c.get("/api/me").json()["email"] == user["email"]
    here = _second_browser(app_started, user)
    assert here.post("/api/me/sessions/end-others").status_code == 200
    assert c.get("/api/me").status_code == 401


# ---------- WW-SEC-06: everyone's address ----------

def test_you_dont_see_the_addresses_of_people_you_share_nothing_with(app_started):
    _, stranger = register(app_started)
    c, _ = register(app_started)
    make_account(c)
    assert stranger["email"] not in c.get("/api/permissions").text


# ---------- More on WW-SEC-06 and -18: sharing by invitation ----------

INVITATION = {"id": int, "account_id": int, "account_name": str, "email": str, "level": str,
              "invited_by": str, "created_at": str}


def _shape(row, fields):
    assert set(row) == set(fields), set(row) ^ set(fields)
    for key, kind in fields.items():
        assert isinstance(row[key], kind), (key, row[key])


def test_an_invitation_shares_an_account_once_its_accepted(app_started):
    o, owner = register(app_started)
    v, viewer = register(app_started)
    acc = make_account(o, "Joint")
    r = o.post("/api/invitations", json={"account_id": acc, "email": f" {viewer['email'].upper()} ",
                                         "level": "read"})
    assert r.status_code == 200, r.text
    inv = r.json()
    _shape(inv, INVITATION)
    assert (inv["email"], inv["level"], inv["account_name"], inv["invited_by"]) == (
        viewer["email"], "read", "Joint", owner["email"])
    # Not theirs yet.
    assert v.get("/api/accounts").json() == []
    assert v.get(f"/api/accounts/{acc}/transactions").status_code == 404
    listed = v.get("/api/invitations").json()
    assert set(listed) == {"received", "sent"} and listed["sent"] == []
    assert [i["id"] for i in listed["received"]] == [inv["id"]]
    _shape(listed["received"][0], INVITATION)
    assert [i["id"] for i in o.get("/api/invitations").json()["sent"]] == [inv["id"]]
    r = v.post(f"/api/invitations/{inv['id']}/accept")
    assert r.status_code == 200 and r.json() == {"ok": True, "account_id": acc, "level": "read"}
    assert [a["level"] for a in v.get("/api/accounts").json()] == ["read"]
    assert v.get("/api/invitations").json()["received"] == []
    assert o.get("/api/invitations").json()["sent"] == []
    assert v.post(f"/api/invitations/{inv['id']}/accept").status_code == 404   # used up
    people = {u["email"] for u in o.get("/api/permissions").json()["users"]}
    assert people == {owner["email"], viewer["email"]}


def test_inviting_an_address_says_nothing_about_whether_it_has_a_user(app_started):
    o, _ = register(app_started)
    _, someone = register(app_started)
    acc = make_account(o)
    nobody = unique_email()
    known = o.post("/api/invitations", json={"account_id": acc, "email": someone["email"], "level": "read"})
    unknown = o.post("/api/invitations", json={"account_id": acc, "email": nobody, "level": "read"})
    assert known.status_code == unknown.status_code == 200
    assert set(known.json()) == set(unknown.json())
    # And the invitation waits for whoever registers that address.
    late, _ = register(app_started, email=nobody)
    assert [i["account_id"] for i in late.get("/api/invitations").json()["received"]] == [acc]


def test_only_an_owner_invites_and_only_to_a_real_level_and_address(app_started):
    o, owner = register(app_started)
    e, editor = register(app_started)
    x, _ = register(app_started)
    acc = make_account(o)
    share_account(o, acc, "edit", e)
    body = {"account_id": acc, "email": unique_email(), "level": "read"}
    assert e.post("/api/invitations", json=body).status_code == 403
    assert x.post("/api/invitations", json=body).status_code == 404
    assert TestClient(app_started).post("/api/invitations", json=body).status_code == 401
    assert o.post("/api/invitations", json={**body, "level": "deny"}).status_code == 400
    assert o.post("/api/invitations", json={**body, "email": "not-an-address"}).status_code == 400
    assert o.post("/api/invitations", json={**body, "email": owner["email"]}).status_code == 400
    assert o.post("/api/invitations", json={**body, "email": editor["email"]}).status_code == 409
    assert o.post("/api/invitations", json={"email": "a@example.test"}).status_code == 422
    assert o.get("/api/invitations").json()["sent"] == []


def test_inviting_again_changes_the_offer_instead_of_adding_one(app_started):
    o, _ = register(app_started)
    v, viewer = register(app_started)
    acc = make_account(o)
    first = o.post("/api/invitations", json={"account_id": acc, "email": viewer["email"], "level": "read"}).json()
    again = o.post("/api/invitations", json={"account_id": acc, "email": viewer["email"], "level": "edit"}).json()
    assert again["id"] == first["id"] and again["level"] == "edit"
    assert len(v.get("/api/invitations").json()["received"]) == 1
    assert v.post(f"/api/invitations/{first['id']}/accept").json()["level"] == "edit"


def test_who_may_accept_decline_and_cancel(app_started):
    o, _ = register(app_started)
    v, viewer = register(app_started)
    x, _ = register(app_started)
    acc = make_account(o)

    def invite():
        return o.post("/api/invitations", json={"account_id": acc, "email": viewer["email"],
                                                "level": "edit"}).json()["id"]
    inv = invite()
    for other in (o, x):                       # not the owner, not a stranger
        assert other.post(f"/api/invitations/{inv}/accept").status_code == 404
    assert x.delete(f"/api/invitations/{inv}").status_code == 404
    assert v.delete(f"/api/invitations/{inv}").json() == {"ok": True}       # declined
    assert v.get("/api/accounts").json() == []
    inv = invite()
    assert o.delete(f"/api/invitations/{inv}").json() == {"ok": True}       # cancelled
    assert v.post(f"/api/invitations/{inv}/accept").status_code == 404
    assert v.delete("/api/invitations/999999999").status_code == 404


def test_access_cant_be_handed_out_without_an_invitation(app_started):
    o, _ = register(app_started)
    _, other = register(app_started)
    acc = make_account(o)
    r = o.post("/api/permissions", json={"account_id": acc, "user_id": other["id"], "level": "read"})
    assert r.status_code == 400 and "Invite them" in r.json()["detail"]


def test_anyone_can_leave_an_account_shared_with_them(app_started):
    o, _ = register(app_started)
    v, viewer = register(app_started)
    acc = make_account(o)
    share_account(o, acc, "read", v)
    r = v.post("/api/permissions", json={"account_id": acc, "user_id": viewer["id"], "level": "deny"})
    assert r.status_code == 200, r.text
    assert v.get("/api/accounts").json() == []


# ---------- More on WW-SEC-13: Google sign-in meeting a password ----------

def test_the_first_google_sign_in_removes_a_password_someone_else_may_know(app_started, monkeypatch):
    squatter, user = register(app_started)          # whoever registered the address first
    token = squatter.post("/api/tokens", json={"name": "kept", "access": "full"}).json()["token"]
    bearer = {"Authorization": "Bearer " + token}
    sub = "sub-" + uuid.uuid4().hex
    _google(monkeypatch, {"sub": sub, "email": user["email"], "email_verified": True})
    owner = TestClient(app_started)
    assert owner.get("/auth/callback", follow_redirects=False).status_code in (302, 307)
    me = owner.get("/api/me").json()
    assert me["email"] == user["email"] and me["has_password"] is False
    assert squatter.get("/api/me").status_code == 401
    assert TestClient(app_started).get("/api/me", headers=bearer).status_code == 401
    r = TestClient(app_started).post("/api/auth/login",
                                     json={"email": user["email"], "password": PASSWORD})
    assert r.status_code == 401
    # The second Google sign-in is an ordinary one: nothing more is ended.
    assert TestClient(app_started).get("/auth/callback", follow_redirects=False).status_code in (302, 307)
    assert owner.get("/api/me").status_code == 200


# ---------- WW-SEC-16: limits that don't depend on one address ----------

def _client_at(app, address):
    return TestClient(app, raise_server_exceptions=False, client=(address, 50000))


def _fail(c, email):
    return c.post("/api/auth/login", json={"email": email, "password": "not-the-one"})


def test_an_email_is_limited_across_addresses(app_started, monkeypatch):
    from app import main
    monkeypatch.setattr(main, "LOGIN_MAX_FAILURES_PER_EMAIL", 3)
    _, user = register(app_started)
    net = uuid.uuid4().int % 200
    for n in range(3):
        assert _fail(_client_at(app_started, f"10.{net}.1.{n}"), user["email"]).status_code == 401
    r = _fail(_client_at(app_started, f"10.{net}.1.99"), user["email"])
    assert r.status_code == 429 and int(r.headers["retry-after"]) > 0
    # The right password is refused too while it lasts, as with the first limit.
    r = _client_at(app_started, f"10.{net}.1.98").post(
        "/api/auth/login", json={"email": user["email"], "password": PASSWORD})
    assert r.status_code == 429
    # Another email from those addresses is untouched.
    assert _fail(_client_at(app_started, f"10.{net}.1.0"), unique_email()).status_code == 401


def test_an_address_is_limited_across_emails(app_started, monkeypatch):
    from app import main
    monkeypatch.setattr(main, "LOGIN_MAX_FAILURES_PER_ADDRESS", 3)
    here = _client_at(app_started, f"10.{uuid.uuid4().int % 200}.2.{uuid.uuid4().int % 200}")
    for _ in range(3):
        assert _fail(here, unique_email()).status_code == 401
    assert _fail(here, unique_email()).status_code == 429
    elsewhere = _client_at(app_started, f"10.{uuid.uuid4().int % 200}.3.{uuid.uuid4().int % 200}")
    assert _fail(elsewhere, unique_email()).status_code == 401


def test_registering_is_limited_per_address(app_started, monkeypatch):
    from app import main
    monkeypatch.setattr(main, "REGISTRATIONS_PER_HOUR", 2)
    address = f"10.{uuid.uuid4().int % 200}.4.{uuid.uuid4().int % 200}"

    def sign_up(**extra):
        return _client_at(app_started, address).post(
            "/api/auth/register", json={"email": unique_email(), "password": PASSWORD, **extra})
    assert sign_up().status_code == 200
    monkeypatch.setattr(main, "REGISTRATION_CODE", "the-code")
    assert sign_up(registration_code="a guess").status_code == 403      # a wrong code counts
    r = sign_up(registration_code="the-code")
    assert r.status_code == 429 and "Too many new users" in r.json()["detail"]
    assert int(r.headers["retry-after"]) > 0
    other = _client_at(app_started, "10.250.4.1").post(
        "/api/auth/register", json={"email": unique_email(), "password": PASSWORD,
                                    "registration_code": "the-code"})
    assert other.status_code == 200
