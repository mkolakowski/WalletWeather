"""Providers' categories onto the user's (bank-providers phase 2, #255).

Teller's details.category and Plaid's personal_finance_category.primary are
kept for each synced line and mapped, as the line lands, onto one of the
user's categories through a table in Settings → Bank sync: one row per
provider category seen, pre-filled where a category of the user's has the
same name, blank landing the line uncategorized. A line that pays a planned
bill keeps the bill's category, changing the table never touches lines
already in, and tag rules run after the category is set. Uses the stand-in
Teller and Plaid from test_bank_providers.py.
"""
from datetime import timedelta

import pytest

from test_bank_providers import (FakeTeller, TODAY, day, descriptions, linked, plaid_fake,  # noqa: F401 (fixtures)
                                 plaid_user, no_provider_keys, simplefin_fake, switched_on, teller_fake,
                                 teller_user)
from test_bank_sync import lines, register


def make_category(c, name):
    r = c.post("/api/categories", json={"name": name})
    assert r.status_code == 200, r.text
    return next(x["id"] for x in c.get("/api/categories").json() if x["name"] == name)


def fresh(c):
    """A user's own categories only: new users start with a default set
    (Groceries, Income, ...), which would pre-fill rows of their own."""
    for x in c.get("/api/categories").json():
        assert c.delete(f"/api/categories/{x['id']}").status_code in (200, 204)


def table(c):
    r = c.get("/api/bank/categories")
    assert r.status_code == 200, r.text
    return r.json()


def row_for(c, key, provider=None):
    return next((r for r in table(c)["rows"] if r["key"] == key
                 and (provider is None or r["provider"] == provider)), None)


def line(c, acc, name):
    return next(t for t in lines(c, acc) if t["description"] == name)


def sync(c):
    r = c.post("/api/bank/sync")
    assert r.status_code == 200, r.text
    return r.json()


def stored_category(user_id, name):
    """What the provider called a line, as stored."""
    from app.db import Account, SessionLocal, Transaction
    db = SessionLocal()
    try:
        for t in db.query(Transaction).join(Account, Account.id == Transaction.account_id) \
                .filter(Account.owner_id == user_id):
            if t.description == name or t.bank_text == name or (t.notes or "") == name:
                return t.bank_category
    finally:
        db.close()


# ---------- A mapped line, a pre-filled one and an unmapped one ----------

def test_a_category_with_the_same_name_is_prefilled_and_the_line_lands_in_it(teller_user):
    c, u, conn = teller_user
    fresh(c)
    groceries = make_category(c, "Groceries")
    acc = linked(c, conn, "Teller Checking")
    sync(c)
    assert row_for(c, "groceries") == {
        "id": row_for(c, "groceries")["id"], "provider": "teller", "provider_name": "Teller",
        "key": "groceries", "name": "Groceries", "category_id": groceries}
    assert line(c, acc, "CORNER GROCERY")["category_id"] == groceries


def test_a_new_users_default_categories_already_match_the_common_names(teller_user):
    c, u, conn = teller_user       # not cleared: Groceries and Income are the defaults
    acc = linked(c, conn, "Teller Checking")
    sync(c)
    names = {x["id"]: x["name"] for x in c.get("/api/categories").json()}
    assert names[row_for(c, "groceries")["category_id"]] == "Groceries"
    assert names[row_for(c, "income")["category_id"]] == "Income"
    assert names[line(c, acc, "CORNER GROCERY")["category_id"]] == "Groceries"


def test_a_provider_category_with_no_match_is_listed_blank_and_lands_uncategorized(teller_user):
    c, u, conn = teller_user
    fresh(c)
    make_category(c, "Groceries")
    acc = linked(c, conn, "Teller Checking")
    sync(c)
    income = row_for(c, "income")
    assert income["name"] == "Income" and income["category_id"] is None
    assert line(c, acc, "PAYROLL ACME")["category_id"] is None


def test_the_table_lists_the_users_categories_to_pick_from(teller_user):
    c, u, conn = teller_user
    fresh(c)
    pay, food = make_category(c, "Pay"), make_category(c, "Food")
    assert table(c) == {"rows": [], "categories": [{"id": food, "name": "Food"}, {"id": pay, "name": "Pay"}]}


def test_names_match_ignoring_case_and_punctuation_with_and_for_an_ampersand(plaid_user):
    c, u, conn = plaid_user
    fresh(c)
    food = make_category(c, "Food & Drink")
    acc = linked(c, conn, "Plaid Checking")
    sync(c)
    row = row_for(c, "food_and_drink")
    assert row["name"] == "Food and drink" and row["category_id"] == food
    assert line(c, acc, "CORNER GROCERY")["category_id"] == food


