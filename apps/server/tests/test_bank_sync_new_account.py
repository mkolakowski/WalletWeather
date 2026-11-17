"""Create an account from Settings → Bank sync (#215).

A bank account with no match can be made into a new account of the user's
own: named (the bank's name unless typed), matched from a start date, synced
at once, and given the starting balance that makes its balance today the
bank's. If the sync can't run, nothing is made. Uses the stand-in SimpleFIN
from test_bank_sync.py: its first bank account (Everyday Checking, balance
1200.00) has CORNER GROCERY -42.50 and PAYROLL ACME +2500.00 in the last 10
days, so the lines add up to 2457.50 and the account starts at -1257.50.
"""
import json
from datetime import datetime, timedelta
from decimal import Decimal

from fastapi.testclient import TestClient

from test_bank_sync import (TODAY, connected, fake, lines, link, make_account, ref_of,  # noqa: F401 (fixtures)
                            register, switched_on)

START = TODAY - timedelta(days=10)


def create(c, status, name="Everyday Checking", bank="Everyday Checking", start=START, **extra):
    body = {"ref": ref_of(status, bank), "name": name, "start_date": start.isoformat()} | extra
    return c.post("/api/bank/accounts", json=body)


def account_row(c, account_id):
    return next(a for a in c.get("/api/accounts").json() if a["id"] == account_id)


def accounts(c):
    return c.get("/api/accounts").json()


def test_a_new_account_gets_the_banks_balance(connected, fake):
    c, u, acc, status = connected
    left = c.get("/api/bank").json()["syncs_left_today"]
    r = create(c, status, name="  Bank checking ")
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["name"] == "Bank checking"
    assert (body["added"], body["matched"], body["skipped"]) == (2, 0, 0)
    assert body["balance_known"] is True
    assert body["starting_balance"] == -1257.5
    new = account_row(c, body["account_id"])
    assert new["name"] == "Bank checking"
    assert new["starting_balance"] == -1257.5 and new["starting_date"] == START.isoformat()
    # Today's balance is the bank's: the starting balance plus the lines.
    assert new["current_balance"] == 1200.0
    assert sorted(t["description"] for t in lines(c, body["account_id"])) == ["CORNER GROCERY", "PAYROLL ACME"]
    # It's matched: the bank account shows it, and the next sync brings in nothing new.
    st = c.get("/api/bank").json()
    row = next(a for a in st["accounts"] if a["name"] == "Everyday Checking")
    assert row["account_id"] == body["account_id"] and row["start_date"] == START.isoformat()
    assert body["status"]["accounts"] == st["accounts"]
    again = c.post("/api/bank/sync").json()
    assert (again["added"], again["skipped"]) == (0, 2)
    # One call to SimpleFIN did all of it, and counts as one of the day's 20.
    assert body["status"]["syncs_left_today"] == left - 1


def test_the_start_date_sets_which_lines_come_in(connected, fake):
    c, u, acc, status = connected
    r = create(c, status, start=TODAY - timedelta(days=1))   # only yesterday's payroll
    assert r.status_code == 200, r.text
    assert r.json()["added"] == 1
    assert r.json()["starting_balance"] == -1300.0           # 1200 - 2500
    assert account_row(c, r.json()["account_id"])["current_balance"] == 1200.0


def test_a_start_of_today_starts_at_the_banks_balance(connected, fake):
    c, u, acc, status = connected
    r = create(c, status, start=TODAY)
    assert r.status_code == 200, r.text
    assert (r.json()["added"], r.json()["starting_balance"]) == (0, 1200.0)


def test_the_start_date_defaults_to_today(connected, fake):
    c, u, acc, status = connected
    r = c.post("/api/bank/accounts", json={"ref": ref_of(status, "Savings"), "name": "Savings"})
    assert r.status_code == 200, r.text
    assert r.json()["starting_balance"] == 5000.0
    assert account_row(c, r.json()["account_id"])["starting_date"] == TODAY.isoformat()


def test_a_bank_with_no_balance_starts_at_zero_and_says_so(connected, fake):
    c, u, acc, status = connected
    del fake.accounts[0]["balance"]
    r = create(c, status)
    assert r.status_code == 200, r.text
    assert r.json()["balance_known"] is False and r.json()["starting_balance"] == 0.0


def test_other_matched_accounts_sync_in_the_same_call(connected, fake):
    c, u, acc, status = connected
    link(c, status, acc, name="Everyday Checking")           # an existing account is matched to it
    left = c.get("/api/bank").json()["syncs_left_today"]
    r = create(c, status, bank="Savings", name="Savings", start=TODAY)
    assert r.status_code == 200, r.text
    assert r.json()["added"] == 2                            # the existing account's lines came in
    assert len(lines(c, acc)) == 2 and r.json()["status"]["syncs_left_today"] == left - 1


