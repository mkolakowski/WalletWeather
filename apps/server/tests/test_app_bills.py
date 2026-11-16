"""What the iOS app's Bills & income and Calendar pages call (ios-app phase 3,
#89): the repeating items with their next dates and monthly totals; adding,
changing, ending and skipping one; the Calendar's month; and moving money
between two accounts. Each test checks the fields the app decodes, so a
change here goes with a change in apps/ios/WalletWeatherKit (and its samples).
"""
from calendar import monthrange
from datetime import date, timedelta

import pytest
from fastapi.testclient import TestClient

from conftest import share_account, unique_email
from test_app_shapes import NUM, has

PASSWORD = "correct-horse-battery"
TODAY = date.today()
OPT_STR = (str, type(None))
OPT_INT = (int, type(None))
OPT_NUM = (int, float, type(None))

ITEM_FIELDS = {
    "id": int, "description": str, "amount": NUM, "frequency": str,
    "day_of_month": OPT_INT, "anchor_date": OPT_STR, "end_date": OPT_STR,
    "category_id": OPT_INT, "category_name": OPT_STR, "category_color": OPT_STR,
    "notes": OPT_STR, "active": bool, "expired": bool, "monthly": OPT_NUM,
    "account_id": int, "account_name": str, "account_level": str,
    "next_date": OPT_STR, "next_dates": list,
}


def register(app):
    c = TestClient(app)
    r = c.post("/api/auth/register", json={"email": unique_email(), "password": PASSWORD})
    assert r.status_code == 200, r.text
    return c, r.json()["id"]


def make_account(c, name, balance=1000):
    r = c.post("/api/accounts", json={"name": name, "starting_balance": balance,
                                      "starting_date": TODAY.replace(day=1).isoformat()})
    assert r.status_code == 200, r.text
    return next(a["id"] for a in c.get("/api/accounts").json() if a["name"] == name)


def items(c, **query):
    q = "&".join(f"{k}={v}" for k, v in {"today": TODAY.isoformat(), **query}.items())
    r = c.get(f"/api/recurring?{q}")
    assert r.status_code == 200, r.text
    return r.json()


def item(c, rec_id, **query):
    return next(i for i in items(c, **query)["items"] if i["id"] == rec_id)


@pytest.fixture
def owner(app_started):
    """Checking and Savings; a weekly Gym bill from today and a monthly
    Paycheck on Checking."""
    c, uid = register(app_started)
    checking, savings = make_account(c, "Checking"), make_account(c, "Savings", 50)
    r = c.post(f"/api/accounts/{checking}/recurring", json={
        "description": "Gym", "amount": -10, "frequency": "weekly", "anchor_date": TODAY.isoformat()})
    assert r.status_code == 200, r.text
    gym = r.json()["id"]
    r = c.post(f"/api/accounts/{checking}/recurring", json={
        "description": "Paycheck", "amount": 2000, "frequency": "monthly_day", "day_of_month": 28})
    assert r.status_code == 200, r.text
    return {"c": c, "uid": uid, "checking": checking, "savings": savings, "gym": gym, "pay": r.json()["id"]}


# ---------- Bills & income ----------

def test_items_and_totals(owner):
    body = items(owner["c"])
    has(body, {"items": list, "totals": dict})
    has(body["totals"], {k: NUM for k in (
        "bills_count", "bills_monthly", "income_count", "income_monthly", "net_monthly")})
    gym = item(owner["c"], owner["gym"])
    has(gym, ITEM_FIELDS)
    assert gym["account_level"] == "owner"
    assert gym["next_date"] == TODAY.isoformat()
    assert gym["next_dates"] == [(TODAY + timedelta(days=7 * i)).isoformat() for i in range(6)]
    assert body["totals"]["income_count"] == 1 and body["totals"]["bills_count"] == 1


