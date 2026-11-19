"""Backups carry tags (#117).

The JSON backup (GET /api/backup/export, POST /api/backup/import) now holds the
user's tags and tag rules, and the tag names on every recurring item and
transaction. Restores match tags by name, so they land on the importing user's
own tags. Backups made before this (no tag keys) still import.
"""
from datetime import date, timedelta

import pytest
from fastapi.testclient import TestClient

from conftest import unique_email

PASSWORD = "correct-horse-battery"


def register(app):
    c = TestClient(app)
    r = c.post("/api/auth/register",
               json={"email": unique_email(), "password": PASSWORD})
    assert r.status_code == 200, r.text
    return c, r.json()["id"]


def make_account(c, name="Checking"):
    r = c.post("/api/accounts", json={
        "name": name, "starting_balance": 100.0,
        "starting_date": date.today().isoformat()})
    assert r.status_code == 200, r.text
    return r.json()["id"]


def make_tag(c, name, color=None):
    r = c.post("/api/tags", json={"name": name, "color": color})
    assert r.status_code == 200, r.text
    return r.json()["id"]


@pytest.fixture
def source(app_started):
    """A user with an account holding a tagged recurring item and a tagged
    transaction, two tags (one coloured), a category and a tag rule."""
    c, _ = register(app_started)
    acc = make_account(c)
    health = make_tag(c, "Health", "#44aa88")
    fixed = make_tag(c, "Fixed")
    cat = c.post("/api/categories", json={"name": "Gym stuff", "color": "#cc8844"}).json()["id"]
    rec = c.post(f"/api/accounts/{acc}/recurring", json={
        "description": "Gym", "amount": -40.0, "frequency": "weekly",
        "anchor_date": (date.today() + timedelta(days=1)).isoformat(),
        "tag_ids": [health, fixed]})
    assert rec.status_code == 200, rec.text
    txn = c.post(f"/api/accounts/{acc}/transactions", json={
        "description": "Lunch", "amount": -12.0,
        "forecast_date": date.today().isoformat(), "tag_ids": [health]})
    assert txn.status_code == 200, txn.text
    rule = c.post("/api/tag-rules", json={
        "name": "Gym spend", "description_pattern": "GYM", "tag_id": health, "category_id": cat})
    assert rule.status_code == 200, rule.text
    return c


def export(c):
    r = c.get("/api/backup/export")
    assert r.status_code == 200, r.text
    return r.json()


def names(tags):
    return sorted(t["name"] for t in tags)


def only_account(c):
    accs = c.get("/api/accounts").json()
    assert len(accs) == 1, accs
    return accs[0]["id"]


def test_export_carries_tags_rules_and_links(source):
    data = export(source)
    assert data["version"] >= 4   # tags came in 4; 5 added transfers (#236)
    assert {(t["name"], t["color"]) for t in data["tags"]} == {("Health", "#44aa88"), ("Fixed", None)}
    assert data["tag_rules"] == [{
        "name": "Gym spend", "description_pattern": "gym", "category_name": "Gym stuff",
        "tag_name": "Health", "active": True}]
    acc = data["accounts"][0]
    assert acc["recurring"][0]["tags"] == ["Fixed", "Health"]
    assert acc["transactions"][0]["tags"] == ["Health"]


def test_import_into_another_user_restores_everything(app_started, source):
    data = export(source)
    other, _ = register(app_started)
    r = other.post("/api/backup/import", json={"payload": data})
    assert r.status_code == 200, r.text
    got = r.json()["imported"]
    assert got["tags"] == 2 and got["tag_rules"] == 1
    assert got["recurring"] == 1 and got["transactions"] == 1

    tags = {t["name"]: t for t in other.get("/api/tags").json()}
    assert set(tags) == {"Health", "Fixed"} and tags["Health"]["color"] == "#44aa88"

    acc = only_account(other)
    rec = other.get(f"/api/accounts/{acc}/recurring").json()[0]
    assert names(rec["tags"]) == ["Fixed", "Health"]
    txn = other.get(f"/api/accounts/{acc}/transactions").json()[0]
    assert names(txn["tags"]) == ["Health"]
    # The ids are the importing user's own tags, not the source user's.
    assert {t["id"] for t in rec["tags"]} <= {t["id"] for t in tags.values()}

    rules = other.get("/api/tag-rules").json()
    assert len(rules) == 1
    assert (rules[0]["description_pattern"], rules[0]["tag_name"], rules[0]["category_name"]) == \
        ("gym", "Health", "Gym stuff")


