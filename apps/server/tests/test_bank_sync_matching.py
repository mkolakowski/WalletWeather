"""Bills matched by bank sync (bank-sync phase 4, #196).

A synced bank line pays a planned bill or income line on the same account
when it goes the same way, its amount is within the bill's match_percent and
its date within match_days of one of the bill's unpaid dates; the nearest
date wins and a tie is left unmatched. Unmatched lines are listed for the
account's owner, who can match one by hand, leave it as its own line, or
un-match a match. Uses the stand-in SimpleFIN from test_bank_sync.py, whose
first bank account has CORNER GROCERY (-42.50, two days ago) and PAYROLL
ACME (+2500, yesterday).
"""
from datetime import timedelta

from conftest import share_account
from test_bank_sync import (TODAY, connected, epoch, fake, lines, link, register,  # noqa: F401 (fixtures)
                            switched_on)

GROCERY_DAY = TODAY - timedelta(days=2)


def bill(c, acc, name, amount, day, **extra):
    """A monthly bill whose date this month falls on `day`."""
    r = c.post(f"/api/accounts/{acc}/recurring", json={
        "description": name, "amount": amount, "frequency": "monthly_day",
        "day_of_month": day.day, **extra})
    assert r.status_code == 200, r.text
    return r.json()["id"]


def forecast_rows(c, acc):
    r = c.get(f"/api/accounts/{acc}/forecast",
              params={"start": (TODAY - timedelta(days=40)).isoformat(),
                      "end": (TODAY + timedelta(days=40)).isoformat()})
    assert r.status_code == 200, r.text
    return r.json()["rows"]


def row(c, acc, rec, day):
    return next((x for x in forecast_rows(c, acc)
                 if x["recurring_id"] == rec and x["forecast_date"] == day.isoformat()), None)


def sync(c):
    r = c.post("/api/bank/sync")
    assert r.status_code == 200, r.text
    return r.json()


def unmatched(c, acc):
    r = c.get(f"/api/accounts/{acc}/bank-unmatched")
    assert r.status_code == 200, r.text
    return r.json()


def descriptions(c, acc):
    return sorted(t["description"] for t in lines(c, acc))


# ---------- Matching as lines arrive ----------

def test_an_exact_match_pays_the_bill(connected, fake):
    c, u, acc, status = connected
    rec = bill(c, acc, "Groceries", -42.50, GROCERY_DAY)
    link(c, status, acc)
    r = sync(c)
    assert (r["added"], r["matched"], r["skipped"]) == (1, 1, 0)
    paid = row(c, acc, rec, GROCERY_DAY)
    assert paid["is_actual_real"] is True and paid["bank_match"] == "auto"
    assert paid["actual_amount"] == -42.5 and paid["actual_date"] == GROCERY_DAY.isoformat()
    # No second line for the bank's own text.
    assert "CORNER GROCERY" not in descriptions(c, acc)
    assert r["status"]["last_sync_status"].startswith("1 new line, 1 matched a bill")
    again = sync(c)
    assert (again["added"], again["matched"], again["skipped"]) == (0, 0, 2)


def test_a_late_bill_at_a_slightly_different_amount(connected, fake):
    c, u, acc, status = connected
    planned = GROCERY_DAY - timedelta(days=3)
    rec = bill(c, acc, "Groceries", -40.00, planned)     # 6.25% off, 3 days late
    link(c, status, acc)
    assert sync(c)["matched"] == 1
    paid = row(c, acc, rec, planned)
    assert (paid["forecast_amount"], paid["actual_amount"]) == (-40.0, -42.5)
    assert paid["actual_date"] == GROCERY_DAY.isoformat()


def test_the_bills_own_settings_are_used(connected, fake):
    c, u, acc, status = connected
    bill(c, acc, "Too far off in amount", -40.00, GROCERY_DAY, match_percent=5)
    bill(c, acc, "Too far off in days", -42.50, GROCERY_DAY - timedelta(days=3), match_days=2)
    link(c, status, acc)
    r = sync(c)
    assert (r["added"], r["matched"]) == (2, 0)
    assert "CORNER GROCERY" in [x["description"] for x in unmatched(c, acc)["lines"]]


def test_two_candidates_as_near_are_left_unmatched(connected, fake):
    c, u, acc, status = connected
    bill(c, acc, "Groceries A", -42.50, GROCERY_DAY - timedelta(days=1))
    bill(c, acc, "Groceries B", -42.50, GROCERY_DAY + timedelta(days=1))
    link(c, status, acc)
    assert sync(c)["matched"] == 0
    assert unmatched(c, acc)["count"] == 2


