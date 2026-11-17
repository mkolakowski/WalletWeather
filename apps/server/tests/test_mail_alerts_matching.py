"""Email alerts matched to bills (bank-alert-emails phase 4, #209).

An alert that lands pays a planned bill or income line the way a bank line
does (bank-sync phase 4): same account and direction, the amount within the
bill's match_percent and the date within its match_days of one of its unpaid
dates, the nearest date winning and a tie left unmatched. Alerts that paid
no bill are listed for the account's owner, who can match one by hand, leave
it as its own line, or un-match a match. Uses the stand-in Microsoft from
test_mail_alerts.py.
"""
from datetime import datetime, timedelta, timezone

from conftest import share_account
from test_mail_alerts import (BANK, TODAY, connect_with_code, connected, lines, make_account,  # noqa: F401
                              ms, register, set_switch, switched_on, taught, teach)

DAY = TODAY - timedelta(days=2)
WHEN = DAY.strftime("%b %d, %Y").replace(" 0", " ")     # "Nov 15, 2026"


def bill(c, acc, name, amount, day, **extra):
    """A monthly bill whose date this month falls on `day`."""
    r = c.post(f"/api/accounts/{acc}/recurring", json={
        "description": name, "amount": amount, "frequency": "monthly_day",
        "day_of_month": day.day, **extra})
    assert r.status_code == 200, r.text
    return r.json()["id"]


def forecast_rows(c, acc):
    r = c.get(f"/api/accounts/{acc}/forecast",
              params={"start": (TODAY - timedelta(days=40)).isoformat(),
                      "end": (TODAY + timedelta(days=40)).isoformat()})
    assert r.status_code == 200, r.text
    return r.json()["rows"]


def row(c, acc, rec, day):
    return next((x for x in forecast_rows(c, acc)
                 if x["recurring_id"] == rec and x["forecast_date"] == day.isoformat()), None)


def check(c, ms_=None):
    """Check now, after waiting out the 15 seconds between checks."""
    from app.db import MailConnection, SessionLocal
    db = SessionLocal()
    db.query(MailConnection).update({MailConnection.last_check_at: datetime.utcnow() - timedelta(minutes=5)})
    db.commit()
    db.close()
    r = c.post("/api/mail/check", json={})
    assert r.status_code == 200, r.text
    return r.json()


def unmatched(c, acc):
    r = c.get(f"/api/accounts/{acc}/bank-unmatched")
    assert r.status_code == 200, r.text
    return r.json()


def descriptions(c, acc):
    return sorted(t["description"] for t in lines(c, acc))


def alert(ms, mid, amount="42.50", merchant="CORNER GROCERY", day=DAY, **kw):
    ms.alert(mid, amount=amount, merchant=merchant,
             when=day.strftime("%b %d, %Y").replace(" 0", " "), **kw)


def first_check(c, ms):
    """The taught sample's own alert is on a day no bill sits on."""
    return check(c)


# ---------- Matching as alerts land ----------

def test_an_exact_match_pays_the_bill(taught, ms):
    c, u, acc = taught
    rec = bill(c, acc, "Groceries", -42.50, DAY)
    alert(ms, "g1")
    r = check(c)
    assert r["added"] == 2 and r["matched"] == 1           # the taught sample, and this one
    paid = row(c, acc, rec, DAY)
    assert paid["is_actual_real"] is True and paid["bank_match"] == "auto" and paid["match_source"] == "alert"
    assert paid["actual_amount"] == -42.5 and paid["actual_date"] == DAY.isoformat()
    # No second line for the alert's own merchant text.
    assert "CORNER GROCERY" not in descriptions(c, acc)
    assert r["status"]["last_check_status"].startswith("2 new lines, 1 of them matched a bill")
    # A second check adds nothing.
    again = check(c)
    assert (again["added"], again["matched"]) == (0, 0)


def test_a_late_bill_at_a_slightly_different_amount(taught, ms):
    c, u, acc = taught
    planned = DAY - timedelta(days=3)
    rec = bill(c, acc, "Groceries", -40.00, planned)       # 6.25% off, 3 days late
    alert(ms, "g1")
    assert check(c)["matched"] == 1
    paid = row(c, acc, rec, planned)
    assert (paid["forecast_amount"], paid["actual_amount"]) == (-40.0, -42.5)
    assert paid["actual_date"] == DAY.isoformat()


def test_the_bills_own_settings_are_used(taught, ms):
    c, u, acc = taught
    bill(c, acc, "Too far off in amount", -40.00, DAY, match_percent=5)
    bill(c, acc, "Too far off in days", -42.50, DAY - timedelta(days=3), match_days=2)
    alert(ms, "g1")
    r = check(c)
    assert r["matched"] == 0
    assert "CORNER GROCERY" in [x["description"] for x in unmatched(c, acc)["lines"]]