def test_a_mapping_the_user_sets_applies_to_the_next_lines_only(plaid_user, plaid_fake):
    c, u, conn = plaid_user
    fresh(c)
    eating = make_category(c, "Eating out")
    acc = linked(c, conn, "Plaid Checking")
    sync(c)                                   # first read: CORNER GROCERY, PAYROLL ACME
    assert line(c, acc, "CORNER GROCERY")["category_id"] is None
    row = row_for(c, "food_and_drink")
    assert row["category_id"] is None
    r = c.put("/api/bank/categories", json={"maps": [{"id": row["id"], "category_id": eating}]})
    assert r.status_code == 200, r.text
    assert next(x for x in r.json()["rows"] if x["key"] == "food_and_drink")["category_id"] == eating
    sync(c)                                   # NEW SANDWICH arrives under the new mapping
    assert line(c, acc, "NEW SANDWICH")["category_id"] == eating
    assert line(c, acc, "CORNER GROCERY")["category_id"] is None    # lines already in are left alone


def test_clearing_a_prefilled_row_lands_the_next_lines_uncategorized(teller_user, teller_fake):
    c, u, conn = teller_user
    fresh(c)
    make_category(c, "Groceries")
    acc = linked(c, conn, "Teller Checking")
    sync(c)
    row = row_for(c, "groceries")
    assert row["category_id"] is not None
    assert c.put("/api/bank/categories", json={"maps": [{"id": row["id"], "category_id": None}]}).status_code == 200
    teller_fake.transactions.insert(0, {"id": "txn_9", "date": day(0), "amount": "-8.00", "status": "posted",
                                        "description": "FARM STAND", "details": {"category": "groceries"}})
    sync(c)
    assert line(c, acc, "FARM STAND")["category_id"] is None
    assert line(c, acc, "CORNER GROCERY")["category_id"] is not None   # already in, unchanged
    assert row_for(c, "groceries")["category_id"] is None              # not filled in again


def test_a_category_made_later_doesnt_change_a_row_already_there(teller_user, teller_fake):
    c, u, conn = teller_user
    fresh(c)
    acc = linked(c, conn, "Teller Checking")
    sync(c)
    make_category(c, "Groceries")
    teller_fake.transactions.insert(0, {"id": "txn_9", "date": day(0), "amount": "-8.00", "status": "posted",
                                        "description": "FARM STAND", "details": {"category": "groceries"}})
    sync(c)
    assert row_for(c, "groceries")["category_id"] is None
    assert line(c, acc, "FARM STAND")["category_id"] is None


def test_each_provider_has_its_own_rows_and_a_user_without_lines_has_none(mixed_user_with_plaid):
    c, u, ids = mixed_user_with_plaid
    sync(c)
    rows = table(c)["rows"]
    assert {(r["provider"], r["key"]) for r in rows} == {
        ("teller", "income"), ("teller", "groceries"),
        ("plaid", "income"), ("plaid", "food_and_drink")}
    # Sorted by provider name, then category.
    assert [r["provider_name"] for r in rows] == ["Plaid", "Plaid", "Teller", "Teller"]


@pytest.fixture
def mixed_user_with_plaid(app_started, teller_fake, plaid_fake, switched_on):
    from test_bank_providers import connect_plaid, connect_teller
    c, u = register(app_started)
    fresh(c)
    tl, pl = connect_teller(c), connect_plaid(c, plaid_fake)
    linked(c, tl, "Teller Checking", "Teller checking")
    linked(c, pl, "Plaid Checking", "Plaid checking")
    return c, u, {"tl": tl, "pl": pl}


def test_simplefin_lines_have_no_category_and_make_no_rows(app_started, simplefin_fake, switched_on):
    from test_bank_providers import connect_simplefin
    c, u = register(app_started)
    conn = connect_simplefin(c, simplefin_fake)
    acc = linked(c, conn, "Everyday Checking")
    assert sync(c)["added"] > 0
    assert table(c)["rows"] == []
    assert all(t["category_id"] is None for t in lines(c, acc))


# ---------- A bill-matched line, and tag rules ----------

def test_a_line_that_pays_a_bill_keeps_the_bills_category(teller_user):
    c, u, conn = teller_user
    fresh(c)
    make_category(c, "Income")            # would be the pre-filled match for "income"
    salary = make_category(c, "Salary")
    acc = linked(c, conn, "Teller Checking")
    r = c.post(f"/api/accounts/{acc}/recurring", json={
        "description": "Paycheck", "amount": 2500, "frequency": "monthly_day",
        "day_of_month": (TODAY - timedelta(days=1)).day, "category_id": salary})
    assert r.status_code == 200, r.text
    result = sync(c)
    assert result["matched"] == 1
    paid = next(t for t in lines(c, acc) if t["recurring_id"] == r.json()["id"])
    assert paid["category_id"] == salary
    assert "PAYROLL ACME" not in descriptions(c, acc)
    # The category was still seen, and still maps for lines that don't pay a bill.
    assert row_for(c, "income")["category_id"] is not None
    assert stored_category(u["id"], "PAYROLL ACME") == "income"


