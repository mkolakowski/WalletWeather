"""GET /api/recurring: every recurring template across the accounts a user
can see, for the Bills & income page (#51).

Each item carries its account and the caller's access level on it; `totals`
covers bills, income and net per month and per year, counting active rows on
a known cadence only. `archived=true` lists the ones whose end date has passed.
"""
from datetime import date, timedelta

import pytest
from fastapi.testclient import TestClient

from conftest import make_account, share_account, unique_email

PASSWORD = "correct-horse-battery"


def register(app):
    """A new signed-in user with their own client (their own cookies)."""
    c = TestClient(app)
    r = c.post("/api/auth/register",
               json={"email": unique_email(), "password": PASSWORD})
    assert r.status_code == 200, r.text
    return c, r.json()["id"]


def make_recurring(c, account_id, description, amount, frequency="monthly_day",
                   **extra):
    body = {"description": description, "amount": amount, "frequency": frequency}
    if frequency == "monthly_day":
        body["day_of_month"] = 5
    else:
        body["anchor_date"] = date.today().isoformat()
    body.update(extra)
    r = c.post(f"/api/accounts/{account_id}/recurring", json=body)
    assert r.status_code == 200, r.text
    return r.json()["id"]


@pytest.fixture
def two_accounts(app_started):
    """One user with two accounts: a bill and a paycheck on Checking, a weekly
    bill and an ended bill on Savings."""
    c, _ = register(app_started)
    checking = make_account(c, "Checking")
    savings = make_account(c, "Savings")
    ids = {
        "rent": make_recurring(c, checking, "Rent", -1200.0),
        "pay": make_recurring(c, checking, "Paycheck", 2000.0, "biweekly"),
        "gym": make_recurring(c, savings, "Gym", -10.0, "weekly"),
        "old": make_recurring(
            c, savings, "Old phone plan", -30.0,
            end_date=(date.today() - timedelta(days=40)).isoformat()),
    }
    return c, checking, savings, ids


def test_lists_every_account_with_totals(two_accounts):
    c, checking, savings, ids = two_accounts
    r = c.get("/api/recurring")
    assert r.status_code == 200, r.text
    body = r.json()
    by_id = {it["id"]: it for it in body["items"]}
    assert set(by_id) == {ids["rent"], ids["pay"], ids["gym"]}

    rent = by_id[ids["rent"]]
    assert rent["account_id"] == checking
    assert rent["account_name"] == "Checking"
    assert rent["account_level"] == "owner"
    assert rent["amount"] == -1200.0
    assert rent["monthly"] == -1200.0
    assert rent["monthly_cost"] == 1200.0
    assert rent["yearly_cost"] == 14400.0
    for key in ("description", "frequency", "day_of_month", "anchor_date",
                "end_date", "category_id", "category_name", "category_color",
                "notes", "skipped_count", "yearly"):
        assert key in rent

    pay = by_id[ids["pay"]]
    assert pay["account_name"] == "Checking"
    assert pay["monthly"] == round(2000.0 * 26 / 12, 2)
    assert pay["monthly_cost"] is None

    gym = by_id[ids["gym"]]
    assert gym["account_id"] == savings
    assert gym["monthly"] == round(-10.0 * 52 / 12, 2)

    t = body["totals"]
    bills = 1200.0 + 10.0 * 52 / 12
    income = 2000.0 * 26 / 12
    assert t["bills_count"] == 2
    assert t["income_count"] == 1
    assert t["bills_monthly"] == round(bills, 2)
    assert t["income_monthly"] == round(income, 2)
    assert t["net_monthly"] == round(income - bills, 2)
    assert t["bills_yearly"] == round(bills * 12, 2)
    assert t["net_yearly"] == round((income - bills) * 12, 2)


def test_account_filter_narrows_items_and_totals(two_accounts):
    c, checking, savings, ids = two_accounts
    body = c.get(f"/api/recurring?account_id={savings}").json()
    assert [it["id"] for it in body["items"]] == [ids["gym"]]
    assert body["totals"]["bills_count"] == 1
    assert body["totals"]["income_count"] == 0
    assert body["totals"]["income_monthly"] == 0


def test_archived_lists_only_ended_templates(two_accounts):
    c, checking, savings, ids = two_accounts
    body = c.get("/api/recurring?archived=true").json()
    assert [it["id"] for it in body["items"]] == [ids["old"]]
    assert body["items"][0]["expired"] is True


def test_shared_read_only_account_shows_its_level(app_started, two_accounts):
    owner, checking, savings, ids = two_accounts
    viewer, viewer_id = register(app_started)
    share_account(owner, checking, "read", viewer)

    body = viewer.get("/api/recurring").json()
    assert {it["id"] for it in body["items"]} == {ids["rent"], ids["pay"]}
    assert {it["account_level"] for it in body["items"]} == {"read"}


def test_account_the_user_cannot_see_is_not_found(app_started, two_accounts):
    owner, checking, savings, ids = two_accounts
    stranger, _ = register(app_started)
    r = stranger.get(f"/api/recurring?account_id={checking}")
    assert r.status_code == 404
    assert stranger.get("/api/recurring").json()["items"] == []


def test_today_far_from_the_server_date_is_refused(two_accounts):
    c, *_ = two_accounts
    far = (date.today() + timedelta(days=5)).isoformat()
    assert c.get(f"/api/recurring?today={far}").status_code == 400


def test_signed_out_is_refused(client):
    assert client.get("/api/recurring").status_code == 401
