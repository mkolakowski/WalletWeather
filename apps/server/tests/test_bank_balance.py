"""The bank's balance next to yours (bank-providers phase 3, #256).

Each sync keeps the balance its provider gave for a linked account (SimpleFIN
and Plaid give it with the accounts; Teller's balance call is billed, so it's
asked for only when the balance has likely moved). The forecast the Accounts
screen reads carries it as `bank_balance`, with the gap against the account's
balance counting lines up to today. POST /api/accounts/{id}/bank-adjust adds
one correction line for the gap, and deleting that line is the undo. Uses the
stand-ins from test_bank_providers.py and test_bank_sync.py.
"""
from datetime import datetime, timedelta

import pytest

from conftest import share_account
from test_bank_providers import (TODAY, day, linked, plaid_fake, plaid_user,  # noqa: F401 (fixtures)
                                 no_provider_keys, switched_on, teller_fake, teller_user)
from test_bank_sync import connected, fake, link, lines, make_account, register, set_switch  # noqa: F401

# Every account below starts at 100 and takes the bank's lines of the last 10
# days: the stand-ins' payroll in (+2,500.00) and grocery out (-42.50), so the
# account's own balance is 2,557.50 once synced.
MINE = 2557.50


def sync(c):
    r = c.post("/api/bank/sync")
    assert r.status_code == 200, r.text
    return r.json()


def info(c, acc):
    r = c.get(f"/api/accounts/{acc}/forecast")
    assert r.status_code == 200, r.text
    return r.json()["bank_balance"]


def adjust(c, acc, gap):
    return c.post(f"/api/accounts/{acc}/bank-adjust", json={"gap": gap})


def current(c, acc):
    return next(a for a in c.get("/api/accounts").json() if a["id"] == acc)["current_balance"]


def stored_link(acc):
    """(encrypted balance, when) as stored for the link of one account."""
    from app.db import BankAccountLink, SessionLocal
    db = SessionLocal()
    try:
        row = db.query(BankAccountLink).filter_by(account_id=acc).one()
        return row.bank_balance_enc, row.bank_balance_at
    finally:
        db.close()


def set_stored_at(acc, when):
    from app.db import BankAccountLink, SessionLocal
    db = SessionLocal()
    try:
        db.query(BankAccountLink).filter_by(account_id=acc).one().bank_balance_at = when
        db.commit()
    finally:
        db.close()


@pytest.fixture
def teller_acc(teller_user):
    c, u, conn = teller_user
    return c, u, linked(c, conn, "Teller Checking"), conn


@pytest.fixture
def plaid_acc(plaid_user):
    c, u, conn = plaid_user
    return c, u, linked(c, conn, "Plaid Checking"), conn


@pytest.fixture
def simplefin_acc(connected):
    c, u, acc, status = connected
    link(c, status, acc)
    return c, u, acc


def balance_calls(fake):
    return len(fake.calls("GET", "/balances"))


# ---------- What's kept at each sync, per provider ----------

def test_nothing_shows_before_the_first_sync(simplefin_acc):
    c, u, acc = simplefin_acc
    assert info(c, acc) is None


def test_simplefin_keeps_the_bank_balance_and_shows_the_gap(simplefin_acc):
    c, u, acc = simplefin_acc
    sync(c)
    b = info(c, acc)
    assert b["balance"] == 1200.00
    assert b["provider"] == "SimpleFIN"
    assert b["gap"] == round(1200.00 - MINE, 2) == -1357.50
    assert b["can_adjust"] is True
    assert b["as_of"].endswith("Z")
    assert current(c, acc) == MINE


def test_simplefin_says_when_the_bank_had_the_balance(simplefin_acc, fake):
    c, u, acc = simplefin_acc
    from test_bank_sync import epoch
    fake.accounts[0]["balance-date"] = epoch(TODAY - timedelta(days=2))
    sync(c)
    assert info(c, acc)["as_of"] == f"{TODAY - timedelta(days=2)}T15:00:00Z"


