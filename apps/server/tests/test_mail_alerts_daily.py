"""Email alerts checked by themselves, their status and the mailbox's log
(bank-alert-emails phase 2, #207).

Uses test_mail_alerts.py's stand-in Microsoft and fixtures. The scheduler's
thread isn't started in tests: run_due_mail_checks, what it calls every
minute, is called directly with a chosen time.
"""
import json
from datetime import datetime, timedelta, timezone

import pytest
from fastapi.testclient import TestClient

from conftest import share_account
from test_mail_alerts import (  # noqa: F401  (fixtures)
    BAD_AUTH, TODAY, ms, connect_with_code, connected, lines, make_account, register,
    set_switch, switched_on, taught, teach,
)

# About 1.5-2 s a test (the stand-ins, real scrypt): the slow tier (#274).
pytestmark = pytest.mark.slow


def conn_row(user_id):
    from app.db import MailConnection, SessionLocal
    db = SessionLocal()
    try:
        return db.query(MailConnection).filter_by(user_id=user_id).first()
    finally:
        db.close()


def set_conn(user_id, **values):
    from app.db import MailConnection, SessionLocal
    db = SessionLocal()
    try:
        db.query(MailConnection).filter_by(user_id=user_id).update(values)
        db.commit()
    finally:
        db.close()


def run_due(now=None):
    from app import main
    from app.db import SessionLocal
    db = SessionLocal()
    try:
        return main.run_due_mail_checks(db, now=now)
    finally:
        db.close()


def only_these_users_due(*user_ids):
    """Other tests' mailboxes in the same database are pushed out of the way
    (a mailbox that needs connecting again is never checked)."""
    from app.db import MailConnection, SessionLocal
    db = SessionLocal()
    try:
        (db.query(MailConnection).filter(MailConnection.user_id.notin_(user_ids))
         .update({MailConnection.needs_reconnect: True}, synchronize_session=False))
        db.commit()
    finally:
        db.close()


@pytest.fixture
def ready(taught, ms):
    c, u, acc = taught
    only_these_users_due(u["id"])
    return c, u, acc


# ---------- Checking by itself ----------

def test_a_due_mailbox_is_checked_and_a_recent_one_skipped(ready, ms):
    c, u, acc = ready
    assert run_due() == {"checked": 1, "failed": 0}          # never checked: due
    assert [t["description"] for t in lines(c, acc)] == ["STARBUCKS #123"]
    assert run_due() == {"checked": 0, "failed": 0}          # just checked: not due
    ms.alert("a2", amount="12.00", merchant="SHELL OIL 5566")
    assert run_due(now=datetime.utcnow() + timedelta(minutes=4)) == {"checked": 0, "failed": 0}
    assert run_due(now=datetime.utcnow() + timedelta(minutes=6))["checked"] == 1
    assert len(lines(c, acc)) == 2
    log = c.get("/api/mail/checks").json()
    assert [r["trigger"] for r in log] == ["schedule", "schedule"]


def test_each_users_own_interval_is_kept(ready, ms, app_started):
    c, u, acc = ready
    assert c.get("/api/mail").json()["check_minutes"] == 5          # starts at 5
    assert c.get("/api/mail/status").json()["check_minutes"] == 5
    for bad in (0, 1, 10, 30, 120, "5"):
        assert c.put("/api/mail/settings", json={"check_minutes": bad}).status_code == 422, bad
    r = c.put("/api/mail/settings", json={"check_minutes": 60})
    assert r.status_code == 200 and r.json()["check_minutes"] == 60
    c2, u2 = register(app_started)
    acc2 = make_account(c2)
    connect_with_code(c2, ms)
    c2.put("/api/mail/settings", json={"folder_id": "ALERTS"})
    teach(c2, ms, acc2)
    only_these_users_due(u["id"], u2["id"])
    set_conn(u["id"], last_check_at=datetime.utcnow() - timedelta(minutes=30))
    set_conn(u2["id"], last_check_at=datetime.utcnow() - timedelta(minutes=30))
    # Thirty minutes on: the 5-minute mailbox is due, the 60-minute one isn't.
    assert run_due() == {"checked": 1, "failed": 0}
    assert conn_row(u["id"]).last_check_at < datetime.utcnow() - timedelta(minutes=29)
    assert conn_row(u2["id"]).last_check_at > datetime.utcnow() - timedelta(minutes=1)
    assert run_due(now=datetime.utcnow() + timedelta(minutes=61)) == {"checked": 2, "failed": 0}


