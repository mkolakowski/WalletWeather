"""Transfers in backups (version 5, Plans/standalone.md phase 5, #236).

Before version 5 a transfer came back from a backup as two plain lines. Now
the backup lists each transfer by its two accounts' places in the file, and
its lines point at it, so a restore (or a move between a server and the
iPhone) keeps them linked. A transfer to an account left out of the backup,
or one a hand-edited file gets wrong, stays as plain lines; a version 4 file
still imports.
"""
from datetime import date

from test_encrypted_backups import PASSPHRASE, make_account, register


def _transfer(c, src, dst, amount=125.0, description="Rainy day fund"):
    r = c.post("/api/transfers", json={"from_account_id": src, "to_account_id": dst, "amount": amount,
                                       "transfer_date": date.today().isoformat(),
                                       "description": description, "notes": "monthly"})
    assert r.status_code == 200, r.text
    return r.json()


def _household(app):
    c, u = register(app)
    chk = make_account(c, "Checking", 1000.0)
    sav = make_account(c, "Savings", 50.0)
    _transfer(c, chk, sav)
    return c, chk, sav


def test_an_export_lists_transfers_and_their_lines_point_at_them(app_started):
    c, chk, sav = _household(app_started)
    data = c.get("/api/backup/export").json()
    assert data["version"] == 5
    assert data["transfers"] == [{
        "from_account": [a["name"] for a in data["accounts"]].index("Checking"),
        "to_account": [a["name"] for a in data["accounts"]].index("Savings"),
        "transfer_date": date.today().isoformat(), "amount": 125.0,
        "description": "Rainy day fund", "notes": "monthly",
    }]
    legs = [t for a in data["accounts"] for t in a["transactions"]]
    assert sorted(t["description"] for t in legs) == ["← Rainy day fund", "→ Rainy day fund"]
    assert all(t["transfer"] == 0 for t in legs)


def test_a_restore_keeps_the_transfer(app_started):
    c, _, _ = _household(app_started)
    sealed = c.post("/api/backup/export", json={"passphrase": PASSPHRASE}).json()
    other, _ = register(app_started)
    r = other.post("/api/backup/import", json={"payload": sealed, "passphrase": PASSPHRASE, "mode": "replace"})
    assert r.status_code == 200, r.text
    assert r.json()["imported"]["transfers"] == 1
    listed = other.get("/api/transfers").json()["transfers"]
    assert len(listed) == 1
    t = listed[0]
    assert (t["from_account_name"], t["to_account_name"], t["amount"]) == ("Checking", "Savings", 125.0)
    assert (t["description"], t["notes"]) == ("Rainy day fund", "monthly")
    assert len(t["transaction_ids"]) == 2
    # Each account's Forecast shows its line as a transfer again.
    for acc in other.get("/api/accounts").json():
        rows = other.get(f"/api/accounts/{acc['id']}/forecast").json()["rows"]
        assert [r["transfer_id"] for r in rows] == [t["id"]]


def test_a_transfer_to_an_account_left_out_stays_plain_lines(app_started):
    c, chk, _ = _household(app_started)
    sealed = c.post("/api/backup/export", json={"passphrase": PASSPHRASE, "account_ids": [chk]}).json()
    other, _ = register(app_started)
    r = other.post("/api/backup/import", json={"payload": sealed, "passphrase": PASSPHRASE})
    assert r.status_code == 200, r.text
    assert r.json()["imported"]["transfers"] == 0
    assert other.get("/api/transfers").json()["transfers"] == []
    acc = other.get("/api/accounts").json()[0]
    rows = other.get(f"/api/accounts/{acc['id']}/forecast").json()["rows"]
    assert [(r["description"], r["transfer_id"]) for r in rows] == [("→ Rainy day fund", None)]


def test_a_hand_edited_transfer_is_skipped_and_the_rest_imports(app_started):
    c, _, _ = _household(app_started)
    data = c.get("/api/backup/export").json()
    good = dict(data["transfers"][0])
    data["transfers"] = [
        {**good, "to_account": good["from_account"]},       # to itself
        {**good, "amount": -5},                               # not an amount it could be
        {**good, "from_account": 99},                         # no such account
        "not a transfer",
    ]
    other, _ = register(app_started)
    r = other.post("/api/backup/import", json={"payload": data})
    assert r.status_code == 200, r.text
    assert r.json()["imported"]["transfers"] == 0
    assert r.json()["imported"]["transactions"] == 2


def test_a_version_4_backup_still_imports(app_started):
    c, _, _ = _household(app_started)
    data = c.get("/api/backup/export").json()
    data["version"] = 4
    del data["transfers"]
    for a in data["accounts"]:
        for t in a["transactions"]:
            t.pop("transfer", None)
    other, _ = register(app_started)
    r = other.post("/api/backup/import", json={"payload": data})
    assert r.status_code == 200, r.text
    assert r.json()["imported"]["transfers"] == 0
    assert other.get("/api/transfers").json()["transfers"] == []
