"""The match pop-in's list of planned lines (match-by-hand phase 1, #222).

GET /api/accounts/{id}/bank-unmatched/{txn_id}/candidates keeps its flat
`candidates` list and adds `choices`: one entry per bill at its nearest open
date, with all its open dates in `dates`, each saying how the bank's line
compares (amount_diff, days_after, same_direction). Uses the stand-in
SimpleFIN from test_bank_sync.py (CORNER GROCERY, -42.50, two days ago).
"""
from datetime import timedelta

from test_bank_sync import connected, fake, link, switched_on  # noqa: F401 (fixtures)
from test_bank_sync_matching import GROCERY_DAY, bill, sync, unmatched


def grocery_line(c, acc):
    return next(x for x in unmatched(c, acc)["lines"] if x["description"] == "CORNER GROCERY")


def candidates(c, acc, txn_id):
    r = c.get(f"/api/accounts/{acc}/bank-unmatched/{txn_id}/candidates")
    assert r.status_code == 200, r.text
    return r.json()


def test_a_monthly_bill_is_one_choice_with_its_dates(connected, fake):
    c, u, acc, status = connected
    rec = bill(c, acc, "Groceries", -60.00, GROCERY_DAY)   # 41% off: not matched by itself
    link(c, status, acc)
    sync(c)
    line = grocery_line(c, acc)
    data = candidates(c, acc, line["id"])

    assert data["line"]["source"] == "bank"
    assert "bank_text" in data["line"]
    # The flat list still has the bill once per date…
    flat = [x for x in data["candidates"] if x["recurring_id"] == rec]
    assert len(flat) >= 3
    # …and choices has it once, at the nearest date, with every date on offer.
    mine = [x for x in data["choices"] if x["recurring_id"] == rec]
    assert len(mine) == 1
    ch = mine[0]
    assert ch["forecast_date"] == GROCERY_DAY.isoformat()
    assert ch["days_apart"] == 0 and ch["days_after"] == 0
    assert ch["amount"] == -60.0 and ch["amount_diff"] == 17.5
    assert ch["same_direction"] is True and ch["transaction_id"] is None
    assert ch["description"] == "Groceries"
    dates = [d["forecast_date"] for d in ch["dates"]]
    assert dates == sorted(dates) and len(dates) == len(flat)
    assert GROCERY_DAY.isoformat() in dates
    later = next(d for d in ch["dates"] if d["forecast_date"] > GROCERY_DAY.isoformat())
    assert later["days_after"] < 0          # the bank's line came before that date
    assert later["days_apart"] == -later["days_after"]


def test_choices_put_the_same_direction_first_and_one_offs_stay_single(connected, fake):
    c, u, acc, status = connected
    plan_day = GROCERY_DAY + timedelta(days=1)
    r = c.post(f"/api/accounts/{acc}/transactions", json={
        "description": "Big shop", "amount": -45.00, "is_actual": False,
        "forecast_date": plan_day.isoformat()})
    assert r.status_code == 200, r.text
    shop = r.json()["id"]
    r = c.post(f"/api/accounts/{acc}/transactions", json={
        "description": "Refund", "amount": 42.50, "is_actual": False,
        "forecast_date": GROCERY_DAY.isoformat()})
    assert r.status_code == 200, r.text
    refund = r.json()["id"]
    link(c, status, acc)
    sync(c)
    line = grocery_line(c, acc)
    choices = candidates(c, acc, line["id"])["choices"]

    ids = [x["transaction_id"] for x in choices]
    # The refund is nearer (same day) but goes the other way, so it comes after.
    assert ids.index(shop) < ids.index(refund)
    first = choices[0]
    assert first["transaction_id"] == shop and first["same_direction"] is True
    assert first["days_after"] == -1 and first["amount_diff"] == 2.5
    assert len(first["dates"]) == 1 and first["dates"][0]["transaction_id"] == shop
    back = next(x for x in choices if x["transaction_id"] == refund)
    assert back["same_direction"] is False


def test_a_choice_can_be_paid_with_any_of_its_dates(connected, fake):
    c, u, acc, status = connected
    rec = bill(c, acc, "Groceries", -60.00, GROCERY_DAY)
    link(c, status, acc)
    sync(c)
    line = grocery_line(c, acc)
    ch = next(x for x in candidates(c, acc, line["id"])["choices"] if x["recurring_id"] == rec)
    other = next(d for d in ch["dates"] if d["forecast_date"] != ch["forecast_date"])
    r = c.post(f"/api/accounts/{acc}/bank-unmatched/{line['id']}/match",
               json={"recurring_id": rec, "forecast_date": other["forecast_date"]})
    assert r.status_code == 200, r.text
    assert all(x["description"] != "CORNER GROCERY" for x in unmatched(c, acc)["lines"])


def test_no_choices_for_a_line_left_as_its_own(connected, fake):
    c, u, acc, status = connected
    link(c, status, acc)
    sync(c)
    line = grocery_line(c, acc)
    assert c.post(f"/api/accounts/{acc}/bank-unmatched/{line['id']}/leave").status_code == 200
    r = c.get(f"/api/accounts/{acc}/bank-unmatched/{line['id']}/candidates")
    assert r.status_code == 404
    r = c.get(f"/api/accounts/{acc}/bank-unmatched/999999/candidates")
    assert r.status_code == 404