def test_next_dates_leave_out_skipped_and_paid_dates(owner):
    c = owner["c"]
    first, second, third = (TODAY + timedelta(days=7 * i) for i in range(3))
    r = c.post(f"/api/recurring/{owner['gym']}/skip", json={"skip_date": first.isoformat()})
    assert r.status_code == 200 and r.json() == {"ok": True}
    r = c.post(f"/api/accounts/{owner['checking']}/transactions", json={
        "description": "Gym", "amount": -10, "forecast_amount": -10, "recurring_id": owner["gym"],
        "forecast_date": second.isoformat(), "actual_date": TODAY.isoformat(), "is_actual": True})
    assert r.status_code == 200, r.text
    gym = item(c, owner["gym"])
    assert gym["next_date"] == third.isoformat()
    assert first.isoformat() not in gym["next_dates"] and second.isoformat() not in gym["next_dates"]
    assert len(gym["next_dates"]) == 6


def test_adding_changing_and_ending_an_item(owner):
    c = owner["c"]
    r = c.post(f"/api/accounts/{owner['checking']}/recurring", json={
        "description": "Phone", "amount": -45.5, "frequency": "monthly_day", "day_of_month": 12,
        "anchor_date": None, "end_date": None, "category_id": None, "notes": "family plan"})
    assert r.status_code == 200, r.text
    has(r.json(), {"id": int})
    phone_id = r.json()["id"]
    phone = item(c, phone_id)
    assert phone["monthly"] == -45.5 and phone["notes"] == "family plan"
    assert phone["next_date"] is not None and phone["next_date"].endswith("-12")

    # Change: a PATCH sends the whole item again, as the app does.
    body = {"description": "Phone", "amount": -50, "frequency": "monthly_day", "day_of_month": 12,
            "anchor_date": None, "end_date": None, "category_id": None, "notes": "family plan",
            "active": True}
    r = c.patch(f"/api/recurring/{phone_id}", json=body)
    assert r.status_code == 200 and r.json() == {"ok": True}
    assert item(c, phone_id)["amount"] == -50

    # End it yesterday: it leaves the list for the ended one, with no next dates.
    r = c.patch(f"/api/recurring/{phone_id}",
                json={**body, "end_date": (TODAY - timedelta(days=1)).isoformat()})
    assert r.status_code == 200
    assert all(i["id"] != phone_id for i in items(c)["items"])
    ended = item(c, phone_id, archived="true")
    assert ended["expired"] and ended["next_dates"] == [] and ended["next_date"] is None


def test_an_item_on_one_account(owner):
    body = items(owner["c"], account_id=owner["savings"])
    assert body["items"] == [] and body["totals"]["bills_count"] == 0


def test_changing_an_unknown_item_is_404(owner):
    r = owner["c"].patch("/api/recurring/999999", json={
        "description": "x", "amount": -1, "frequency": "weekly", "anchor_date": TODAY.isoformat()})
    assert r.status_code == 404


def test_a_read_only_account_cant_be_changed(app_started, owner):
    viewer, viewer_id = register(app_started)
    share_account(owner["c"], owner["checking"], "read", viewer)
    assert item(viewer, owner["gym"])["account_level"] == "read"
    r = viewer.post(f"/api/recurring/{owner['gym']}/skip", json={"skip_date": TODAY.isoformat()})
    assert r.status_code == 404
    r = viewer.post(f"/api/accounts/{owner['checking']}/recurring", json={
        "description": "Sneaky", "amount": -1, "frequency": "weekly", "anchor_date": TODAY.isoformat()})
    assert r.status_code == 404