def test_two_candidates_as_near_are_left_unmatched(taught, ms):
    c, u, acc = taught
    bill(c, acc, "Groceries A", -42.50, DAY - timedelta(days=1))
    bill(c, acc, "Groceries B", -42.50, DAY + timedelta(days=1))
    alert(ms, "g1")
    assert check(c)["matched"] == 0
    assert "CORNER GROCERY" in [x["description"] for x in unmatched(c, acc)["lines"]]


def test_the_nearest_date_wins_and_only_the_same_direction(taught, ms):
    c, u, acc = taught
    near = bill(c, acc, "Near", -42.50, DAY)
    far = bill(c, acc, "Far", -42.50, DAY - timedelta(days=2))
    income = bill(c, acc, "Refund", 42.50, DAY)
    alert(ms, "g1")
    assert check(c)["matched"] == 1
    assert row(c, acc, near, DAY)["bank_match"] == "auto"
    assert row(c, acc, far, DAY - timedelta(days=2))["bank_match"] is None
    assert row(c, acc, income, DAY)["bank_match"] is None


def test_a_paid_bill_is_never_matched_twice(taught, ms):
    c, u, acc = taught
    rec = bill(c, acc, "Groceries", -42.50, DAY)
    alert(ms, "g1")
    alert(ms, "g2")                                         # the same amount, the same day
    r = check(c)
    assert r["matched"] == 1
    # The second alert is left for you (and the taught sample's own line, which pays no bill).
    assert sorted(x["description"] for x in unmatched(c, acc)["lines"]) == ["CORNER GROCERY", "STARBUCKS #123"]
    assert row(c, acc, rec, DAY)["bank_match"] == "auto"


def test_an_alert_gives_money_in_and_pays_income(taught, ms):
    c, u, acc = taught
    ms.add("dep", "Deposit received: $2,500.00",
           f"<p>We've deposited $2,500.00 from ACME PAYROLL into your account ending in 1234 on {WHEN}.</p>")
    pv = c.post("/api/mail/preview", json={"message_id": "graph-dep"}).json()
    text = pv["text"]
    s = text.index("ACME PAYROLL")
    teach(c, ms, acc, mid="dep", direction="in", fields=("amount", "date"),
          merchant=[s, s + len("ACME PAYROLL")])
    pay = bill(c, acc, "Paycheck", 2500.00, DAY)
    assert check(c)["matched"] == 1
    assert row(c, acc, pay, DAY)["match_source"] == "alert"


def test_the_matched_line_keeps_the_bills_tags(taught, ms):
    c, u, acc = taught
    tag = c.post("/api/tags", json={"name": "Food"}).json()["id"]
    rec = bill(c, acc, "Groceries", -42.50, DAY, tag_ids=[tag])
    alert(ms, "g1")
    check(c)
    assert [x["name"] for x in row(c, acc, rec, DAY)["tags"]] == ["Food"]


# ---------- Un-matching ----------

def test_unmatch_puts_the_bill_back_and_keeps_the_alerts_line(taught, ms):
    c, u, acc = taught
    rec = bill(c, acc, "Groceries", -42.50, DAY)
    alert(ms, "g1")
    check(c)
    paid = row(c, acc, rec, DAY)
    r = c.post(f"/api/transactions/{paid['transaction_id']}/bank-unmatch")
    assert r.status_code == 200, r.text
    back = row(c, acc, rec, DAY)
    assert back["is_actual_real"] is False and back["bank_match"] is None and back["match_source"] is None
    own = next(t for t in lines(c, acc) if t["id"] == r.json()["transaction_id"])
    assert (own["description"], own["amount"], own["actual_date"]) == ("CORNER GROCERY", -42.5, DAY.isoformat())
    # It's off the Unmatched list and isn't matched again, even by another check.
    assert [x["description"] for x in unmatched(c, acc)["lines"]] == ["STARBUCKS #123"]
    check(c)
    assert row(c, acc, rec, DAY)["bank_match"] is None
    assert c.get("/api/mail").json()["unmatched"] == [{"account_id": acc, "count": 1}]


def test_unmatch_needs_a_matched_line(taught, ms):
    c, u, acc = taught
    alert(ms, "g1")
    check(c)
    own = next(t for t in lines(c, acc) if t["description"] == "CORNER GROCERY")
    r = c.post(f"/api/transactions/{own['id']}/bank-unmatch")
    assert r.status_code == 409


# ---------- The Unmatched list ----------

