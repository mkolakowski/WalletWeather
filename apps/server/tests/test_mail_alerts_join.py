"""Email alerts joined to bank sync rows (bank-alert-emails phase 5, #210).

An account may take lines from email alerts and from bank sync. A bank row
that is an alert line's posted version (same account and direction, 0 to the
account's join days after it, its amount the alert's or up to the account's
percent higher) joins that line instead of landing a second one: the
alert's name, the bank's id, amount and date, the user's own edits over
both. The nearest date wins and a tie is left on the Unmatched list. A join
can be undone (both lines come back, and the pair isn't joined again) or
made by hand, and an alert no bank row met is flagged "never posted". Uses
the stand-in SimpleFIN from test_bank_sync.py and the stand-in Microsoft
from test_mail_alerts.py.
"""
from datetime import timedelta

import pytest

import test_bank_sync as bank
import test_mail_alerts as mail
from conftest import share_account
from test_bank_sync import epoch, fake  # noqa: F401  (the stand-in SimpleFIN)
from test_mail_alerts import TODAY, ms  # noqa: F401  (the stand-in Microsoft)
from test_mail_alerts_matching import alert, bill, check, forecast_rows

DAY = TODAY - timedelta(days=2)


@pytest.fixture
def both(app_started, fake, ms):
    """A user whose account takes email alerts (a taught sender) and bank
    sync (the stand-in SimpleFIN, from 20 days ago). The bank lists no rows
    until a test gives it some."""
    bank.set_switch(True)
    mail.set_switch(True)
    c, u = mail.register(app_started)
    bank.allow_bank(u["id"])
    acc = mail.make_account(c)
    mail.connect_with_code(c, ms)
    r = c.put("/api/mail/settings", json={"folder_id": "ALERTS", "utc_offset_minutes": -300,
                                          "start_date": (TODAY - timedelta(days=1)).isoformat()})
    assert r.status_code == 200, r.text
    ms.alert("sample", amount="4.50", merchant="SAMPLE SHOP", when=_when(TODAY - timedelta(days=15)))
    mail.teach(c, ms, acc)
    fake.accounts[0]["transactions"] = []
    r = c.post("/api/bank/connect", json={"token": fake.token()})
    assert r.status_code == 200, r.text
    bank.link(c, r.json(), acc, start=TODAY - timedelta(days=20))
    yield c, u, acc
    bank.set_switch(False)
    mail.set_switch(False)


def _when(day):
    return day.strftime("%b %d, %Y").replace(" 0", " ")


def bank_rows(fake, *rows):
    """What the bank lists: (id, day, amount, description) each."""
    fake.accounts[0]["transactions"] = [
        {"id": i, "posted": epoch(d), "amount": a, "description": text} for i, d, a, text in rows]


def sync(c):
    r = c.post("/api/bank/sync")
    assert r.status_code == 200, r.text
    return r.json()


def lines(c, acc):
    """(description, amount, actual date) of every line but the taught sample's."""
    return sorted((t["description"], t["amount"], t["actual_date"]) for t in mail.lines(c, acc)
                  if t["description"] != "SAMPLE SHOP")


def line_named(c, acc, name):
    return next(t for t in mail.lines(c, acc) if t["description"] == name)


def unmatched(c, acc):
    r = c.get(f"/api/accounts/{acc}/bank-unmatched")
    assert r.status_code == 200, r.text
    return r.json()


def joins(c, acc):
    r = c.get(f"/api/accounts/{acc}/bank-unmatched/joins")
    assert r.status_code == 200, r.text
    return r.json()


def unmatched_line(c, acc, name):
    """A line on the Unmatched list, with what the joins endpoint says of it."""
    got = next((dict(x) for x in unmatched(c, acc)["lines"] if x["description"] == name), None)
    if got is not None:
        j = joins(c, acc)
        got["joined"] = got["id"] in j["joined"]
        got["never_posted"] = got["id"] in j["never_posted"]
        got["can_join"] = j["can_join"] and not got["joined"]
    return got


def account(c, acc):
    r = c.get("/api/accounts")
    assert r.status_code == 200, r.text
    return next(a for a in r.json() if a["id"] == acc)


# ---------- Joined as the bank row lands ----------

