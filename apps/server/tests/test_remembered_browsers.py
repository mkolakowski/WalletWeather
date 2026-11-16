"""Two-factor sign-in: remembered browsers (two-factor phase 3, #167)."""
import hashlib
from datetime import datetime, timedelta

import pytest
from fastapi.testclient import TestClient

from conftest import unique_email

COOKIE = "ww_remember"
IPHONE = ("Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 "
          "(KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1")


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
    """The password step from a browser that holds nothing (no cookies at all)."""
    client.cookies.clear()
    return client.post("/api/auth/login",
                       json={"email": user["email"], "password": user["password"]}, **kw)


def password_step_same_browser(client, user, password=None, **kw):
    """The password step from a browser that signed out: the sign-in session
    is gone, the ww_remember cookie stays."""
    client.cookies.delete("session")
    return client.post("/api/auth/login",
                       json={"email": user["email"],
                             "password": password or user["password"]}, **kw)


def code_step(client, code, **kw):
    return client.post("/api/auth/login/two-factor", json={"code": code}, **kw)


def remember_this_browser(client, user, secret, **kw):
    """Sign in with the code and ask to be remembered. Returns the response."""
    assert password_step(client, user, **kw).json() == {"two_factor_required": True}
    r = client.post("/api/auth/login/two-factor",
                    json={"code": fresh_code(user["email"], secret), "remember": True}, **kw)
    assert r.status_code == 200, r.text
    return r


def expire_all(user_id):
    from app.db import RememberedBrowser, SessionLocal
    db = SessionLocal()
    try:
        db.query(RememberedBrowser).filter_by(user_id=user_id).update(
            {RememberedBrowser.expires_at: datetime.utcnow() - timedelta(minutes=1)})
        db.commit()
    finally:
        db.close()


def stored_rows(user_id):
    from app.db import RememberedBrowser, SessionLocal
    db = SessionLocal()
    try:
        return [(r.id, r.token_hash, r.label)
                for r in db.query(RememberedBrowser).filter_by(user_id=user_id).all()]
    finally:
        db.close()


def make_admin(app_started):
    from app import main
    admin_client = TestClient(app_started)
    admin = {"email": unique_email(), "password": "admin-good-password"}
    assert admin_client.post("/api/auth/register", json=admin).status_code == 200
    main.ADMIN_EMAILS.add(admin["email"])
    return admin_client, admin


def signed_in_with_remembered(client, registered):
    """Two-factor on and this browser remembered; returns the secret."""
    secret, _ = turn_on(client, registered)
    remember_this_browser(client, registered, secret)
    assert len(stored_rows(registered["id"])) == 1
    return secret


# ---------- Remembering ----------

def test_remembered_browser_signs_in_with_the_password_alone(client, registered, limits):
    secret, _ = turn_on(client, registered)
    r = remember_this_browser(client, registered, secret)
    body = r.json()
    assert body["id"] == registered["id"] and body["email"] == registered["email"]
    assert body["remembered"] is True
    assert client.cookies.get(COOKIE)
    assert "httponly" in r.headers["set-cookie"].lower()
    assert ("browser_remembered", "30 days") in events(registered["email"])

    # Sign out (drop the session), then the password alone is enough.
    r = password_step_same_browser(client, registered)
    assert r.status_code == 200, r.text
    assert r.json() == {"id": registered["id"], "email": registered["email"]}
    assert "two_factor_required" not in r.json()
    assert client.get("/api/me").json()["email"] == registered["email"]
    assert events(registered["email"])[-1] == ("login", "password; remembered browser")


def test_without_remember_the_code_is_still_asked(client, registered, limits):
    secret, _ = turn_on(client, registered)
    assert password_step(client, registered).json() == {"two_factor_required": True}
    r = code_step(client, fresh_code(registered["email"], secret))
    assert r.status_code == 200 and r.json()["remembered"] is False
    assert client.cookies.get(COOKIE) is None
    assert stored_rows(registered["id"]) == []
    assert not any(e == "browser_remembered" for e, _ in events(registered["email"]))

    r = password_step_same_browser(client, registered)
    assert r.status_code == 200 and r.json() == {"two_factor_required": True}
    assert client.get("/api/me").status_code == 401


def test_an_expired_remembering_asks_for_the_code_and_is_not_listed(client, registered, limits):
    secret = signed_in_with_remembered(client, registered)
    assert len(client.get("/api/me/remembered-browsers").json()) == 1
    expire_all(registered["id"])

    assert client.get("/api/me/remembered-browsers").json() == []
    r = password_step_same_browser(client, registered)
    assert r.status_code == 200 and r.json() == {"two_factor_required": True}
    assert client.get("/api/me").status_code == 401

    # The code step still works, and remembering again lists the new one only.
    r = client.post("/api/auth/login/two-factor",
                    json={"code": fresh_code(registered["email"], secret), "remember": True})
    assert r.status_code == 200
    listed = client.get("/api/me/remembered-browsers").json()
    assert len(listed) == 1 and listed[0]["current"] is True


