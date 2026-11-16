"""Fixes from the 2026-11-16 security review (#178), each guarded by the test
that failed before it (#183, 1.62.0). The ids (WW-SEC-01 ...) are the
review's.
"""
import uuid
from datetime import date

import pytest
from fastapi.testclient import TestClient

from conftest import unique_email

PASSWORD = "correct-horse-battery"
TODAY = date.today().isoformat()
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
