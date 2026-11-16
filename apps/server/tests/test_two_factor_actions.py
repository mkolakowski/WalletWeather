"""A code for sensitive actions (two-factor phase 5, #169): with two-factor on,
changing the password, deleting the user, making a token and allowing an app in
each need a current authenticator code or an unused recovery code, every time.
Wrong codes are recorded and counted toward the per-user code limit."""
import base64
import hashlib
import secrets

import pytest

from conftest import unique_email

NEEDED = "Two-factor sign-in is on"
WRONG = "That code isn't right"
USED = "already been used"
STATE = "state-1234"


# ---------- Helpers (copied from test_two_factor.py) ----------

@pytest.fixture
def limits():
    """The app module with its limits at the defaults the tests assume, put
    back afterwards."""
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
    """A code the server will take now (the last step used is forgotten)."""
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


def challenge():
    verifier = secrets.token_urlsafe(48)
    return base64.urlsafe_b64encode(
        hashlib.sha256(verifier.encode()).digest()).rstrip(b"=").decode()


# ---------- The four actions, and the two that already had a code ----------

def _body(extra, code, field):
    body = dict(extra)
    if code is not None:
        body[field] = code
    return body


def do_password(client, user, code, password=None):
    return client.post("/api/me/password", json=_body(
        {"current_password": password or user["password"],
         "new_password": "another-long-password"}, code, "code"))


def do_delete(client, user, code, password=None):
    return client.request("DELETE", "/api/me", json=_body(
        {"password": password or user["password"]}, code, "code"))


def do_token(client, user, code, password=None, access="full"):
    return client.post("/api/tokens", json=_body(
        {"name": "ci", "access": access, "expires_in_days": 30}, code, "code"))


def do_app(client, user, code, password=None):
    return client.post("/api/app-sign-in", json=_body(
        {"name": "iPhone", "access": "full", "code_challenge": challenge(),
         "state": STATE}, code, "two_factor_code"))


def do_disable(client, user, code, password=None):
    return client.post("/api/me/two-factor/disable", json={
        "password": password or user["password"], "code": code or ""})


def do_recovery(client, user, code, password=None):
    return client.post("/api/me/two-factor/recovery-codes", json={
        "password": password or user["password"], "code": code or ""})


ACTIONS = {
    "password change": do_password,
    "account deletion": do_delete,
    "token": do_token,
    "app sign-in": do_app,
}
ALL_ACTIONS = {**ACTIONS, "two-factor off": do_disable, "recovery codes": do_recovery}
all_action_names = pytest.mark.parametrize("action", list(ALL_ACTIONS))


@pytest.fixture
def secured(client, registered):
    """A signed-in user with two-factor on: (user, secret, recovery codes)."""
    secret, recovery = turn_on(client, registered)
    return registered, secret, recovery


def failures(email, action):
    return [e for e in events(email) if e == ("login_failed", f"{action}; wrong code")]


# ---------- No code, wrong code, right code ----------

@all_action_names
def test_no_code_is_refused(client, secured, limits, action):
    user, secret, _ = secured
    for missing in (None, "", "   "):
        r = ALL_ACTIONS[action](client, user, missing)
        assert r.status_code == 403, r.text
        assert NEEDED in r.json()["detail"]
    # Nothing was done and nothing was counted as a wrong guess.
    assert failures(user["email"], action) == []
    assert client.get("/api/me").status_code == 200


@all_action_names
def test_a_wrong_code_is_refused_and_recorded(client, secured, limits, action):
    user, secret, _ = secured
    r = ALL_ACTIONS[action](client, user, wrong_code(secret))
    assert r.status_code == 403, r.text
    assert WRONG in r.json()["detail"]
    assert ("login_failed", f"{action}; wrong code") in events(user["email"])
    # Still signed in, still the same password, two-factor still on.
    me = client.get("/api/me").json()
    assert me["two_factor_enabled"] is True
    assert client.post("/api/auth/login", json={
        "email": user["email"], "password": user["password"]}).status_code == 200


def test_a_right_code_changes_the_password(client, secured, limits):
    user, secret, _ = secured
    r = do_password(client, user, fresh_code(user["email"], secret))
    assert r.status_code == 200 and r.json() == {"ok": True}
    assert ("password_changed", None) in events(user["email"])
    client.cookies.clear()
    r = client.post("/api/auth/login", json={
        "email": user["email"], "password": "another-long-password"})
    assert r.status_code == 200


def test_a_right_code_deletes_the_user(client, secured, limits):
    user, secret, _ = secured
    r = do_delete(client, user, fresh_code(user["email"], secret))
    assert r.status_code == 200 and r.json() == {"ok": True}
    assert client.get("/api/me").status_code == 401


@pytest.mark.parametrize("access", ["read", "full"])
def test_a_right_code_makes_a_token(client, secured, limits, access):
    user, secret, _ = secured
    r = do_token(client, user, fresh_code(user["email"], secret), access=access)
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["access"] == access and body["token"] and body["name"] == "ci"
    assert body["id"] in [t["id"] for t in client.get("/api/tokens").json()]


def test_an_admin_token_needs_a_code_too(client, secured, limits, monkeypatch):
    from app import main
    user, secret, _ = secured
    monkeypatch.setattr(main, "is_admin", lambda u: True)
    r = do_token(client, user, None, access="admin")
    assert r.status_code == 403 and NEEDED in r.json()["detail"]
    r = do_token(client, user, wrong_code(secret), access="admin")
    assert r.status_code == 403 and WRONG in r.json()["detail"]
    r = do_token(client, user, fresh_code(user["email"], secret), access="admin")
    assert r.status_code == 200 and r.json()["access"] == "admin"