def test_the_unmatched_list_and_its_count(taught, ms):
    c, u, acc = taught
    bill(c, acc, "Groceries", -42.50, DAY)
    alert(ms, "g1")
    alert(ms, "g2", amount="9.99", merchant="BAKERY")
    check(c)
    data = unmatched(c, acc)
    assert data["count"] == 2           # the taught sample's line and the bakery
    assert {l["description"] for l in data["lines"]} == {"STARBUCKS #123", "BAKERY"}
    assert all(set(l) == {"id", "date", "description", "amount", "notes", "source"} for l in data["lines"])
    assert {l["source"] for l in data["lines"]} == {"alert"}
    assert c.get("/api/mail").json()["unmatched"] == [{"account_id": acc, "count": 2}]


def test_leave_as_its_own_line(taught, ms):
    c, u, acc = taught
    alert(ms, "g1", amount="9.99", merchant="BAKERY")
    check(c)
    line = next(l for l in unmatched(c, acc)["lines"] if l["description"] == "BAKERY")
    assert c.post(f"/api/accounts/{acc}/bank-unmatched/{line['id']}/leave").status_code == 200
    assert "BAKERY" not in [l["description"] for l in unmatched(c, acc)["lines"]]
    assert "BAKERY" in descriptions(c, acc)
    assert c.post(f"/api/accounts/{acc}/bank-unmatched/{line['id']}/leave").status_code == 404


def test_match_by_hand_to_a_bill_outside_its_settings(taught, ms):
    c, u, acc = taught
    planned = DAY - timedelta(days=6)
    rec = bill(c, acc, "Groceries", -60.00, planned, match_days=1)
    alert(ms, "g1")
    assert check(c)["matched"] == 0
    line = next(l for l in unmatched(c, acc)["lines"] if l["description"] == "CORNER GROCERY")
    cands = c.get(f"/api/accounts/{acc}/bank-unmatched/{line['id']}/candidates").json()["candidates"]
    pick = next(x for x in cands if x["recurring_id"] == rec and x["forecast_date"] == planned.isoformat())
    r = c.post(f"/api/accounts/{acc}/bank-unmatched/{line['id']}/match",
               json={"recurring_id": rec, "forecast_date": pick["forecast_date"]})
    assert r.status_code == 200, r.text
    paid = row(c, acc, rec, planned)
    assert paid["bank_match"] == "hand" and paid["match_source"] == "alert"
    assert (paid["forecast_amount"], paid["actual_amount"]) == (-60.0, -42.5)
    assert "CORNER GROCERY" not in descriptions(c, acc)            # the separate line went away
    # A match by hand can be un-matched like any other.
    assert c.post(f"/api/transactions/{paid['transaction_id']}/bank-unmatch").status_code == 200
    assert "CORNER GROCERY" in descriptions(c, acc)


def test_match_by_hand_to_a_planned_one_off_line(taught, ms):
    c, u, acc = taught
    r = c.post(f"/api/accounts/{acc}/transactions", json={
        "description": "Planned groceries", "amount": -50.0, "is_actual": False,
        "forecast_date": (DAY - timedelta(days=9)).isoformat()})
    assert r.status_code == 200, r.text
    planned_id = r.json()["id"]
    alert(ms, "g1")
    check(c)
    line = next(l for l in unmatched(c, acc)["lines"] if l["description"] == "CORNER GROCERY")
    r = c.post(f"/api/accounts/{acc}/bank-unmatched/{line['id']}/match", json={"transaction_id": planned_id})
    assert r.status_code == 200, r.text
    t = next(t for t in lines(c, acc) if t["id"] == planned_id)
    assert (t["is_actual"], t["amount"]) == (True, -42.5)
    # A line already paid can't be picked.
    ms.alert("g3", amount="5.00", merchant="KIOSK", when=WHEN)
    check(c)
    other = next(l for l in unmatched(c, acc)["lines"] if l["description"] == "KIOSK")
    r = c.post(f"/api/accounts/{acc}/bank-unmatched/{other['id']}/match", json={"transaction_id": planned_id})
    assert r.status_code == 409


def test_a_transfer_leg_is_never_on_the_list_or_matched(taught, ms):
    c, u, acc = taught
    other = make_account(c, "Savings")
    r = c.post("/api/transfers", json={"from_account_id": acc, "to_account_id": other, "amount": 42.5,
                                       "transfer_date": DAY.isoformat()})
    assert r.status_code == 200, r.text
    bill(c, acc, "Groceries", -42.50, DAY)
    alert(ms, "g1")
    check(c)
    leg = next(x["transaction_id"] for x in forecast_rows(c, acc) if x["transfer_id"])
    assert leg not in [l["id"] for l in unmatched(c, acc)["lines"]]
    assert c.post(f"/api/accounts/{acc}/bank-unmatched/{leg}/leave").status_code == 404
    line = next(l for l in unmatched(c, acc)["lines"] if l["description"] == "STARBUCKS #123")
    cands = c.get(f"/api/accounts/{acc}/bank-unmatched/{line['id']}/candidates").json()["candidates"]
    assert all(x["transaction_id"] != leg for x in cands)
    r = c.post(f"/api/accounts/{acc}/bank-unmatched/{line['id']}/match", json={"transaction_id": leg})
    assert r.status_code == 409
    # The transfer leg didn't take the alert's place on the bill either: the bill was paid by the alert.
    assert row(c, acc, next(x["recurring_id"] for x in forecast_rows(c, acc) if x["description"] == "Groceries"),
               DAY)["bank_match"] == "auto"


