"""Bills learn bank text (match-by-hand phase 3, #224).

Matching a line by hand with `remember: true` teaches the bill the line's
name. A taught bill takes a later line with that name at any amount going
its way within its days, and is preferred over bills that fit by amount, so
a tie between two bills goes to the taught one; lines already on the
Unmatched list with that name are caught up; the bill's Forget clears it. Two weekly bills a day either side of each bank
line make the tie: Gym A from GROCERY_DAY - 8, Gym B from GROCERY_DAY - 6.
"""
from datetime import timedelta

from test_bank_sync import connected, epoch, fake, link, register, switched_on  # noqa: F401 (fixtures)
from test_bank_sync_matching import GROCERY_DAY, row, sync, unmatched
from conftest import share_account

G = GROCERY_DAY
LATER_LINE_DAY = G - timedelta(days=7)    # Gym A's G-8 and Gym B's G-6 are a day either side


def weekly(c, acc, name, amount, anchor):
    r = c.post(f"/api/accounts/{acc}/recurring", json={
        "description": name, "amount": amount, "frequency": "weekly", "anchor_date": anchor.isoformat()})
    assert r.status_code == 200, r.text
    return r.json()["id"]


def gyms(c, acc):
    return weekly(c, acc, "Gym A", -40.00, G - timedelta(days=8)), weekly(c, acc, "Gym B", -40.00, G - timedelta(days=6))


def bank_line(fake, ref, day, amount, name):
    fake.accounts[0]["transactions"].append(
        {"id": ref, "posted": epoch(day), "amount": f"{amount:.2f}", "description": name})


def names(c, acc):
    return [x["description"] for x in unmatched(c, acc)["lines"]]


def taught(c, acc, rec):
    r = c.get(f"/api/accounts/{acc}/recurring")
    assert r.status_code == 200, r.text
    return next(x for x in r.json() if x["id"] == rec)["match_text"]


def match(c, acc, line_id, **body):
    r = c.post(f"/api/accounts/{acc}/bank-unmatched/{line_id}/match", json=body)
    assert r.status_code == 200, r.text
    return r.json()


def grocery(c, acc):
    return next(x for x in unmatched(c, acc)["lines"] if x["description"] == "CORNER GROCERY")


def test_a_taught_bill_takes_the_next_tie(connected, fake):
    c, u, acc, status = connected
    a, b = gyms(c, acc)
    link(c, status, acc)
    sync(c)
    line = grocery(c, acc)                                  # a tie: left unmatched
    cands = c.get(f"/api/accounts/{acc}/bank-unmatched/{line['id']}/candidates").json()
    assert cands["line"]["learn_name"] == "CORNER GROCERY"
    out = match(c, acc, line["id"], recurring_id=a, forecast_date=(G - timedelta(days=1)).isoformat(),
                remember=True)
    assert out["learned"] == "CORNER GROCERY" and out["also_matched"] == 0
    assert taught(c, acc, a) == "CORNER GROCERY" and taught(c, acc, b) is None
    # A line with another name still ties, and is left unmatched.
    bank_line(fake, "T-10", LATER_LINE_DAY, -41.00, "OTHER SHOP")
    assert sync(c)["matched"] == 0
    # The next line with the taught name ties too, and goes to Gym A by itself.
    bank_line(fake, "T-9", LATER_LINE_DAY, -41.00, "Corner  Grocery")   # case and spaces don't matter
    assert sync(c)["matched"] == 1
    paid = row(c, acc, a, G - timedelta(days=8))
    assert paid["bank_match"] == "auto" and paid["actual_amount"] == -41.0
    assert sorted(names(c, acc)) == ["OTHER SHOP", "PAYROLL ACME"]