def test_the_nearest_date_wins(connected, fake):
    c, u, acc, status = connected
    near = bill(c, acc, "Near", -42.50, GROCERY_DAY)
    far = bill(c, acc, "Far", -42.50, GROCERY_DAY - timedelta(days=2))
    link(c, status, acc)
    assert sync(c)["matched"] == 1
    assert row(c, acc, near, GROCERY_DAY)["bank_match"] == "auto"
    assert row(c, acc, far, GROCERY_DAY - timedelta(days=2))["is_actual_real"] is False


def test_only_the_same_direction_matches(connected, fake):
    c, u, acc, status = connected
    bill(c, acc, "Refund", 42.50, GROCERY_DAY)            # money in; the bank line is money out
    link(c, status, acc)
    assert sync(c)["matched"] == 0


def test_a_paid_bill_is_never_matched_twice(connected, fake):
    c, u, acc, status = connected
    rec = bill(c, acc, "Groceries", -42.50, GROCERY_DAY)
    r = c.post(f"/api/accounts/{acc}/forecast/actual", json={
        "recurring_id": rec, "forecast_date": GROCERY_DAY.isoformat(), "actual_amount": -42.5})
    assert r.status_code == 200, r.text
    # Two bank lines near one unpaid date: only one pays it.
    fake.accounts[0]["transactions"].append(
        {"id": "T-7", "posted": epoch(GROCERY_DAY), "amount": "-42.50", "description": "CORNER GROCERY 2"})
    other = bill(c, acc, "Second shop", -42.50, GROCERY_DAY + timedelta(days=1))
    link(c, status, acc)
    r = sync(c)
    assert r["matched"] == 1
    assert row(c, acc, other, GROCERY_DAY + timedelta(days=1))["bank_match"] == "auto"
    assert row(c, acc, rec, GROCERY_DAY)["bank_match"] is None   # paid by hand, untouched


def test_a_switched_off_bill_is_not_matched(connected, fake):
    c, u, acc, status = connected
    bill(c, acc, "Groceries", -42.50, GROCERY_DAY, active=False)
    link(c, status, acc)
    assert sync(c)["matched"] == 0


# ---------- Un-matching ----------

def test_unmatch_puts_the_bill_back_and_keeps_the_bank_line(connected, fake):
    c, u, acc, status = connected
    rec = bill(c, acc, "Groceries", -42.50, GROCERY_DAY)
    link(c, status, acc)
    sync(c)
    paid = row(c, acc, rec, GROCERY_DAY)
    r = c.post(f"/api/transactions/{paid['transaction_id']}/bank-unmatch")
    assert r.status_code == 200, r.text
    planned = row(c, acc, rec, GROCERY_DAY)
    assert planned["transaction_id"] is None and planned["is_actual_real"] is False
    own = next(t for t in lines(c, acc) if t["description"] == "CORNER GROCERY")
    assert own["amount"] == -42.5 and own["is_actual"] is True
    # Not offered for matching again, and the next sync doesn't re-match it.
    assert unmatched(c, acc)["count"] == 1      # PAYROLL ACME only
    again = sync(c)
    assert (again["added"], again["matched"]) == (0, 0)
    assert row(c, acc, rec, GROCERY_DAY)["transaction_id"] is None


def test_unmatch_needs_a_matched_line(connected, fake):
    c, u, acc, status = connected
    link(c, status, acc)
    sync(c)
    own = lines(c, acc)[0]
    assert c.post(f"/api/transactions/{own['id']}/bank-unmatch").status_code == 409
    assert c.post("/api/transactions/999999999/bank-unmatch").status_code == 404


# ---------- The Unmatched list ----------

def test_the_unmatched_list(connected, fake):
    c, u, acc, status = connected
    link(c, status, acc)
    sync(c)
    got = unmatched(c, acc)
    assert got["count"] == 2
    first = got["lines"][0]
    assert set(first) == {"id", "date", "description", "amount", "notes", "source"}
    assert first["source"] == "bank"       # an email alert's line says "alert" (#209)
    assert [x["description"] for x in got["lines"]] == ["PAYROLL ACME", "CORNER GROCERY"]   # newest first
    st = c.get("/api/bank").json()
    assert next(a for a in st["accounts"] if a["account_id"] == acc)["unmatched_count"] == 2
    log = c.get(f"/api/accounts/{acc}/bank-syncs").json()
    assert (log[0]["added"], log[0]["matched"]) == (2, 0)