def test_another_users_lines_cannot_be_matched(app_started, taught, ms):
    c, u, acc = taught
    alert(ms, "g1")
    check(c)
    line = next(l for l in unmatched(c, acc)["lines"] if l["description"] == "CORNER GROCERY")
    c2, _ = register(app_started)
    acc2 = make_account(c2)
    assert c2.get(f"/api/accounts/{acc}/bank-unmatched").status_code == 404
    assert c2.post(f"/api/accounts/{acc2}/bank-unmatched/{line['id']}/leave").status_code == 404
    assert c2.post(f"/api/accounts/{acc2}/bank-unmatched/{line['id']}/match",
                   json={"transaction_id": 1}).status_code == 404
    assert c2.post(f"/api/transactions/{line['id']}/bank-unmatch").status_code == 404
    # The account's shared viewers can't read the list either.
    share_account(c, acc, "edit", c2)
    assert c2.get(f"/api/accounts/{acc}/bank-unmatched").status_code == 404


# ---------- The log and the response ----------

def test_the_log_counts_matches(taught, ms):
    c, u, acc = taught
    bill(c, acc, "Groceries", -42.50, DAY)
    alert(ms, "g1")
    check(c)
    (r,) = c.get("/api/mail/checks").json()
    assert (r["added"], r["matched"]) == (2, 1)
    lines_ = c.get(f"/api/mail/checks/{r['id']}").json()
    assert lines_["matched"] == 1
    assert sorted((l["description"], l["matched"]) for l in lines_["lines"]) == [
        ("Groceries", "auto"), ("STARBUCKS #123", None)]


def test_a_retried_alert_is_matched_too(taught, ms):
    c, u, acc = taught
    rec = bill(c, acc, "Groceries", -42.50, DAY)
    ms.alert("c1", amount="42.50", merchant="CORNER GROCERY", when=WHEN, card="9876")
    check(c)
    other = make_account(c, "Card 9876")
    assert c.get("/api/mail/unread").json()[0]["reason"] == "card"
    sender = c.get("/api/mail").json()["senders"][0]
    c.put(f"/api/mail/senders/{sender['id']}", json={"cards": {"9876": other}})
    bill(c, other, "Groceries 2", -42.50, DAY)
    assert check(c)["matched"] == 1
    assert c.get("/api/mail/unread").json() == []


def test_the_forecast_says_where_a_match_came_from(taught, ms):
    c, u, acc = taught
    rec = bill(c, acc, "Groceries", -42.50, DAY)
    other = bill(c, acc, "Still planned", -10.0, TODAY + timedelta(days=5))
    alert(ms, "g1")
    check(c)
    rows = forecast_rows(c, acc)
    assert all("match_source" in r for r in rows)
    assert row(c, acc, rec, DAY)["match_source"] == "alert"
    assert row(c, acc, other, TODAY + timedelta(days=5))["match_source"] is None


def test_alert_matches_go_into_encrypted_backups(app_started, taught, ms):
    from app.backup import open_sealed
    c, u, acc = taught
    rec = bill(c, acc, "Groceries", -42.50, DAY)
    alert(ms, "g1")
    check(c)
    sealed = c.post("/api/backup/export", json={"passphrase": "a long passphrase"}).json()
    inside = open_sealed(sealed, "a long passphrase")
    paid = [t for a in inside["accounts"] for t in a["transactions"] if t.get("bank_match")]
    assert len(paid) == 1 and paid[0]["mail_ref"] and paid[0]["bank_text"] == "CORNER GROCERY"
    other, ou = register(app_started)
    r = other.post("/api/backup/import", json={"payload": sealed, "passphrase": "a long passphrase"})
    assert r.status_code == 200, r.text
    new_acc = next(a for a in other.get("/api/accounts").json() if a["name"] == "Checking")["id"]
    restored = [t for t in lines(other, new_acc) if t["description"] == "Groceries"]
    assert restored and next(x for x in forecast_rows(other, new_acc)
                             if x["transaction_id"] == restored[0]["id"])["match_source"] == "alert"
