"""Two bugs found during the security review: a line whose own tag a tag
rule also adds (#182), and notes lost when a backup is imported (#191)."""
from datetime import date

from fastapi.testclient import TestClient

from conftest import unique_email

PASSWORD = "correct-horse-battery"
TODAY = date.today().isoformat()


def register(app):
    c = TestClient(app)
    r = c.post("/api/auth/register", json={"email": unique_email(), "password": PASSWORD})
    assert r.status_code == 200, r.text
    return c


def make_account(c, name="Checking"):
    r = c.post("/api/accounts", json={"name": name, "starting_balance": 0, "starting_date": TODAY})
    assert r.status_code == 200, r.text
    return r.json()["id"]


def tags_of(c, acc, description):
    return [[t["name"] for t in line["tags"]]
            for line in c.get(f"/api/accounts/{acc}/transactions").json()
            if line["description"] == description]


def test_a_line_with_a_tag_its_own_rule_also_adds_saves_with_the_tag_once(app_started):
    c = register(app_started)
    acc = make_account(c)
    tag = c.post("/api/tags", json={"name": "caffeine"}).json()["id"]
    other = c.post("/api/tags", json={"name": "treat"}).json()["id"]
    assert c.post("/api/tag-rules", json={"description_pattern": "coffee", "tag_id": tag}).status_code == 200
    line = {"description": "Morning coffee", "amount": -4, "actual_date": TODAY, "is_actual": True}
    r = c.post(f"/api/accounts/{acc}/transactions", json={**line, "tag_ids": [tag]})
    assert r.status_code == 200, r.text
    assert tags_of(c, acc, "Morning coffee") == [["caffeine"]]
    # Editing it with the tag kept, and with another tag beside it.
    tid = r.json()["id"]
    assert c.patch(f"/api/transactions/{tid}", json={**line, "tag_ids": [tag]}).status_code == 200
    assert c.patch(f"/api/transactions/{tid}", json={**line, "tag_ids": [other, tag]}).status_code == 200
    assert tags_of(c, acc, "Morning coffee") == [["caffeine", "treat"]]
    # A rule still adds its tag where the line didn't have it.
    assert c.post(f"/api/accounts/{acc}/transactions",
                  json={**line, "description": "Iced coffee"}).status_code == 200
    assert tags_of(c, acc, "Iced coffee") == [["caffeine"]]


def test_a_csv_row_with_a_tag_its_own_rule_also_adds_imports(app_started):
    c = register(app_started)
    acc = make_account(c)
    tag = c.post("/api/tags", json={"name": "caffeine"}).json()["id"]
    c.post("/api/tag-rules", json={"description_pattern": "coffee", "tag_id": tag})
    r = c.post(f"/api/accounts/{acc}/import/commit", json={
        "csv_text": "Date,Description,Amount,Tags\n2026-01-05,Coffee beans,-12.00,caffeine\n",
        "mapping": {"date": 0, "description": 1, "amount": 2, "tags": 3}})
    assert r.status_code == 200 and r.json()["inserted"] == 1, r.text
    assert tags_of(c, acc, "Coffee beans") == [["caffeine"]]


def test_notes_come_back_when_a_backup_is_imported(app_started):
    c = register(app_started)
    acc = make_account(c, "Everyday")
    r = c.post(f"/api/accounts/{acc}/recurring", json={
        "description": "Rent", "amount": -900, "frequency": "monthly_day", "day_of_month": 1,
        "notes": "Goes up in March"})
    assert r.status_code == 200, r.text
    r = c.post(f"/api/accounts/{acc}/transactions", json={
        "description": "Plumber", "amount": -120, "actual_date": TODAY, "is_actual": True,
        "notes": "Invoice 4411"})
    assert r.status_code == 200, r.text
    c.post(f"/api/accounts/{acc}/transactions", json={
        "description": "No note", "amount": -1, "actual_date": TODAY, "is_actual": True})
    backup = c.get("/api/backup/export").json()

    other = register(app_started)
    r = other.post("/api/backup/import", json={"mode": "merge", "payload": backup})
    assert r.status_code == 200, r.text
    new = other.get("/api/accounts").json()[0]["id"]
    notes = {t["description"]: t["notes"]
             for t in other.get(f"/api/accounts/{new}/transactions").json()}
    assert notes == {"Plumber": "Invoice 4411", "No note": None}
    bills = other.get(f"/api/accounts/{new}/recurring").json()
    assert [(b["description"], b["notes"]) for b in bills] == [("Rent", "Goes up in March")]
