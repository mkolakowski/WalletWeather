"""The daily bank sync, its status and the sync log (bank-sync phase 3, #195).

Uses test_bank_sync.py's stand-in SimpleFIN and fixtures. The scheduler's
thread isn't started in tests: run_due_bank_syncs, what it calls every 30
minutes, is called directly with a chosen time.
"""
import json
from datetime import datetime, timedelta

import pytest
from fastapi.testclient import TestClient

from conftest import share_account
from test_bank_sync import (  # noqa: F401  (fixtures)
    TODAY, admin, connected, fake, lines, link, make_account, register, set_switch, switched_on,
)


def conn_row(user_id):
    from app.db import BankConnection, SessionLocal
    db = SessionLocal()
    try:
        return db.query(BankConnection).filter_by(user_id=user_id).first()
    finally:
        db.close()


def set_conn(user_id, **values):
    from app.db import BankConnection, SessionLocal
    db = SessionLocal()
    try:
        db.query(BankConnection).filter_by(user_id=user_id).update(values)
        db.commit()
    finally:
        db.close()


def run_due(now=None):
    from app import main
    from app.db import SessionLocal
    db = SessionLocal()
    try:
        return main.run_due_bank_syncs(db, now=now)
    finally:
        db.close()


def only_this_user_due(user_id):
    """Other tests' connections in the same database are pushed out of the way."""
    from app.db import BankConnection, SessionLocal
    db = SessionLocal()
    try:
        (db.query(BankConnection).filter(BankConnection.user_id != user_id)
         .update({BankConnection.needs_reconnect: True}))
        db.commit()
    finally:
        db.close()


@pytest.fixture
def linked(connected):
    c, u, acc, status = connected
    link(c, status, acc)
    only_this_user_due(u["id"])
    return c, u, acc


# ---------- The daily sync ----------

def test_a_due_user_is_synced_and_a_recent_one_skipped(linked, fake):
    c, u, acc = linked
    assert run_due()["synced"] == 1               # never synced: due
    assert len(lines(c, acc)) == 2
    assert run_due()["synced"] == 0               # just synced: not due
    later = datetime.utcnow() + timedelta(hours=24)
    fake.accounts[0]["transactions"].append(
        {"id": "T-9", "posted": int(datetime.utcnow().timestamp()), "amount": "-3.00",
         "description": "BUS FARE"})
    assert run_due(now=later)["synced"] == 1      # a day later: due
    assert len(lines(c, acc)) == 3
    log = c.get(f"/api/accounts/{acc}/bank-syncs").json()
    assert [r["trigger"] for r in log] == ["schedule", "schedule"]


def test_a_failure_is_recorded_and_retried_later(linked, fake):
    c, u, acc = linked
    fake.status = 500
    assert run_due() == {"synced": 0, "failed": 1}
    row = conn_row(u["id"])
    assert row.last_sync_ok is False and "Try again" in row.last_sync_status
    assert run_due()["failed"] == 0                         # not again straight away
    fake.status = 200
    assert run_due(now=datetime.utcnow() + timedelta(hours=7))["synced"] == 1


def test_one_users_failure_doesnt_stop_the_others(app_started, fake, switched_on):
    from app import simplefin
    users = []
    for _ in range(2):
        c, u = register(app_started)
        acc = make_account(c)
        st = c.post("/api/bank/connect", json={"token": fake.token()}).json()
        link(c, st, acc)
        users.append((c, u, acc))
    from app.db import BankConnection, SessionLocal
    db = SessionLocal()
    try:
        ids = [u["id"] for _, u, _ in users]
        (db.query(BankConnection).filter(BankConnection.user_id.notin_(ids))
         .update({BankConnection.needs_reconnect: True}, synchronize_session=False))
        db.commit()
    finally:
        db.close()
    # The first user's access address is damaged: their sync fails.
    from app.db import encrypt_str
    set_conn(users[0][1]["id"], access_url_enc=encrypt_str("https://user1:wrong@bridge.simplefin.org/simplefin"))
    assert run_due() == {"synced": 1, "failed": 1}
    assert conn_row(users[0][1]["id"]).last_sync_ok is False
    assert len(lines(users[1][0], users[1][2])) == 2


def test_a_revoked_connection_stops_the_daily_sync(linked, fake):
    c, u, acc = linked
    fake.status = 403
    assert run_due()["failed"] == 1
    assert conn_row(u["id"]).needs_reconnect is True
    fake.status = 200
    assert run_due(now=datetime.utcnow() + timedelta(days=2)) == {"synced": 0, "failed": 0}
    st = c.get("/api/bank/status").json()
    assert st["needs_reconnect"] is True and st["next_sync_at"] is None


def test_nothing_runs_with_the_switch_off(linked):
    set_switch(False)
    assert run_due() == {"synced": 0, "failed": 0}


def test_the_daily_sync_keeps_the_limit(linked):
    c, u, acc = linked
    now = datetime.utcnow()
    set_conn(u["id"], calls_json=json.dumps([(now - timedelta(minutes=i)).isoformat() for i in range(20)]))
    assert run_due() == {"synced": 0, "failed": 0}
    st = c.get("/api/bank/status").json()
    assert st["syncs_left_today"] == 0 and st["sync_wait_seconds"] > 0


def test_a_sync_already_running_is_refused(linked):
    from app import main
    c, u, acc = linked
    lock = main._bank_lock(u["id"])
    lock.acquire()
    try:
        r = c.post("/api/bank/sync")
        assert r.status_code == 409 and "already running" in r.json()["detail"]
        assert run_due()["failed"] == 1
    finally:
        lock.release()


