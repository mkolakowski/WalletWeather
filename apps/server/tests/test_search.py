"""GET /api/search (#111): one search across transactions, bills and income,
accounts, categories, tags and saved reports, for the web app's top bar and
the iOS app (ios-app phase 10, #112). Each test checks the fields the
clients read, so a change here goes with a change in apps/web/index.html and
apps/ios/WalletWeatherKit.
"""
from datetime import date

import pytest

from test_app_forecast import bearer, register
from test_app_shapes import NUM, has

TODAY = date.today()
GROUPS = ("transactions", "recurring", "accounts", "categories", "tags", "reports")
OPT_STR = (str, type(None))
OPT_INT = (int, type(None))


def search(c, q, **params):
    r = c.get("/api/search", params={"q": q, "today": TODAY.isoformat(), **params})
    assert r.status_code == 200, r.text
    return r.json()


@pytest.fixture
def owner(app_started):
    """Harbor Checking with a paid "Harbor Market" run (note "weekly shop")
    in the Harbor food category, tagged Harbor trip; a monthly "Harbor rent"
    bill; and a saved report called "Harbor spending"."""
    c, uid = register(app_started)
    r = c.post("/api/accounts", json={"name": "Harbor Checking", "starting_balance": 1000,
                                      "starting_date": TODAY.replace(day=1).isoformat()})
    assert r.status_code == 200, r.text
    acc = next(a["id"] for a in c.get("/api/accounts").json() if a["name"] == "Harbor Checking")
    r = c.post("/api/categories", json={"name": "Harbor food", "color": "#3fb950"})
    assert r.status_code == 200, r.text
    cat = r.json()["id"]
    r = c.post("/api/tags", json={"name": "Harbor trip", "color": "#58a6ff"})
    assert r.status_code == 200, r.text
    tag = r.json()["id"]
    r = c.post(f"/api/accounts/{acc}/transactions", json={
        "description": "Harbor Market", "notes": "weekly shop", "amount": -40,
        "forecast_amount": -40, "is_actual": True, "forecast_date": TODAY.isoformat(),
        "actual_date": TODAY.isoformat(), "category_id": cat, "tag_ids": [tag]})
    assert r.status_code == 200, r.text
    r = c.post(f"/api/accounts/{acc}/recurring", json={
        "description": "Harbor rent", "amount": -900, "frequency": "monthly_day",
        "day_of_month": 28, "category_id": cat})
    assert r.status_code == 200, r.text
    bill = r.json()["id"]
    r = c.post("/api/saved-reports", json={
        "name": "Harbor spending", "params": {"group_by": "category", "kind": "spending"},
        "pinned": False})
    assert r.status_code == 200, r.text
    return {"c": c, "uid": uid, "acc": acc, "cat": cat, "tag": tag, "bill": bill}


def test_finds_each_kind_with_the_fields_clients_read(owner):
    body = search(owner["c"], "harbor")
    assert body["query"] == "harbor"
    for g in GROUPS:
        has(body[g], {"total": int, "results": list})
        assert body[g]["total"] == len(body[g]["results"]) == 1, g

    [t] = body["transactions"]["results"]
    has(t, {"id": int, "description": str, "date": str, "amount": NUM, "is_actual": bool,
            "account_id": int, "account_name": str, "category_id": OPT_INT,
            "category_name": OPT_STR, "recurring_id": OPT_INT, "transfer_id": OPT_INT})
    assert (t["description"], t["date"], t["amount"]) == ("Harbor Market", TODAY.isoformat(), -40)
    assert (t["account_id"], t["category_id"]) == (owner["acc"], owner["cat"])

    [b] = body["recurring"]["results"]
    has(b, {"id": int, "description": str, "amount": NUM, "frequency": str,
            "next_date": OPT_STR, "expired": bool, "account_id": int, "account_name": str,
            "account_level": str, "category_id": OPT_INT, "category_name": OPT_STR})
    assert (b["id"], b["amount"], b["expired"], b["account_level"]) == (owner["bill"], -900, False, "owner")
    assert b["next_date"] is not None and b["next_date"].endswith("-28")

    [a] = body["accounts"]["results"]
    has(a, {"id": int, "name": str, "current_balance": NUM, "level": str})
    assert (a["id"], a["current_balance"], a["level"]) == (owner["acc"], 960, "owner")

    [cat] = body["categories"]["results"]
    has(cat, {"id": int, "name": str, "color": OPT_STR, "transaction_count": int})
    assert (cat["id"], cat["transaction_count"]) == (owner["cat"], 1)

    [tag] = body["tags"]["results"]
    has(tag, {"id": int, "name": str, "color": OPT_STR, "transaction_count": int})
    assert (tag["id"], tag["transaction_count"]) == (owner["tag"], 1)

    [rep] = body["reports"]["results"]
    has(rep, {"id": int, "name": str})
    assert rep["name"] == "Harbor spending"


