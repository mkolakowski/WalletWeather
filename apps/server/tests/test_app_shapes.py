"""The shape of the responses the iOS app reads (ios-app phase 1, #87).

The app decodes these fields; a change made for the web page that drops or
renames one would break the app without anyone noticing. Each test checks the
fields and their types, so a change here goes with a change in
apps/ios/WalletWeatherKit (and its recorded samples).
"""
from datetime import date, timedelta

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
        "notice_acknowledged_at": (str, type(None))})


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