def test_a_failure_is_recorded_and_retried_at_the_interval(ready, ms):
    c, u, acc = ready
    ms.down = True
    assert run_due() == {"checked": 0, "failed": 1}
    row = conn_row(u["id"])
    assert row.last_check_ok is False and "Couldn't reach Microsoft" in row.last_check_status
    assert run_due() == {"checked": 0, "failed": 0}            # not again straight away
    ms.down = False
    assert run_due(now=datetime.utcnow() + timedelta(minutes=6)) == {"checked": 1, "failed": 0}
    assert conn_row(u["id"]).last_check_ok is True
    log = c.get("/api/mail/checks").json()
    assert [(r["added"], bool(r["error"])) for r in log] == [(1, False), (0, True)]


def test_one_users_failure_doesnt_stop_the_others(app_started, ms, switched_on):
    users = []
    for _ in range(2):
        c, u = register(app_started)
        acc = make_account(c)
        connect_with_code(c, ms)
        c.put("/api/mail/settings", json={"folder_id": "ALERTS"})
        if not users:
            ms.alert("sample")
        teach(c, ms, acc)
        users.append((c, u, acc))
    only_these_users_due(*[u["id"] for _, u, _ in users])
    # The first user's sign-in is damaged: their check fails.
    from app.db import encrypt_str
    set_conn(users[0][1]["id"], tokens_enc=encrypt_str("not json"))
    assert run_due() == {"checked": 1, "failed": 1}
    assert conn_row(users[0][1]["id"]).last_check_ok is False
    assert len(lines(users[1][0], users[1][2])) == 1
    # A damaged sign-in doesn't stop the system backup of everyone else.
    from app import main
    from app.db import SessionLocal
    db = SessionLocal()
    try:
        from app.backup import export_full_system
        export_full_system(db)
    finally:
        db.close()


def test_a_lapsed_sign_in_stops_the_schedule(ready, ms):
    c, u, acc = ready
    from app.db import MailConnection, SessionLocal, encrypt_str
    set_conn(u["id"], tokens_enc=encrypt_str(json.dumps(
        {"access": ms.access, "refresh": ms.refresh, "expires_at": 0})))
    ms.revoked = True
    assert run_due() == {"checked": 0, "failed": 1}
    assert conn_row(u["id"]).needs_reconnect is True
    ms.revoked = False
    assert run_due(now=datetime.utcnow() + timedelta(days=2)) == {"checked": 0, "failed": 0}
    st = c.get("/api/mail/status").json()
    assert st["needs_reconnect"] is True and st["next_check_at"] is None


def test_nothing_runs_with_the_switch_off_or_without_a_folder_or_a_sender(app_started, ms, switched_on):
    c, u = register(app_started)
    acc = make_account(c)
    connect_with_code(c, ms)
    only_these_users_due(u["id"])
    assert run_due() == {"checked": 0, "failed": 0}               # no folder
    assert c.get("/api/mail/status").json()["next_check_at"] is None
    c.put("/api/mail/settings", json={"folder_id": "ALERTS"})
    assert run_due() == {"checked": 0, "failed": 0}               # nothing taught
    ms.alert("sample")
    teach(c, ms, acc)
    assert c.get("/api/mail/status").json()["next_check_at"] is not None
    set_switch(False)
    assert run_due() == {"checked": 0, "failed": 0}
    assert c.get("/api/mail/status").json()["next_check_at"] is None
    assert not any(q.url.path.endswith("/messages") and "ALERTS" in q.url.path
                   for q in ms.requests[-3:])


def test_a_disabled_user_is_skipped(ready, ms):
    c, u, acc = ready
    from app.db import SessionLocal, User
    db = SessionLocal()
    db.query(User).filter_by(id=u["id"]).update({User.disabled: True})
    db.commit()
    db.close()
    assert run_due() == {"checked": 0, "failed": 0}


def test_a_check_already_running_is_refused(ready):
    import app.main as main
    c, u, acc = ready
    lock = main._mail_lock(u["id"])
    assert lock.acquire(blocking=False)
    try:
        r = c.post("/api/mail/check", json={})
        assert r.status_code == 409 and "already running" in r.json()["detail"]
        assert run_due() == {"checked": 0, "failed": 1}
    finally:
        lock.release()


# ---------- The status ----------