def test_leave_as_its_own_line(connected, fake):
    c, u, acc, status = connected
    link(c, status, acc)
    sync(c)
    line = unmatched(c, acc)["lines"][0]
    r = c.post(f"/api/accounts/{acc}/bank-unmatched/{line['id']}/leave")
    assert r.status_code == 200, r.text
    assert unmatched(c, acc)["count"] == 1
    assert line["description"] in descriptions(c, acc)      # still a line
    assert c.post(f"/api/accounts/{acc}/bank-unmatched/{line['id']}/leave").status_code == 404


def test_match_by_hand_to_a_bill_outside_its_settings(connected, fake):
    c, u, acc, status = connected
    far_day = GROCERY_DAY - timedelta(days=20)
    rec = bill(c, acc, "Groceries", -50.00, far_day)       # 20 days and 15% away
    link(c, status, acc)
    sync(c)
    line = next(x for x in unmatched(c, acc)["lines"] if x["description"] == "CORNER GROCERY")
    cands = c.get(f"/api/accounts/{acc}/bank-unmatched/{line['id']}/candidates").json()
    offer = next(x for x in cands["candidates"]
                 if x["recurring_id"] == rec and x["forecast_date"] == far_day.isoformat())
    assert offer["forecast_date"] == far_day.isoformat() and offer["days_apart"] == 20
    assert offer["transaction_id"] is None
    r = c.post(f"/api/accounts/{acc}/bank-unmatched/{line['id']}/match",
               json={"recurring_id": rec, "forecast_date": far_day.isoformat()})
    assert r.status_code == 200, r.text
    paid = row(c, acc, rec, far_day)
    assert paid["bank_match"] == "hand" and paid["actual_amount"] == -42.5
    assert "CORNER GROCERY" not in descriptions(c, acc)
    assert unmatched(c, acc)["count"] == 1
    # A match by hand can be un-matched like any other.
    assert c.post(f"/api/transactions/{paid['transaction_id']}/bank-unmatch").status_code == 200
    assert "CORNER GROCERY" in descriptions(c, acc)
    assert sync(c)["added"] == 0


def test_match_by_hand_to_a_planned_one_off_line(connected, fake):
    c, u, acc, status = connected
    plan_day = GROCERY_DAY + timedelta(days=3)
    r = c.post(f"/api/accounts/{acc}/transactions", json={
        "description": "Big shop", "amount": -45.00, "is_actual": False,
        "forecast_date": plan_day.isoformat()})
    assert r.status_code == 200, r.text
    planned_id = r.json()["id"]
    link(c, status, acc)
    sync(c)
    line = next(x for x in unmatched(c, acc)["lines"] if x["description"] == "CORNER GROCERY")
    cands = c.get(f"/api/accounts/{acc}/bank-unmatched/{line['id']}/candidates").json()["candidates"]
    assert any(x["transaction_id"] == planned_id for x in cands)
    r = c.post(f"/api/accounts/{acc}/bank-unmatched/{line['id']}/match", json={"transaction_id": planned_id})
    assert r.status_code == 200, r.text
    shop = next(t for t in lines(c, acc) if t["id"] == planned_id)
    assert shop["is_actual"] is True and shop["amount"] == -42.5
    # Un-match: back to planned at its planned amount.
    assert c.post(f"/api/transactions/{planned_id}/bank-unmatch").status_code == 200
    shop = next(t for t in lines(c, acc) if t["id"] == planned_id)
    assert shop["is_actual"] is False and shop["amount"] == -45.0


def test_a_paid_line_or_a_transfer_leg_cannot_be_picked(connected, fake):
    c, u, acc, status = connected
    savings = c.post("/api/accounts", json={"name": "Savings", "starting_balance": 0,
                                            "starting_date": (TODAY - timedelta(days=100)).isoformat()}).json()["id"]
    r = c.post("/api/transfers", json={"from_account_id": acc, "to_account_id": savings,
                                       "amount": 42.5, "transfer_date": GROCERY_DAY.isoformat()})
    assert r.status_code == 200, r.text
    link(c, status, acc)
    sync(c)
    line = next(x for x in unmatched(c, acc)["lines"] if x["description"] == "CORNER GROCERY")
    leg = next(x["transaction_id"] for x in forecast_rows(c, acc) if x["transfer_id"])
    cands = c.get(f"/api/accounts/{acc}/bank-unmatched/{line['id']}/candidates").json()["candidates"]
    assert all(x["transaction_id"] != leg for x in cands)
    r = c.post(f"/api/accounts/{acc}/bank-unmatched/{line['id']}/match", json={"transaction_id": leg})
    assert r.status_code == 409
    payroll = next(x for x in unmatched(c, acc)["lines"] if x["description"] == "PAYROLL ACME")
    r = c.post(f"/api/accounts/{acc}/bank-unmatched/{line['id']}/match", json={"transaction_id": payroll["id"]})
    assert r.status_code == 409                        # already paid