# ---------- Status ----------

def test_the_status_shape(linked):
    c, u, acc = linked
    st = c.get("/api/bank/status").json()
    assert st["enabled"] is True and st["connected"] is True
    assert st["linked_account_ids"] == [acc]
    assert st["last_sync_at"] is None and st["next_sync_at"] is not None
    c.post("/api/bank/sync")
    st = c.get("/api/bank/status").json()
    for key in ("last_sync_at", "last_ok_at", "next_sync_at"):
        assert st[key].endswith("Z"), key
    assert st["last_sync_ok"] is True and st["failing_since"] is None and st["failing_over_a_day"] is False
    assert st["syncs_left_today"] == 18 and st["needs_reconnect"] is False
    text = json.dumps(st)
    assert "Everyday" not in text and "s3cret" not in text


def test_the_status_warns_after_a_day_of_failing(linked, fake):
    c, u, acc = linked
    c.post("/api/bank/sync")
    set_conn(u["id"], last_ok_at=datetime.utcnow() - timedelta(days=2))
    fake.status = 500
    c.post("/api/bank/sync")
    st = c.get("/api/bank/status").json()
    assert st["last_sync_ok"] is False and st["failing_over_a_day"] is True


def test_not_connected_status(app_started, switched_on):
    c, _ = register(app_started)
    # `providers_allowed`: ticked for all three, but only SimpleFIN has keys here (#267);
    # `providers_ticked` and `own_keys` say so (#278).
    assert c.get("/api/bank/status").json() == {"enabled": True, "connected": False,
                                                "providers_allowed": ["simplefin"], "shared": [],
                                                "providers_ticked": ["simplefin", "teller", "plaid"],
                                                "own_keys": {"teller": None, "plaid": None}}


# ---------- Tokens ----------

def _token(c, access):
    r = c.post("/api/tokens", json={"name": access, "access": access, "expires_in_days": 30})
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['token']}"}


def test_tokens_read_status_and_a_write_token_may_sync(app_started, linked):
    c, u, acc = linked
    full = TestClient(app_started, headers=_token(c, "full"))
    read = TestClient(app_started, headers=_token(c, "read"))
    assert read.get("/api/bank/status").status_code == 200
    assert read.post("/api/bank/sync").status_code == 403
    r = full.post("/api/bank/sync")
    assert r.status_code == 200 and r.json()["added"] == 2
    assert r.json()["status"]["last_sync_ok"] is True


# ---------- The sync log ----------

def test_the_sync_log_and_its_lines(linked, fake):
    c, u, acc = linked
    c.post("/api/bank/sync")
    c.post("/api/bank/sync")
    log = c.get(f"/api/accounts/{acc}/bank-syncs").json()
    assert [(r["trigger"], r["added"], r["skipped"], r["error"]) for r in log] == [
        ("manual", 0, 2, None), ("manual", 2, 0, None)]
    assert all(r["run_at"].endswith("Z") for r in log)
    first = c.get(f"/api/accounts/{acc}/bank-syncs/{log[1]['id']}").json()
    assert sorted((x["description"], x["amount"]) for x in first["lines"]) == [
        ("CORNER GROCERY", -42.5), ("PAYROLL ACME", 2500.0)]
    assert c.get(f"/api/accounts/{acc}/bank-syncs/{log[0]['id']}").json()["lines"] == []
    fake.status = 402
    c.post("/api/bank/sync")
    newest = c.get(f"/api/accounts/{acc}/bank-syncs").json()[0]
    assert newest["added"] == 0 and "subscription" in newest["error"]


def test_read_only_people_cant_read_the_log_but_editors_can(app_started, linked):
    # Editors read the log since #265 (the account holds its sync).
    c, u, acc = linked
    c.post("/api/bank/sync")
    run_id = c.get(f"/api/accounts/{acc}/bank-syncs").json()[0]["id"]
    for level, code in (("read", 404), ("edit", 200)):
        other, _ = register(app_started)
        share_account(c, acc, level, invitee_client=other)
        assert other.get(f"/api/accounts/{acc}/bank-syncs").status_code == code, level
        assert other.get(f"/api/accounts/{acc}/bank-syncs/{run_id}").status_code == code, level


def test_a_sync_from_another_account_isnt_found(linked):
    c, u, acc = linked
    c.post("/api/bank/sync")
    run_id = c.get(f"/api/accounts/{acc}/bank-syncs").json()[0]["id"]
    other_acc = make_account(c, "Other")
    assert c.get(f"/api/accounts/{other_acc}/bank-syncs").json() == []
    assert c.get(f"/api/accounts/{other_acc}/bank-syncs/{run_id}").status_code == 404


def test_the_log_is_pruned_with_the_audit_log(linked):
    from app import main
    from app.db import BankSyncRun, SessionLocal
    c, u, acc = linked
    c.post("/api/bank/sync")
    db = SessionLocal()
    try:
        # Only this account's rows are made old, so the rest of the shared
        # test database (other tests' audit events) is left alone.
        old = datetime.utcnow() - timedelta(days=main.AUDIT_RETENTION_DAYS + 1)
        db.query(BankSyncRun).filter_by(account_id=acc).update({BankSyncRun.run_at: old})
        db.commit()
        main.prune_audit_events(db)
        assert db.query(BankSyncRun).filter_by(account_id=acc).count() == 0
    finally:
        db.close()
    # The lines stay; they just no longer point at a sync.
    assert len(lines(c, acc)) == 2
