"""Two-factor sign-in: set-up, the code step, recovery codes and the admin
switch-off (two-factor phase 1, #165)."""
import base64

import pytest
from fastapi.testclient import TestClient

from conftest import unique_email


@pytest.fixture
def limits():
    """The app module with its limits at the defaults the tests assume, put
    back afterwards (they're module settings read at start-up)."""
    from app import main
    saved = (main.LOGIN_MAX_FAILURES, main.LOGIN_WINDOW_MINUTES,
             main.TRUST_PROXY_HEADERS, main.TWO_FACTOR_STEP_MINUTES)
    main.LOGIN_MAX_FAILURES, main.LOGIN_WINDOW_MINUTES, main.TRUST_PROXY_HEADERS = 5, 15, False
    yield main
    (main.LOGIN_MAX_FAILURES, main.LOGIN_WINDOW_MINUTES,
     main.TRUST_PROXY_HEADERS, main.TWO_FACTOR_STEP_MINUTES) = saved


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


def wrong_code(secret):
    """Six digits that aren't right for any step the server would accept."""
    from app import twofactor
    now = twofactor.current_step()
    taken = {twofactor.code_at(secret, s) for s in range(now - 2, now + 4)}
    return next(c for c in ("000000", "111111", "222222", "333333", "444444",
                            "555555", "666666") if c not in taken)


def turn_on(client, user):
    """Set two-factor up for the signed-in user. Returns (key, recovery codes)."""
    r = client.post("/api/me/two-factor/setup", json={"password": user["password"]})
    assert r.status_code == 200, r.text
    secret = r.json()["secret"]
    r = client.post("/api/me/two-factor/enable",
                    json={"code": fresh_code(user["email"], secret)})
    assert r.status_code == 200, r.text
    return secret, r.json()["recovery_codes"]


def password_step(client, user, **kw):
    client.cookies.clear()
    return client.post("/api/auth/login",
                       json={"email": user["email"], "password": user["password"]}, **kw)


def code_step(client, code, **kw):
    return client.post("/api/auth/login/two-factor", json={"code": code}, **kw)


# ---------- The codes themselves ----------

