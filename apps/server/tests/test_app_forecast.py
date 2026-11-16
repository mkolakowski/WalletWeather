"""What the iOS app's Forecast page and search call (ios-app phase 2, #88).

The app reads the month's forecast, the caller's categories and transaction
search, and saves a line the way the web app's editor does: a new
transaction for a projected line (POST), the whole line again for one that
exists (PATCH), DELETE, and a skip for a projected date. Each test checks the
fields the app decodes, so a change here goes with a change in
apps/ios/WalletWeatherKit (and its recorded samples).
"""
from calendar import monthrange
from datetime import date

import pytest
from fastapi.testclient import TestClient

from conftest import share_account, unique_email
from test_app_shapes import NUM, has

PASSWORD = "correct-horse-battery"
TODAY = date.today()
START = TODAY.replace(day=1)
END = TODAY.replace(day=monthrange(TODAY.year, TODAY.month)[1])
MONTH = f"start={START}&end={END}&today={TODAY}"
OPT_STR = (str, type(None))
OPT_INT = (int, type(None))
OPT_NUM = (int, float, type(None))

ROW_FIELDS = {
    "forecast_date": OPT_STR, "actual_date": OPT_STR, "description": str,
    "category": OPT_STR, "category_id": OPT_INT, "notes": OPT_STR,
    "forecast_amount": OPT_NUM, "forecast_balance": NUM,
    "actual_amount": OPT_NUM, "actual_balance": NUM,
    "diff_amount": OPT_NUM, "diff_balance": NUM, "is_actual_real": bool,
    "recurring_id": OPT_INT, "transaction_id": OPT_INT, "transfer_id": OPT_INT,
}


def register(app):
    c = TestClient(app)
    r = c.post("/api/auth/register", json={"email": unique_email(), "password": PASSWORD})
    assert r.status_code == 200, r.text
    return c, r.json()["id"]


def bearer(app, client, access):
    r = client.post("/api/tokens", json={"name": "iPhone", "access": access})
    assert r.status_code == 200, r.text
    c = TestClient(app)
    c.headers["Authorization"] = f"Bearer {r.json()['token']}"
    return c


@pytest.fixture
def owner(app_started):
    """A user with Checking (1000 at the start of the month), a Bills
    category, and Rent on the 5th of each month in Bills."""
    c, uid = register(app_started)
    r = c.post("/api/accounts", json={"name": "Checking", "starting_balance": 1000,
                                      "starting_date": START.isoformat()})
    assert r.status_code == 200, r.text
    acc = next(a for a in c.get("/api/accounts").json() if a["name"] == "Checking")
    r = c.post("/api/categories", json={"name": "Bills", "color": "#cf222e"})
    assert r.status_code == 200, r.text
    cat = next(x for x in c.get("/api/categories").json() if x["name"] == "Bills")
    r = c.post(f"/api/accounts/{acc['id']}/recurring", json={
        "description": "Rent", "amount": -800, "frequency": "monthly_day",
        "day_of_month": 5, "category_id": cat["id"]})
    assert r.status_code == 200, r.text
    return {"c": c, "uid": uid, "acc": acc["id"], "cat": cat["id"], "rec": r.json()["id"]}


def month(c, acc):
    r = c.get(f"/api/accounts/{acc}/forecast?{MONTH}")
    assert r.status_code == 200, r.text
    return r.json()


def rent(c, acc):
    return next(r for r in month(c, acc)["rows"] if r["description"] == "Rent")


# ---------- Reading ----------

def test_forecast_month(owner):
    body = month(owner["c"], owner["acc"])
    has(body, {"opening_balance": NUM, "forecast_ending_balance": NUM,
               "actual_ending_balance": NUM, "current_balance": NUM, "rows": list})
    [row] = body["rows"]
    has(row, ROW_FIELDS)
    assert row["category_id"] == owner["cat"] and row["category"] == "Bills"
    assert row["recurring_id"] == owner["rec"] and row["transaction_id"] is None
    assert row["forecast_date"] == START.replace(day=5).isoformat()
    assert body["forecast_ending_balance"] == 200


def test_forecast_of_an_account_you_cant_see_is_404(app_started, owner):
    stranger, _ = register(app_started)
    assert stranger.get(f"/api/accounts/{owner['acc']}/forecast?{MONTH}").status_code == 404


def test_categories(owner):
    cats = owner["c"].get("/api/categories").json()
    assert any(c["id"] == owner["cat"] for c in cats)
    for cat in cats:
        has(cat, {"id": int, "name": str, "color": OPT_STR})


def test_me_says_what_the_token_may_do(app_started, owner):
    assert owner["c"].get("/api/me").json()["token_access"] is None
    for access in ("read", "full"):
        me = bearer(app_started, owner["c"], access).get("/api/me").json()
        assert me["token_access"] == access


def test_search(owner):
    c = owner["c"]
    r = c.post(f"/api/accounts/{owner['acc']}/transactions", json={
        "description": "Corner shop", "amount": -12.5, "forecast_amount": -12.5,
        "forecast_date": TODAY.isoformat(), "actual_date": TODAY.isoformat(),
        "is_actual": True, "category_id": owner["cat"], "notes": "milk"})
    assert r.status_code == 200, r.text
    body = c.get("/api/transactions/search?q=corner&limit=50").json()
    has(body, {"total": int, "results": list})
    [hit] = body["results"]
    has(hit, {"id": int, "account_id": int, "account_name": str, "description": str,
              "amount": NUM, "forecast_amount": OPT_NUM, "actual_date": OPT_STR,
              "forecast_date": OPT_STR, "is_actual": bool, "category_id": OPT_INT,
              "category_name": OPT_STR, "recurring_id": OPT_INT, "transfer_id": OPT_INT,
              "notes": OPT_STR})
    assert hit["account_id"] == owner["acc"] and hit["category_id"] == owner["cat"]
    # Notes are searched too; nothing matches an unknown word.
    assert c.get("/api/transactions/search?q=milk").json()["total"] == 1
    assert c.get("/api/transactions/search?q=zzzz").json()["total"] == 0