def test_a_right_code_allows_an_app_in(client, secured, limits):
    user, secret, _ = secured
    r = do_app(client, user, fresh_code(user["email"], secret))
    assert r.status_code == 200, r.text
    assert "walletweather://" in r.text


# ---------- A code already used ----------

@all_action_names
def test_a_code_works_once(client, secured, limits, action):
    """A code just spent (here on a token) is "already used", not "wrong", for
    every action, and isn't counted as a guess."""
    user, secret, _ = secured
    code = fresh_code(user["email"], secret)
    assert do_token(client, user, code).status_code == 200
    # The same code again, with the used step not forgotten between the two
    # (the same string, so a step boundary between the tries can't flake it).
    again = code
    r = ALL_ACTIONS[action](client, user, again)
    assert r.status_code == 403, r.text
    assert USED in r.json()["detail"]
    assert [e for e in events(user["email"]) if e[0] == "login_failed"] == []
    assert client.get("/api/me").json()["two_factor_enabled"] is True


def test_the_same_code_is_not_good_for_two_actions(client, secured, limits):
    user, secret, _ = secured
    code = fresh_code(user["email"], secret)
    assert do_password(client, user, code).status_code == 200
    again = code
    r = do_password(client, user, again, password="another-long-password")
    assert r.status_code == 403 and USED in r.json()["detail"]


# ---------- A recovery code ----------

def test_a_recovery_code_works_once(client, secured, limits):
    user, secret, recovery = secured
    r = do_token(client, user, recovery[0])
    assert r.status_code == 200, r.text
    assert ("recovery_code_used", "token; 9 left") in events(user["email"])
    r = do_token(client, user, recovery[0])
    assert r.status_code == 403 and WRONG in r.json()["detail"]
    assert ("login_failed", "token; wrong code") in events(user["email"])
    assert client.get("/api/me").json()["recovery_codes_left"] == 9


def test_a_recovery_code_confirms_a_password_change(client, secured, limits):
    user, secret, recovery = secured
    r = do_password(client, user, recovery[1])
    assert r.status_code == 200
    assert ("recovery_code_used", "password change; 9 left") in events(user["email"])


# ---------- The limit ----------

@all_action_names
def test_wrong_codes_are_limited(client, secured, limits, action):
    user, secret, _ = secured
    for _ in range(limits.LOGIN_MAX_FAILURES):
        r = ALL_ACTIONS[action](client, user, wrong_code(secret))
        assert r.status_code == 403
    # Even the right code is turned away now.
    r = ALL_ACTIONS[action](client, user, fresh_code(user["email"], secret))
    assert r.status_code == 429, r.text
    assert "Too many wrong codes" in r.json()["detail"]
    assert int(r.headers["Retry-After"]) > 0
    assert client.get("/api/me").json()["two_factor_enabled"] is True


def test_the_limit_is_shared_between_actions(client, secured, limits):
    user, secret, _ = secured
    names = list(ALL_ACTIONS)
    for i in range(limits.LOGIN_MAX_FAILURES):
        r = ALL_ACTIONS[names[i % len(names)]](client, user, wrong_code(secret))
        assert r.status_code == 403
    r = do_token(client, user, fresh_code(user["email"], secret))
    assert r.status_code == 429


def test_a_missing_code_or_used_code_is_not_counted(client, secured, limits):
    user, secret, _ = secured
    for _ in range(limits.LOGIN_MAX_FAILURES + 2):
        assert do_token(client, user, None).status_code == 403
    assert do_token(client, user, fresh_code(user["email"], secret)).status_code == 200


# ---------- The password comes first ----------

@pytest.mark.parametrize("do", [do_password, do_delete, do_disable, do_recovery])
def test_the_password_is_checked_before_the_code(client, secured, limits, do):
    user, secret, _ = secured
    code = fresh_code(user["email"], secret)
    r = do(client, user, code, password="not-my-password")
    assert r.status_code == 403
    assert r.json()["detail"] == "That password is incorrect."
    # The code wasn't spent, and a wrong password isn't a wrong code.
    assert [e for e in events(user["email"]) if e[0] == "login_failed"] == []
    if do is do_disable:
        return
    from app import twofactor
    again = twofactor.code_at(secret, twofactor.current_step())
    r = do(client, user, again)
    assert r.status_code == 200, r.text


# ---------- Disable and recovery codes now count wrong codes ----------

def test_disable_still_works_with_a_right_code(client, secured, limits):
    user, secret, _ = secured
    r = do_disable(client, user, fresh_code(user["email"], secret))
    assert r.status_code == 200 and r.json() == {"two_factor_enabled": False}
    assert client.get("/api/me").json()["two_factor_enabled"] is False


def test_new_recovery_codes_still_work_with_a_right_code(client, secured, limits):
    user, secret, _ = secured
    r = do_recovery(client, user, fresh_code(user["email"], secret))
    assert r.status_code == 200
    assert len(r.json()["recovery_codes"]) == 10


# ---------- Users without two-factor ----------

def test_no_code_is_needed_without_two_factor(client, registered, limits):
    assert client.get("/api/me").json()["two_factor_enabled"] is False
    assert do_token(client, registered, None).status_code == 200
    assert do_app(client, registered, None).status_code == 200
    assert do_password(client, registered, None).status_code == 200
    registered["password"] = "another-long-password"
    assert do_delete(client, registered, None).status_code == 200
    assert client.get("/api/me").status_code == 401


def test_a_code_sent_without_two_factor_is_ignored(client, registered, limits):
    assert do_token(client, registered, "123456").status_code == 200
    assert [e for e in events(registered["email"])
            if e[0] in ("login_failed", "recovery_code_used")] == []