def test_a_forgotten_browser_is_asked_again(client, registered, limits):
    signed_in_with_remembered(client, registered)
    listed = client.get("/api/me/remembered-browsers").json()
    assert len(listed) == 1
    r = client.delete(f"/api/me/remembered-browsers/{listed[0]['id']}")
    assert r.status_code == 200 and r.json() == {"ok": True}
    assert ("browser_forgotten", "one browser") in events(registered["email"])
    assert client.get("/api/me/remembered-browsers").json() == []
    assert stored_rows(registered["id"]) == []

    r = password_step_same_browser(client, registered)
    assert r.status_code == 200 and r.json() == {"two_factor_required": True}


def test_forgetting_an_unknown_or_anothers_browser_is_404(app_started, client, registered, limits):
    signed_in_with_remembered(client, registered)
    mine = client.get("/api/me/remembered-browsers").json()[0]["id"]

    other = TestClient(app_started)
    assert other.post("/api/auth/register", json={
        "email": unique_email(), "password": "another-good-password"}).status_code == 200
    assert other.delete(f"/api/me/remembered-browsers/{mine}").status_code == 404
    assert other.delete("/api/me/remembered-browsers/999999999").status_code == 404
    # Still there for its owner.
    assert [b["id"] for b in client.get("/api/me/remembered-browsers").json()] == [mine]
    assert client.delete("/api/me/remembered-browsers/999999999").status_code == 404


def test_one_users_cookie_does_not_work_for_another(app_started, client, registered, limits):
    signed_in_with_remembered(client, registered)
    cookie = client.cookies.get(COOKIE)

    other_client = TestClient(app_started)
    other = {"email": unique_email(), "password": "another-good-password"}
    r = other_client.post("/api/auth/register", json=other)
    assert r.status_code == 200
    other["id"] = r.json()["id"]
    turn_on(other_client, other)

    other_client.cookies.clear()
    other_client.cookies.set(COOKIE, cookie)
    r = other_client.post("/api/auth/login",
                          json={"email": other["email"], "password": other["password"]})
    assert r.status_code == 200 and r.json() == {"two_factor_required": True}
    assert other_client.get("/api/me").status_code == 401
    assert events(other["email"])[-1] == ("two_factor_asked", "password")


def test_a_wrong_password_with_a_remembered_cookie_is_refused(client, registered, limits):
    signed_in_with_remembered(client, registered)
    r = password_step_same_browser(client, registered, password="not-the-password")
    assert r.status_code == 401
    assert client.get("/api/me").status_code == 401


# ---------- The list ----------

def test_the_list_shape_and_what_is_stored(client, registered, limits):
    secret, _ = turn_on(client, registered)
    remember_this_browser(client, registered, secret, headers={"User-Agent": IPHONE})
    cookie = client.cookies.get(COOKIE)

    r = client.get("/api/me/remembered-browsers")
    assert r.status_code == 200
    listed = r.json()
    assert len(listed) == 1
    row = listed[0]
    assert set(row) == {"id", "label", "created_at", "last_used_at", "expires_at", "current"}
    assert row["label"] == "Safari on iPhone"
    assert row["current"] is True
    created = datetime.fromisoformat(row["created_at"].replace("Z", "+00:00")).replace(tzinfo=None)
    expires = datetime.fromisoformat(row["expires_at"].replace("Z", "+00:00")).replace(tzinfo=None)
    assert row["last_used_at"]
    assert timedelta(days=29, hours=23) < expires - created <= timedelta(days=30, minutes=1)

    # Only the hash is kept, never the cookie.
    stored = stored_rows(registered["id"])
    assert len(stored) == 1
    _, token_hash, label = stored[0]
    assert token_hash != cookie
    assert token_hash == hashlib.sha256(cookie.encode()).hexdigest()
    assert label == "Safari on iPhone"

    # Another browser (no cookie) sees the same row, but not as "current".
    client.cookies.delete(COOKIE)
    row = client.get("/api/me/remembered-browsers").json()[0]
    assert row["current"] is False


def test_the_list_is_newest_first_with_current_marked(app_started, client, registered, limits):
    secret, _ = turn_on(client, registered)
    remember_this_browser(client, registered, secret, headers={"User-Agent": IPHONE})
    first_cookie = client.cookies.get(COOKIE)

    second = TestClient(app_started)
    remember_this_browser(second, registered, secret)
    assert second.cookies.get(COOKIE) != first_cookie

    listed = second.get("/api/me/remembered-browsers").json()
    assert len(listed) == 2
    assert listed[0]["id"] > listed[1]["id"]
    assert [b["current"] for b in listed] == [True, False]
    assert listed[1]["label"] == "Safari on iPhone"