def test_a_taught_name_pays_at_any_amount_within_the_days(connected, fake):
    c, u, acc, status = connected
    a, b = gyms(c, acc)
    link(c, status, acc)
    sync(c)
    match(c, acc, grocery(c, acc)["id"], recurring_id=a, forecast_date=(G - timedelta(days=1)).isoformat(),
          remember=True)
    bank_line(fake, "T-12", LATER_LINE_DAY, -95.00, "OTHER SHOP")        # 137% off, no taught name
    bank_line(fake, "T-9", LATER_LINE_DAY, -95.00, "CORNER GROCERY")     # 137% off, the taught name
    bank_line(fake, "T-13", LATER_LINE_DAY, 95.00, "CORNER GROCERY")     # a refund: the other way
    assert sync(c)["matched"] == 1
    paid = row(c, acc, a, G - timedelta(days=8))
    assert paid["bank_match"] == "auto" and paid["actual_amount"] == -95.0
    left = sorted((x["description"], x["amount"]) for x in unmatched(c, acc)["lines"])
    assert left == [("CORNER GROCERY", 95.0), ("OTHER SHOP", -95.0), ("PAYROLL ACME", 2500.0)]
    # Outside the bill's days it still waits: Gym A's next open date is 13 days on.
    bank_line(fake, "T-14", G, -95.00, "CORNER GROCERY")
    assert sync(c)["matched"] == 0


def test_without_remember_the_tie_stays(connected, fake):
    c, u, acc, status = connected
    a, b = gyms(c, acc)
    link(c, status, acc)
    sync(c)
    out = match(c, acc, grocery(c, acc)["id"], recurring_id=a,
                forecast_date=(G - timedelta(days=1)).isoformat())
    assert out["learned"] is None and out["also_matched"] == 0
    assert taught(c, acc, a) is None
    bank_line(fake, "T-9", LATER_LINE_DAY, -41.00, "CORNER GROCERY")
    assert sync(c)["matched"] == 0
    assert "CORNER GROCERY" in names(c, acc)


def test_teaching_catches_up_lines_already_unmatched(connected, fake):
    c, u, acc, status = connected
    a, b = gyms(c, acc)
    bank_line(fake, "T-9", LATER_LINE_DAY, -41.00, "CORNER GROCERY")
    bank_line(fake, "T-11", LATER_LINE_DAY, -80.00, "CORNER GROCERY")   # no open date of Gym A is left for it
    link(c, status, acc)
    sync(c)
    lines = [x for x in unmatched(c, acc)["lines"] if x["description"] == "CORNER GROCERY"]
    assert len(lines) == 3                                  # all left unmatched
    newest = max(lines, key=lambda x: x["date"])
    out = match(c, acc, newest["id"], recurring_id=a, forecast_date=(G - timedelta(days=1)).isoformat(),
                remember=True)
    assert out["also_matched"] == 1
    paid = row(c, acc, a, G - timedelta(days=8))
    assert paid["bank_match"] == "auto" and paid["actual_amount"] == -41.0
    left = [x for x in unmatched(c, acc)["lines"] if x["description"] == "CORNER GROCERY"]
    assert [x["amount"] for x in left] == [-80.0]


def test_forget(app_started, connected, fake):
    c, u, acc, status = connected
    a, b = gyms(c, acc)
    link(c, status, acc)
    sync(c)
    match(c, acc, grocery(c, acc)["id"], recurring_id=a, forecast_date=(G - timedelta(days=1)).isoformat(),
          remember=True)
    other, ou = register(app_started)
    share_account(c, acc, "read", other)
    assert other.delete(f"/api/recurring/{a}/match-text").status_code == 404   # read-only sharing
    assert c.delete("/api/recurring/999999/match-text").status_code == 404
    assert c.delete(f"/api/recurring/{a}/match-text").status_code == 200
    assert taught(c, acc, a) is None
    bank_line(fake, "T-9", LATER_LINE_DAY, -41.00, "CORNER GROCERY")
    assert sync(c)["matched"] == 0                          # a tie again
    assert "CORNER GROCERY" in names(c, acc)