def test_the_status_shape(ready, ms):
    c, u, acc = ready
    st = c.get("/api/mail/status").json()
    assert set(st) == {"enabled", "connected", "check_minutes", "last_check_at", "last_check_ok",
                       "last_check_status", "last_ok_at", "needs_reconnect", "failing_since",
                       "failing_over_a_day", "next_check_at", "unread_count", "paused",
                       "providers_allowed", "shared"}
    assert st["connected"] is True and st["last_check_at"] is None and st["next_check_at"].endswith("Z")
    assert st["failing_over_a_day"] is False and st["unread_count"] == 0
    # Nothing in it names the folder, a sender or the sign-in.
    text = json.dumps(st)
    for secret in ("ALERTS", "Bank alerts", BANK_ADDRESS, "access-", "refresh-"):
        assert secret not in text
    run_due()
    st = c.get("/api/mail/status").json()
    assert st["last_check_ok"] is True and st["last_check_status"].startswith("1 new line")
    assert st["next_check_at"] > st["last_check_at"]
    # The full status carries the same fields.
    full = c.get("/api/mail").json()
    assert all(full[k] == st[k] for k in st)


BANK_ADDRESS = "alerts@bank.example"


def test_not_connected_status(app_started, switched_on, ms):
    c, u = register(app_started)
    # Ticked for Microsoft 365 (#268), with nothing shared yet.
    assert c.get("/api/mail/status").json() == {"enabled": True, "connected": False,
                                                "providers_allowed": ["microsoft"], "shared": []}
    set_switch(False)
    assert c.get("/api/mail/status").json() == {"enabled": False, "connected": False,
                                                "providers_allowed": ["microsoft"], "shared": []}


def test_the_status_warns_after_a_day_of_failing_and_counts_unread(ready, ms):
    c, u, acc = ready
    ms.alert("forged", auth=BAD_AUTH)
    run_due()
    assert c.get("/api/mail/status").json()["unread_count"] == 1
    ms.down = True
    set_conn(u["id"], last_check_at=datetime.utcnow() - timedelta(minutes=30))
    run_due()
    st = c.get("/api/mail/status").json()
    assert st["last_check_ok"] is False and st["failing_over_a_day"] is False and st["failing_since"]
    set_conn(u["id"], last_ok_at=datetime.utcnow() - timedelta(days=2))
    assert c.get("/api/mail/status").json()["failing_over_a_day"] is True


def _token(c, access):
    r = c.post("/api/tokens", json={"name": access, "access": access, "expires_in_days": 30})
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['token']}"}


def test_tokens_read_status_and_a_write_token_may_check(app_started, ready, ms):
    c, u, acc = ready
    full = TestClient(app_started, headers=_token(c, "full"))
    read = TestClient(app_started, headers=_token(c, "read"))
    assert read.get("/api/mail/status").status_code == 200
    assert read.post("/api/mail/check", json={}).status_code == 403
    r = full.post("/api/mail/check", json={})
    assert r.status_code == 200 and r.json()["added"] == 1
    assert r.json()["status"]["last_check_ok"] is True
    # The log, the folder and teaching stay browser-session only.
    for method, path in [("GET", "/api/mail/checks"), ("GET", "/api/mail/folders"),
                         ("GET", "/api/mail"), ("POST", "/api/mail/senders")]:
        assert full.request(method, path, json={}).status_code == 403, path


# ---------- The log ----------

def test_the_log_and_its_lines(ready, ms):
    c, u, acc = ready
    run_due()
    ms.alert("a2", amount="12.00", merchant="SHELL OIL 5566")
    ms.alert("forged", auth=BAD_AUTH)
    run_due(now=datetime.utcnow() + timedelta(minutes=6))
    log = c.get("/api/mail/checks").json()
    assert len(log) == 2
    assert all(set(r) == {"id", "run_at", "trigger", "added", "matched", "skipped", "unread", "error"}
               for r in log)
    newest, oldest = log
    assert (newest["added"], newest["unread"], newest["error"]) == (1, 1, None)
    assert (oldest["added"], oldest["unread"]) == (1, 0)
    one = c.get(f"/api/mail/checks/{newest['id']}").json()
    assert [(l["description"], l["amount"], l["account_name"]) for l in one["lines"]] == [
        ("SHELL OIL 5566", -12.0, "Checking")]
    assert all(set(l) == {"id", "date", "description", "amount", "account_id", "account_name", "matched"}
               for l in one["lines"])
    two = c.get(f"/api/mail/checks/{oldest['id']}").json()
    assert [l["description"] for l in two["lines"]] == ["STARBUCKS #123"]


def test_a_check_that_found_nothing_isnt_listed(ready, ms):
    c, u, acc = ready
    run_due()
    assert len(c.get("/api/mail/checks").json()) == 1
    run_due(now=datetime.utcnow() + timedelta(minutes=6))       # nothing new
    r = c.post("/api/mail/check", json={})                       # nor now
    assert r.status_code in (200, 429)
    assert len(c.get("/api/mail/checks").json()) == 1