def test_a_token_cannot_list_or_forget_browsers(client, registered, limits):
    secret = signed_in_with_remembered(client, registered)
    mine = client.get("/api/me/remembered-browsers").json()[0]["id"]
    # Making a token now needs a current code (#169).
    token = client.post("/api/tokens", json={
        "name": "script", "access": "full",
        "code": fresh_code(registered["email"], secret)}).json()["token"]
    client.cookies.clear()
    bearer = {"Authorization": "Bearer " + token}
    assert client.get("/api/me/remembered-browsers", headers=bearer).status_code == 403
    assert client.delete(f"/api/me/remembered-browsers/{mine}", headers=bearer).status_code == 403
    assert client.delete("/api/me/remembered-browsers", headers=bearer).status_code == 403
    assert len(stored_rows(registered["id"])) == 1


def test_the_list_needs_a_sign_in(client):
    assert client.get("/api/me/remembered-browsers").status_code == 401


# ---------- Forgetting them all ----------

def test_forget_all(app_started, client, registered, limits):
    secret, _ = turn_on(client, registered)
    remember_this_browser(client, registered, secret)
    second = TestClient(app_started)
    remember_this_browser(second, registered, secret)
    assert len(stored_rows(registered["id"])) == 2

    r = client.delete("/api/me/remembered-browsers")
    assert r.status_code == 200 and r.json() == {"forgotten": 2}
    assert stored_rows(registered["id"]) == []
    assert client.get("/api/me/remembered-browsers").json() == []
    assert ("browser_forgotten", "all, 2 browsers") in events(registered["email"])

    # Nothing left to forget.
    r = client.delete("/api/me/remembered-browsers")
    assert r.status_code == 200 and r.json() == {"forgotten": 0}

    # Neither browser skips the code now.
    assert password_step_same_browser(client, registered).json() == {"two_factor_required": True}
    assert password_step_same_browser(second, registered).json() == {"two_factor_required": True}


# ---------- What forgets them on its own ----------

def test_switching_two_factor_off_forgets_them(client, registered, limits):
    secret = signed_in_with_remembered(client, registered)
    r = client.post("/api/me/two-factor/disable", json={
        "password": registered["password"],
        "code": fresh_code(registered["email"], secret)})
    assert r.status_code == 200, r.text
    assert stored_rows(registered["id"]) == []
    assert client.get("/api/me/remembered-browsers").json() == []


def test_an_admin_switching_it_off_forgets_them(app_started, client, registered, limits):
    from app import main
    signed_in_with_remembered(client, registered)
    admin_client, admin = make_admin(app_started)
    try:
        r = admin_client.patch(f"/api/admin/users/{registered['id']}", json={"two_factor": False})
        assert r.status_code == 200, r.text
    finally:
        main.ADMIN_EMAILS.discard(admin["email"])
    assert stored_rows(registered["id"]) == []


def test_changing_your_own_password_forgets_them(client, registered, limits):
    secret = signed_in_with_remembered(client, registered)
    # A password change needs a current code (#169).
    r = client.post("/api/me/password", json={
        "current_password": registered["password"], "new_password": "a-brand-new-password",
        "code": fresh_code(registered["email"], secret)})
    assert r.status_code == 200, r.text
    assert stored_rows(registered["id"]) == []
    registered["password"] = "a-brand-new-password"
    # Two-factor is still on, and this browser is asked for the code again.
    r = password_step_same_browser(client, registered)
    assert r.status_code == 200 and r.json() == {"two_factor_required": True}


def test_a_wrong_current_password_keeps_them(client, registered, limits):
    signed_in_with_remembered(client, registered)
    r = client.post("/api/me/password", json={
        "current_password": "not-my-password", "new_password": "a-brand-new-password"})
    assert r.status_code == 403
    assert len(stored_rows(registered["id"])) == 1


def test_an_admin_password_reset_forgets_them(app_started, client, registered, limits):
    from app import main
    signed_in_with_remembered(client, registered)
    admin_client, admin = make_admin(app_started)
    try:
        r = admin_client.patch(f"/api/admin/users/{registered['id']}",
                               json={"new_password": "reset-by-the-admin"})
        assert r.status_code == 200, r.text
    finally:
        main.ADMIN_EMAILS.discard(admin["email"])
    assert stored_rows(registered["id"]) == []
    registered["password"] = "reset-by-the-admin"
    r = password_step_same_browser(client, registered)
    assert r.status_code == 200 and r.json() == {"two_factor_required": True}