def test_an_exact_join_keeps_one_line(both, fake, ms):
    c, u, acc = both
    alert(ms, "a1", amount="42.50", merchant="CORNER GROCERY", day=DAY)
    check(c)
    bank_rows(fake, ("T-1", DAY, "-42.50", "POS CORNER GROCERY #55 SPRINGFIELD"),
              ("T-2", DAY, "2500.00", "PAYROLL ACME"))
    r = sync(c)
    assert (r["joined"], r["added"], r["skipped"]) == (1, 1, 0)
    assert "1 joined an email alert" in r["status"]["last_sync_status"]
    assert lines(c, acc) == [("CORNER GROCERY", -42.5, DAY.isoformat()),
                             ("PAYROLL ACME", 2500.0, (TODAY - timedelta(days=2)).isoformat())]
    got = unmatched_line(c, acc, "CORNER GROCERY")
    assert got["joined"] is True and got["source"] == "bank" and got["never_posted"] is False
    assert got["can_join"] is False                     # joined already
    assert unmatched_line(c, acc, "PAYROLL ACME")["can_join"] is True
    # The list keeps its shape (the shared core's answer key pins it); the
    # joins endpoint says the rest.
    assert set(unmatched(c, acc)["lines"][0]) == {"id", "date", "description", "amount", "notes", "source"}
    assert set(joins(c, acc)) == {"can_join", "joined", "never_posted"}
    # The forecast says it's the bank's, and when the bank posted it.
    row = next(x for x in forecast_rows(c, acc) if x["description"] == "CORNER GROCERY")
    assert row["alert_joined_posted"] == DAY.isoformat() and row["bank_unmatched"] is True
    # The sync log counts it, and lists the line.
    log = c.get(f"/api/accounts/{acc}/bank-syncs").json()
    assert log[0]["joined"] == 1 and log[0]["added"] == 1
    run = c.get(f"/api/accounts/{acc}/bank-syncs/{log[0]['id']}").json()
    assert [(x["description"], x["joined"]) for x in run["lines"]] == [
        ("CORNER GROCERY", True), ("PAYROLL ACME", False)]
    # Again: nothing new, nothing doubled.
    again = sync(c)
    assert (again["joined"], again["added"], again["skipped"]) == (0, 0, 2)
    assert len(lines(c, acc)) == 2


def test_a_tip_a_few_days_later_takes_the_banks_amount_and_date(both, fake, ms):
    c, u, acc = both
    alert(ms, "a1", amount="40.00", merchant="BISTRO", day=DAY - timedelta(days=3))
    check(c)
    bank_rows(fake, ("T-1", DAY, "-48.00", "BISTRO 123"))        # 20% more, 3 days on
    assert sync(c)["joined"] == 1
    assert lines(c, acc) == [("BISTRO", -48.0, DAY.isoformat())]


def test_the_users_own_edits_win_over_the_banks(both, fake, ms):
    c, u, acc = both
    alert(ms, "a1", amount="40.00", merchant="BISTRO", day=DAY - timedelta(days=1))
    check(c)
    t = line_named(c, acc, "BISTRO")
    r = c.patch(f"/api/transactions/{t['id']}", json={
        "description": "Dinner out", "amount": -47.00, "forecast_date": t["forecast_date"],
        "actual_date": t["actual_date"], "is_actual": True, "notes": "with the tip"})
    assert r.status_code == 200, r.text
    bank_rows(fake, ("T-1", DAY, "-48.00", "BISTRO 123"))
    assert sync(c)["joined"] == 1
    got = line_named(c, acc, "Dinner out")
    # The amount and the name were the user's; the date wasn't.
    assert (got["amount"], got["actual_date"], got["notes"]) == (-47.0, DAY.isoformat(), "with the tip")
    assert len(lines(c, acc)) == 1


