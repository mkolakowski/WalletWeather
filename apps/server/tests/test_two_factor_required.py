"""An admin can require two-factor sign-in (two-factor phase 4, #168).

The requirement is one row in the shared admin_settings table, and the test
database is shared by the whole suite, so the `requirement` fixture clears it
before and after every test that touches it: a failing test can't leave every
other file's users held back.
"""
import pytest
from fastapi.testclient import TestClient

from conftest import unique_email

MESSAGE = "requires two-factor sign-in"
KEY = "require_two_factor"


def _clear_requirement():
    from app.db import AdminSetting, SessionLocal
    db = SessionLocal()
    try:
        db.query(AdminSetting).filter_by(key=KEY).delete()
        db.commit()
    finally:
        db.close()


@pytest.fixture
def requirement(app_started):
    """The requirement is off before the test and is always removed after it."""
    _clear_requirement()
    yield
    _clear_requirement()


def events(email):
    from app.db import AuditEvent, SessionLocal
    db = SessionLocal()
    try:
        rows = (db.query(AuditEvent).filter_by(email=email.lower())
                .order_by(AuditEvent.id).all())
        return [(r.event, r.detail) for r in rows]
    finally:
        db.close()


def fresh_code(email, secret):
    """A code the server will take now. A code works once, so the last step
    used is forgotten first: the tests can't wait 30 seconds for the next."""
    from app import twofactor
    from app.db import SessionLocal, User
    db = SessionLocal()
    try:
        db.query(User).filter_by(email=email).update({User.totp_last_step: None})
        db.commit()
    finally:
        db.close()
    return twofactor.code_at(secret, twofactor.current_step())


def turn_on(client, user):
    """Set two-factor up for the signed-in user. Returns (key, recovery codes)."""
    r = client.post("/api/me/two-factor/setup", json={"password": user["password"]})
    assert r.status_code == 200, r.text
    secret = r.json()["secret"]
    r = client.post("/api/me/two-factor/enable",
                    json={"code": fresh_code(user["email"], secret)})
    assert r.status_code == 200, r.text
    return secret, r.json()["recovery_codes"]


@pytest.fixture
def admin(app_started, requirement):
    """A signed-in admin (their address is in ADMIN_EMAILS for the test)."""
    from app import main
    admin_client = TestClient(app_started)
    user = {"email": unique_email(), "password": "admin-good-password"}
    r = admin_client.post("/api/auth/register", json=user)
    assert r.status_code == 200, r.text
    user["id"] = r.json()["id"]
    main.ADMIN_EMAILS.add(user["email"])
    try:
        yield admin_client, user
    finally:
        main.ADMIN_EMAILS.discard(user["email"])


def require(admin_client, admin_user, on=True):
    """Turn the requirement on or off as an admin who has two-factor set up."""
    me = admin_client.get("/api/me").json()
    if on and not me["two_factor_enabled"]:
        turn_on(admin_client, admin_user)
    r = admin_client.put("/api/admin/two-factor", json={"required": on})
    assert r.status_code == 200, r.text
    return r


def second_user(app_started, **kw):
    """Another registered user with their own client (password, no two-factor)."""
    c = TestClient(app_started)
    user = {"email": unique_email(), "password": "other-good-password"}
    r = c.post("/api/auth/register", json=user)
    assert r.status_code == 200, r.text
    user["id"] = r.json()["id"]
    return c, user


def make_token(client, access="full", code=None):
    body = {"name": "script", "access": access}
    if code:
        body["code"] = code  # a user with two-factor on needs one (#169)
    r = client.post("/api/tokens", json=body)
    assert r.status_code == 200, r.text
    return r.json()["token"]


def bearer(app_started, token):
    c = TestClient(app_started)
    c.headers["Authorization"] = "Bearer " + token
    return c


def held(r):
    return r.status_code == 403 and MESSAGE in r.json()["detail"]


def to_set_up(admin_client):
    return admin_client.get("/api/admin/two-factor").json()["users_to_set_up"]


ACCOUNT = {"name": "Checking", "starting_balance": 10, "starting_date": "2026-01-01"}


# ---------- The admin's switch ----------

def test_off_by_default_and_nothing_is_held(app_started, admin, registered):
    admin_client, _ = admin
    r = admin_client.get("/api/admin/two-factor")
    assert r.status_code == 200
    body = r.json()
    assert body["required"] is False and isinstance(body["users_to_set_up"], int)
    # `registered` (the `client` fixture) has a password and no two-factor.
    client = TestClient(app_started)
    assert client.post("/api/auth/login", json={
        "email": registered["email"], "password": registered["password"]}).status_code == 200
    me = client.get("/api/me").json()
    assert me["two_factor_setup_required"] is False
    assert client.get("/api/accounts").status_code == 200
    assert client.post("/api/accounts", json=ACCOUNT).status_code == 200
    assert client.get("/api/me/remembered-browsers").status_code == 200