def test_notes_match_and_case_doesnt_matter(owner):
    body = search(owner["c"], "  WEEKLY Shop ")
    assert body["query"] == "WEEKLY Shop"
    assert [t["description"] for t in body["transactions"]["results"]] == ["Harbor Market"]
    assert all(body[g]["total"] == 0 for g in GROUPS if g != "transactions")


def test_an_empty_query_finds_nothing(owner):
    for q in ("", "   "):
        body = search(owner["c"], q)
        assert body["query"] == ""
        assert all(body[g] == {"total": 0, "results": []} for g in GROUPS)
    assert owner["c"].get("/api/search").status_code == 200


def test_limit_caps_each_group_but_total_counts_all(owner):
    c = owner["c"]
    for i in range(3):
        r = c.post(f"/api/accounts/{owner['acc']}/transactions", json={
            "description": f"Harbor ferry {i}", "amount": -5, "forecast_amount": -5,
            "forecast_date": TODAY.isoformat()})
        assert r.status_code == 200, r.text
    body = search(c, "harbor", limit=2)
    assert body["transactions"]["total"] == 4
    assert len(body["transactions"]["results"]) == 2


def test_nothing_from_accounts_the_caller_cant_see(app_started, owner):
    stranger, _ = register(app_started)
    body = search(stranger, "harbor")
    assert all(body[g]["total"] == 0 for g in GROUPS)


def test_a_shared_account_shows_but_not_the_owners_own_things(app_started, owner):
    viewer, viewer_id = register(app_started)
    r = owner["c"].post("/api/permissions", json={
        "account_id": owner["acc"], "user_id": viewer_id, "level": "read"})
    assert r.status_code == 200, r.text
    body = search(viewer, "harbor")
    assert body["transactions"]["total"] == 1
    assert body["recurring"]["results"][0]["account_level"] == "read"
    assert body["accounts"]["results"][0]["level"] == "read"
    # Categories, tags and reports belong to their owner.
    assert body["categories"]["total"] == body["tags"]["total"] == body["reports"]["total"] == 0


def test_an_ended_bill_comes_after_running_ones(owner):
    c = owner["c"]
    r = c.post(f"/api/accounts/{owner['acc']}/recurring", json={
        "description": "Harbor parking (old)", "amount": -20, "frequency": "monthly_day",
        "day_of_month": 1, "anchor_date": "2020-01-01", "end_date": "2020-06-01"})
    assert r.status_code == 200, r.text
    bills = search(c, "harbor")["recurring"]["results"]
    assert [b["expired"] for b in bills] == [False, True]
    assert bills[1]["next_date"] is None


def test_works_with_a_read_token(app_started, owner):
    phone = bearer(app_started, owner["c"], "read")
    assert search(phone, "harbor")["accounts"]["total"] == 1


def test_needs_a_sign_in(app_started):
    from fastapi.testclient import TestClient
    assert TestClient(app_started).get("/api/search?q=x").status_code == 401


def test_today_must_be_near_the_servers_date(owner):
    r = owner["c"].get("/api/search", params={"q": "harbor", "today": "2001-01-01"})
    assert r.status_code == 400
