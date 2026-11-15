"""Login rate limiting and sign-in events (login-limits phase 1, #132)."""
from datetime import datetime, timedelta

import pytest
from fastapi.testclient import TestClient

from conftest import unique_email


@pytest.fixture
def limits():
    """The app module with its limits at the defaults the tests assume, put
    back afterwards (they're module settings read at start-up)."""
    from app import main
    saved = (main.LOGIN_MAX_FAILURES, main.LOGIN_WINDOW_MINUTES, main.TRUST_PROXY_HEADERS)
    main.LOGIN_MAX_FAILURES, main.LOGIN_WINDOW_MINUTES, main.TRUST_PROXY_HEADERS = 5, 15, False
    yield main
    main.LOGIN_MAX_FAILURES, main.LOGIN_WINDOW_MINUTES, main.TRUST_PROXY_HEADERS = saved


def login(client, email, password, **kw):
    return client.post("/api/auth/login", json={"email": email, "password": password}, **kw)


def events(email):
    from app.db import AuditEvent, SessionLocal
    db = SessionLocal()
    try:
        rows = (db.query(AuditEvent).filter_by(email=email.lower())
                .order_by(AuditEvent.id).all())
        return [{"event": r.event, "user_id": r.user_id, "ip": r.ip, "detail": r.detail,
                 "created_at": r.created_at} for r in rows]
    finally:
        db.close()


def age_events(email, by):
    """Move this email's events back in time (the window can't be waited out)."""
    from app.db import AuditEvent, SessionLocal
    db = SessionLocal()
    try:
        for r in db.query(AuditEvent).filter_by(email=email.lower()):
            r.created_at = r.created_at - by
        db.commit()
    finally:
        db.close()


def fail(client, email, times, **kw):
    for _ in range(times):
        assert login(client, email, "wrong-password", **kw).status_code == 401


def test_a_right_password_signs_in_and_is_recorded(client, registered, limits):
    client.cookies.clear()
    r = login(client, registered["email"], registered["password"])
    assert r.status_code == 200
    assert client.get("/api/accounts").status_code == 200
    last = events(registered["email"])[-1]
    assert last["event"] == "login" and last["user_id"] == registered["id"]
    assert last["detail"] == "password" and last["ip"] == "testclient"


def test_a_wrong_password_is_recorded_without_the_password(client, registered, limits):
    client.cookies.clear()
    assert login(client, registered["email"], "hunter2-not-it").status_code == 401
    last = events(registered["email"])[-1]
    assert last["event"] == "login_failed" and last["user_id"] == registered["id"]
    assert "hunter2" not in repr(events(registered["email"]))


def test_the_sixth_failure_is_blocked_with_retry_after(client, registered, limits):
    client.cookies.clear()
    fail(client, registered["email"], 5)
    r = login(client, registered["email"], "wrong-password")
    assert r.status_code == 429
    assert 0 < int(r.headers["retry-after"]) <= 15 * 60
    assert r.json()["detail"].startswith("Too many failed sign-ins. Try again in ")
    assert events(registered["email"])[-1]["event"] == "login_blocked"


def test_a_right_password_is_refused_during_a_block(client, registered, limits):
    client.cookies.clear()
    fail(client, registered["email"], 5)
    assert login(client, registered["email"], registered["password"]).status_code == 429
    assert client.get("/api/accounts").status_code == 401


def test_trying_during_a_block_does_not_make_it_longer(client, registered, limits):
    client.cookies.clear()
    fail(client, registered["email"], 5)
    first = int(login(client, registered["email"], "x").headers["retry-after"])
    for _ in range(3):
        login(client, registered["email"], "x")
    again = int(login(client, registered["email"], "x").headers["retry-after"])
    assert again <= first
    assert [e["event"] for e in events(registered["email"])].count("login_failed") == 5


def test_a_right_password_before_the_limit_clears_the_count(client, registered, limits):
    client.cookies.clear()
    fail(client, registered["email"], 4)
    assert login(client, registered["email"], registered["password"]).status_code == 200
    client.cookies.clear()
    fail(client, registered["email"], 4)
    assert login(client, registered["email"], registered["password"]).status_code == 200


def test_the_block_ends_once_the_window_has_passed(client, registered, limits):
    client.cookies.clear()
    fail(client, registered["email"], 5)
    assert login(client, registered["email"], registered["password"]).status_code == 429
    age_events(registered["email"], timedelta(minutes=15, seconds=5))
    assert login(client, registered["email"], registered["password"]).status_code == 200


def test_failures_spread_wider_than_the_window_dont_block(client, registered, limits):
    client.cookies.clear()
    fail(client, registered["email"], 4)
    age_events(registered["email"], timedelta(minutes=20))
    fail(client, registered["email"], 1)
    assert login(client, registered["email"], registered["password"]).status_code == 200


def test_another_email_from_the_same_address_is_not_blocked(app_started, client, registered, limits):
    client.cookies.clear()
    fail(client, registered["email"], 5)
    other_email, pw = unique_email(), "correct-horse-battery"
    TestClient(app_started).post("/api/auth/register", json={"email": other_email, "password": pw})
    assert login(client, other_email, pw).status_code == 200