def test_simplefin_giving_no_balance_shows_none(simplefin_acc, fake):
    c, u, acc = simplefin_acc
    del fake.accounts[0]["balance"]
    sync(c)
    assert info(c, acc) is None


def test_a_balance_the_provider_stops_giving_is_cleared_not_left_to_go_stale(simplefin_acc, fake):
    c, u, acc = simplefin_acc
    sync(c)
    assert info(c, acc) is not None
    del fake.accounts[0]["balance"]
    sync(c)
    assert info(c, acc) is None
    assert stored_link(acc) == (None, None)


def test_the_balance_is_stored_encrypted(simplefin_acc):
    c, u, acc = simplefin_acc
    sync(c)
    raw, _ = stored_link(acc)
    assert bytes(raw).startswith(b"gAAAA") and b"1200" not in bytes(raw)


def test_a_later_sync_brings_the_new_balance(simplefin_acc, fake):
    c, u, acc = simplefin_acc
    sync(c)
    fake.accounts[0]["balance"] = "1500.25"
    sync(c)
    assert info(c, acc)["balance"] == 1500.25


def test_plaid_keeps_the_balance_it_gave_with_the_accounts(plaid_acc):
    c, u, acc, conn = plaid_acc
    sync(c)
    b = info(c, acc)
    assert b["balance"] == 900.00 and b["provider"] == "Plaid"
    assert b["gap"] == round(900.00 - MINE, 2) == -1657.50


def test_a_plaid_card_counts_against_you(plaid_acc, plaid_fake):
    c, u, acc, conn = plaid_acc
    plaid_fake.accounts[0].update(type="credit", balances={"current": 300.0})
    sync(c)
    assert info(c, acc)["balance"] == -300.00


def test_plaid_giving_no_balance_shows_none(plaid_acc, plaid_fake):
    c, u, acc, conn = plaid_acc
    plaid_fake.accounts[0]["balances"] = {"current": None}
    sync(c)
    assert info(c, acc) is None


def test_teller_asks_for_the_balance_at_the_first_sync(teller_acc, teller_fake):
    c, u, acc, conn = teller_acc
    sync(c)
    assert balance_calls(teller_fake) == 1
    b = info(c, acc)
    assert b["balance"] == 1200.00 and b["provider"] == "Teller"
    assert b["gap"] == -1357.50


def test_a_quiet_teller_sync_makes_no_billed_balance_call(teller_acc, teller_fake):
    c, u, acc, conn = teller_acc
    sync(c)
    sync(c)
    sync(c)
    assert balance_calls(teller_fake) == 1
    assert info(c, acc)["balance"] == 1200.00   # the one kept still stands


def test_a_new_line_makes_teller_ask_again_so_the_pair_stays_in_step(teller_acc, teller_fake):
    c, u, acc, conn = teller_acc
    sync(c)
    teller_fake.transactions.insert(0, {"id": "txn_9", "date": day(0), "amount": "-10.00",
                                        "status": "posted", "description": "NEW COFFEE"})
    teller_fake.balance = "1190.00"
    sync(c)
    assert balance_calls(teller_fake) == 2
    b = info(c, acc)
    assert b["balance"] == 1190.00 and b["gap"] == round(1190.00 - (MINE - 10), 2)


def test_a_week_old_teller_balance_is_asked_for_again(teller_acc, teller_fake):
    c, u, acc, conn = teller_acc
    sync(c)
    set_stored_at(acc, datetime.utcnow() - timedelta(days=8))
    teller_fake.balance = "1250.00"
    sync(c)
    assert balance_calls(teller_fake) == 2
    assert info(c, acc)["balance"] == 1250.00


def test_a_teller_balance_that_fails_shows_none_and_is_asked_for_again(teller_acc, teller_fake):
    c, u, acc, conn = teller_acc
    teller_fake.balance_status = 500
    sync(c)
    assert info(c, acc) is None
    teller_fake.balance_status = 200
    sync(c)
    assert info(c, acc)["balance"] == 1200.00
    assert balance_calls(teller_fake) == 2