def test_the_accounts_own_settings_and_their_limits(both, fake, ms, app_started):
    c, u, acc = both
    a = account(c, acc)
    assert (a["alert_join_days"], a["alert_join_percent"], a["alerts_and_bank"]) == (7, 30, True)
    for bad in ({"alert_join_days": 32}, {"alert_join_days": -1}, {"alert_join_percent": 101},
                {"alert_join_percent": -5}):
        assert c.patch(f"/api/accounts/{acc}", json=bad).status_code == 422
    r = c.patch(f"/api/accounts/{acc}", json={"alert_join_days": 2, "alert_join_percent": 10})
    assert r.status_code == 200 and (r.json()["alert_join_days"], r.json()["alert_join_percent"]) == (2, 10)
    # Only the owner changes them.
    editor, _ = mail.register(app_started, mail=False)
    share_account(c, acc, "edit", editor)
    assert editor.patch(f"/api/accounts/{acc}", json={"alert_join_days": 9}).status_code == 403
    assert account(c, acc)["alert_join_days"] == 2
    alert(ms, "a1", amount="50.00", merchant="TOO LATE", day=DAY - timedelta(days=3))
    alert(ms, "a2", amount="30.00", merchant="TOO MUCH TIP", day=DAY)
    alert(ms, "a3", amount="40.00", merchant="JUST RIGHT", day=DAY - timedelta(days=1))
    check(c)
    bank_rows(fake, ("T-1", DAY, "-50.00", "LATE ROW"),             # 3 days on: past 2
              ("T-2", DAY + timedelta(days=1), "-36.00", "TIP ROW"),   # 20% more: past 10%
              ("T-3", DAY + timedelta(days=1), "-43.00", "RIGHT ROW"))  # 2 days, 7.5%
    r = sync(c)
    assert (r["joined"], r["added"]) == (1, 2)
    names = [n for n, _a, _d in lines(c, acc)]
    assert "JUST RIGHT" in names and "RIGHT ROW" not in names
    assert {"TOO LATE", "LATE ROW", "TOO MUCH TIP", "TIP ROW"} <= set(names)
    # An account without both doesn't say it has.
    other = mail.make_account(c, "Savings")
    assert account(c, other)["alerts_and_bank"] is False


def test_a_lower_amount_an_earlier_row_or_money_the_other_way_isnt_joined(both, fake, ms):
    c, u, acc = both
    alert(ms, "a1", amount="40.00", merchant="SHOP", day=DAY)
    check(c)
    bank_rows(fake, ("T-1", DAY, "-39.00", "LESS"),
              ("T-2", DAY - timedelta(days=1), "-40.00", "BEFORE"),
              ("T-3", DAY, "40.00", "REFUND"))
    r = sync(c)
    assert (r["joined"], r["added"]) == (0, 3)
    assert len(lines(c, acc)) == 4


def test_the_nearest_wins_and_a_tie_is_left_for_you(both, fake, ms):
    c, u, acc = both
    alert(ms, "a1", amount="20.00", merchant="NEAR", day=DAY - timedelta(days=1))
    alert(ms, "a2", amount="20.00", merchant="FAR", day=DAY - timedelta(days=3))
    alert(ms, "b1", amount="10.00", merchant="TWIN ONE", day=DAY - timedelta(days=1))
    alert(ms, "b2", amount="10.00", merchant="TWIN TWO", day=DAY - timedelta(days=1))
    check(c)
    bank_rows(fake, ("T-1", DAY, "-20.00", "ROW TWENTY"), ("T-2", DAY, "-10.00", "ROW TEN"))
    r = sync(c)
    assert (r["joined"], r["added"]) == (1, 1)
    assert unmatched_line(c, acc, "NEAR")["joined"] is True
    assert unmatched_line(c, acc, "FAR")["joined"] is False
    # Two alerts as near: the bank row waits on the Unmatched list, and pays no bill.
    assert unmatched_line(c, acc, "ROW TEN")["source"] == "bank"
    assert not unmatched_line(c, acc, "TWIN ONE")["joined"] and not unmatched_line(c, acc, "TWIN TWO")["joined"]


def test_a_join_undone_brings_both_back_and_isnt_made_again(both, fake, ms):
    c, u, acc = both
    alert(ms, "a1", amount="40.00", merchant="BISTRO", day=DAY - timedelta(days=1))
    check(c)
    bank_rows(fake, ("T-1", DAY, "-48.00", "BISTRO 123"))
    assert sync(c)["joined"] == 1
    t = line_named(c, acc, "BISTRO")
    r = c.post(f"/api/transactions/{t['id']}/alert-unjoin")
    assert r.status_code == 200, r.text
    assert r.json()["transaction_id"] == t["id"]
    assert lines(c, acc) == [("BISTRO", -40.0, (DAY - timedelta(days=1)).isoformat()),
                             ("BISTRO 123", -48.0, DAY.isoformat())]
    # The alert's line is back on the Unmatched list; the bank row is its own line.
    assert unmatched_line(c, acc, "BISTRO")["joined"] is False
    assert unmatched_line(c, acc, "BISTRO 123") is None
    # Twice is refused, and a line that isn't joined can't be.
    assert c.post(f"/api/transactions/{t['id']}/alert-unjoin").status_code == 409
    # The next sync doesn't join them again.
    again = sync(c)
    assert (again["joined"], again["added"], again["skipped"]) == (0, 0, 1)
    assert len(lines(c, acc)) == 2


