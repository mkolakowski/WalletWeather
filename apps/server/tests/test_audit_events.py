"""More audit events (login-limits phase 2, #133), and changing your own
password (POST /api/me/password).

Each action leaves one audit_events row naming who did it (`user_id`) and,
for an action on someone else, who it was done to by number in `detail`
("user #7"), never by email and never with amounts or account names. A
refused action (a 403, a wrong password, a 404) writes nothing.

Not covered: the scheduled backup's event (it runs from a background thread
every 30 minutes, which the tests don't start). Its call is the same
record_event as the manual backup's.
"""
from datetime import date

import pytest
from fastapi.testclient import TestClient

from conftest import unique_email

PASSWORD = "correct-horse-battery"


def register(app):
    """A new signed-in user with their own client (their own cookies)."""
    c = TestClient(app)
    email = unique_email()
    r = c.post("/api/auth/register", json={"email": email, "password": PASSWORD})
    assert r.status_code == 200, r.text
    return c, {"email": email, "id": r.json()["id"]}


@pytest.fixture
def admin(app_started):
    """A signed-in admin (ADMIN_EMAILS is read at start-up, so the address is
    added and taken out again)."""
    from app import main
    c, u = register(app_started)
    main.ADMIN_EMAILS.add(u["email"])
    yield c, u
    main.ADMIN_EMAILS.discard(u["email"])


def events(user_id):
    """Every audit event done by this user, oldest first, sign-ins left out."""
    from app.db import AuditEvent, SessionLocal
    db = SessionLocal()
    try:
        rows = (db.query(AuditEvent).filter(AuditEvent.user_id == user_id,
                                            ~AuditEvent.event.like("login%"))
                .order_by(AuditEvent.id).all())
        return [{"event": r.event, "email": r.email, "detail": r.detail, "ip": r.ip}
                for r in rows]
    finally:
        db.close()


def last(user_id):
    rows = events(user_id)
    assert rows, "no event was written"
    return rows[-1]


def make_account(c, name="Secret savings"):
    r = c.post("/api/accounts", json={
        "name": name, "starting_balance": 4321.0,
        "starting_date": date.today().isoformat()})
    assert r.status_code == 200, r.text
    return r.json()["id"]


def no_financial_data(row):
    text = repr(row)
    assert "Secret savings" not in text and "4321" not in text


# ---------- Your own password ----------

def test_me_says_whether_you_have_a_password(client, registered):
    r = client.get("/api/me")
    assert r.status_code == 200
    assert r.json()["has_password"] is True


def test_changing_your_password_works_and_is_recorded(app_started):
    c, u = register(app_started)
    r = c.post("/api/me/password",
               json={"current_password": PASSWORD, "new_password": "a-brand-new-one"})
    assert r.status_code == 200 and r.json() == {"ok": True}
    row = last(u["id"])
    assert row["event"] == "password_changed" and row["email"] == u["email"]
    assert row["detail"] is None and row["ip"] == "testclient"
    assert "a-brand-new-one" not in repr(events(u["id"]))

    fresh = TestClient(app_started)
    assert fresh.post("/api/auth/login", json={"email": u["email"], "password": PASSWORD}
                      ).status_code == 401
    assert fresh.post("/api/auth/login", json={"email": u["email"],
                                               "password": "a-brand-new-one"}).status_code == 200


def test_a_wrong_current_password_changes_and_records_nothing(app_started):
    c, u = register(app_started)
    r = c.post("/api/me/password",
               json={"current_password": "not-the-password", "new_password": "a-brand-new-one"})
    assert r.status_code == 403 and r.json()["detail"] == "That password is incorrect."
    assert events(u["id"]) == []
    fresh = TestClient(app_started)
    assert fresh.post("/api/auth/login", json={"email": u["email"], "password": PASSWORD}
                      ).status_code == 200


def test_a_short_new_password_is_refused(app_started):
    c, u = register(app_started)
    r = c.post("/api/me/password", json={"current_password": PASSWORD, "new_password": "short"})
    assert r.status_code == 422
    assert events(u["id"]) == []


def test_a_token_cant_change_the_password(app_started):
    c, u = register(app_started)
    token = c.post("/api/tokens", json={"name": "t", "access": "full"}).json()["token"]
    tok = TestClient(app_started)
    tok.headers["Authorization"] = f"Bearer {token}"
    r = tok.post("/api/me/password",
                 json={"current_password": PASSWORD, "new_password": "a-brand-new-one"})
    assert r.status_code in (401, 403)
    assert [e["event"] for e in events(u["id"])] == ["token_created"]


def test_signed_out_is_refused(client):
    r = client.post("/api/me/password",
                    json={"current_password": PASSWORD, "new_password": "a-brand-new-one"})
    assert r.status_code == 401


# ---------- An admin acting on users ----------

def test_admin_password_reset_names_the_user_by_number(app_started, admin):
    ac, a = admin
    _, u = register(app_started)
    r = ac.patch(f"/api/admin/users/{u['id']}", json={"new_password": "reset-by-admin"})
    assert r.status_code == 200
    row = last(a["id"])
    assert row["event"] == "password_reset" and row["detail"] == f"user #{u['id']}"
    assert u["email"] not in repr(row) and "reset-by-admin" not in repr(row)