def test_a_teller_card_counts_against_you(teller_acc, teller_fake):
    c, u, acc, conn = teller_acc
    teller_fake.accounts[0]["type"] = "credit"
    teller_fake.balance = "300.00"
    sync(c)
    assert info(c, acc)["balance"] == -300.00


# ---------- The gap ----------

def test_a_matching_balance_has_no_gap_and_nothing_to_adjust(simplefin_acc, fake):
    c, u, acc = simplefin_acc
    fake.accounts[0]["balance"] = f"{MINE:.2f}"
    sync(c)
    assert info(c, acc)["gap"] == 0
    r = adjust(c, acc, 0)
    assert r.status_code == 400 and "already agree" in r.json()["detail"]
    assert [t["description"] for t in lines(c, acc)].count("Adjust to bank") == 0


def test_the_gap_follows_your_own_edits_without_a_new_sync(simplefin_acc, fake):
    c, u, acc = simplefin_acc
    fake.accounts[0]["balance"] = f"{MINE:.2f}"
    sync(c)
    assert info(c, acc)["gap"] == 0
    r = c.post(f"/api/accounts/{acc}/transactions", json={
        "description": "cash", "amount": -20, "actual_date": TODAY.isoformat(),
        "forecast_date": TODAY.isoformat(), "is_actual": True})
    assert r.status_code == 200, r.text
    assert info(c, acc)["gap"] == 20.00


def test_a_line_dated_after_today_isnt_counted_in_the_comparison(simplefin_acc, fake):
    c, u, acc = simplefin_acc
    fake.accounts[0]["balance"] = f"{MINE:.2f}"
    sync(c)
    tomorrow = (TODAY + timedelta(days=1)).isoformat()
    r = c.post(f"/api/accounts/{acc}/transactions", json={
        "description": "later", "amount": -500, "actual_date": tomorrow,
        "forecast_date": tomorrow, "is_actual": True})
    assert r.status_code == 200, r.text
    assert info(c, acc)["gap"] == 0


# ---------- Adjust to bank, and its undo ----------

def test_adjust_adds_one_line_for_the_gap_and_the_balances_agree(simplefin_acc):
    c, u, acc = simplefin_acc
    sync(c)
    r = adjust(c, acc, -1357.50)
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["amount"] == -1357.50 and body["current_balance"] == 1200.00
    made = [t for t in lines(c, acc) if t["description"] == "Adjust to bank"]
    assert len(made) == 1 and made[0]["id"] == body["transaction_id"] and made[0]["amount"] == -1357.50
    assert info(c, acc)["gap"] == 0
    assert current(c, acc) == 1200.00


def test_adjusting_up_works_the_same_way(simplefin_acc, fake):
    c, u, acc = simplefin_acc
    fake.accounts[0]["balance"] = "3000.00"
    sync(c)
    assert info(c, acc)["gap"] == 442.50
    assert adjust(c, acc, 442.50).status_code == 200
    assert current(c, acc) == 3000.00


def test_adjusting_twice_is_refused_the_second_time(simplefin_acc):
    c, u, acc = simplefin_acc
    sync(c)
    assert adjust(c, acc, -1357.50).status_code == 200
    assert adjust(c, acc, -1357.50).status_code == 400
    assert [t["description"] for t in lines(c, acc)].count("Adjust to bank") == 1


def test_deleting_the_correction_line_undoes_it(simplefin_acc):
    c, u, acc = simplefin_acc
    sync(c)
    tid = adjust(c, acc, -1357.50).json()["transaction_id"]
    assert c.delete(f"/api/transactions/{tid}").status_code == 200
    assert info(c, acc)["gap"] == -1357.50
    assert current(c, acc) == MINE
    assert adjust(c, acc, -1357.50).status_code == 200   # and it can be made again


def test_adjust_works_for_teller_and_plaid_too(teller_acc, plaid_user, teller_fake):
    c, u, acc, conn = teller_acc
    sync(c)
    assert adjust(c, acc, -1357.50).status_code == 200
    assert current(c, acc) == 1200.00
    # Plaid, as another user's own connection.
    c2, u2, conn2 = plaid_user
    acc2 = linked(c2, conn2, "Plaid Checking")
    sync(c2)
    assert adjust(c2, acc2, -1657.50).status_code == 200
    assert current(c2, acc2) == 900.00