def test_someone_you_share_with_can_end_a_bill_keeping_its_category(app_started, owner):
    c = owner["c"]
    c.post("/api/categories", json={"name": "Fitness"})
    cat = next(x["id"] for x in c.get("/api/categories").json() if x["name"] == "Fitness")
    body = {"description": "Gym", "amount": -10, "frequency": "weekly", "day_of_month": None,
            "anchor_date": TODAY.isoformat(), "end_date": None, "category_id": cat, "notes": None,
            "active": True}
    assert c.patch(f"/api/recurring/{owner['gym']}", json=body).status_code == 200
    editor, editor_id = register(app_started)
    share_account(c, owner["checking"], "edit", editor)
    ended = {**body, "end_date": (TODAY + timedelta(days=30)).isoformat()}
    assert editor.patch(f"/api/recurring/{owner['gym']}", json=ended).status_code == 200
    assert item(editor, owner["gym"])["category_id"] == cat
    other = {**ended, "category_id": next(
        x["id"] for x in c.get("/api/categories").json() if x["id"] != cat)}
    assert editor.patch(f"/api/recurring/{owner['gym']}", json=other).status_code == 404


# ---------- Calendar ----------

def month():
    return TODAY.replace(day=1), TODAY.replace(day=monthrange(TODAY.year, TODAY.month)[1])


def test_calendar_all_accounts_and_one(owner):
    c = owner["c"]
    start, end = month()
    body = c.get(f"/api/calendar?start={start}&end={end}").json()
    has(body, {"start": str, "end": str, "events": list})
    assert body["daily_balances"] is None, "no one balance across accounts"
    gym = next(e for e in body["events"] if e["description"] == "Gym")
    has(gym, {"date": str, "account_id": int, "account_name": str, "description": str,
              "amount": NUM, "forecast_amount": OPT_NUM, "actual_amount": OPT_NUM,
              "category_name": OPT_STR, "category_color": OPT_STR, "recurring_id": OPT_INT,
              "transaction_id": OPT_INT, "transfer_id": OPT_INT, "is_actual_real": bool,
              "notes": OPT_STR})
    one = c.get(f"/api/calendar?start={start}&end={end}&account_id={owner['checking']}").json()
    balances = one["daily_balances"]
    assert isinstance(balances, dict) and len(balances) == end.day
    assert balances[start.isoformat()] == 1000 or start == TODAY


def test_calendar_errors(owner):
    c = owner["c"]
    start, end = month()
    assert c.get(f"/api/calendar?start={end}&end={start}").status_code == 400
    assert c.get(f"/api/calendar?start={start}&end={end}&account_id=999999").status_code == 404


# ---------- Moving money ----------

def test_moving_money(owner):
    c = owner["c"]
    r = c.post("/api/transfers", json={
        "from_account_id": owner["checking"], "to_account_id": owner["savings"],
        "amount": 125.5, "transfer_date": TODAY.isoformat(), "description": "To savings", "notes": None})
    assert r.status_code == 200, r.text
    t = r.json()
    has(t, {"id": int, "from_account_id": int, "from_account_name": str, "to_account_id": int,
            "to_account_name": str, "amount": NUM, "transfer_date": str, "description": str,
            "transaction_ids": list})
    assert t["amount"] == 125.5 and len(t["transaction_ids"]) == 2
    start, end = month()
    rows = c.get(f"/api/accounts/{owner['savings']}/forecast?start={start}&end={end}"
                 f"&today={TODAY}").json()["rows"]
    leg = next(row for row in rows if row["transfer_id"] == t["id"])
    assert leg["actual_amount"] == 125.5 and leg["is_actual_real"]


def test_moving_money_errors(app_started, owner):
    c = owner["c"]
    same = {"from_account_id": owner["checking"], "to_account_id": owner["checking"],
            "amount": 5, "transfer_date": TODAY.isoformat()}
    assert c.post("/api/transfers", json=same).status_code == 400
    assert c.post("/api/transfers", json={**same, "to_account_id": owner["savings"],
                                           "amount": 0}).status_code == 422
    stranger, _ = register(app_started)
    theirs = make_account(stranger, "Theirs")
    r = c.post("/api/transfers", json={**same, "to_account_id": theirs})
    assert r.status_code == 404
