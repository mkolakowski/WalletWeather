"""What the iOS app's More pages call (ios-app phase 5, #91): Net worth,
Budgets and Reports, read-only, each for the phone's own month (`today=`).
Each test checks the fields the app decodes, so a change here goes with a
change in apps/ios/WalletWeatherKit (and its samples).
"""
from datetime import date, timedelta

import pytest

from test_app_forecast import bearer, register
from test_app_shapes import NUM, has

TODAY = date.today()
OPT_STR = (str, type(None))
OPT_INT = (int, type(None))
OPT_NUM = (int, float, type(None))


@pytest.fixture
def owner(app_started):
    """Checking with 1000 and a paid $40 grocery run today in Groceries,
    budgeted at $100 a month; Savings with 500."""
    c, uid = register(app_started)
    for name, balance in (("Checking", 1000), ("Savings", 500)):
        r = c.post("/api/accounts", json={"name": name, "starting_balance": balance,
                                          "starting_date": TODAY.replace(day=1).isoformat()})
        assert r.status_code == 200, r.text
    accounts = {a["name"]: a["id"] for a in c.get("/api/accounts").json()}
    r = c.post("/api/categories", json={"name": "Food shop", "color": "#3fb950"})
    assert r.status_code == 200, r.text
    cat = next(x["id"] for x in c.get("/api/categories").json() if x["name"] == "Food shop")
    r = c.post(f"/api/accounts/{accounts['Checking']}/transactions", json={
        "description": "Market", "amount": -40, "forecast_amount": -40, "is_actual": True,
        "forecast_date": TODAY.isoformat(), "actual_date": TODAY.isoformat(), "category_id": cat})
    assert r.status_code == 200, r.text
    r = c.post("/api/budgets", json={"category_id": cat, "amount": 100})
    assert r.status_code == 200, r.text
    return {"c": c, "accounts": accounts, "cat": cat}


def test_net_worth(owner):
    body = owner["c"].get(f"/api/networth?window=month&today={TODAY}").json()
    has(body, {"window": str, "label": str, "start": str, "end": str, "opening_total": NUM,
               "forecast_end_total": NUM, "actual_end_total": NUM, "trend": list, "accounts": list})
    assert body["start"] == TODAY.replace(day=1).isoformat()
    assert body["actual_end_total"] == 1460
    has(body["trend"][0], {"date": str, "balance": NUM})
    acc = next(a for a in body["accounts"] if a["account_name"] == "Checking")
    has(acc, {"account_id": int, "account_name": str, "opening_balance": NUM,
              "forecast_end": NUM, "actual_end": NUM, "trend": list})
    assert acc["actual_end"] == 960
    for window in ("30d", "90d"):
        assert owner["c"].get(f"/api/networth?window={window}&today={TODAY}").status_code == 200


def test_budgets(owner):
    body = owner["c"].get(f"/api/budgets/progress?window=month&today={TODAY}").json()
    has(body, {"window": str, "label": str, "start": str, "end": str, "rows": list, "totals": dict})
    has(body["totals"], {"budget": NUM, "spend": NUM, "remaining": NUM})
    row = next(r for r in body["rows"] if r["category_name"] == "Food shop")
    has(row, {"category_id": OPT_INT, "category_name": str, "category_color": OPT_STR,
              "budget": NUM, "spend": NUM, "remaining": NUM, "pct": OPT_NUM, "over": bool,
              "has_budget": bool})
    assert row["spend"] == 40 and row["remaining"] == 60 and row["pct"] == 40 and not row["over"]


def test_running_a_saved_report(app_started, owner):
    c = owner["c"]
    r = c.post("/api/saved-reports", json={
        "name": "Spending", "params": {"group_by": "category", "kind": "spending"}, "pinned": False})
    assert r.status_code == 200, r.text
    [saved] = c.get("/api/saved-reports").json()
    has(saved, {"id": int, "name": str, "pinned": bool, "params": dict})
    body = c.post(f"/api/saved-reports/{saved['id']}/run?today={TODAY}", json={}).json()
    has(body, {"start": str, "end": str, "range_label": str, "group_by": str,
               "groups": list, "totals": dict})
    has(body["totals"], {k: NUM for k in ("forecast_income", "actual_income", "forecast_spending",
                                          "actual_spending", "forecast_net", "actual_net")})
    [g] = body["groups"]
    has(g, {"name": str, "color": OPT_STR, "actual_total": NUM, "actual_count": int,
            "forecast_total": NUM, "forecast_count": int})
    assert g["name"] == "Food shop" and g["actual_total"] == -40
    # A read-only token may run one: it changes nothing.
    ro = bearer(app_started, c, "read")
    assert ro.post(f"/api/saved-reports/{saved['id']}/run?today={TODAY}", json={}).status_code == 200


def test_errors(owner):
    c = owner["c"]
    far = (TODAY + timedelta(days=5)).isoformat()
    assert c.get(f"/api/networth?today={far}").status_code == 400
    assert c.get(f"/api/budgets/progress?today={far}").status_code == 400
    assert c.get("/api/networth?window=year").status_code == 400
    assert c.post("/api/saved-reports/999999/run", json={}).status_code == 404