def csv_import(c, acc, text, **extra):
    r = c.post(f"/api/accounts/{acc}/import/commit", json={
        "csv_text": f"Date,Description,Amount\n{DAY.isoformat()},{text},-42.50\n",
        "mapping": {"date": 0, "description": 1, "amount": 2}, **extra})
    assert r.status_code == 200, r.text


def test_a_row_already_brought_in_by_csv(both, fake, ms):
    c, u, acc = both
    alert(ms, "a1", amount="42.50", merchant="CORNER GROCERY", day=DAY)
    check(c)
    # The import takes the alert's line for the same purchase.
    csv_import(c, acc, "Corner Grocery")
    assert len(lines(c, acc)) == 1
    bank_rows(fake, ("T-1", DAY, "-42.50", "CORNER GROCERY"))
    assert sync(c)["joined"] == 1
    assert lines(c, acc) == [("CORNER GROCERY", -42.5, DAY.isoformat())]


def test_a_csv_row_kept_beside_an_alert_is_the_bank_rows(both, fake, ms):
    c, u, acc = both
    alert(ms, "a1", amount="42.50", merchant="CORNER GROCERY", day=DAY)
    check(c)
    csv_import(c, acc, "Corner Grocery", skip_duplicates=False)
    bank_rows(fake, ("T-1", DAY, "-42.50", "CORNER GROCERY"))
    r = sync(c)
    # The bank row finds the CSV's line (as before) and no third line lands;
    # the alert's line isn't taken for a CSV row.
    assert (r["joined"], r["added"], r["skipped"]) == (0, 0, 1)
    assert lines(c, acc) == [("CORNER GROCERY", -42.5, DAY.isoformat()),
                             ("Corner Grocery", -42.5, DAY.isoformat())]
    assert unmatched_line(c, acc, "CORNER GROCERY")["joined"] is False


def test_an_alert_that_never_posts_is_flagged(both, fake, ms):
    c, u, acc = both
    alert(ms, "a1", amount="150.00", merchant="HOTEL HOLD", day=TODAY - timedelta(days=12))
    alert(ms, "a2", amount="9.00", merchant="RECENT", day=TODAY - timedelta(days=3))
    check(c)
    # Not before bank sync has read the bank past it.
    assert unmatched_line(c, acc, "HOTEL HOLD")["never_posted"] is False
    bank_rows(fake, ("T-1", DAY, "-1.00", "SOMETHING ELSE"))
    sync(c)
    assert unmatched_line(c, acc, "HOTEL HOLD")["never_posted"] is True
    assert unmatched_line(c, acc, "RECENT")["never_posted"] is False
    assert unmatched_line(c, acc, "SOMETHING ELSE")["never_posted"] is False
    # Nothing is removed by itself; keeping it takes it off the list.
    held = unmatched_line(c, acc, "HOTEL HOLD")
    assert c.post(f"/api/accounts/{acc}/bank-unmatched/{held['id']}/leave").status_code == 200
    assert "HOTEL HOLD" in [n for n, _a, _d in lines(c, acc)]