def test_an_admin_sets_up_their_own_first(admin):
    admin_client, user = admin
    r = admin_client.put("/api/admin/two-factor", json={"required": True})
    assert r.status_code == 409
    assert admin_client.get("/api/admin/two-factor").json()["required"] is False
    assert ("two_factor_requirement_changed", "on") not in events(user["email"])

    turn_on(admin_client, user)
    r = admin_client.put("/api/admin/two-factor", json={"required": True})
    assert r.status_code == 200
    body = r.json()
    assert body["required"] is True and isinstance(body["users_to_set_up"], int)
    assert admin_client.get("/api/admin/two-factor").json()["required"] is True
    # The admin has it on, so they aren't held back themselves.
    assert admin_client.get("/api/accounts").status_code == 200
    assert admin_client.get("/api/me").json()["two_factor_setup_required"] is False


def test_a_user_who_is_not_an_admin_cannot(app_started, requirement, client, registered):
    assert client.get("/api/admin/two-factor").status_code == 403
    assert client.put("/api/admin/two-factor", json={"required": True}).status_code == 403
    assert client.put("/api/admin/two-factor", json={"required": False}).status_code == 403
    assert client.get("/api/me").json()["two_factor_setup_required"] is False


def test_the_switch_needs_a_sign_in(app_started, requirement):
    anon = TestClient(app_started)
    assert anon.get("/api/admin/two-factor").status_code == 401
    assert anon.put("/api/admin/two-factor", json={"required": True}).status_code == 401


def test_an_admin_token_reads_but_cannot_change_it(app_started, admin):
    admin_client, user = admin
    secret, _ = turn_on(admin_client, user)
    tok = bearer(app_started, make_token(
        admin_client, "admin", code=fresh_code(user["email"], secret)))
    r = tok.get("/api/admin/two-factor")
    assert r.status_code == 200 and r.json()["required"] is False
    assert tok.put("/api/admin/two-factor", json={"required": True}).status_code == 403
    assert admin_client.get("/api/admin/two-factor").json()["required"] is False


def test_the_change_is_recorded_once_per_change(admin):
    admin_client, user = admin
    turn_on(admin_client, user)
    changes = lambda: [e for e in events(user["email"]) if e[0] == "two_factor_requirement_changed"]
    admin_client.put("/api/admin/two-factor", json={"required": False})
    assert changes() == []  # off to off is no change
    admin_client.put("/api/admin/two-factor", json={"required": True})
    admin_client.put("/api/admin/two-factor", json={"required": True})
    assert changes() == [("two_factor_requirement_changed", "on")]
    admin_client.put("/api/admin/two-factor", json={"required": False})
    admin_client.put("/api/admin/two-factor", json={"required": False})
    assert changes() == [("two_factor_requirement_changed", "on"),
                         ("two_factor_requirement_changed", "off")]


# ---------- The hold ----------

def test_a_user_without_two_factor_is_held_back(app_started, admin):
    admin_client, admin_user = admin
    client, user = second_user(app_started)
    require(admin_client, admin_user)

    assert held(client.get("/api/accounts"))
    assert held(client.post("/api/accounts", json=ACCOUNT))
    assert held(client.get("/api/me/remembered-browsers"))
    assert held(client.post("/api/tokens", json={"name": "x", "access": "full"}))
    # Nothing was written by the refused request.
    me = client.get("/api/me")
    assert me.status_code == 200
    body = me.json()
    assert body["two_factor_setup_required"] is True
    assert body["email"] == user["email"] and body["two_factor_enabled"] is False
    assert client.post("/api/me/acknowledge-notice").status_code == 200


def test_the_held_users_token_is_held_back_too(app_started, admin):
    admin_client, admin_user = admin
    client, user = second_user(app_started)
    token = make_token(client)  # made before it was required
    tok = bearer(app_started, token)
    assert tok.get("/api/accounts").status_code == 200

    require(admin_client, admin_user)
    assert held(tok.get("/api/accounts"))
    assert held(tok.post("/api/accounts", json=ACCOUNT))
    r = tok.get("/api/me")
    assert r.status_code == 200 and r.json()["two_factor_setup_required"] is True

    # An app can still sign itself out, and the token is then gone.
    assert tok.delete("/api/tokens/current").status_code == 200
    assert tok.get("/api/me").status_code == 401