def test_a_gap_that_changed_since_it_was_shown_is_refused_and_adds_nothing(simplefin_acc, fake):
    c, u, acc = simplefin_acc
    sync(c)
    fake.accounts[0]["balance"] = "1300.00"
    sync(c)                                     # the gap is now -1257.50
    r = adjust(c, acc, -1357.50)
    assert r.status_code == 409
    assert [t["description"] for t in lines(c, acc)].count("Adjust to bank") == 0
    assert info(c, acc)["gap"] == -1257.50


def test_adjust_with_no_balance_from_the_bank_is_refused(simplefin_acc, fake):
    c, u, acc = simplefin_acc
    del fake.accounts[0]["balance"]
    sync(c)
    assert adjust(c, acc, 5).status_code == 400


def test_adjust_on_an_account_with_no_bank_match_is_refused(app_started, switched_on):
    c, u = register(app_started)
    acc = make_account(c)
    assert info(c, acc) is None
    assert adjust(c, acc, 5).status_code == 400


def test_adjust_needs_a_gap_in_the_body(simplefin_acc):
    c, u, acc = simplefin_acc
    sync(c)
    assert c.post(f"/api/accounts/{acc}/bank-adjust", json={}).status_code == 422
    assert c.post(f"/api/accounts/{acc}/bank-adjust", json={"gap": "lots"}).status_code == 422


def test_adjust_on_an_account_that_isnt_yours_is_not_found(simplefin_acc, app_started):
    c, u, acc = simplefin_acc
    sync(c)
    other, _ = register(app_started)
    assert adjust(other, acc, -1357.50).status_code == 404
    assert [t["description"] for t in lines(c, acc)].count("Adjust to bank") == 0


def test_a_signed_out_caller_is_refused(simplefin_acc, app_started):
    from fastapi.testclient import TestClient
    c, u, acc = simplefin_acc
    assert adjust(TestClient(app_started), acc, 1).status_code == 401


def test_adjust_records_an_audit_event(simplefin_acc):
    from app.db import AuditEvent, SessionLocal
    c, u, acc = simplefin_acc
    sync(c)
    assert adjust(c, acc, -1357.50).status_code == 200
    db = SessionLocal()
    try:
        ev = db.query(AuditEvent).filter_by(event="bank_balance_adjusted", user_id=u["id"]).one()
        assert ev.detail == f"account #{acc}"
    finally:
        db.close()


# ---------- Who sees it ----------

def test_someone_an_account_is_shared_with_sees_no_bank_balance_and_cant_adjust(simplefin_acc, app_started):
    c, u, acc = simplefin_acc
    sync(c)
    editor, _ = register(app_started)
    share_account(c, acc, "edit", invitee_client=editor)
    assert info(editor, acc) is None
    assert adjust(editor, acc, -1357.50).status_code == 400
    viewer, _ = register(app_started)
    share_account(c, acc, "read", invitee_client=viewer)
    assert info(viewer, acc) is None
    assert adjust(viewer, acc, -1357.50).status_code in (403, 404)
    assert [t["description"] for t in lines(c, acc)].count("Adjust to bank") == 0
    assert info(c, acc)["gap"] == -1357.50     # the owner still sees it


def test_with_bank_sync_switched_off_nothing_shows_and_adjust_is_refused(simplefin_acc):
    c, u, acc = simplefin_acc
    sync(c)
    assert info(c, acc) is not None
    set_switch(False)
    assert info(c, acc) is None
    assert adjust(c, acc, -1357.50).status_code == 403
    set_switch(True)
    assert info(c, acc)["gap"] == -1357.50


def test_disconnecting_the_bank_takes_the_balance_with_it(simplefin_acc):
    c, u, acc = simplefin_acc
    sync(c)
    assert c.post("/api/bank/disconnect", json={}).status_code == 200
    assert info(c, acc) is None