def test_a_manual_check_is_logged_as_manual(ready, ms):
    c, u, acc = ready
    assert c.post("/api/mail/check", json={}).status_code == 200
    (r,) = c.get("/api/mail/checks").json()
    assert r["trigger"] == "manual" and r["added"] == 1


def test_a_failed_check_is_in_the_log_with_its_error(ready, ms):
    c, u, acc = ready
    ms.down = True
    run_due()
    (r,) = c.get("/api/mail/checks").json()
    assert r["trigger"] == "schedule" and "Couldn't reach Microsoft" in r["error"] and r["added"] == 0
    assert c.get(f"/api/mail/checks/{r['id']}").json()["lines"] == []


def test_a_failure_after_lines_landed_keeps_them_in_its_row(ready, ms):
    """An alert that couldn't become a line is tried again from its kept text;
    when renewing the sign-in then commits and the listing fails, the lines
    landed first still point at the failed check."""
    c, u, acc = ready
    ms.alert("c1", amount="20.00", card="9876")
    assert c.post("/api/mail/check", json={}).status_code == 200      # unmatched card: kept
    other = make_account(c, "Card 9876")
    sender = c.get("/api/mail").json()["senders"][0]
    c.put(f"/api/mail/senders/{sender['id']}", json={"cards": {"9876": other}})
    from app.db import encrypt_str
    set_conn(u["id"], last_check_at=datetime.utcnow() - timedelta(minutes=30),
             tokens_enc=encrypt_str(json.dumps(
                 {"access": ms.access, "refresh": ms.refresh, "expires_at": 0})))
    ms.down = True
    run_due()
    log = c.get("/api/mail/checks").json()
    assert log[0]["error"] and log[0]["added"] in (0, 1)
    assert sum(1 for r in log if r["error"]) == 1


def test_other_people_cant_read_the_log(app_started, ready, ms):
    c, u, acc = ready
    run_due()
    (r,) = c.get("/api/mail/checks").json()
    c2, _ = register(app_started)
    assert c2.get("/api/mail/checks").status_code == 404           # no mailbox
    make_account(c2)
    connect_with_code(c2, ms)
    assert c2.get("/api/mail/checks").json() == []
    assert c2.get(f"/api/mail/checks/{r['id']}").status_code == 404
    assert c.get("/api/mail/checks/99999999").status_code == 404


def test_the_log_is_pruned_with_the_audit_log(ready, ms):
    from app import main
    from app.db import MailCheckRun, MailConnection, SessionLocal
    c, u, acc = ready
    run_due()
    db = SessionLocal()
    try:
        # Only this mailbox's rows are made old, so the rest of the shared
        # test database is left alone.
        conn_id = db.query(MailConnection.id).filter_by(user_id=u["id"]).scalar()
        old = datetime.utcnow() - timedelta(days=main.AUDIT_RETENTION_DAYS + 1)
        db.query(MailCheckRun).filter_by(connection_id=conn_id).update({MailCheckRun.run_at: old})
        db.commit()
        main.prune_audit_events(db)
        assert db.query(MailCheckRun).filter_by(connection_id=conn_id).count() == 0
    finally:
        db.close()
    # The lines stay; they just no longer point at a check.
    assert len(lines(c, acc)) == 1


def test_disconnecting_removes_the_log_and_lines_stay(ready, ms):
    from app.db import MailCheckRun, SessionLocal
    c, u, acc = ready
    run_due()
    conn_id = conn_row(u["id"]).id
    assert c.post("/api/mail/disconnect", json={}).status_code == 200
    db = SessionLocal()
    try:
        assert db.query(MailCheckRun).filter_by(connection_id=conn_id).count() == 0
    finally:
        db.close()
    assert len(lines(c, acc)) == 1


def test_the_interval_goes_into_encrypted_backups(app_started, ready, ms):
    from app.backup import open_sealed
    c, u, acc = ready
    c.put("/api/mail/settings", json={"check_minutes": 15})
    sealed = c.post("/api/backup/export", json={"passphrase": "a long passphrase"}).json()
    assert open_sealed(sealed, "a long passphrase")["mail_connection"]["check_minutes"] == 15
    other, ou = register(app_started)
    r = other.post("/api/backup/import", json={"payload": sealed, "passphrase": "a long passphrase"})
    assert r.status_code == 200, r.text
    assert other.get("/api/mail").json()["check_minutes"] == 15