def test_an_admin_resetting_their_own_password_says_so(admin):
    ac, a = admin
    assert ac.patch(f"/api/admin/users/{a['id']}",
                    json={"new_password": "reset-my-own"}).status_code == 200
    assert last(a["id"])["detail"] == "own user"


def test_disabling_and_enabling_a_user(app_started, admin):
    ac, a = admin
    _, u = register(app_started)
    assert ac.patch(f"/api/admin/users/{u['id']}", json={"disabled": True}).status_code == 200
    assert ac.patch(f"/api/admin/users/{u['id']}", json={"disabled": True}).status_code == 200
    assert ac.patch(f"/api/admin/users/{u['id']}", json={"disabled": False}).status_code == 200
    # The repeat changed nothing, so it isn't an event.
    assert [(e["event"], e["detail"]) for e in events(a["id"])] == [
        ("user_disabled", f"user #{u['id']}"), ("user_enabled", f"user #{u['id']}")]


def test_disabling_yourself_is_refused_and_records_nothing(admin):
    ac, a = admin
    assert ac.patch(f"/api/admin/users/{a['id']}", json={"disabled": True}).status_code == 400
    assert events(a["id"]) == []


def test_deleting_a_user(app_started, admin):
    ac, a = admin
    _, u = register(app_started)
    assert ac.delete(f"/api/admin/users/{u['id']}").status_code == 200
    row = last(a["id"])
    assert row["event"] == "user_deleted" and row["detail"] == f"user #{u['id']}"
    assert u["email"] not in repr(row)


def test_a_non_admin_is_refused_and_nothing_is_recorded(app_started):
    c, u = register(app_started)
    _, other = register(app_started)
    assert c.patch(f"/api/admin/users/{other['id']}", json={"disabled": True}).status_code == 403
    assert c.delete(f"/api/admin/users/{other['id']}").status_code == 403
    assert c.post("/api/admin/app-title", json={"app_title": "Mine"}).status_code == 403
    assert c.post("/api/admin/backups/now").status_code == 403
    assert events(u["id"]) == []


# ---------- An admin changing settings ----------

def test_changing_a_permission_names_the_account_by_number(app_started, admin):
    ac, a = admin
    oc, owner = register(app_started)
    _, u = register(app_started)
    acc = make_account(oc)
    body = {"account_id": acc, "user_id": u["id"], "level": "read"}
    assert ac.post("/api/admin/permissions", json=body).status_code == 200
    assert ac.post("/api/admin/permissions", json=body).status_code == 200  # no change
    assert ac.post("/api/admin/permissions", json={**body, "level": "deny"}).status_code == 200
    rows = events(a["id"])
    assert [(e["event"], e["detail"]) for e in rows] == [
        ("permission_changed", f"user #{u['id']}, account #{acc}: deny → read"),
        ("permission_changed", f"user #{u['id']}, account #{acc}: read → deny"),
    ]
    for row in rows:
        no_financial_data(row)


def test_removing_the_last_owner_is_refused_and_records_nothing(app_started, admin):
    ac, a = admin
    oc, owner = register(app_started)
    acc = make_account(oc)
    r = ac.post("/api/admin/permissions",
                json={"account_id": acc, "user_id": owner["id"], "level": "read"})
    assert r.status_code == 400
    assert events(a["id"]) == []


def test_changing_and_resetting_the_instance_title(admin):
    ac, a = admin
    try:
        assert ac.post("/api/admin/app-title", json={"app_title": "Family money"}).status_code == 200
    finally:
        assert ac.delete("/api/admin/app-title").status_code == 200
    assert [(e["event"], e["detail"]) for e in events(a["id"])] == [
        ("app_title_changed", "Family money"),
        ("app_title_changed", "reset to WalletWeather"),
    ]


def test_changing_the_backup_settings(admin):
    ac, a = admin
    r = ac.post("/api/admin/backup-config",
                json={"enabled": False, "frequency": "weekly", "hour": 4, "retention_days": 14})
    assert r.status_code == 200
    row = last(a["id"])
    assert row["event"] == "backup_settings_changed"
    assert row["detail"] == "off, weekly at 4:00 UTC, keep 14 days"


def test_bad_backup_settings_record_nothing(admin):
    ac, a = admin
    r = ac.post("/api/admin/backup-config",
                json={"enabled": True, "frequency": "hourly", "hour": 4, "retention_days": 14})
    assert r.status_code == 400
    assert events(a["id"]) == []


# ---------- Backups ----------

def test_making_and_downloading_a_system_backup(admin):
    ac, a = admin
    made = ac.post("/api/admin/backups/now")
    assert made.status_code == 200
    filename = made.json()["filename"]
    assert ac.get(f"/api/admin/backups/download/{filename}").status_code == 200
    assert [(e["event"], e["detail"]) for e in events(a["id"])] == [
        ("backup_made", f"manual: {filename}"),
        ("backup_downloaded", filename),
    ]