def test_the_app_sign_in_is_refused_and_recorded(app_started, admin):
    admin_client, admin_user = admin
    _, user = second_user(app_started)
    require(admin_client, admin_user)

    anon = TestClient(app_started)
    r = anon.post("/api/auth/token", json={
        "email": user["email"], "password": user["password"],
        "name": "phone", "access": "full"})
    assert r.status_code == 403
    body = r.json()
    assert MESSAGE in body["detail"] and "token" not in body
    assert events(user["email"])[-1] == ("two_factor_asked", "token; set-up required")


def test_the_app_sign_in_works_without_the_requirement(app_started, requirement, registered):
    anon = TestClient(app_started)
    r = anon.post("/api/auth/token", json={
        "email": registered["email"], "password": registered["password"],
        "name": "phone", "access": "full"})
    assert r.status_code == 200 and r.json()["token"]
    assert ("two_factor_asked", "token; set-up required") not in events(registered["email"])


def test_setting_up_while_held_lifts_the_hold(app_started, admin):
    admin_client, admin_user = admin
    client, user = second_user(app_started)
    token = bearer(app_started, make_token(client))
    require(admin_client, admin_user)
    assert held(client.get("/api/accounts"))
    before = to_set_up(admin_client)

    turn_on(client, user)  # setup + enable are both open while held

    assert client.get("/api/me").json()["two_factor_setup_required"] is False
    assert client.get("/api/accounts").status_code == 200
    assert client.post("/api/accounts", json=ACCOUNT).status_code == 200
    assert client.get("/api/me/remembered-browsers").status_code == 200
    assert token.get("/api/accounts").status_code == 200
    assert to_set_up(admin_client) == before - 1

    # And the app sign-in now asks for a code instead of refusing outright.
    anon = TestClient(app_started)
    r = anon.post("/api/auth/token", json={
        "email": user["email"], "password": user["password"],
        "name": "phone", "access": "full"})
    assert r.status_code == 403 and r.json().get("two_factor_required") is True


def test_turning_it_off_lifts_the_hold(app_started, admin):
    admin_client, admin_user = admin
    client, user = second_user(app_started)
    tok = bearer(app_started, make_token(client))
    require(admin_client, admin_user)
    assert held(client.get("/api/accounts")) and held(tok.get("/api/accounts"))

    r = admin_client.put("/api/admin/two-factor", json={"required": False})
    assert r.status_code == 200 and r.json()["required"] is False
    assert admin_client.get("/api/admin/two-factor").json()["required"] is False
    assert events(admin_user["email"])[-1] == ("two_factor_requirement_changed", "off")

    assert client.get("/api/accounts").status_code == 200
    assert tok.get("/api/accounts").status_code == 200
    assert client.get("/api/me").json()["two_factor_setup_required"] is False


def test_a_google_only_user_is_not_held_back(app_started, admin):
    from app.db import SessionLocal, User
    admin_client, admin_user = admin
    client, user = second_user(app_started)
    tok = bearer(app_started, make_token(client))
    require(admin_client, admin_user)
    assert held(client.get("/api/accounts"))
    before = to_set_up(admin_client)

    # No password, as for a user who only ever signed in with Google; the
    # browser session they already hold stays valid.
    db = SessionLocal()
    try:
        db.query(User).filter_by(id=user["id"]).update({User.password_hash: None})
        db.commit()
    finally:
        db.close()

    assert client.get("/api/me").json()["two_factor_setup_required"] is False
    assert client.get("/api/accounts").status_code == 200
    assert client.post("/api/accounts", json=ACCOUNT).status_code == 200
    assert tok.get("/api/accounts").status_code == 200
    assert to_set_up(admin_client) == before - 1


def test_a_disabled_user_is_not_counted(app_started, admin):
    from app.db import SessionLocal, User
    admin_client, admin_user = admin
    _, user = second_user(app_started)
    before = to_set_up(admin_client)
    db = SessionLocal()
    try:
        db.query(User).filter_by(id=user["id"]).update({User.disabled: True})
        db.commit()
    finally:
        db.close()
    assert to_set_up(admin_client) == before - 1


# ---------- How many users it waits on ----------

def test_users_to_set_up_counts_users_without_it(app_started, admin):
    admin_client, admin_user = admin
    start = to_set_up(admin_client)  # includes the admin, who has none yet
    c1, u1 = second_user(app_started)
    c2, u2 = second_user(app_started)
    assert to_set_up(admin_client) == start + 2

    turn_on(admin_client, admin_user)
    assert to_set_up(admin_client) == start + 2 - 1  # the admin set up theirs

    turn_on(c1, u1)
    assert to_set_up(admin_client) == start + 2 - 2

    # The same number comes back from the PUT.
    r = admin_client.put("/api/admin/two-factor", json={"required": True})
    assert r.json()["users_to_set_up"] == to_set_up(admin_client) == start + 2 - 2
    turn_on(c2, u2)
    assert to_set_up(admin_client) == start + 2 - 3
