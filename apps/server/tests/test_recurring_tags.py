"""Tags on recurring items (recurring-tags plan, #118).

A recurring item carries tags (`tag_ids` on create and PATCH, `tags` in both
recurring lists and on its projected forecast rows). A line created from it
starts with those tags unless the request names its own; changing the item's
tags later leaves lines already saved alone.
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


def make_tag(c, name):
    r = c.post("/api/tags", json={"name": name})
    assert r.status_code == 200, r.text
    return r.json()["id"]


def weekly(c, account_id, tag_ids=None, **extra):
    body = {"description": "Gym", "amount": -40.0, "frequency": "weekly",
            "anchor_date": (date.today() + timedelta(days=1)).isoformat()}
    if tag_ids is not None:
        body["tag_ids"] = tag_ids
    body.update(extra)
    return c.post(f"/api/accounts/{account_id}/recurring", json=body)


def item(c, account_id, rec_id):
    rows = c.get(f"/api/accounts/{account_id}/recurring").json()
    return next(r for r in rows if r["id"] == rec_id)


def tag_ids(tags):
    return sorted(t["id"] for t in tags)


@pytest.fixture
def setup(app_started):
    c, user_id = register(app_started)
    acc = make_account(c)
    tags = {"health": make_tag(c, "Health"), "fixed": make_tag(c, "Fixed")}
    return c, acc, tags


def test_create_with_tags_shows_them_in_both_lists(setup):
    c, acc, tags = setup
    r = weekly(c, acc, [tags["health"], tags["fixed"]])
    assert r.status_code == 200, r.text
    rec_id = r.json()["id"]

    row = item(c, acc, rec_id)
    assert tag_ids(row["tags"]) == sorted(tags.values())
    assert {t["name"] for t in row["tags"]} == {"Health", "Fixed"}
    assert all({"id", "name", "color"} <= set(t) for t in row["tags"])
    # Sorted by name, like transaction tags.
    assert [t["name"] for t in row["tags"]] == ["Fixed", "Health"]

    everything = c.get("/api/recurring").json()["items"]
    assert tag_ids(next(i for i in everything if i["id"] == rec_id)["tags"]) == sorted(tags.values())


def test_item_without_tags_has_an_empty_list(setup):
    c, acc, _ = setup
    rec_id = weekly(c, acc).json()["id"]
    assert item(c, acc, rec_id)["tags"] == []


def test_patch_replaces_clears_and_leaves_tags(setup):
    c, acc, tags = setup
    rec_id = weekly(c, acc, [tags["health"]]).json()["id"]
    base = {"description": "Gym", "amount": -40.0, "frequency": "weekly",
            "anchor_date": (date.today() + timedelta(days=1)).isoformat()}

    r = c.patch(f"/api/recurring/{rec_id}", json={**base, "tag_ids": [tags["fixed"]]})
    assert r.status_code == 200, r.text
    assert tag_ids(item(c, acc, rec_id)["tags"]) == [tags["fixed"]]

    # No tag_ids: tags stay as they are.
    r = c.patch(f"/api/recurring/{rec_id}", json={**base, "description": "Gym+"})
    assert r.status_code == 200, r.text
    assert tag_ids(item(c, acc, rec_id)["tags"]) == [tags["fixed"]]

    # An empty list clears them.
    r = c.patch(f"/api/recurring/{rec_id}", json={**base, "tag_ids": []})
    assert r.status_code == 200, r.text
    assert item(c, acc, rec_id)["tags"] == []


def test_someone_elses_tag_is_refused(app_started, setup):
    c, acc, tags = setup
    other, _ = register(app_started)
    theirs = make_tag(other, "Not yours")
    r = weekly(c, acc, [theirs])
    assert r.status_code == 404, r.text

    rec_id = weekly(c, acc, [tags["health"]]).json()["id"]
    r = c.patch(f"/api/recurring/{rec_id}", json={
        "description": "Gym", "amount": -40.0, "frequency": "weekly",
        "anchor_date": date.today().isoformat(), "tag_ids": [theirs]})
    assert r.status_code == 404, r.text
    assert tag_ids(item(c, acc, rec_id)["tags"]) == [tags["health"]]


def test_projected_rows_carry_the_items_tags(setup):
    c, acc, tags = setup
    rec_id = weekly(c, acc, [tags["health"]]).json()["id"]
    data = c.get(f"/api/accounts/{acc}/forecast", params={"days": 30}).json()
    projected = [r for r in data["rows"] if r["recurring_id"] == rec_id]
    assert projected, data
    assert all(r["transaction_id"] is None for r in projected)
    assert all(tag_ids(r["tags"]) == [tags["health"]] for r in projected)


def test_line_saved_from_an_item_starts_with_its_tags(setup):
    c, acc, tags = setup
    rec_id = weekly(c, acc, [tags["health"], tags["fixed"]]).json()["id"]
    when = (date.today() + timedelta(days=1)).isoformat()
    r = c.post(f"/api/accounts/{acc}/transactions", json={
        "description": "Gym", "amount": -40.0, "forecast_date": when,
        "recurring_id": rec_id})
    assert r.status_code == 200, r.text
    txn_id = r.json()["id"]
    txns = c.get(f"/api/accounts/{acc}/transactions").json()
    saved = next(t for t in txns if t["id"] == txn_id)
    assert tag_ids(saved["tags"]) == sorted(tags.values())


def test_explicit_tag_ids_win_over_the_items(setup):
    c, acc, tags = setup
    rec_id = weekly(c, acc, [tags["health"]]).json()["id"]
    r = c.post(f"/api/accounts/{acc}/transactions", json={
        "description": "Gym", "amount": -40.0,
        "forecast_date": date.today().isoformat(),
        "recurring_id": rec_id, "tag_ids": [tags["fixed"]]})
    assert r.status_code == 200, r.text
    saved = next(t for t in c.get(f"/api/accounts/{acc}/transactions").json()
                 if t["id"] == r.json()["id"])
    assert tag_ids(saved["tags"]) == [tags["fixed"]]


def test_actual_against_a_projection_starts_with_its_tags(setup):
    c, acc, tags = setup
    rec_id = weekly(c, acc, [tags["health"]]).json()["id"]
    when = (date.today() + timedelta(days=1)).isoformat()
    r = c.post(f"/api/accounts/{acc}/forecast/actual", json={
        "recurring_id": rec_id, "forecast_date": when, "actual_amount": -42.0})
    assert r.status_code == 200, r.text
    saved = next(t for t in c.get(f"/api/accounts/{acc}/transactions").json()
                 if t["id"] == r.json()["transaction_id"])
    assert tag_ids(saved["tags"]) == [tags["health"]]


def test_changing_the_items_tags_leaves_saved_lines_alone(setup):
    c, acc, tags = setup
    rec_id = weekly(c, acc, [tags["health"]]).json()["id"]
    r = c.post(f"/api/accounts/{acc}/transactions", json={
        "description": "Gym", "amount": -40.0,
        "forecast_date": date.today().isoformat(), "recurring_id": rec_id})
    txn_id = r.json()["id"]
    c.patch(f"/api/recurring/{rec_id}", json={
        "description": "Gym", "amount": -40.0, "frequency": "weekly",
        "anchor_date": date.today().isoformat(), "tag_ids": [tags["fixed"]]})
    saved = next(t for t in c.get(f"/api/accounts/{acc}/transactions").json()
                 if t["id"] == txn_id)
    assert tag_ids(saved["tags"]) == [tags["health"]]


def test_deleted_tag_disappears_from_items(setup):
    c, acc, tags = setup
    rec_id = weekly(c, acc, [tags["health"], tags["fixed"]]).json()["id"]
    r = c.delete(f"/api/tags/{tags['health']}")
    assert r.status_code == 200, r.text
    assert tag_ids(item(c, acc, rec_id)["tags"]) == [tags["fixed"]]