# ---------- Saving, as the app does ----------

def paid_body(row, amount, on, category_id, notes=None):
    """What the app sends to mark a line paid: the line again, paid."""
    return {"description": row["description"], "amount": amount,
            "forecast_date": row["forecast_date"], "forecast_amount": row["forecast_amount"],
            "actual_date": on, "is_actual": True, "recurring_id": row["recurring_id"],
            "category_id": category_id, "notes": notes}


def test_marking_a_projected_line_paid_and_undoing_it(owner):
    c, acc = owner["c"], owner["acc"]
    row = rent(c, acc)
    paid_on = START.replace(day=4).isoformat()
    r = c.post(f"/api/accounts/{acc}/transactions",
               json=paid_body(row, -812.34, paid_on, row["category_id"], "paid early"))
    assert r.status_code == 200, r.text
    has(r.json(), {"id": int})

    row = rent(c, acc)
    assert row["is_actual_real"] and row["transaction_id"] == r.json()["id"]
    assert row["actual_amount"] == -812.34 and row["forecast_amount"] == -800
    assert row["actual_date"] == paid_on and row["notes"] == "paid early"
    assert round(row["diff_amount"], 2) == -12.34

    # Undo: the line again, not paid, at its planned amount.
    undo = {**paid_body(row, -800, None, row["category_id"], "paid early"), "is_actual": False}
    r = c.patch(f"/api/transactions/{row['transaction_id']}", json=undo)
    assert r.status_code == 200, r.text
    assert r.json() == {"ok": True}
    row = rent(c, acc)
    assert not row["is_actual_real"] and row["actual_amount"] == -800
    assert row["category_id"] == owner["cat"] and row["notes"] == "paid early"


def test_adding_and_deleting_a_one_off(owner):
    c, acc = owner["c"], owner["acc"]
    r = c.post(f"/api/accounts/{acc}/transactions", json={
        "description": "Coffee", "amount": -4.5, "forecast_amount": -4.5,
        "forecast_date": TODAY.isoformat(), "actual_date": TODAY.isoformat(),
        "is_actual": True, "category_id": None, "notes": None})
    assert r.status_code == 200, r.text
    tid = r.json()["id"]
    coffee = next(x for x in month(c, acc)["rows"] if x["transaction_id"] == tid)
    assert coffee["is_actual_real"] and coffee["recurring_id"] is None
    r = c.delete(f"/api/transactions/{tid}")
    assert r.status_code == 200 and r.json() == {"ok": True}
    assert all(x["transaction_id"] != tid for x in month(c, acc)["rows"])
    assert c.delete(f"/api/transactions/{tid}").status_code == 404


def test_skipping_a_projected_date(owner):
    c, acc = owner["c"], owner["acc"]
    row = rent(c, acc)
    r = c.post(f"/api/recurring/{row['recurring_id']}/skip", json={"skip_date": row["forecast_date"]})
    assert r.status_code == 200 and r.json() == {"ok": True}
    assert month(c, acc)["rows"] == []


def test_a_category_that_isnt_yours_is_refused(app_started, owner):
    stranger, _ = register(app_started)
    stranger.post("/api/categories", json={"name": "Theirs"})
    theirs = next(x["id"] for x in stranger.get("/api/categories").json() if x["name"] == "Theirs")
    row = rent(owner["c"], owner["acc"])
    r = owner["c"].post(f"/api/accounts/{owner['acc']}/transactions",
                        json=paid_body(row, -800, TODAY.isoformat(), theirs))
    assert r.status_code == 404


def test_a_read_only_token_cant_save(app_started, owner):
    ro = bearer(app_started, owner["c"], "read")
    assert ro.get(f"/api/accounts/{owner['acc']}/forecast?{MONTH}").status_code == 200
    row = rent(ro, owner["acc"])
    r = ro.post(f"/api/accounts/{owner['acc']}/transactions",
                json=paid_body(row, -800, TODAY.isoformat(), row["category_id"]))
    assert r.status_code == 403


def test_someone_you_share_with_keeps_the_lines_category(app_started, owner):
    """On an account shared for editing, a line's category is the owner's.
    Saving the line with that category kept works; picking another
    category that isn't the saver's own is still refused."""
    editor, editor_id = register(app_started)
    share_account(owner["c"], owner["acc"], "edit", editor)
    acc = owner["acc"]

    row = rent(editor, acc)
    r = editor.post(f"/api/accounts/{acc}/transactions",
                    json=paid_body(row, -800, TODAY.isoformat(), row["category_id"]))
    assert r.status_code == 200, r.text
    row = rent(editor, acc)
    assert row["category_id"] == owner["cat"]

    body = {**paid_body(row, -790, TODAY.isoformat(), row["category_id"], "split")}
    assert editor.patch(f"/api/transactions/{row['transaction_id']}", json=body).status_code == 200
    assert rent(editor, acc)["notes"] == "split"

    owner["c"].post("/api/categories", json={"name": "Other"})
    other = next(x["id"] for x in owner["c"].get("/api/categories").json() if x["name"] == "Other")
    body["category_id"] = other
    assert editor.patch(f"/api/transactions/{row['transaction_id']}", json=body).status_code == 404