def test_a_bill_the_alert_paid_stays_paid_once_at_the_banks_amount(both, fake, ms):
    c, u, acc = both
    rec = bill(c, acc, "Dinner club", -40.00, DAY)
    alert(ms, "a1", amount="40.00", merchant="DINNER CLUB", day=DAY)
    assert check(c)["matched"] == 1
    bank_rows(fake, ("T-1", DAY + timedelta(days=1), "-46.00", "DINNER CLUB 99"))
    r = sync(c)
    assert (r["joined"], r["matched"], r["added"]) == (1, 0, 0)
    rows = [x for x in forecast_rows(c, acc) if x["recurring_id"] == rec
            and x["forecast_date"] == DAY.isoformat()]
    assert len(rows) == 1
    paid = rows[0]
    assert paid["is_actual_real"] is True and paid["bank_match"] == "auto"
    assert (paid["actual_amount"], paid["actual_date"]) == (-46.0, (DAY + timedelta(days=1)).isoformat())
    # It shows as the bank's (the Bank sync mark), and says when it posted.
    assert paid["match_source"] == "bank"
    assert paid["alert_joined_posted"] == (DAY + timedelta(days=1)).isoformat()
    assert "DINNER CLUB 99" not in [n for n, _a, _d in lines(c, acc)]
    # Un-joined, the bill stays paid by the alert at its amount, and the bank
    # row is its own line.
    assert c.post(f"/api/transactions/{paid['transaction_id']}/alert-unjoin").status_code == 200
    paid = next(x for x in forecast_rows(c, acc) if x["recurring_id"] == rec
                and x["forecast_date"] == DAY.isoformat())
    assert (paid["actual_amount"], paid["match_source"], paid.get("alert_joined_posted")) == (-40.0, "alert", None)
    assert ("DINNER CLUB 99", -46.0, (DAY + timedelta(days=1)).isoformat()) in lines(c, acc)


def test_an_alert_after_its_bank_row_joins_it(both, fake, ms):
    c, u, acc = both
    bank_rows(fake, ("T-1", DAY, "-25.00", "TAXI 8812"))
    assert sync(c)["added"] == 1
    alert(ms, "a1", amount="25.00", merchant="CITY TAXI", day=DAY)
    check(c)
    assert lines(c, acc) == [("CITY TAXI", -25.0, DAY.isoformat())]
    assert unmatched_line(c, acc, "CITY TAXI")["joined"] is True


def test_an_un_match_keeps_a_joined_line_whole(both, fake, ms):
    c, u, acc = both
    rec = bill(c, acc, "Dinner club", -40.00, DAY)
    alert(ms, "a1", amount="40.00", merchant="DINNER CLUB", day=DAY)
    check(c)
    bank_rows(fake, ("T-1", DAY, "-40.00", "DINNER CLUB 99"))
    assert sync(c)["joined"] == 1
    paid = next(x for x in forecast_rows(c, acc) if x["recurring_id"] == rec
                and x["forecast_date"] == DAY.isoformat())
    assert c.post(f"/api/transactions/{paid['transaction_id']}/bank-unmatch").status_code == 200
    # The line left over is still both the alert's and the bank's: the next
    # sync brings nothing in again, and it can still be un-joined.
    assert sync(c)["skipped"] == 1
    own = line_named(c, acc, "DINNER CLUB")
    assert c.post(f"/api/transactions/{own['id']}/alert-unjoin").status_code == 200
    assert len(lines(c, acc)) == 2


# ---------- Joined by hand ----------

def test_join_by_hand_and_undo_puts_the_bank_line_back_as_it_was(both, fake, ms):
    c, u, acc = both
    alert(ms, "a1", amount="30.00", merchant="GARAGE", day=DAY - timedelta(days=12))
    check(c)
    bank_rows(fake, ("T-1", DAY, "-31.00", "AUTO REPAIR 44"))        # 12 days on: past 7
    assert sync(c)["joined"] == 0
    a = unmatched_line(c, acc, "GARAGE")
    b = line_named(c, acc, "AUTO REPAIR 44")
    r = c.patch(f"/api/transactions/{b['id']}", json={
        "description": "AUTO REPAIR 44", "amount": -31.00, "forecast_date": b["forecast_date"],
        "actual_date": b["actual_date"], "is_actual": True, "notes": "brakes"})
    assert r.status_code == 200, r.text
    r = c.get(f"/api/accounts/{acc}/bank-unmatched/{a['id']}/join-candidates")
    assert r.status_code == 200, r.text
    cand = r.json()
    assert cand["line"]["source"] == "alert" and (cand["join_days"], cand["join_percent"]) == (7, 30)
    first = cand["lines"][0]
    assert (first["id"], first["source"], first["within"], first["days_after"]) == (b["id"], "bank", False, 12)
    assert first["amount_diff"] == 1.0 and first["same_direction"] is True
    # The other way round: from the bank row, the alert lines.
    back = c.get(f"/api/accounts/{acc}/bank-unmatched/{b['id']}/join-candidates").json()
    assert a["id"] in [x["id"] for x in back["lines"]]
    r = c.post(f"/api/accounts/{acc}/bank-unmatched/{a['id']}/join", json={"transaction_id": b["id"]})
    assert r.status_code == 200, r.text
    assert lines(c, acc) == [("GARAGE", -31.0, DAY.isoformat())]
    # A joined line can't be joined again.
    assert c.get(f"/api/accounts/{acc}/bank-unmatched/{a['id']}/join-candidates").status_code == 409
    r = c.post(f"/api/transactions/{a['id']}/alert-unjoin")
    assert r.status_code == 200, r.text
    assert lines(c, acc) == [("AUTO REPAIR 44", -31.0, DAY.isoformat()),
                             ("GARAGE", -30.0, (DAY - timedelta(days=12)).isoformat())]
    assert line_named(c, acc, "AUTO REPAIR 44")["notes"] == "brakes"
    # It was on the Unmatched list, so it's back on it.
    assert unmatched_line(c, acc, "AUTO REPAIR 44") is not None