def test_match_by_hand_checks(connected, fake):
    c, u, acc, status = connected
    rec = bill(c, acc, "Groceries", -50.00, GROCERY_DAY - timedelta(days=20))
    link(c, status, acc)
    sync(c)
    line = next(x for x in unmatched(c, acc)["lines"] if x["description"] == "CORNER GROCERY")
    url = f"/api/accounts/{acc}/bank-unmatched/{line['id']}/match"
    assert c.post(url, json={}).status_code == 400
    # A day the bill has no date on.
    assert c.post(url, json={"recurring_id": rec, "forecast_date": GROCERY_DAY.isoformat()}).status_code == 400
    assert c.post(url, json={"transaction_id": 999999999}).status_code == 404
    assert c.post(f"/api/accounts/{acc}/bank-unmatched/999999999/match",
                  json={"recurring_id": rec, "forecast_date": GROCERY_DAY.isoformat()}).status_code == 404


def test_another_users_lines_cannot_be_matched(app_started, connected, fake):
    c, u, acc, status = connected
    rec = bill(c, acc, "Groceries", -50.00, GROCERY_DAY - timedelta(days=20))
    link(c, status, acc)
    sync(c)
    line = unmatched(c, acc)["lines"][0]
    other, ou = register(app_started)
    # Not even with the account shared for editing: matching is the owner's.
    share_account(c, acc, "edit", other)
    assert other.get(f"/api/accounts/{acc}/bank-unmatched").status_code == 404
    assert other.get(f"/api/accounts/{acc}/bank-unmatched/{line['id']}/candidates").status_code == 404
    assert other.post(f"/api/accounts/{acc}/bank-unmatched/{line['id']}/match",
                      json={"recurring_id": rec,
                            "forecast_date": (GROCERY_DAY - timedelta(days=20)).isoformat()}).status_code == 404
    assert other.post(f"/api/accounts/{acc}/bank-unmatched/{line['id']}/leave").status_code == 404
    assert unmatched(c, acc)["count"] == 2


# ---------- A bill's settings, and the forecast's new field ----------

def test_a_bills_match_settings(connected):
    c, u, acc, status = connected
    rec = bill(c, acc, "Rent", -1500, TODAY)
    item = next(x for x in c.get(f"/api/accounts/{acc}/recurring").json() if x["id"] == rec)
    assert (item["match_days"], item["match_percent"]) == (5, 10)
    body = {"description": "Rent", "amount": -1500, "frequency": "monthly_day", "day_of_month": TODAY.day}
    assert c.patch(f"/api/recurring/{rec}", json=body | {"match_days": 2, "match_percent": 0}).status_code == 200
    # A save that leaves them out (an older app) keeps them.
    assert c.patch(f"/api/recurring/{rec}", json=body).status_code == 200
    item = next(x for x in c.get("/api/recurring").json()["items"] if x["id"] == rec)
    assert (item["match_days"], item["match_percent"]) == (2, 0)
    for bad in ({"match_days": 32}, {"match_days": -1}, {"match_percent": 101}, {"match_percent": -5}):
        assert c.patch(f"/api/recurring/{rec}", json=body | bad).status_code == 422


def test_the_forecast_says_which_lines_were_matched(connected, fake):
    c, u, acc, status = connected
    rec = bill(c, acc, "Groceries", -42.50, GROCERY_DAY)
    link(c, status, acc)
    sync(c)
    rows = forecast_rows(c, acc)
    assert all("bank_match" in x for x in rows)
    assert {x["bank_match"] for x in rows if x["recurring_id"] == rec} >= {"auto"}
    assert next(x for x in rows if x["description"] == "PAYROLL ACME")["bank_match"] is None
    lines_of_run = c.get(f"/api/accounts/{acc}/bank-syncs").json()[0]
    shown = c.get(f"/api/accounts/{acc}/bank-syncs/{lines_of_run['id']}").json()
    assert sorted(x["matched"] or "" for x in shown["lines"]) == ["", "auto"]