# ---------- Errors: nothing is made ----------

def test_over_the_daily_limit_nothing_is_made(connected, fake):
    from app.db import BankConnection, SessionLocal
    c, u, acc, status = connected
    link(c, status, acc, name="Savings")
    db = SessionLocal()
    try:
        row = db.query(BankConnection).filter_by(user_id=u["id"]).first()
        now = datetime.utcnow()
        row.calls_json = json.dumps([(now - timedelta(hours=1, minutes=i)).isoformat() for i in range(20)])
        db.commit()
    finally:
        db.close()
    before, calls = len(accounts(c)), len(fake.requests)
    r = create(c, status)
    assert r.status_code == 429 and "run again in" in r.json()["detail"]
    assert len(accounts(c)) == before and len(fake.requests) == calls


def test_simplefin_down_makes_nothing(connected, fake):
    c, u, acc, status = connected
    fake.down = True
    before = len(accounts(c))
    r = create(c, status)
    assert r.status_code >= 400
    assert len(accounts(c)) == before
    # Nothing is left matched: the bank account can be made again.
    row = next(a for a in c.get("/api/bank").json()["accounts"] if a["name"] == "Everyday Checking")
    assert row["account_id"] is None
    fake.down = False
    assert create(c, status).status_code == 200


def test_a_revoked_connection_makes_nothing(connected, fake):
    c, u, acc, status = connected
    fake.status = 403
    before = len(accounts(c))
    r = create(c, status)
    assert r.status_code >= 400
    assert len(accounts(c)) == before


def test_a_matched_bank_account_cannot_be_made_again(connected, fake):
    c, u, acc, status = connected
    link(c, status, acc)
    before = len(accounts(c))
    r = create(c, status)
    assert r.status_code == 400 and "already matched" in r.json()["detail"]
    assert len(accounts(c)) == before


def test_input_checks(connected, fake):
    c, u, acc, status = connected
    ref = ref_of(status, "Everyday Checking")
    before = len(accounts(c))
    assert c.post("/api/bank/accounts", json={"ref": ref, "name": "   "}).status_code == 400
    assert c.post("/api/bank/accounts", json={"ref": ref, "name": ""}).status_code == 422
    assert c.post("/api/bank/accounts", json={"ref": ref, "name": "x" * 121}).status_code == 422
    assert c.post("/api/bank/accounts", json={"ref": "a" * 64, "name": "x"}).status_code == 404
    assert c.post("/api/bank/accounts", json={"ref": "short", "name": "x"}).status_code == 422
    for bad in (TODAY + timedelta(days=1), TODAY - timedelta(days=91)):
        r = c.post("/api/bank/accounts", json={"ref": ref, "name": "x", "start_date": bad.isoformat()})
        assert r.status_code == 400, bad
    assert len(accounts(c)) == before


def test_it_needs_a_connection_and_the_switch(app_started, fake, switched_on):
    from test_bank_sync import set_switch
    c, u = register(app_started)
    r = c.post("/api/bank/accounts", json={"ref": "a" * 64, "name": "x"})
    assert r.status_code == 404                       # no bank connected
    set_switch(False)
    r = c.post("/api/bank/accounts", json={"ref": "a" * 64, "name": "x"})
    assert r.status_code == 403 and "switched off" in r.json()["detail"]
    set_switch(True)


def test_a_token_and_a_signed_out_caller_are_refused(app_started, connected, fake):
    c, u, acc, status = connected
    tok = c.post("/api/tokens", json={"name": "t", "access": "full", "expires_in_days": 30}).json()["token"]
    bearer = TestClient(app_started, headers={"Authorization": f"Bearer {tok}"})
    body = {"ref": ref_of(status, "Everyday Checking"), "name": "x"}
    assert bearer.post("/api/bank/accounts", json=body).status_code == 403
    assert TestClient(app_started).post("/api/bank/accounts", json=body).status_code == 401
    assert len(accounts(c)) == 1


def test_the_demo_user_cannot(app_started, switched_on):
    from test_bank_sync import PASSWORD  # noqa: F401
    c = TestClient(app_started)
    r = c.post("/api/auth/login", json={"email": "admin@demo.walletweather.local", "password": "demo1234"})
    if r.status_code != 200:
        return   # no demo user on this instance
    assert c.post("/api/bank/accounts", json={"ref": "a" * 64, "name": "x"}).status_code in (403, 404)


def test_another_users_bank_listing_is_not_theirs(app_started, connected, fake):
    c, u, acc, status = connected
    other, ou = register(app_started)
    r = other.post("/api/bank/accounts", json={"ref": ref_of(status, "Everyday Checking"), "name": "x"})
    assert r.status_code == 404                       # they have no connection, so nothing to make from