def test_a_bill_edit_keeps_or_sets_what_it_learned(connected, fake):
    c, u, acc, status = connected
    a, b = gyms(c, acc)
    edit = {"description": "Gym A", "amount": -40.00, "frequency": "weekly",
            "anchor_date": (G - timedelta(days=8)).isoformat()}
    assert c.patch(f"/api/recurring/{a}", json={**edit, "match_text": "  Corner Grocery "}).status_code == 200
    assert taught(c, acc, a) == "Corner Grocery"
    assert c.patch(f"/api/recurring/{a}", json=edit).status_code == 200        # left out: kept
    assert taught(c, acc, a) == "Corner Grocery"
    assert c.patch(f"/api/recurring/{a}", json={**edit, "match_text": None}).status_code == 200
    assert taught(c, acc, a) is None
    r = c.patch(f"/api/recurring/{a}", json={**edit, "match_text": "x" * 121})
    assert r.status_code == 422


def test_remember_on_a_one_off_teaches_nothing(connected, fake):
    c, u, acc, status = connected
    r = c.post(f"/api/accounts/{acc}/transactions", json={
        "description": "Big shop", "amount": -45.00, "is_actual": False,
        "forecast_date": (G + timedelta(days=3)).isoformat()})
    assert r.status_code == 200, r.text
    link(c, status, acc)
    sync(c)
    out = match(c, acc, grocery(c, acc)["id"], transaction_id=r.json()["id"], remember=True)
    assert out["learned"] is None and out["also_matched"] == 0


def test_the_v31_migration_adds_the_column(connected):
    """A schema-30 database (no match_text_enc) gets the column on start-up,
    and its bills read as taught nothing."""
    from sqlalchemy import text
    from app.db import SessionLocal, init_db
    c, u, acc, status = connected
    a, b = gyms(c, acc)
    db = SessionLocal()
    try:
        db.execute(text("ALTER TABLE recurring_transactions DROP COLUMN match_text_enc"))
        db.commit()
        init_db()
        assert db.execute(text("SELECT count(*) FROM information_schema.columns "
                               "WHERE table_name = 'recurring_transactions' "
                               "AND column_name = 'match_text_enc'")).scalar() == 1
    finally:
        db.close()
    assert taught(c, acc, a) is None


def test_names_are_compared_without_codes():
    """#230: digits and codes after * or # don't count."""
    from app.main import _match_key
    assert _match_key("AMAZON MKTPL*2K4AB1") == _match_key("Amazon Mktpl*9XZ3") == "amazon mktpl"
    assert _match_key("SQ *COFFEE SHOP 0423") == "sq coffee shop"
    assert _match_key("SHELL OIL #5741 ") == "shell oil"
    assert _match_key("AMAZON PRIME") != _match_key("AMAZON MKTPL*2K4AB1")
    assert _match_key("  123 456 ") == "123 456"            # nothing left: compared as itself
    assert _match_key(None) == ""


def test_a_taught_card_name_takes_a_new_code(connected, fake):
    c, u, acc, status = connected
    a, b = gyms(c, acc)
    fake.accounts[0]["transactions"][0]["description"] = "AMAZON MKTPL*2K4AB1"   # the grocery line
    link(c, status, acc)
    sync(c)
    line = next(x for x in unmatched(c, acc)["lines"] if x["description"].startswith("AMAZON"))
    out = match(c, acc, line["id"], recurring_id=a, forecast_date=(G - timedelta(days=1)).isoformat(),
                remember=True)
    assert out["learned"] == "AMAZON MKTPL*2K4AB1"
    bank_line(fake, "T-15", LATER_LINE_DAY, -41.00, "AMAZON PRIME")          # another name: still a tie
    bank_line(fake, "T-9", LATER_LINE_DAY, -41.00, "AMAZON MKTPL*9XZ3")      # a new code: Gym A's
    assert sync(c)["matched"] == 1
    paid = row(c, acc, a, G - timedelta(days=8))
    assert paid["bank_match"] == "auto" and paid["actual_amount"] == -41.0
    assert "AMAZON PRIME" in names(c, acc)
