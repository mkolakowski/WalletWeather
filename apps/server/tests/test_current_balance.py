"""current_balance on GET /api/accounts and GET /api/accounts/{id}/forecast.

It's the balance as of today: the opening balance plus every line dated on
or before today, cleared lines at their real amount and uncleared ones at
their forecast amount (#30). "Today" is the viewer's date, sent by the
browser as ?today=, because the server's UTC clock is already on tomorrow
during the evening in the Americas (#39).
"""
from datetime import date, timedelta

import pytest

STARTING = 1000.0


@pytest.fixture
def account(client, registered):
    """An account opened well before this month, with lines around today.

    Dates are relative to the server's date; the tests say which day is
    "today" through ?today= so they don't depend on the server's clock.
    """
    server_today = date.today()
    r = client.post("/api/accounts", json={
        "name": "Checking", "starting_balance": STARTING,
        "starting_date": (server_today - timedelta(days=40)).isoformat()})
    assert r.status_code == 200, r.text
    account_id = r.json()["id"]

    def add(description, day, amount, cleared):
        body = {"description": description, "amount": amount,
                "forecast_date": day.isoformat(), "is_actual": cleared}
        if cleared:
            body["actual_date"] = day.isoformat()
        r = client.post(f"/api/accounts/{account_id}/transactions", json=body)
        assert r.status_code == 200, r.text

    d = server_today
    add("cleared yesterday", d - timedelta(days=1), -5.0, True)
    add("uncleared today", d, -100.0, False)
    add("cleared today", d, -10.0, True)
    add("uncleared tomorrow", d + timedelta(days=1), -1.0, False)
    return {"id": account_id, "today": d}


def _from_accounts(client, account_id, **params):
    r = client.get("/api/accounts", params=params)
    assert r.status_code == 200, r.text
    (row,) = [a for a in r.json() if a["id"] == account_id]
    return row["current_balance"]


def _from_forecast(client, account_id, **params):
    r = client.get(f"/api/accounts/{account_id}/forecast", params=params)
    assert r.status_code == 200, r.text
    return r.json()["current_balance"]


# --- #30: today's lines count, cleared or not; tomorrow's don't ------------

def test_balance_counts_todays_lines(client, account):
    today = account["today"].isoformat()
    expected = STARTING - 5 - 100 - 10  # tomorrow's -1 not yet
    assert _from_accounts(client, account["id"], today=today) == expected
    assert _from_forecast(client, account["id"], today=today) == expected


# --- #39: the viewer's date decides what "today" is ------------------------

def test_viewer_a_day_ahead_counts_the_next_days_lines(client, account):
    tomorrow = (account["today"] + timedelta(days=1)).isoformat()
    expected = STARTING - 5 - 100 - 10 - 1
    assert _from_accounts(client, account["id"], today=tomorrow) == expected
    assert _from_forecast(client, account["id"], today=tomorrow) == expected


def test_viewer_a_day_behind_leaves_out_the_servers_today(client, account):
    yesterday = (account["today"] - timedelta(days=1)).isoformat()
    expected = STARTING - 5
    assert _from_accounts(client, account["id"], today=yesterday) == expected
    assert _from_forecast(client, account["id"], today=yesterday) == expected


def test_without_today_the_servers_date_is_used(client, account):
    expected = STARTING - 5 - 100 - 10
    assert _from_accounts(client, account["id"]) == expected
    assert _from_forecast(client, account["id"]) == expected


def test_a_date_more_than_a_day_off_is_refused(client, account):
    far = (account["today"] + timedelta(days=3)).isoformat()
    assert client.get("/api/accounts", params={"today": far}).status_code == 400
    r = client.get(f"/api/accounts/{account['id']}/forecast", params={"today": far})
    assert r.status_code == 400


def test_a_malformed_date_is_refused(client, account):
    r = client.get("/api/accounts", params={"today": "not-a-date"})
    assert r.status_code == 422


def test_accounts_come_back_in_creation_order_even_after_one_is_changed(app_started):
    """Every list of accounts is by id (creation order), whatever order
    PostgreSQL's plan gives the rows. Guards the ordering; it does not
    reproduce the rare reorder behind test_core_answer_key's occasional
    failure (the calendar's accounts came back with the second first), whose
    cause is taken to be the missing ORDER BY but wasn't reproduced."""
    from fastapi.testclient import TestClient
    from conftest import unique_email
    c = TestClient(app_started)
    assert c.post("/api/auth/register", json={"email": unique_email(), "password": "correct-horse-battery"}).status_code == 200
    ids = []
    for name in ("One", "Two", "Three"):
        r = c.post("/api/accounts", json={"name": name, "starting_balance": 1, "starting_date": "2026-01-01"})
        assert r.status_code == 200, r.text
        ids.append(r.json()["id"])
    assert c.patch(f"/api/accounts/{ids[0]}", json={"name": "One, renamed"}).status_code == 200
    assert c.patch(f"/api/accounts/{ids[1]}", json={"name": "Two, renamed"}).status_code == 200
    # The lists join the permission rows, so an update to the first one's moves
    # it to the end of that table.
    from app.db import AccountPermission, SessionLocal
    db = SessionLocal()
    try:
        for i in (0, 1):
            row = db.query(AccountPermission).filter_by(account_id=ids[i]).one()
            row.level = "edit"
            db.commit()
            row.level = "owner"
            db.commit()
    finally:
        db.close()
    assert [a["id"] for a in c.get("/api/accounts").json()] == ids
