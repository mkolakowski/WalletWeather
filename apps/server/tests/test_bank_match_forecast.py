"""Matching from Forecast (match-by-hand phase 2, #223).

Forecast rows say which lines wait on the Unmatched list (`bank_unmatched`),
the forecast says how many wait for its owner (`bank_unmatched_count`), and
GET /api/accounts/{id}/bank-unmatched/near lists the lines that could pay one
planned line. Uses the stand-in SimpleFIN from test_bank_sync.py (CORNER
GROCERY -42.50 two days ago, PAYROLL ACME +2500 yesterday).
"""
from datetime import timedelta

from conftest import share_account
from test_bank_sync import connected, fake, link, register, switched_on  # noqa: F401 (fixtures)
from test_bank_sync_matching import GROCERY_DAY, TODAY, bill, sync, unmatched


def forecast(c, acc):
    r = c.get(f"/api/accounts/{acc}/forecast",
              params={"start": (TODAY - timedelta(days=40)).isoformat(),
                      "end": (TODAY + timedelta(days=40)).isoformat()})
    assert r.status_code == 200, r.text
    return r.json()


def near(c, acc, **params):
    return c.get(f"/api/accounts/{acc}/bank-unmatched/near", params=params)


def test_the_forecast_marks_unmatched_lines(connected, fake):
    c, u, acc, status = connected
    rec = bill(c, acc, "Groceries", -60.00, GROCERY_DAY)        # 41% off: not matched by itself
    link(c, status, acc)
    sync(c)
    data = forecast(c, acc)
    assert data["bank_unmatched_count"] == 2
    by_name = {r["description"]: r for r in data["rows"]}
    assert by_name["CORNER GROCERY"]["bank_unmatched"] is True
    assert by_name["PAYROLL ACME"]["bank_unmatched"] is True
    planned = next(r for r in data["rows"] if r["recurring_id"] == rec
                   and r["forecast_date"] == GROCERY_DAY.isoformat())
    assert planned["bank_unmatched"] is False
    # Leaving one takes its mark off and lowers the count.
    line = next(x for x in unmatched(c, acc)["lines"] if x["description"] == "PAYROLL ACME")
    assert c.post(f"/api/accounts/{acc}/bank-unmatched/{line['id']}/leave").status_code == 200
    data = forecast(c, acc)
    assert data["bank_unmatched_count"] == 1
    assert next(r for r in data["rows"] if r["description"] == "PAYROLL ACME")["bank_unmatched"] is False


def test_editors_see_the_count_and_read_only_people_dont(app_started, connected, fake):
    c, u, acc, status = connected
    link(c, status, acc)
    sync(c)
    other, ou = register(app_started)
    share_account(c, acc, "edit", other)
    assert forecast(other, acc)["bank_unmatched_count"] == 2     # an editor works the list (#265)
    viewer, _ = register(app_started)
    share_account(c, acc, "read", viewer)
    assert forecast(viewer, acc)["bank_unmatched_count"] == 0
    assert near(viewer, acc, transaction_id=1).status_code == 404


def test_lines_near_a_bill_date(connected, fake):
    c, u, acc, status = connected
    rec = bill(c, acc, "Groceries", -60.00, GROCERY_DAY)
    link(c, status, acc)
    sync(c)
    r = near(c, acc, recurring_id=rec, forecast_date=GROCERY_DAY.isoformat())
    assert r.status_code == 200, r.text
    data = r.json()
    assert data["planned"] == {"transaction_id": None, "recurring_id": rec,
                               "forecast_date": GROCERY_DAY.isoformat(),
                               "description": "Groceries", "amount": -60.0}
    names = [x["description"] for x in data["lines"]]
    assert names == ["CORNER GROCERY", "PAYROLL ACME"]     # same direction first
    grocery, payroll = data["lines"]
    assert grocery["date"] == GROCERY_DAY.isoformat() and grocery["amount"] == -42.5
    assert grocery["days_apart"] == 0 and grocery["days_after"] == 0
    assert grocery["amount_diff"] == 17.5 and grocery["same_direction"] is True
    assert grocery["source"] == "bank" and "bank_text" in grocery
    assert payroll["same_direction"] is False and payroll["days_after"] == 1
    # The line it lists pays the bill.
    r = c.post(f"/api/accounts/{acc}/bank-unmatched/{grocery['id']}/match",
               json={"recurring_id": rec, "forecast_date": GROCERY_DAY.isoformat()})
    assert r.status_code == 200, r.text
    r = near(c, acc, recurring_id=rec, forecast_date=GROCERY_DAY.isoformat())
    assert r.status_code == 409                            # that date is paid now


def test_lines_near_a_planned_one_off(connected, fake):
    c, u, acc, status = connected
    plan_day = GROCERY_DAY + timedelta(days=5)
    r = c.post(f"/api/accounts/{acc}/transactions", json={
        "description": "Big shop", "amount": -45.00, "is_actual": False,
        "forecast_date": plan_day.isoformat()})
    assert r.status_code == 200, r.text
    shop = r.json()["id"]
    link(c, status, acc)
    sync(c)
    data = near(c, acc, transaction_id=shop).json()
    assert data["planned"]["transaction_id"] == shop and data["planned"]["amount"] == -45.0
    first = data["lines"][0]
    assert first["description"] == "CORNER GROCERY" and first["days_after"] == -5
    assert first["amount_diff"] == 2.5


def test_near_checks(connected, fake):
    c, u, acc, status = connected
    rec = bill(c, acc, "Groceries", -60.00, GROCERY_DAY)
    link(c, status, acc)
    sync(c)
    assert near(c, acc).status_code == 400                                     # nothing named
    assert near(c, acc, recurring_id=rec).status_code == 400                   # no date
    off_day = GROCERY_DAY + timedelta(days=3)
    assert near(c, acc, recurring_id=rec, forecast_date=off_day.isoformat()).status_code == 400
    assert near(c, acc, recurring_id=999999, forecast_date=GROCERY_DAY.isoformat()).status_code == 404
    assert near(c, acc, transaction_id=999999).status_code == 404
    paid = next(x for x in unmatched(c, acc)["lines"] if x["description"] == "PAYROLL ACME")
    assert near(c, acc, transaction_id=paid["id"]).status_code == 409          # already paid


def test_near_lines_say_whether_they_are_within_the_bills_days(connected, fake):
    """#231: the bill's match_days decide within_days, and come back too."""
    c, u, acc, status = connected
    rec = bill(c, acc, "Groceries", -60.00, GROCERY_DAY, match_days=0)
    link(c, status, acc)
    sync(c)
    data = near(c, acc, recurring_id=rec, forecast_date=GROCERY_DAY.isoformat()).json()
    assert data["match_days"] == 0
    by = {x["description"]: x for x in data["lines"]}
    assert by["CORNER GROCERY"]["within_days"] is True          # the same day
    assert by["PAYROLL ACME"]["within_days"] is False           # a day later