def test_join_by_hand_checks(both, fake, ms):
    c, u, acc = both
    alert(ms, "a1", amount="30.00", merchant="SHOP", day=DAY)
    alert(ms, "a2", amount="12.00", merchant="OTHER ALERT", day=DAY)
    check(c)
    bank_rows(fake, ("T-1", DAY - timedelta(days=5), "30.00", "A REFUND"))
    sync(c)
    a = unmatched_line(c, acc, "SHOP")
    other = unmatched_line(c, acc, "OTHER ALERT")
    refund = unmatched_line(c, acc, "A REFUND")
    url = f"/api/accounts/{acc}/bank-unmatched/{a['id']}/join"
    # Two alert lines aren't a pair; money in and out isn't the same purchase.
    assert c.post(url, json={"transaction_id": other["id"]}).status_code == 404
    assert c.post(url, json={"transaction_id": refund["id"]}).status_code == 409
    assert c.post(url, json={}).status_code == 422
    assert c.post(f"/api/accounts/{acc}/bank-unmatched/999999/join",
                  json={"transaction_id": refund["id"]}).status_code == 404
    # An account without bank sync has nothing to join.
    plain = mail.make_account(c, "Cash")
    assert joins(c, plain) == {"can_join": False, "joined": [], "never_posted": []}
    assert c.get(f"/api/accounts/{plain}/bank-unmatched/{a['id']}/join-candidates").status_code == 409


def test_another_users_lines_cant_be_joined(both, fake, ms, app_started):
    c, u, acc = both
    alert(ms, "a1", amount="42.50", merchant="CORNER GROCERY", day=DAY)
    check(c)
    bank_rows(fake, ("T-1", DAY, "-42.50", "CORNER GROCERY"), ("T-2", DAY, "-9.00", "LONE ROW"))
    sync(c)
    joined = line_named(c, acc, "CORNER GROCERY")
    lone = line_named(c, acc, "LONE ROW")
    stranger, _ = mail.register(app_started)
    theirs = mail.make_account(stranger, "Theirs")
    r = stranger.post(f"/api/accounts/{theirs}/bank-unmatched/{lone['id']}/join",
                      json={"transaction_id": joined["id"]})
    assert r.status_code in (404, 409)      # not on their account (which has no bank sync)
    assert stranger.post(f"/api/accounts/{acc}/bank-unmatched/{lone['id']}/join",
                         json={"transaction_id": joined["id"]}).status_code == 404
    assert stranger.get(f"/api/accounts/{acc}/bank-unmatched/{lone['id']}/join-candidates").status_code == 404
    assert stranger.get(f"/api/accounts/{acc}/bank-unmatched/joins").status_code == 404
    assert stranger.post(f"/api/transactions/{joined['id']}/alert-unjoin").status_code == 404
    # A read-only share can't either.
    viewer, _ = mail.register(app_started, mail=False)
    share_account(c, acc, "read", viewer)
    assert viewer.post(f"/api/transactions/{joined['id']}/alert-unjoin").status_code == 404
    assert len(lines(c, acc)) == 2


def test_signed_out_is_refused(app_started):
    from fastapi.testclient import TestClient
    anon = TestClient(app_started)
    assert anon.get("/api/accounts/1/bank-unmatched/1/join-candidates").status_code == 401
    assert anon.post("/api/accounts/1/bank-unmatched/1/join", json={"transaction_id": 2}).status_code == 401
    assert anon.post("/api/transactions/1/alert-unjoin").status_code == 401
    assert anon.get("/api/accounts/1/bank-unmatched/joins").status_code == 401