def test_restoring_a_system_backup(app_started, admin):
    """Restores a file holding one throwaway user, not the whole test
    database (a restore replaces every user in the file)."""
    import json
    import uuid
    from app import main
    ac, a = admin
    c, u = register(app_started)
    make_account(c)
    udata = c.get("/api/backup/export").json()
    filename = f"system-backup-test-{uuid.uuid4().hex[:8]}.json"
    (main.BACKUP_DIR / filename).write_text(
        json.dumps({"system_backup": True, "users": [udata]}))
    try:
        r = ac.post(f"/api/admin/backups/restore/{filename}")
    finally:
        (main.BACKUP_DIR / filename).unlink()
    assert r.status_code == 200, r.text
    row = last(a["id"])
    assert row["event"] == "backup_restored" and row["detail"] == f"{filename}, 1 user"
    no_financial_data(row)


def test_a_missing_backup_file_records_nothing(admin):
    ac, a = admin
    name = "system-backup-19990101_000000.json"
    assert ac.get(f"/api/admin/backups/download/{name}").status_code == 404
    assert ac.post(f"/api/admin/backups/restore/{name}").status_code == 404
    assert events(a["id"]) == []


def test_your_own_export_and_import(app_started):
    c, u = register(app_started)
    make_account(c)
    exported = c.get("/api/backup/export")
    assert exported.status_code == 200
    r = c.post("/api/backup/import", json={"mode": "merge", "payload": exported.json()})
    assert r.status_code == 200
    rows = events(u["id"])
    assert [(e["event"], e["detail"]) for e in rows] == [
        ("backup_exported", "1 account"),
        ("backup_imported", f"merge, {r.json()['imported']['accounts']} account"
                            f"{'' if r.json()['imported']['accounts'] == 1 else 's'}"),
    ]
    for row in rows:
        no_financial_data(row)


def test_an_unusable_import_records_nothing(app_started):
    c, u = register(app_started)
    r = c.post("/api/backup/import", json={"mode": "merge", "payload": {"nope": True}})
    assert r.status_code == 400
    assert events(u["id"]) == []


# ---------- Deleting your own user ----------

def test_deleting_yourself_leaves_an_event_that_no_longer_names_you(app_started):
    from app.db import AuditEvent, SessionLocal
    c, u = register(app_started)
    r = c.request("DELETE", "/api/me", json={"password": PASSWORD})
    assert r.status_code == 200
    db = SessionLocal()
    try:
        rows = (db.query(AuditEvent).filter_by(event="user_deleted", detail="own user")
                .order_by(AuditEvent.id.desc()).limit(1).all())
    finally:
        db.close()
    # Blanked like the rest of their entries (#139): no user, no email.
    assert rows and rows[0].user_id is None and rows[0].email is None
    assert rows[0].ip == "testclient"


def test_deleting_yourself_with_a_wrong_password_records_nothing(app_started):
    c, u = register(app_started)
    r = c.request("DELETE", "/api/me", json={"password": "not-the-password"})
    assert r.status_code == 403
    assert events(u["id"]) == []


# ---------- API tokens ----------

def test_making_and_revoking_your_own_token(app_started):
    c, u = register(app_started)
    made = c.post("/api/tokens", json={"name": "Secret savings script", "access": "read"})
    assert made.status_code == 200
    tid = made.json()["id"]
    assert c.delete(f"/api/tokens/{tid}").status_code == 200
    assert c.delete(f"/api/tokens/{tid}").status_code == 200  # already revoked
    rows = events(u["id"])
    assert [(e["event"], e["detail"]) for e in rows] == [
        ("token_created", f"token #{tid}, read"),
        ("token_revoked", f"token #{tid}"),
    ]
    assert made.json()["token"] not in repr(rows) and "Secret savings" not in repr(rows)


def test_a_token_made_by_signing_in(app_started):
    _, u = register(app_started)
    r = TestClient(app_started).post("/api/auth/token", json={
        "email": u["email"], "password": PASSWORD, "name": "phone", "access": "full"})
    assert r.status_code == 200, r.text
    row = last(u["id"])
    assert row["event"] == "token_created"
    assert row["detail"] == f"token #{r.json()['id']}, full; by sign-in"


def test_an_admin_revoking_someone_elses_token(app_started, admin):
    ac, a = admin
    c, u = register(app_started)
    tid = c.post("/api/tokens", json={"name": "t", "access": "read"}).json()["id"]
    assert ac.delete(f"/api/admin/tokens/{tid}").status_code == 200
    row = last(a["id"])
    assert row["event"] == "token_revoked" and row["detail"] == f"token #{tid} of user #{u['id']}"


def test_revoking_someone_elses_token_yourself_is_refused_and_records_nothing(app_started):
    c, u = register(app_started)
    oc, other = register(app_started)
    tid = oc.post("/api/tokens", json={"name": "t", "access": "read"}).json()["id"]
    assert c.delete(f"/api/tokens/{tid}").status_code == 404
    assert c.delete(f"/api/admin/tokens/{tid}").status_code == 403
    assert events(u["id"]) == []
