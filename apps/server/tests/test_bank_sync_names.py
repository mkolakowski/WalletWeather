"""Shorter names for bank-synced lines (#213).

Some banks put the whole ACH record in a line's description. A synced line
is named after the part before " / ", without "Withdrawal" or "Deposit",
and keeps the bank's full text in its notes; lines synced before this get
the same treatment at start-up. Uses the stand-in SimpleFIN from
test_bank_sync.py.
"""
from datetime import timedelta

import pytest

from test_bank_sync import (TODAY, connected, epoch, fake, lines, link,  # noqa: F401 (fixtures)
                            switched_on)

ACH = ("Withdrawal Example Internet / TYPE: ExampleNet ID: 1234567890 CO: Example Internet "
       "NAME: Pat Example Entry Class Code: WEB ACH Trace Number: 000000000000001")
PAY = ("Deposit Example Payroll / TYPE: Bill.com ID: 2234567890 CO: Example Payroll "
       "Entry Class Code: PPD ACH Trace Number: 000000000000002")


@pytest.mark.parametrize("text, short", [
    (ACH, "Example Internet"),
    (PAY, "Example Payroll"),
    ("ACH Withdrawal Gym Co / ref 1", "Gym Co"),
    ("CORNER GROCERY", None),          # nothing to shorten
    ("Withdrawal / TYPE: X", None),    # nothing left of the name: keep the bank's text
    ("Example Internet", None),        # already short: shortening twice changes nothing
    ("", None),
    (None, None),
])
def test_short_name(text, short):
    from app import simplefin
    assert simplefin.short_name(text) == short


def add_bank_lines(fake, *texts):
    for i, text in enumerate(texts):
        fake.accounts[0]["transactions"].append(
            {"id": f"ACH-{i}", "posted": epoch(TODAY - timedelta(days=1)),
             "amount": "-108.87" if text.startswith("Withdrawal") else "48.18", "description": text})


def test_a_synced_line_gets_the_short_name_and_keeps_the_bank_text(connected, fake):
    c, u, acc, status = connected
    add_bank_lines(fake, ACH, PAY)
    link(c, status, acc)
    r = c.post("/api/bank/sync")
    assert r.status_code == 200, r.text
    assert r.json()["added"] == 4
    got = {t["description"]: t for t in lines(c, acc)}
    assert got["Example Internet"]["notes"] == ACH
    assert got["Example Payroll"]["notes"] == PAY
    # A plain bank name stays as it is, with no notes added.
    assert got["CORNER GROCERY"]["notes"] is None
    again = c.post("/api/bank/sync").json()
    assert (again["added"], again["skipped"]) == (0, 4)


def test_tag_rules_still_see_the_bank_text(connected, fake):
    c, u, acc, status = connected
    tag = c.post("/api/tags", json={"name": "Internet"}).json()["id"]
    assert c.post("/api/tag-rules", json={"description_pattern": "examplenet", "tag_id": tag}).status_code == 200
    add_bank_lines(fake, ACH)
    link(c, status, acc)
    c.post("/api/bank/sync")
    line = next(t for t in lines(c, acc) if t["description"] == "Example Internet")
    assert tag in [x["id"] for x in line["tags"]]


def test_a_csv_row_under_the_short_name_is_not_doubled(connected, fake):
    c, u, acc, status = connected
    day = (TODAY - timedelta(days=1)).isoformat()
    r = c.post(f"/api/accounts/{acc}/import/commit", json={
        "csv_text": f"Date,Description,Amount\n{day},Example Internet,-108.87\n",
        "mapping": {"date": 0, "description": 1, "amount": 2}})
    assert r.status_code == 200, r.text
    add_bank_lines(fake, ACH)
    link(c, status, acc)
    r = c.post("/api/bank/sync").json()
    assert (r["added"], r["skipped"]) == (2, 1)
    assert [t["description"] for t in lines(c, acc)].count("Example Internet") == 1


def test_lines_synced_before_get_the_short_name(connected, fake):
    from app.db import SessionLocal, Transaction
    from app.main import shorten_synced_names

    c, u, acc, status = connected
    add_bank_lines(fake, ACH, PAY)
    link(c, status, acc)
    c.post("/api/bank/sync")
    hand = c.post(f"/api/accounts/{acc}/transactions", json={
        "description": "Withdrawal Cash / by hand", "amount": -20, "is_actual": True,
        "actual_date": TODAY.isoformat(), "forecast_date": TODAY.isoformat()})
    assert hand.status_code == 200, hand.text
    # Put the synced lines back as they were before #213: the bank's full
    # text as the name. One has a note of its own; one was renamed.
    db = SessionLocal()
    try:
        rows = {t.notes: t for t in db.query(Transaction).filter(
            Transaction.account_id == acc, Transaction.bank_ref.isnot(None))}
        internet, payroll = rows[ACH], rows[PAY]
        internet.description, internet.notes = ACH, "my note"
        payroll.description, payroll.notes = "Paycheck (renamed)", None
        db.commit()
        assert shorten_synced_names(db) >= 1
        assert shorten_synced_names(db) == 0   # safe on every start
    finally:
        db.close()
    got = {t["description"]: t for t in lines(c, acc)}
    assert got["Example Internet"]["notes"] == "my note\n\n" + ACH
    assert got["Paycheck (renamed)"]["notes"] is None
    assert "Withdrawal Cash / by hand" in got   # added by hand: not touched
    again = c.post("/api/bank/sync").json()
    assert again["added"] == 0
