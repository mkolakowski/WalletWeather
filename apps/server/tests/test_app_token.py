"""Password sign-in for apps: POST /api/auth/token (#43)."""
from datetime import datetime, timedelta

import pytest
from fastapi.testclient import TestClient

from conftest import unique_email


@pytest.fixture
def limits():
    from app import main
    saved = (main.LOGIN_MAX_FAILURES, main.LOGIN_WINDOW_MINUTES, main.TRUST_PROXY_HEADERS)
    main.LOGIN_MAX_FAILURES, main.LOGIN_WINDOW_MINUTES, main.TRUST_PROXY_HEADERS = 5, 15, False
    yield main
    main.LOGIN_MAX_FAILURES, main.LOGIN_WINDOW_MINUTES, main.TRUST_PROXY_HEADERS = saved


def ask(client, email, password, **body):
    body = {"name": "iPhone", "access": "full", **body}
    return client.post("/api/auth/token", json={"email": email, "password": password, **body})


def bearer(app, token):
    c = TestClient(app)
    c.headers["Authorization"] = f"Bearer {token}"
    return c


def last_event(email):
    from app.db import AuditEvent, SessionLocal
    db = SessionLocal()
    try:
        r = (db.query(AuditEvent).filter_by(email=email.lower())
             .order_by(AuditEvent.id.desc()).first())
        return (r.event, r.detail) if r else None
    finally:
        db.close()


def test_a_right_password_returns_a_working_token(app_started, client, registered, limits):
    anon = TestClient(app_started)
    r = ask(anon, registered["email"], registered["password"])
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["token"].startswith("ww_")
    assert body["name"] == "iPhone" and body["access"] == "full"
    assert body["user"] == {"id": registered["id"], "email": registered["email"]}
    assert not anon.cookies  # a token, not a session
    tok = bearer(app_started, body["token"])
    assert tok.get("/api/accounts").status_code == 200
    # It's the owner's token like any other: listed in Settings, never shown again.
    [listed] = client.get("/api/tokens").json()
    assert listed["id"] == body["id"] and "token" not in listed
    assert last_event(registered["email"]) == ("login", "token")


def test_it_expires_in_90_days_unless_asked(client, registered, limits):
    r = ask(client, registered["email"], registered["password"])
    expires = datetime.fromisoformat(r.json()["expires_at"].rstrip("Z"))
    assert abs(expires - (datetime.utcnow() + timedelta(days=90))) < timedelta(minutes=1)
    r = ask(client, registered["email"], registered["password"], expires_in_days=30)
    expires = datetime.fromisoformat(r.json()["expires_at"].rstrip("Z"))
    assert abs(expires - (datetime.utcnow() + timedelta(days=30))) < timedelta(minutes=1)
    r = ask(client, registered["email"], registered["password"], expires_in_days=None)
    assert r.status_code == 200 and r.json()["expires_at"] is None


def test_a_read_only_token_is_read_only(app_started, client, registered, limits):
    r = ask(client, registered["email"], registered["password"], access="read")
    tok = bearer(app_started, r.json()["token"])
    assert tok.get("/api/accounts").status_code == 200
    w = tok.post("/api/accounts", json={"name": "x", "starting_balance": 0,
                                        "starting_date": "2026-01-01"})
    assert w.status_code == 403


def test_an_admin_token_is_refused_even_for_an_admin(client, registered, limits):
    from app import main
    main.ADMIN_EMAILS.add(registered["email"])
    try:
        r = ask(client, registered["email"], registered["password"], access="admin")
        assert r.status_code == 403
        assert client.get("/api/tokens").json() == []
    finally:
        main.ADMIN_EMAILS.discard(registered["email"])


@pytest.mark.parametrize("body,status", [
    ({"access": "owner"}, 400),
    ({"expires_in_days": 7}, 400),
    ({"name": "   "}, 400),
    ({"name": "x" * 81}, 422),
])
def test_bad_requests_are_refused_before_the_password_is_checked(client, registered, limits, body, status):
    before = last_event(registered["email"])
    assert ask(client, registered["email"], registered["password"], **body).status_code == status
    assert last_event(registered["email"]) == before
    assert client.get("/api/tokens").json() == []


def test_name_and_access_are_required(client, registered, limits):
    r = client.post("/api/auth/token", json={"email": registered["email"],
                                             "password": registered["password"]})
    assert r.status_code == 422


def test_a_wrong_password_gets_401_and_is_logged(client, registered, limits):
    r = ask(client, registered["email"], "wrong-password")
    assert r.status_code == 401
    assert last_event(registered["email"]) == ("login_failed", "token")
    assert client.get("/api/tokens").json() == []


def test_an_unknown_email_gets_the_same_401(client, limits):
    assert ask(client, unique_email(), "whatever-password").status_code == 401


def test_a_google_only_account_gets_401(client, limits):
    from app.db import SessionLocal, User
    email = unique_email()
    db = SessionLocal()
    try:
        db.add(User(email=email, google_sub="g-" + email))
        db.commit()
    finally:
        db.close()
    r = ask(client, email, "anything-at-all")
    assert r.status_code == 401
    assert last_event(email) == ("login_failed", "token; no password set")


def test_a_disabled_user_gets_403(client, registered, limits):
    from app.db import SessionLocal, User
    db = SessionLocal()
    try:
        db.get(User, registered["id"]).disabled = True
        db.commit()
        assert ask(client, registered["email"], registered["password"]).status_code == 403
    finally:
        db.get(User, registered["id"]).disabled = False
        db.commit()
        db.close()


def test_web_sign_in_failures_block_app_sign_in(client, registered, limits):
    client.cookies.clear()
    for _ in range(5):
        client.post("/api/auth/login", json={"email": registered["email"], "password": "x"})
    r = ask(client, registered["email"], registered["password"])
    assert r.status_code == 429 and "retry-after" in r.headers


def test_app_sign_in_failures_block_web_sign_in(client, registered, limits):
    client.cookies.clear()
    for _ in range(5):
        assert ask(client, registered["email"], "x").status_code == 401
    r = client.post("/api/auth/login", json={"email": registered["email"],
                                             "password": registered["password"]})
    assert r.status_code == 429