def test_a_tag_rule_limited_to_a_category_sees_the_mapped_category(teller_user):
    c, u, conn = teller_user
    fresh(c)
    groceries = make_category(c, "Groceries")
    tag = c.post("/api/tags", json={"name": "Food"}).json()["id"]
    r = c.post("/api/tag-rules", json={"description_pattern": "corner", "tag_id": tag,
                                       "category_id": groceries})
    assert r.status_code == 200, r.text
    other = c.post("/api/tag-rules", json={"description_pattern": "payroll", "tag_id": tag,
                                           "category_id": groceries})
    assert other.status_code == 200, other.text
    acc = linked(c, conn, "Teller Checking")
    sync(c)
    assert tag in [x["id"] for x in line(c, acc, "CORNER GROCERY")["tags"]]
    assert line(c, acc, "PAYROLL ACME")["tags"] == []      # a different category: the rule doesn't apply


# ---------- What's stored ----------

def test_the_providers_own_category_is_kept_on_the_line_lowercased(plaid_user):
    c, u, conn = plaid_user
    fresh(c)
    linked(c, conn, "Plaid Checking")
    sync(c)
    assert stored_category(u["id"], "CORNER GROCERY") == "food_and_drink"


def test_a_line_with_no_category_keeps_none_and_makes_no_row(teller_user, teller_fake):
    c, u, conn = teller_user
    fresh(c)
    teller_fake.transactions = [{"id": "txn_7", "date": day(1), "amount": "-3.00", "status": "posted",
                                 "description": "NO CATEGORY"}]
    acc = linked(c, conn, "Teller Checking")
    assert sync(c)["added"] == 1
    assert table(c)["rows"] == []
    assert line(c, acc, "NO CATEGORY")["category_id"] is None


def test_an_odd_category_is_cut_to_size_and_cleaned(teller_user, teller_fake):
    c, u, conn = teller_user
    fresh(c)
    teller_fake.transactions = [{"id": "txn_8", "date": day(1), "amount": "-3.00", "status": "posted",
                                 "description": "ODD", "details": {"category": "  <B>Big\x00Category  " + "x" * 200}}]
    linked(c, conn, "Teller Checking")
    assert sync(c)["added"] == 1
    key = table(c)["rows"][0]["key"]
    assert len(key) <= 60 and "\x00" not in key and key == key.lower()


# ---------- The endpoints ----------

def test_saving_a_row_that_isnt_the_users_is_not_found_and_changes_nothing(teller_user, app_started):
    c, u, conn = teller_user
    fresh(c)
    make_category(c, "Groceries")
    linked(c, conn, "Teller Checking")
    sync(c)
    mine = row_for(c, "groceries")["id"]
    other, _ = register(app_started)
    # Another user's request for my row, and my request mixing a good row with a bad one.
    assert other.put("/api/bank/categories", json={"maps": [{"id": mine, "category_id": None}]}).status_code == 404
    assert row_for(c, "groceries")["category_id"] is not None
    r = c.put("/api/bank/categories", json={"maps": [{"id": mine, "category_id": None}, {"id": mine + 9999}]})
    assert r.status_code == 404
    assert row_for(c, "groceries")["category_id"] is not None
    assert other.get("/api/bank/categories").json()["rows"] == []


def test_saving_another_users_category_is_refused_and_changes_nothing(teller_user, app_started):
    c, u, conn = teller_user
    fresh(c)
    linked(c, conn, "Teller Checking")
    sync(c)
    other, _ = register(app_started)
    theirs = make_category(other, "Theirs")
    row = row_for(c, "income")["id"]
    r = c.put("/api/bank/categories", json={"maps": [{"id": row, "category_id": theirs}]})
    assert r.status_code == 400
    assert row_for(c, "income")["category_id"] is None
    assert c.put("/api/bank/categories", json={"maps": [{"id": row, "category_id": 999999}]}).status_code == 400


def test_a_bad_body_is_refused(teller_user):
    c, u, conn = teller_user
    fresh(c)
    assert c.put("/api/bank/categories", json={}).status_code == 422
    assert c.put("/api/bank/categories", json={"maps": [{"category_id": 1}]}).status_code == 422


def test_deleting_a_category_blanks_the_rows_that_pointed_at_it(teller_user):
    c, u, conn = teller_user
    fresh(c)
    groceries = make_category(c, "Groceries")
    linked(c, conn, "Teller Checking")
    sync(c)
    assert c.delete(f"/api/categories/{groceries}").status_code in (200, 204)
    assert row_for(c, "groceries")["category_id"] is None


def test_deleting_the_user_deletes_their_table(teller_user):
    from test_bank_sync import PASSWORD
    from app.db import BankCategoryMap, SessionLocal
    c, u, conn = teller_user
    linked(c, conn, "Teller Checking")
    sync(c)
    db = SessionLocal()
    try:
        assert db.query(BankCategoryMap).filter_by(user_id=u["id"]).count() == 2
        assert c.request("DELETE", "/api/me", json={"password": PASSWORD}).status_code == 200
        db.expire_all()
        assert db.query(BankCategoryMap).filter_by(user_id=u["id"]).count() == 0
    finally:
        db.close()


def test_the_table_needs_a_signed_in_user(app_started):
    from fastapi.testclient import TestClient
    anon = TestClient(app_started)
    assert anon.get("/api/bank/categories").status_code == 401
    assert anon.put("/api/bank/categories", json={"maps": []}).status_code == 401
