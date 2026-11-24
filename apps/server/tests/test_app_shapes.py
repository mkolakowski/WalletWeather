"""The shape of the responses the iOS app reads (ios-app phase 1, #87).

The app decodes these fields; a change made for the web page that drops or
renames one would break the app without anyone noticing. Each test checks the
fields and their types, so a change here goes with a change in
apps/ios/WalletWeatherKit (and its recorded samples).
"""
from datetime import date, timedelta

from test_bank_sync import connected, fake, link, register, switched_on  # noqa: F401 (fixtures)
from test_bank_sync_matching import GROCERY_DAY, bill, sync

NUM = (int, float)


def has(obj, fields):
    """Each field present, with a value of the given type(s)."""
    for name, kind in fields.items():
        assert name in obj, f"missing {name}"
        assert isinstance(obj[name], kind), f"{name} is {type(obj[name]).__name__}"


def make_account(client, name="Checking"):
    r = client.post("/api/accounts", json={
        "name": name, "starting_balance": 1000,
        "starting_date": date.today().replace(day=1).isoformat()})
    assert r.status_code == 200, r.text
    accounts = client.get("/api/accounts").json()
    return next(a for a in accounts if a["name"] == name)


def test_version(client):
    has(client.get("/api/version").json(), {"app_version": str, "schema_version": str})


def test_me(client, registered):
    has(client.get("/api/me").json(), {
        "id": int, "email": str, "is_admin": bool, "notice_required": bool,
        "notice_acknowledged_at": (str, type(None)), "token_access": (str, type(None))})


def test_accounts(client, registered):
    acc = make_account(client)
    has(acc, {"id": int, "name": str, "current_balance": NUM, "level": str})
    assert acc["level"] in ("owner", "edit", "read")


def test_dashboard(client, registered):
    make_account(client)
    today = date.today().isoformat()
    body = client.get(f"/api/dashboard?today={today}").json()
    [card] = body["cards"]
    has(card, {
        "id": int, "name": str, "month_label": str, "opening_balance": NUM,
        "current_balance": NUM, "forecast_end": NUM, "actual_end": NUM,
        "forecast_high": NUM, "forecast_low": NUM,
        "forecast_high_date": (str, type(None)), "forecast_low_date": (str, type(None)),
        "actual_high": NUM, "actual_low": NUM, "row_count": int,
        "upcoming_count": int, "upcoming_net": NUM})
    assert card["current_balance"] == 1000


def test_dashboard_refuses_a_far_off_today(client, registered):
    far = (date.today() + timedelta(days=5)).isoformat()
    assert client.get(f"/api/dashboard?today={far}").status_code == 400


def test_dashboard_charts(client, registered):
    make_account(client)
    for window in ("month", "30d", "90d"):
        body = client.get(f"/api/dashboard/charts?window={window}"
                          f"&today={date.today().isoformat()}").json()
        has(body, {"window": str, "label": str, "start": str, "end": str, "accounts": list})
        [acc] = body["accounts"]
        has(acc, {"account_id": int, "account_name": str, "totals": dict,
                  "categories": list, "balance_trend": list, "opening_balance": NUM,
                  "forecast_end": NUM, "actual_end": NUM})
        has(acc["totals"], {k: NUM for k in (
            "income_actual", "spending_actual", "net_actual",
            "income_forecast", "spending_forecast", "net_forecast")})
        assert acc["balance_trend"], "a point for each day"
        has(acc["balance_trend"][0], {"date": str, "balance": NUM})


def test_dashboard_charts_refuses_an_unknown_window(client, registered):
    assert client.get("/api/dashboard/charts?window=year").status_code == 400


def test_signed_out_gets_401(client):
    for path in ("/api/me", "/api/accounts", "/api/dashboard", "/api/dashboard/charts"):
        assert client.get(path).status_code == 401, path