def test_importing_twice_reuses_tags_and_does_not_repeat_rules(app_started, source):
    data = export(source)
    other, _ = register(app_started)
    other.post("/api/backup/import", json={"payload": data})
    r = other.post("/api/backup/import", json={"payload": data})
    assert r.status_code == 200, r.text
    got = r.json()["imported"]
    assert got["tags"] == 0 and got["tag_rules"] == 0
    assert len(other.get("/api/tags").json()) == 2
    assert len(other.get("/api/tag-rules").json()) == 1


def test_replace_mode_swaps_tags_without_duplicating(source):
    data = export(source)
    r = source.post("/api/backup/import", json={"payload": data, "mode": "replace"})
    assert r.status_code == 200, r.text
    assert len(source.get("/api/tags").json()) == 2
    assert len(source.get("/api/tag-rules").json()) == 1
    acc = only_account(source)
    rec = source.get(f"/api/accounts/{acc}/recurring").json()[0]
    assert names(rec["tags"]) == ["Fixed", "Health"]
    assert names(source.get(f"/api/accounts/{acc}/transactions").json()[0]["tags"]) == ["Health"]


def test_a_tag_used_but_not_listed_is_created(app_started):
    c, _ = register(app_started)
    payload = {"version": 4, "accounts": [{
        "name": "Imported", "starting_balance": 0, "starting_date": date.today().isoformat(),
        "recurring": [], "transactions": [{
            "description": "Coffee", "amount": -3.0, "forecast_date": date.today().isoformat(),
            "tags": ["Treat", "Treat", " "]}]}],
        "tag_rules": [{"description_pattern": "cafe", "tag_name": "Treat"},
                      {"description_pattern": "x", "tag_name": ""}]}
    r = c.post("/api/backup/import", json={"payload": payload})
    assert r.status_code == 200, r.text
    assert r.json()["imported"]["tags"] == 1 and r.json()["imported"]["tag_rules"] == 1
    acc = only_account(c)
    assert names(c.get(f"/api/accounts/{acc}/transactions").json()[0]["tags"]) == ["Treat"]


def test_a_backup_from_before_tags_still_imports(app_started):
    c, _ = register(app_started)
    payload = {"version": 3, "categories": [], "accounts": [{
        "name": "Old", "starting_balance": 10, "starting_date": date.today().isoformat(),
        "recurring": [{"description": "Rent", "amount": -500, "frequency": "monthly_day",
                       "day_of_month": 1, "anchor_date": None, "end_date": None, "active": True}],
        "transactions": [{"description": "Pay", "amount": 100,
                          "forecast_date": date.today().isoformat(), "is_actual": False}]}]}
    r = c.post("/api/backup/import", json={"payload": payload})
    assert r.status_code == 200, r.text
    got = r.json()["imported"]
    assert got["accounts"] == 1 and got["recurring"] == 1 and got["transactions"] == 1
    assert got["tags"] == 0 and got["tag_rules"] == 0
    assert c.get("/api/tags").json() == []


def test_unusable_backups_are_refused(app_started):
    c, _ = register(app_started)
    assert c.post("/api/backup/import", json={"payload": {"version": 99, "accounts": []}}).status_code == 400
    assert c.post("/api/backup/import", json={"payload": {"version": 4}}).status_code == 400
    assert c.post("/api/backup/import", json={"payload": {"version": 4, "accounts": []},
                                              "mode": "bogus"}).status_code == 400
    assert c.get("/api/tags").json() == []


def test_the_system_backup_builds_on_the_same_export(source):
    """The admin / scheduled system backup calls export_user for each user, so
    it carries tags too, and restoring it uses import_user in replace mode.
    (Checked on one user: the system export walks every user in the database.)"""
    from app.backup import export_user, import_user
    from app.db import Account, SessionLocal, User
    me = source.get("/api/me").json()["email"]
    with SessionLocal() as db:
        user = db.query(User).filter_by(email=me).one()
        accounts = db.query(Account).filter_by(owner_id=user.id).all()
        data = export_user(db, user, accounts=accounts)
        assert names(data["tags"]) == ["Fixed", "Health"]
        assert data["accounts"][0]["recurring"][0]["tags"] == ["Fixed", "Health"]
        counts = import_user(db, user, data, mode="replace")   # what a system restore does
        assert counts["tags"] == 2 and counts["tag_rules"] == 1