def test_codes_match_the_standards_test_values():
    """RFC 6238, appendix B (SHA-1 rows), cut to six digits."""
    from app import twofactor
    secret = base64.b32encode(b"12345678901234567890").decode()
    for at, code in ((59, "287082"), (1111111109, "081804"), (1111111111, "050471"),
                     (1234567890, "005924"), (2000000000, "279037")):
        assert twofactor.code_at(secret, at // 30) == code
        assert twofactor.matching_step(secret, code, now=at) == at // 30
        # One step either side is still accepted; two is not.
        assert twofactor.matching_step(secret, code, now=at + 30) == at // 30
        assert twofactor.matching_step(secret, code, now=at + 90) is None
        # A step already used never matches again.
        assert twofactor.matching_step(secret, code, after_step=at // 30, now=at) is None
    assert twofactor.matching_step(secret, "28708", now=59) is None
    assert twofactor.matching_step(secret, "abcdef", now=59) is None


# ---------- Set-up ----------

def test_set_up_and_switch_on(client, registered):
    me = client.get("/api/me").json()
    assert me["two_factor_enabled"] is False and me["recovery_codes_left"] == 0

    r = client.post("/api/me/two-factor/setup", json={"password": "not-my-password"})
    assert r.status_code == 403

    r = client.post("/api/me/two-factor/setup", json={"password": registered["password"]})
    assert r.status_code == 200
    made = r.json()
    assert len(made["secret"]) == 32
    assert made["otpauth_url"].startswith("otpauth://totp/")
    assert "secret=" + made["secret"] in made["otpauth_url"]
    assert registered["email"] in made["otpauth_url"]
    # Nothing is on until a code proves the app has the key.
    assert client.get("/api/me").json()["two_factor_enabled"] is False

    r = client.post("/api/me/two-factor/enable", json={"code": wrong_code(made["secret"])})
    assert r.status_code == 403
    assert client.get("/api/me").json()["two_factor_enabled"] is False

    r = client.post("/api/me/two-factor/enable",
                    json={"code": fresh_code(registered["email"], made["secret"])})
    assert r.status_code == 200
    codes = r.json()["recovery_codes"]
    assert len(codes) == 10 and len(set(codes)) == 10
    assert all(len(c) == 11 and c[5] == "-" for c in codes)

    me = client.get("/api/me").json()
    assert me["two_factor_enabled"] is True and me["recovery_codes_left"] == 10
    assert ("two_factor_enabled", None) in events(registered["email"])

    # Already on: set-up can't be started over it.
    r = client.post("/api/me/two-factor/setup", json={"password": registered["password"]})
    assert r.status_code == 409
    r = client.post("/api/me/two-factor/enable", json={"code": "123456"})
    assert r.status_code == 409


def test_enable_without_starting_is_refused(client, registered):
    r = client.post("/api/me/two-factor/enable", json={"code": "123456"})
    assert r.status_code == 400


def test_the_key_and_codes_are_not_stored_readable(client, registered):
    from app.db import RecoveryCode, SessionLocal, User
    secret, codes = turn_on(client, registered)
    db = SessionLocal()
    try:
        user = db.query(User).filter_by(email=registered["email"]).one()
        assert secret.encode() not in bytes(user.totp_secret_enc)
        hashes = {r.code_hash for r in db.query(RecoveryCode).filter_by(user_id=user.id)}
        assert len(hashes) == 10 and not hashes & set(codes)
    finally:
        db.close()


def test_a_token_cannot_reach_the_set_up(client, registered):
    token = client.post("/api/tokens", json={"name": "script", "access": "full"}).json()["token"]
    client.cookies.clear()
    bearer = {"Authorization": "Bearer " + token}
    for path, body in (("setup", {"password": registered["password"]}),
                       ("enable", {"code": "123456"}),
                       ("disable", {"password": registered["password"], "code": "123456"}),
                       ("recovery-codes", {"password": registered["password"], "code": "123456"})):
        r = client.post("/api/me/two-factor/" + path, json=body, headers=bearer)
        assert r.status_code == 403, path


# ---------- Signing in ----------

def test_sign_in_asks_for_the_code(client, registered, limits):
    secret, _ = turn_on(client, registered)
    r = password_step(client, registered)
    assert r.status_code == 200 and r.json() == {"two_factor_required": True}
    # The password alone signs nobody in.
    assert client.get("/api/me").status_code == 401
    assert events(registered["email"])[-1] == ("two_factor_asked", "password")

    r = code_step(client, fresh_code(registered["email"], secret))
    assert r.status_code == 200
    body = r.json()
    assert body["id"] == registered["id"] and body["email"] == registered["email"]
    assert body["recovery_codes_left"] == 10
    assert client.get("/api/me").json()["two_factor_enabled"] is True
    assert events(registered["email"])[-1] == ("login", "password; code")


def test_a_wrong_code_is_refused_and_recorded(client, registered, limits):
    secret, _ = turn_on(client, registered)
    password_step(client, registered)
    r = code_step(client, wrong_code(secret))
    assert r.status_code == 401
    assert client.get("/api/me").status_code == 401
    assert events(registered["email"])[-1] == ("login_failed", "password; wrong code")
    # The same sign-in can still be finished with the right code.
    assert code_step(client, fresh_code(registered["email"], secret)).status_code == 200


def test_a_code_works_once(client, registered, limits):
    secret, _ = turn_on(client, registered)
    password_step(client, registered)
    code = fresh_code(registered["email"], secret)
    assert code_step(client, code).status_code == 200
    password_step(client, registered)
    assert code_step(client, code).status_code == 401


def test_the_code_step_needs_the_password_first(client, registered, limits):
    turn_on(client, registered)
    client.cookies.clear()
    r = code_step(client, "123456")
    assert r.status_code == 401 and "expired" in r.json()["detail"]


def test_the_code_step_expires(client, registered, limits):
    secret, _ = turn_on(client, registered)
    password_step(client, registered)
    limits.TWO_FACTOR_STEP_MINUTES = -1
    r = code_step(client, fresh_code(registered["email"], secret))
    assert r.status_code == 401 and "expired" in r.json()["detail"]
    assert client.get("/api/me").status_code == 401


def test_a_recovery_code_works_once(client, registered, limits):
    _, codes = turn_on(client, registered)
    password_step(client, registered)
    # Typed in capitals with a space: still the same code.
    r = code_step(client, codes[0].upper().replace("-", " "))
    assert r.status_code == 200 and r.json()["recovery_codes_left"] == 9
    assert events(registered["email"])[-2:] == [
        ("recovery_code_used", "9 left"), ("login", "password; recovery code")]

    password_step(client, registered)
    assert code_step(client, codes[0]).status_code == 401
    assert code_step(client, codes[1]).status_code == 200
    assert client.get("/api/me").json()["recovery_codes_left"] == 8


def test_another_users_recovery_code_is_refused(app_started, client, registered, limits):
    _, codes = turn_on(client, registered)
    other_client = TestClient(app_started)
    other = {"email": unique_email(), "password": "another-good-password"}
    assert other_client.post("/api/auth/register", json=other).status_code == 200
    turn_on(other_client, other)
    password_step(other_client, other)
    assert code_step(other_client, codes[0]).status_code == 401


def test_wrong_codes_reach_the_limit_from_any_address(client, registered, limits):
    secret, _ = turn_on(client, registered)
    limits.TRUST_PROXY_HEADERS = True
    here = {"cf-connecting-ip": "203.0.113.5"}
    password_step(client, registered, headers=here)
    for _ in range(5):
        assert code_step(client, wrong_code(secret), headers=here).status_code == 401
    # A right code is refused too, until the block ends.
    r = code_step(client, fresh_code(registered["email"], secret), headers=here)
    assert r.status_code == 429 and int(r.headers["Retry-After"]) > 0
    # Another address gets past the password (its own count is clean) but not
    # the code: wrong codes are counted for the user, wherever they came from.
    there = {"cf-connecting-ip": "198.51.100.7"}
    assert password_step(client, registered, headers=there).status_code == 200
    r = code_step(client, fresh_code(registered["email"], secret), headers=there)
    assert r.status_code == 429
    assert client.get("/api/me").status_code == 401


def test_a_right_password_does_not_clear_the_wrong_codes(client, registered, limits):
    """Otherwise someone with the password could guess codes forever, four
    at a time."""
    secret, _ = turn_on(client, registered)
    for _ in range(5):
        assert password_step(client, registered).status_code == 200
        assert code_step(client, wrong_code(secret)).status_code == 401
    assert password_step(client, registered).status_code == 429


# ---------- The apps' password sign-in, POST /api/auth/token (#166) ----------

def app_token(client, user, **extra):
    client.cookies.clear()
    return client.post("/api/auth/token", json={
        "email": user["email"], "password": user["password"],
        "name": "phone", "access": "full", **extra})


def test_the_app_sign_in_asks_for_a_code(client, registered, limits):
    turn_on(client, registered)
    for extra in ({}, {"code": None}, {"code": "  "}):
        r = app_token(client, registered, **extra)
        assert r.status_code == 403
        body = r.json()
        assert body["two_factor_required"] is True and "token" not in body
        assert "two-factor" in body["detail"]
    assert events(registered["email"])[-1] == ("two_factor_asked", "token")


def test_the_app_sign_in_takes_a_code(app_started, client, registered, limits):
    secret, _ = turn_on(client, registered)
    r = app_token(client, registered, code=fresh_code(registered["email"], secret))
    assert r.status_code == 200
    body = r.json()
    assert body["token"].startswith("ww_") and body["access"] == "full"
    assert body["user"] == {"id": registered["id"], "email": registered["email"]}
    assert events(registered["email"])[-2:] == [
        ("login", "token; code"), ("token_created", f"token #{body['id']}, full; by sign-in")]
    # The token works, and no session cookie came with it.
    assert client.get("/api/me").status_code == 401
    phone = TestClient(app_started)
    me = phone.get("/api/me", headers={"Authorization": "Bearer " + body["token"]})
    assert me.status_code == 200 and me.json()["two_factor_enabled"] is True


def test_the_app_sign_in_refuses_a_wrong_or_used_code(client, registered, limits):
    secret, _ = turn_on(client, registered)
    r = app_token(client, registered, code=wrong_code(secret))
    assert r.status_code == 403
    assert r.json()["two_factor_required"] is True and "token" not in r.json()
    assert "isn't right" in r.json()["detail"]
    assert events(registered["email"])[-1] == ("login_failed", "token; wrong code")
    code = fresh_code(registered["email"], secret)
    assert app_token(client, registered, code=code).status_code == 200
    assert app_token(client, registered, code=code).status_code == 403


def test_the_app_sign_in_takes_a_recovery_code_once(client, registered, limits):
    _, codes = turn_on(client, registered)
    assert app_token(client, registered, code=codes[0]).status_code == 200
    kinds = events(registered["email"])
    assert ("recovery_code_used", "9 left") in kinds and ("login", "token; recovery code") in kinds
    assert app_token(client, registered, code=codes[0]).status_code == 403


def test_the_app_sign_in_checks_the_password_before_the_code(client, registered, limits):
    secret, _ = turn_on(client, registered)
    r = app_token(client, {**registered, "password": "not-my-password"},
                  code=fresh_code(registered["email"], secret))
    assert r.status_code == 401 and "two_factor_required" not in r.json()


def test_wrong_codes_at_the_app_sign_in_reach_the_limit(client, registered, limits):
    secret, _ = turn_on(client, registered)
    for _ in range(5):
        assert app_token(client, registered, code=wrong_code(secret)).status_code == 403
    r = app_token(client, registered, code=fresh_code(registered["email"], secret))
    assert r.status_code == 429 and int(r.headers["Retry-After"]) > 0
    # One count for the user: the web sign-in's code step is blocked too.
    limits.TRUST_PROXY_HEADERS = True
    there = {"cf-connecting-ip": "198.51.100.7"}
    assert password_step(client, registered, headers=there).status_code == 200
    assert code_step(client, fresh_code(registered["email"], secret), headers=there).status_code == 429


def test_the_app_sign_in_ignores_a_code_without_two_factor(client, registered, limits):
    r = app_token(client, registered, code="123456")
    assert r.status_code == 200 and r.json()["token"].startswith("ww_")


def test_users_without_it_sign_in_as_before(client, registered, limits):
    r = password_step(client, registered)
    assert r.status_code == 200
    assert r.json() == {"id": registered["id"], "email": registered["email"]}
    assert client.get("/api/me").status_code == 200
    r = code_step(client, "123456")
    assert r.status_code == 401


# ---------- Switching off, new recovery codes ----------

def test_switching_off_needs_the_password_and_a_code(client, registered, limits):
    secret, codes = turn_on(client, registered)
    r = client.post("/api/me/two-factor/disable", json={
        "password": "not-my-password", "code": fresh_code(registered["email"], secret)})
    assert r.status_code == 403
    r = client.post("/api/me/two-factor/disable", json={
        "password": registered["password"], "code": wrong_code(secret)})
    assert r.status_code == 403
    assert client.get("/api/me").json()["two_factor_enabled"] is True

    r = client.post("/api/me/two-factor/disable", json={
        "password": registered["password"], "code": fresh_code(registered["email"], secret)})
    assert r.status_code == 200 and r.json() == {"two_factor_enabled": False}
    me = client.get("/api/me").json()
    assert me["two_factor_enabled"] is False and me["recovery_codes_left"] == 0
    assert events(registered["email"])[-1] == ("two_factor_disabled", "own user")

    # The password alone signs in again, and the old codes are gone.
    r = password_step(client, registered)
    assert r.status_code == 200 and "two_factor_required" not in r.json()
    r = client.post("/api/me/two-factor/disable", json={
        "password": registered["password"], "code": codes[0]})
    assert r.status_code == 400


def test_new_recovery_codes_replace_the_old(client, registered, limits):
    secret, old = turn_on(client, registered)
    r = client.post("/api/me/two-factor/recovery-codes", json={
        "password": registered["password"], "code": wrong_code(secret)})
    assert r.status_code == 403
    r = client.post("/api/me/two-factor/recovery-codes", json={
        "password": registered["password"], "code": old[0]})
    assert r.status_code == 200
    new = r.json()["recovery_codes"]
    assert len(new) == 10 and not set(new) & set(old)
    assert client.get("/api/me").json()["recovery_codes_left"] == 10
    assert events(registered["email"])[-1] == ("recovery_codes_remade", None)

    password_step(client, registered)
    assert code_step(client, old[1]).status_code == 401
    assert code_step(client, new[0]).status_code == 200


def test_deleting_yourself_works_with_it_on(client, registered):
    secret, _ = turn_on(client, registered)
    # Deleting the user needs a current code (#169).
    r = client.request("DELETE", "/api/me", json={
        "password": registered["password"],
        "code": fresh_code(registered["email"], secret)})
    assert r.status_code == 200, r.text


# ---------- Admin ----------

def test_an_admin_can_switch_a_users_off(app_started, client, registered, limits):
    from app import main
    secret, _ = turn_on(client, registered)
    admin_client = TestClient(app_started)
    admin = {"email": unique_email(), "password": "admin-good-password"}
    assert admin_client.post("/api/auth/register", json=admin).status_code == 200
    main.ADMIN_EMAILS.add(admin["email"])
    try:
        users = admin_client.get("/api/admin/users").json()
        flags = {u["email"]: u["two_factor_enabled"] for u in users}
        assert flags[registered["email"]] is True and flags[admin["email"]] is False

        # Never on: only the user can do that, with their own phone.
        r = admin_client.patch(f"/api/admin/users/{registered['id']}", json={"two_factor": True})
        assert r.status_code == 400
        # Setting a password leaves it on.
        r = admin_client.patch(f"/api/admin/users/{registered['id']}",
                               json={"new_password": "a-brand-new-password"})
        assert r.status_code == 200
        registered["password"] = "a-brand-new-password"
        assert password_step(client, registered).json() == {"two_factor_required": True}

        r = admin_client.patch(f"/api/admin/users/{registered['id']}", json={"two_factor": False})
        assert r.status_code == 200
        assert events(admin["email"])[-1] == ("two_factor_disabled", f"user #{registered['id']}")
        users = admin_client.get("/api/admin/users").json()
        assert {u["email"]: u["two_factor_enabled"] for u in users}[registered["email"]] is False
    finally:
        main.ADMIN_EMAILS.discard(admin["email"])

    r = password_step(client, registered)
    assert r.status_code == 200 and "two_factor_required" not in r.json()
    assert client.get("/api/me").json()["two_factor_enabled"] is False


def test_a_user_who_is_not_an_admin_cannot(app_started, client, registered):
    turn_on(client, registered)
    other = TestClient(app_started)
    assert other.post("/api/auth/register", json={
        "email": unique_email(), "password": "another-good-password"}).status_code == 200
    r = other.patch(f"/api/admin/users/{registered['id']}", json={"two_factor": False})
    assert r.status_code == 403
    assert client.get("/api/me").json()["two_factor_enabled"] is True