def test_pinned_reports(client, registered):
    acc = make_account(client)
    r = client.post(f"/api/accounts/{acc['id']}/transactions", json={
        "description": "Groceries", "amount": -42, "forecast_amount": -40,
        "is_actual": True, "forecast_date": date.today().isoformat(),
        "actual_date": date.today().isoformat()})
    assert r.status_code == 200, r.text
    r = client.post("/api/saved-reports", json={
        "name": "Spending", "params": {"group_by": "category"}, "pinned": True})
    assert r.status_code == 200, r.text
    [saved] = client.get("/api/saved-reports").json()
    has(saved, {"id": int, "name": str, "pinned": bool})
    body = client.post(f"/api/saved-reports/{saved['id']}/run", json={}).json()
    has(body, {"start": str, "end": str, "range_label": str, "groups": list, "totals": dict})
    has(body["totals"], {"actual_net": NUM})
    assert body["groups"]
    for g in body["groups"]:
        has(g, {"name": str, "actual_total": NUM, "actual_count": int,
                "color": (str, type(None))})


def test_running_someone_elses_report_is_404(client, registered):
    assert client.post("/api/saved-reports/999999/run", json={}).status_code == 404


# ---------- Unmatched bank lines (duo-more phase 3, #306) ----------

def unmatched_setup(c, acc, status):
    """A bill 41% off the bank's CORNER GROCERY line, so the line stays on
    the Unmatched list with the bill as a close choice."""
    rec = bill(c, acc, "Groceries", -60.00, GROCERY_DAY)
    link(c, status, acc)
    sync(c)
    return rec


def test_bank_unmatched_list(connected, fake):
    c, u, acc, status = connected
    unmatched_setup(c, acc, status)
    got = c.get(f"/api/accounts/{acc}/bank-unmatched").json()
    has(got, {"count": int, "lines": list})
    assert got["count"] == len(got["lines"]) >= 1
    for line in got["lines"]:
        has(line, {"id": int, "date": str, "description": str, "amount": NUM,
                   "notes": (str, type(None)), "source": str})
        assert line["source"] in ("bank", "alert")
        date.fromisoformat(line["date"])
    assert "CORNER GROCERY" in [x["description"] for x in got["lines"]]


def test_bank_unmatched_candidates(connected, fake):
    c, u, acc, status = connected
    rec = unmatched_setup(c, acc, status)
    lines = c.get(f"/api/accounts/{acc}/bank-unmatched").json()["lines"]
    line = next(x for x in lines if x["description"] == "CORNER GROCERY")
    r = c.get(f"/api/accounts/{acc}/bank-unmatched/{line['id']}/candidates")
    assert r.status_code == 200, r.text
    got = r.json()
    has(got, {"line": dict, "choices": list})
    has(got["line"], {"id": int, "date": str, "description": str, "amount": NUM,
                      "bank_text": (str, type(None)), "learn_name": str})
    assert got["line"]["id"] == line["id"]
    assert got["choices"]
    for ch in got["choices"]:
        has(ch, {"transaction_id": (int, type(None)), "recurring_id": (int, type(None)),
                 "forecast_date": str, "amount": NUM, "description": str,
                 "days_apart": int, "days_after": int, "amount_diff": NUM,
                 "same_direction": bool, "within_days": bool})
    close = next(ch for ch in got["choices"] if ch["recurring_id"] == rec)
    assert close["description"] == "Groceries" and close["forecast_date"] == GROCERY_DAY.isoformat()
    assert close["transaction_id"] is None and close["same_direction"] is True


def test_bank_unmatched_unknown_account_or_line_is_404(connected, fake):
    c, u, acc, status = connected
    unmatched_setup(c, acc, status)
    assert c.get("/api/accounts/999999/bank-unmatched").status_code == 404
    assert c.get(f"/api/accounts/{acc}/bank-unmatched/999999/candidates").status_code == 404
    assert c.post(f"/api/accounts/{acc}/bank-unmatched/999999/leave").status_code == 404
    assert c.get("/api/accounts/999999/bank-unmatched/1/candidates").status_code == 404


def test_bank_unmatched_someone_elses_account_is_refused(app_started, connected, fake):
    c, u, acc, status = connected
    unmatched_setup(c, acc, status)
    line = c.get(f"/api/accounts/{acc}/bank-unmatched").json()["lines"][0]
    other, _ou = register(app_started)
    assert other.get(f"/api/accounts/{acc}/bank-unmatched").status_code == 404
    assert other.get(f"/api/accounts/{acc}/bank-unmatched/{line['id']}/candidates").status_code == 404
    assert other.post(f"/api/accounts/{acc}/bank-unmatched/{line['id']}/leave").status_code == 404
    assert c.get(f"/api/accounts/{acc}/bank-unmatched").json()["count"] >= 1
