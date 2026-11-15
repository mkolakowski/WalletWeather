"""The audit log viewer and pruning (login-limits phase 3, #134):
GET /api/admin/audit and prune_audit_events.

Rows are written straight to the table with an email unique to the test, and
each test filters on it, since the shared test database holds every other
test's events too.
"""
from datetime import datetime, timedelta

import pytest
from fastapi.testclient import TestClient

from conftest import unique_email

PASSWORD = "correct-horse-battery"


def register(app):
    c = TestClient(app)
    email = unique_email()
    r = c.post("/api/auth/register", json={"email": email, "password": PASSWORD})
    assert r.status_code == 200, r.text
    return c, {"email": email, "id": r.json()["id"]}


@pytest.fixture
def admin(app_started):
    from app import main
    c, u = register(app_started)
    main.ADMIN_EMAILS.add(u["email"])
    yield c, u
    main.ADMIN_EMAILS.discard(u["email"])


def add_events(email, events, user_id=None, age=timedelta(0), detail=None):
    """Write audit rows directly; returns their ids, oldest first."""
    from app.db import AuditEvent, SessionLocal
    db = SessionLocal()
    try:
        rows = [AuditEvent(event=e, email=email, user_id=user_id, ip="198.51.100.7",
                           detail=detail, created_at=datetime.utcnow() - age)
                for e in events]
        db.add_all(rows)
        db.commit()
        return [r.id for r in rows]
    finally:
        db.close()


def ids_for(email):
    from app.db import AuditEvent, SessionLocal
    db = SessionLocal()
    try:
        return [i for (i,) in db.query(AuditEvent.id).filter_by(email=email).order_by(AuditEvent.id)]
    finally:
        db.close()


def token(app, c, access):
    made = c.post("/api/tokens", json={"name": "t", "access": access})
    assert made.status_code == 200, made.text
    t = TestClient(app)
    t.headers["Authorization"] = f"Bearer {made.json()['token']}"
    return t


# ---------- The endpoint ----------

def test_lists_newest_first_with_the_fields_the_panel_reads(admin):
    ac, a = admin
    email = unique_email()
    ids = add_events(email, ["login_failed", "login"], user_id=a["id"])
    r = ac.get("/api/admin/audit", params={"email": email})
    assert r.status_code == 200
    body = r.json()
    assert [e["id"] for e in body["events"]] == ids[::-1]
    first = body["events"][0]
    assert set(first) == {"id", "created_at", "event", "user_id", "email", "ip", "detail"}
    assert first["event"] == "login" and first["email"] == email
    assert first["ip"] == "198.51.100.7" and first["created_at"].endswith("Z")
    assert body["next"] is None
    assert "password_changed" in body["event_types"] and "login" in body["event_types"]
    assert body["retention_days"] == 180
    assert body["users"] == {str(a["id"]): a["email"]}


def test_filters_by_event_and_by_part_of_the_email_in_any_case(admin):
    ac, _ = admin
    email = unique_email()
    add_events(email, ["login", "login_failed", "login_failed"])
    r = ac.get("/api/admin/audit", params={"email": email.upper()[5:20], "event": "login_failed"})
    events = [e for e in r.json()["events"] if e["email"] == email]
    assert [e["event"] for e in events] == ["login_failed", "login_failed"]
    assert all(e["event"] == "login_failed" for e in r.json()["events"])


def test_a_wildcard_in_the_email_filter_matches_only_itself(admin):
    ac, _ = admin
    r = ac.get("/api/admin/audit", params={"email": "%"})
    assert r.status_code == 200
    assert all("%" in (e["email"] or "") for e in r.json()["events"])


def test_pages_with_the_cursor(admin):
    ac, _ = admin
    email = unique_email()
    ids = add_events(email, ["login"] * 5)
    seen, before = [], None
    for _ in range(3):
        params = {"email": email, "limit": 2}
        if before:
            params["before"] = before
        body = ac.get("/api/admin/audit", params=params).json()
        seen += [e["id"] for e in body["events"]]
        before = body["next"]
        if not before:
            break
    assert seen == ids[::-1]
    assert before is None


def test_names_users_referred_to_in_details_while_they_exist(app_started, admin):
    ac, a = admin
    _, u = register(app_started)
    email = unique_email()
    add_events(email, ["password_reset"], user_id=a["id"],
               detail=f"user #{u['id']}")
    add_events(email, ["user_deleted"], user_id=a["id"], detail="user #999999999")
    body = ac.get("/api/admin/audit", params={"email": email}).json()
    assert body["users"][str(u["id"])] == u["email"]
    assert "999999999" not in body["users"]


def test_a_non_admin_is_refused(app_started):
    c, _ = register(app_started)
    assert c.get("/api/admin/audit").status_code == 403


def test_signed_out_is_refused(client):
    assert client.get("/api/admin/audit").status_code == 401


def test_read_and_full_tokens_are_refused_and_an_admin_token_works(app_started, admin):
    ac, _ = admin
    assert token(app_started, ac, "read").get("/api/admin/audit").status_code == 403
    assert token(app_started, ac, "full").get("/api/admin/audit").status_code == 403
    assert token(app_started, ac, "admin").get("/api/admin/audit").status_code == 200


def test_a_bad_cursor_is_refused(admin):
    ac, _ = admin
    assert ac.get("/api/admin/audit", params={"before": "abc"}).status_code == 422


# ---------- Pruning ----------

def test_pruning_deletes_old_events_and_keeps_recent_ones(app_started):
    from app import main
    from app.db import SessionLocal
    email = unique_email()
    old = add_events(email, ["login"], age=timedelta(days=181))
    recent = add_events(email, ["login"], age=timedelta(days=179))
    db = SessionLocal()
    try:
        assert main.prune_audit_events(db) >= 1
    finally:
        db.close()
    assert ids_for(email) == recent
    assert old[0] not in ids_for(email)


def test_pruning_never_deletes_anything_newer_than_a_day(app_started, monkeypatch):
    from app import main
    from app.db import SessionLocal
    monkeypatch.setattr(main, "AUDIT_RETENTION_DAYS", 0)
    email = unique_email()
    kept = add_events(email, ["login_failed"], age=timedelta(hours=23))
    gone = add_events(email, ["login_failed"], age=timedelta(hours=25))
    db = SessionLocal()
    try:
        main.prune_audit_events(db)
    finally:
        db.close()
    assert ids_for(email) == kept and gone[0] not in ids_for(email)