def test_an_unknown_email_is_counted_and_blocked_the_same_way(client, limits):
    ghost = unique_email()
    fail(client, ghost, 5)
    r = login(client, ghost, "wrong-password")
    assert r.status_code == 429 and "retry-after" in r.headers
    assert [e["event"] for e in events(ghost)] == ["login_failed"] * 5 + ["login_blocked"]
    assert all(e["user_id"] is None for e in events(ghost))


def test_the_email_is_matched_whatever_its_case(client, registered, limits):
    client.cookies.clear()
    fail(client, registered["email"].upper(), 5)
    assert login(client, registered["email"], registered["password"]).status_code == 429


def test_cf_connecting_ip_is_ignored_unless_switched_on(client, registered, limits):
    client.cookies.clear()
    for n in range(5):
        login(client, registered["email"], "x", headers={"CF-Connecting-IP": f"203.0.113.{n}"})
    # Off: every request is the connection's address, so it's blocked even
    # with a "new" forwarded address, and the rows don't hold the header.
    r = login(client, registered["email"], registered["password"],
              headers={"CF-Connecting-IP": "198.51.100.7"})
    assert r.status_code == 429
    assert {e["ip"] for e in events(registered["email"])} == {"testclient"}


def test_cf_connecting_ip_is_used_when_switched_on(client, registered, limits):
    limits.TRUST_PROXY_HEADERS = True
    client.cookies.clear()
    fail(client, registered["email"], 5, headers={"CF-Connecting-IP": "203.0.113.9"})
    blocked = login(client, registered["email"], registered["password"],
                    headers={"CF-Connecting-IP": "203.0.113.9"})
    assert blocked.status_code == 429
    # Another visitor through the same tunnel isn't blocked.
    ok = login(client, registered["email"], registered["password"],
               headers={"CF-Connecting-IP": "198.51.100.7"})
    assert ok.status_code == 200
    ips = [e["ip"] for e in events(registered["email"])]
    assert ips[:5] == ["203.0.113.9"] * 5 and ips[-1] == "198.51.100.7"


def test_the_limits_come_from_the_settings(client, registered, limits):
    limits.LOGIN_MAX_FAILURES = 2
    client.cookies.clear()
    fail(client, registered["email"], 2)
    assert login(client, registered["email"], registered["password"]).status_code == 429


def test_a_disabled_users_right_password_is_recorded_as_failed(client, registered, limits):
    from app.db import SessionLocal, User
    db = SessionLocal()
    try:
        db.get(User, registered["id"]).disabled = True
        db.commit()
        client.cookies.clear()
        assert login(client, registered["email"], registered["password"]).status_code == 403
        last = events(registered["email"])[-1]
        assert last["event"] == "login_failed" and "disabled" in last["detail"]
    finally:
        db.get(User, registered["id"]).disabled = False
        db.commit()
        db.close()


def _rows_by_id(ids):
    from app.db import AuditEvent, SessionLocal
    db = SessionLocal()
    try:
        return [(r.email, r.user_id, r.event) for r in
                db.query(AuditEvent).filter(AuditEvent.id.in_(ids)).order_by(AuditEvent.id)]
    finally:
        db.close()


def _ids_for(email):
    from app.db import AuditEvent, SessionLocal
    db = SessionLocal()
    try:
        return [r.id for r in db.query(AuditEvent).filter_by(email=email.lower())]
    finally:
        db.close()


def test_deleting_yourself_keeps_your_events_without_your_email(client, registered, limits):
    """Decided 2026-11-15 (#139): the rows stay, the email and the link go."""
    client.cookies.clear()
    login(client, registered["email"], "wrong-password")
    login(client, registered["email"], registered["password"])
    ids = _ids_for(registered["email"])
    assert len(ids) >= 2
    r = client.request("DELETE", "/api/me", json={"password": registered["password"]})
    assert r.status_code == 200
    rows = _rows_by_id(ids)
    assert len(rows) == len(ids)
    assert all(email is None and user_id is None for (email, user_id, _) in rows)
    assert {e for (_, _, e) in rows} >= {"login", "login_failed"}


def test_an_admin_deleting_a_user_blanks_their_email_too(app_started, client, registered, limits):
    from app import main
    main.ADMIN_EMAILS.add(registered["email"])
    try:
        victim = TestClient(app_started)
        email, pw = unique_email(), "correct-horse-battery"
        uid = victim.post("/api/auth/register", json={"email": email, "password": pw}).json()["id"]
        victim.cookies.clear()
        login(victim, email, pw)
        # A failed try on their address with the email typed in capitals.
        login(TestClient(app_started), email.upper(), "nope-nope")
        ids = _ids_for(email)
        assert client.delete(f"/api/admin/users/{uid}").status_code == 200
        rows = _rows_by_id(ids)
        assert len(rows) == len(ids) and all(r[0] is None and r[1] is None for r in rows)
    finally:
        main.ADMIN_EMAILS.discard(registered["email"])


def test_deleting_a_user_leaves_other_peoples_events_alone(app_started, client, registered, limits):
    other_email = unique_email()
    login(TestClient(app_started), other_email, "whatever-pw")
    client.cookies.clear()
    login(client, registered["email"], registered["password"])
    client.request("DELETE", "/api/me", json={"password": registered["password"]})
    assert events(other_email) and all(e["event"] == "login_failed" for e in events(other_email))
