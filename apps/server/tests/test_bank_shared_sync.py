"""The account holds its sync (sync-access phase 2, #265).

A linked account's sync belongs to the account, not to the person whose bank
connection feeds it: its owners and editors read the sync log, work the
Unmatched list, see the bank's balance and press Sync now for it, while
read-only people and strangers still get 404. The editor's sync runs the
holder's connection as the holder (their pause, limit and lock). Linking and
the connection's own controls stay with the connection's person. Uses the
stand-in SimpleFIN from test_bank_sync.py (CORNER GROCERY -42.50 two days
ago, PAYROLL ACME +2500 yesterday).
"""
from datetime import datetime, timedelta

import pytest

from conftest import share_account
from test_bank_access import admin, set_access  # noqa: F401 (fixture)
from test_bank_sync import (TODAY, allow_bank, connected, epoch, fake, lines, link, make_account,  # noqa: F401
                            ref_of, register, switched_on)
from test_bank_sync_matching import GROCERY_DAY, bill, forecast_rows, sync, unmatched  # noqa: F401

HOLDER_NAME = "Holly Holder"
FAR_DAY = GROCERY_DAY - timedelta(days=20)
MINE = 2557.50     # 100 + 2,500.00 - 42.50, once synced


class Crowd:
    """The connection's person (`c`, who owns `acc`), an editor, a read-only
    person and a stranger, with the account synced once."""

    def __init__(self, c, u, acc, status, editor, viewer, stranger, bill_id):
        self.c, self.u, self.acc, self.status = c, u, acc, status
        self.editor, self.viewer, self.stranger = editor, viewer, stranger
        self.bill_id = bill_id

    def no_access(self):
        return [("read-only", self.viewer), ("stranger", self.stranger)]

    def can(self):
        return [("owner", self.c), ("editor", self.editor)]


def name_the_holder(user_id, name=HOLDER_NAME):
    from app.db import SessionLocal, User
    db = SessionLocal()
    try:
        db.get(User, user_id).name = name
        db.commit()
    finally:
        db.close()


@pytest.fixture
def crowd(app_started, connected, fake):
    c, u, acc, status = connected
    name_the_holder(u["id"])
    # 41% off, so the sync leaves both bank lines on the Unmatched list.
    bill_id = bill(c, acc, "Groceries", -60.00, FAR_DAY)
    link(c, status, acc)
    sync(c)
    editor, _ = register(app_started)
    share_account(c, acc, "edit", invitee_client=editor)
    viewer, _ = register(app_started)
    share_account(c, acc, "read", invitee_client=viewer)
    stranger, _ = register(app_started)
    return Crowd(c, u, acc, status, editor, viewer, stranger, bill_id)


def grocery(c, acc):
    return next(x for x in unmatched(c, acc)["lines"] if x["description"] == "CORNER GROCERY")


def forecast(c, acc):
    r = c.get(f"/api/accounts/{acc}/forecast")
    assert r.status_code == 200, r.text
    return r.json()


def audit_details(event, user_id):
    from app.db import AuditEvent, SessionLocal
    db = SessionLocal()
    try:
        return [e.detail for e in db.query(AuditEvent).filter_by(event=event, user_id=user_id)
                .order_by(AuditEvent.id)]
    finally:
        db.close()


def shared_of(c, acc):
    return [x for x in c.get("/api/bank").json()["shared"] if x["account_id"] == acc]


# ---------- The sync log ----------

def test_owner_and_editor_read_the_same_sync_log(crowd):
    logs = {}
    for who, c in crowd.can():
        r = c.get(f"/api/accounts/{crowd.acc}/bank-syncs")
        assert r.status_code == 200, (who, r.text)
        log = r.json()
        assert len(log) == 1, who
        assert (log[0]["added"], log[0]["matched"], log[0]["skipped"]) == (2, 0, 0), who
        assert {"id", "run_at", "trigger", "added", "matched", "skipped", "error"} <= set(log[0]), who
        logs[who] = log
    assert logs["owner"] == logs["editor"]


def test_owner_and_editor_open_one_sync_run(crowd):
    run_id = crowd.c.get(f"/api/accounts/{crowd.acc}/bank-syncs").json()[0]["id"]
    seen = {}
    for who, c in crowd.can():
        r = c.get(f"/api/accounts/{crowd.acc}/bank-syncs/{run_id}")
        assert r.status_code == 200, (who, r.text)
        seen[who] = r.json()
        assert sorted(x["description"] for x in seen[who]["lines"]) == ["CORNER GROCERY", "PAYROLL ACME"], who
    assert seen["owner"] == seen["editor"]


def test_the_editor_sees_the_runs_the_holders_syncs_made(crowd):
    # A second run, pressed by the holder; the editor's log shows both.
    sync(crowd.c)
    log = crowd.editor.get(f"/api/accounts/{crowd.acc}/bank-syncs").json()
    assert len(log) == 2
    assert log == crowd.c.get(f"/api/accounts/{crowd.acc}/bank-syncs").json()


def test_read_only_and_strangers_cant_read_the_sync_log(crowd):
    run_id = crowd.c.get(f"/api/accounts/{crowd.acc}/bank-syncs").json()[0]["id"]
    for who, c in crowd.no_access():
        assert c.get(f"/api/accounts/{crowd.acc}/bank-syncs").status_code == 404, who
        assert c.get(f"/api/accounts/{crowd.acc}/bank-syncs/{run_id}").status_code == 404, who


# ---------- The Unmatched list ----------

def test_owner_and_editor_list_the_unmatched_lines(crowd):
    for who, c in crowd.can():
        r = c.get(f"/api/accounts/{crowd.acc}/bank-unmatched")
        assert r.status_code == 200, (who, r.text)
        got = r.json()
        assert got["count"] == 2, who
        assert [x["description"] for x in got["lines"]] == ["PAYROLL ACME", "CORNER GROCERY"], who
        assert set(got["lines"][0]) == {"id", "date", "description", "amount", "notes", "source"}, who


def test_owner_and_editor_get_the_candidates_for_a_line(crowd):
    line = grocery(crowd.c, crowd.acc)
    for who, c in crowd.can():
        r = c.get(f"/api/accounts/{crowd.acc}/bank-unmatched/{line['id']}/candidates")
        assert r.status_code == 200, (who, r.text)
        data = r.json()
        assert data["line"]["id"] == line["id"] and data["line"]["source"] == "bank", who
        assert any(x["recurring_id"] == crowd.bill_id for x in data["candidates"]), who
        assert any(x["recurring_id"] == crowd.bill_id for x in data["choices"]), who


def test_owner_and_editor_find_the_lines_near_a_planned_one(crowd):
    r = crowd.c.post(f"/api/accounts/{crowd.acc}/transactions", json={
        "description": "Big shop", "amount": -45.00, "is_actual": False,
        "forecast_date": GROCERY_DAY.isoformat()})
    assert r.status_code == 200, r.text
    planned = r.json()["id"]
    for who, c in crowd.can():
        r = c.get(f"/api/accounts/{crowd.acc}/bank-unmatched/near", params={"transaction_id": planned})
        assert r.status_code == 200, (who, r.text)
        found = r.json()
        assert "CORNER GROCERY" in str(found), who


def test_read_only_and_strangers_cant_use_the_unmatched_routes(crowd):
    line = grocery(crowd.c, crowd.acc)
    base = f"/api/accounts/{crowd.acc}/bank-unmatched"
    for who, c in crowd.no_access():
        assert c.get(base).status_code == 404, who
        assert c.get(f"{base}/{line['id']}/candidates").status_code == 404, who
        assert c.get(f"{base}/near", params={"transaction_id": line["id"]}).status_code == 404, who
        assert c.post(f"{base}/{line['id']}/match", json={
            "recurring_id": crowd.bill_id, "forecast_date": FAR_DAY.isoformat()}).status_code == 404, who
        assert c.post(f"{base}/{line['id']}/leave").status_code == 404, who
    assert unmatched(crowd.c, crowd.acc)["count"] == 2


def test_an_editor_matches_a_line_by_hand_and_the_owner_sees_it(crowd):
    line = grocery(crowd.c, crowd.acc)
    r = crowd.editor.post(f"/api/accounts/{crowd.acc}/bank-unmatched/{line['id']}/match", json={
        "recurring_id": crowd.bill_id, "forecast_date": FAR_DAY.isoformat()})
    assert r.status_code == 200, r.text
    assert "CORNER GROCERY" not in [t["description"] for t in lines(crowd.c, crowd.acc)]
    paid = next(x for x in forecast_rows(crowd.c, crowd.acc)
                if x["recurring_id"] == crowd.bill_id and x["forecast_date"] == FAR_DAY.isoformat())
    assert paid["bank_match"] == "hand" and paid["actual_amount"] == -42.5
    assert unmatched(crowd.c, crowd.acc)["count"] == 1
    assert unmatched(crowd.editor, crowd.acc)["count"] == 1


def test_an_editor_leaves_a_line_as_its_own(crowd):
    line = grocery(crowd.c, crowd.acc)
    r = crowd.editor.post(f"/api/accounts/{crowd.acc}/bank-unmatched/{line['id']}/leave")
    assert r.status_code == 200, r.text
    assert unmatched(crowd.c, crowd.acc)["count"] == 1
    assert "CORNER GROCERY" in [t["description"] for t in lines(crowd.c, crowd.acc)]
    # Once left, it isn't on the list to leave again.
    assert crowd.editor.post(f"/api/accounts/{crowd.acc}/bank-unmatched/{line['id']}/leave").status_code == 404


def test_the_owner_still_matches_and_leaves(crowd):
    line = grocery(crowd.c, crowd.acc)
    r = crowd.c.post(f"/api/accounts/{crowd.acc}/bank-unmatched/{line['id']}/match", json={
        "recurring_id": crowd.bill_id, "forecast_date": FAR_DAY.isoformat()})
    assert r.status_code == 200, r.text
    payroll = next(x for x in unmatched(crowd.c, crowd.acc)["lines"])
    assert crowd.c.post(f"/api/accounts/{crowd.acc}/bank-unmatched/{payroll['id']}/leave").status_code == 200
    assert unmatched(crowd.c, crowd.acc)["count"] == 0


def test_unmatch_errors_for_an_editor_are_the_usual_ones(crowd):
    line = grocery(crowd.c, crowd.acc)
    assert crowd.editor.post("/api/transactions/999999999/bank-unmatch").status_code == 404
    assert crowd.editor.post(f"/api/transactions/{line['id']}/bank-unmatch").status_code == 409


# ---------- Un-matching ----------

def matched_bill(crowd, fake_):
    """The account's grocery line paid against a bill by hand; its transaction id."""
    line = grocery(crowd.c, crowd.acc)
    r = crowd.c.post(f"/api/accounts/{crowd.acc}/bank-unmatched/{line['id']}/match", json={
        "recurring_id": crowd.bill_id, "forecast_date": FAR_DAY.isoformat()})
    assert r.status_code == 200, r.text
    return next(x for x in forecast_rows(crowd.c, crowd.acc)
                if x["recurring_id"] == crowd.bill_id
                and x["forecast_date"] == FAR_DAY.isoformat())["transaction_id"]


def test_an_editor_unmatches_a_line(crowd, fake):
    txn = matched_bill(crowd, fake)
    r = crowd.editor.post(f"/api/transactions/{txn}/bank-unmatch")
    assert r.status_code == 200, r.text
    assert "CORNER GROCERY" in [t["description"] for t in lines(crowd.c, crowd.acc)]
    # Back planned, and the bank line isn't offered for matching again.
    assert unmatched(crowd.c, crowd.acc)["count"] == 1


def test_a_line_an_editor_unmatches_gets_the_holders_tag_rules(crowd, fake):
    tag = crowd.c.post("/api/tags", json={"name": "Groceries"}).json()["id"]
    assert crowd.c.post("/api/tag-rules", json={"description_pattern": "grocery",
                                                "tag_id": tag}).status_code == 200
    txn = matched_bill(crowd, fake)
    assert crowd.editor.post(f"/api/transactions/{txn}/bank-unmatch").status_code == 200
    own = next(t for t in lines(crowd.c, crowd.acc) if t["description"] == "CORNER GROCERY")
    assert tag in [x["id"] for x in own["tags"]]


def test_read_only_and_strangers_cant_unmatch(crowd, fake):
    txn = matched_bill(crowd, fake)
    for who, c in crowd.no_access():
        assert c.post(f"/api/transactions/{txn}/bank-unmatch").status_code in (403, 404), who
    paid = next(x for x in forecast_rows(crowd.c, crowd.acc)
                if x["recurring_id"] == crowd.bill_id and x["forecast_date"] == FAR_DAY.isoformat())
    assert paid["transaction_id"] == txn and paid["bank_match"] == "hand"


# ---------- The forecast ----------

def test_the_forecasts_unmatched_count_by_level(crowd):
    assert forecast(crowd.c, crowd.acc)["bank_unmatched_count"] == 2
    assert forecast(crowd.editor, crowd.acc)["bank_unmatched_count"] == 2
    assert forecast(crowd.viewer, crowd.acc)["bank_unmatched_count"] == 0
    assert crowd.stranger.get(f"/api/accounts/{crowd.acc}/forecast").status_code == 404


def test_the_forecasts_bank_balance_by_level(crowd):
    shown = {}
    for who, c in crowd.can():
        b = forecast(c, crowd.acc)["bank_balance"]
        assert b is not None, who
        assert b["balance"] == 1200.00 and b["provider"] == "SimpleFIN", who
        assert b["gap"] == round(1200.00 - MINE, 2) == -1357.50, who
        assert b["can_adjust"] is True, who
        assert b["as_of"].endswith("Z"), who
        assert "unpaid_planned" in b, who
        shown[who] = b
    assert shown["owner"] == shown["editor"]
    assert forecast(crowd.viewer, crowd.acc)["bank_balance"] is None


# ---------- Adjusting to the bank's balance ----------

def test_an_editor_adjusts_to_the_banks_balance(crowd):
    r = crowd.editor.post(f"/api/accounts/{crowd.acc}/bank-adjust", json={"gap": -1357.50})
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["ok"] is True and body["amount"] == -1357.50
    assert body["current_balance"] == 1200.00 and "transaction_id" in body
    assert "Adjust to bank" in [t["description"] for t in lines(crowd.c, crowd.acc)]
    assert forecast(crowd.c, crowd.acc)["bank_balance"]["gap"] == 0
    # The gap is closed now.
    assert crowd.editor.post(f"/api/accounts/{crowd.acc}/bank-adjust",
                             json={"gap": -1357.50}).status_code == 400


def test_the_owner_adjusts_too(crowd):
    r = crowd.c.post(f"/api/accounts/{crowd.acc}/bank-adjust", json={"gap": -1357.50})
    assert r.status_code == 200, r.text
    assert r.json()["current_balance"] == 1200.00


def test_read_only_and_strangers_cant_adjust(crowd):
    for who, c in crowd.no_access():
        assert c.post(f"/api/accounts/{crowd.acc}/bank-adjust",
                      json={"gap": -1357.50}).status_code == 404, who
    assert "Adjust to bank" not in [t["description"] for t in lines(crowd.c, crowd.acc)]


def test_an_editor_with_a_stale_gap_is_told_so(crowd):
    assert crowd.editor.post(f"/api/accounts/{crowd.acc}/bank-adjust",
                             json={"gap": -5.00}).status_code == 409


# ---------- Sync now by account ----------

def test_an_editor_syncs_the_account_and_lines_land(crowd, fake):
    fake.accounts[0]["transactions"].append(
        {"id": "T-9", "posted": epoch(TODAY), "amount": "-3.00",
         "description": "BUS FARE"})
    r = crowd.editor.post("/api/bank/sync", json={"account_id": crowd.acc})
    assert r.status_code == 200, r.text
    body = r.json()
    assert (body["added"], body["matched"], body["skipped"]) == (1, 0, 2)
    assert body["messages"] == [] and body["calibrated"] == []
    assert isinstance(body["status"], dict)
    assert body["status"]["shared"][0]["account_id"] == crowd.acc
    entry = body["account"]
    assert entry["account_id"] == crowd.acc and entry["level"] == "edit"
    assert entry["provider"] == "simplefin" and entry["last_sync_ok"] is True
    assert entry["last_sync_status"].startswith("1 new line")
    assert "BUS FARE" in [t["description"] for t in lines(crowd.c, crowd.acc)]
    # The runs it made show in everyone's log, as the connection's.
    for who, c in crowd.can():
        log = c.get(f"/api/accounts/{crowd.acc}/bank-syncs").json()
        assert len(log) == 2 and log[0]["added"] == 1, who


def test_the_audit_event_is_the_editors_and_names_the_connection(crowd, fake):
    conn = next(x for x in crowd.c.get("/api/bank").json()["connections"])
    editor_id = crowd.editor.get("/api/me").json()["id"]
    assert crowd.editor.post("/api/bank/sync", json={"account_id": crowd.acc}).status_code == 200
    details = audit_details("bank_sync_run", editor_id)
    assert len(details) == 1
    assert details[0].endswith(f", connection #{conn['id']} of user #{crowd.u['id']}")
    assert audit_details("bank_sync_run", crowd.u["id"]) == [
        "2 added, 0 matched, 0 skipped, manual"]


def test_the_owner_can_sync_by_account_too(crowd):
    r = crowd.c.post("/api/bank/sync", json={"account_id": crowd.acc})
    assert r.status_code == 200, r.text
    assert r.json()["skipped"] == 2 and r.json()["account"]["mine"] is True


def test_read_only_and_strangers_cant_sync_the_account(crowd):
    for who, c in crowd.no_access():
        assert c.post("/api/bank/sync", json={"account_id": crowd.acc}).status_code == 404, who
    assert len(crowd.c.get(f"/api/accounts/{crowd.acc}/bank-syncs").json()) == 1


def test_syncing_an_account_that_isnt_linked_is_a_400(crowd):
    loose = make_account(crowd.editor, "Not linked")
    r = crowd.editor.post("/api/bank/sync", json={"account_id": loose})
    assert r.status_code == 400
    assert "doesn't take lines from a bank" in r.json()["detail"]


def test_an_unknown_account_is_a_404(crowd):
    assert crowd.editor.post("/api/bank/sync", json={"account_id": 999999999}).status_code == 404


def test_both_ids_is_a_400(crowd):
    conn = crowd.c.get("/api/bank").json()["connections"][0]["id"]
    for c in (crowd.c, crowd.editor):
        r = c.post("/api/bank/sync", json={"account_id": crowd.acc, "connection_id": conn})
        assert r.status_code == 400 and "not both" in r.json()["detail"]


def test_a_paused_connection_refuses_the_editor_and_names_the_holder(crowd, admin, fake):
    a, _ = admin
    set_access(a, crowd.u["id"], [])
    before = len(fake.requests)
    r = crowd.editor.post("/api/bank/sync", json={"account_id": crowd.acc})
    assert r.status_code == 403
    detail = r.json()["detail"]
    assert detail.startswith(f"An admin has paused {HOLDER_NAME}'s SimpleFIN connection")
    assert len(fake.requests) == before
    # Carries on once they're ticked again.
    set_access(a, crowd.u["id"], ["simplefin"])
    assert crowd.editor.post("/api/bank/sync", json={"account_id": crowd.acc}).status_code == 200


def test_a_disabled_holder_refuses_the_editor(crowd, fake):
    from app.db import SessionLocal, User
    db = SessionLocal()
    try:
        db.get(User, crowd.u["id"]).disabled = True
        db.commit()
    finally:
        db.close()
    try:
        before = len(fake.requests)
        r = crowd.editor.post("/api/bank/sync", json={"account_id": crowd.acc})
        assert r.status_code == 403
        assert "can't sign in" in r.json()["detail"]
        assert len(fake.requests) == before
    finally:
        db = SessionLocal()
        try:
            db.get(User, crowd.u["id"]).disabled = False
            db.commit()
        finally:
            db.close()


def test_the_holders_daily_limit_applies_to_the_editors_sync(crowd, fake):
    from app import main
    from app.db import BankConnection, SessionLocal
    db = SessionLocal()
    try:
        conn = db.query(BankConnection).filter_by(user_id=crowd.u["id"]).one()
        for _ in range(main.BANK_CALLS_PER_DAY):
            main._note_bank_call(conn, datetime.utcnow())
        db.commit()
    finally:
        db.close()
    r = crowd.editor.post("/api/bank/sync", json={"account_id": crowd.acc})
    assert r.status_code == 429


# ---------- `shared` in /api/bank and /api/bank/status ----------

SHARED_KEYS = {"account_id", "account_name", "archived", "level", "holder_name", "mine", "provider",
               "provider_name", "synced_through", "last_sync_at", "last_sync_ok", "last_sync_status",
               "needs_reconnect", "paused", "next_sync_at", "syncs_left_today", "sync_wait_seconds",
               "unmatched_count"}


def test_the_editors_bank_state_lists_the_shared_account(crowd):
    s = crowd.editor.get("/api/bank").json()
    assert s["connected"] is False and s["connections"] == []
    assert len(s["shared"]) == 1
    e = s["shared"][0]
    assert set(e) == SHARED_KEYS | {"bank_account_name"}
    assert e["account_id"] == crowd.acc and e["account_name"] == "Checking"
    assert e["archived"] is False and e["level"] == "edit"
    assert e["holder_name"] == HOLDER_NAME and e["mine"] is False
    assert e["provider"] == "simplefin" and e["provider_name"] == "SimpleFIN"
    assert e["synced_through"] == TODAY.isoformat()
    assert e["last_sync_at"].endswith("Z") and e["last_sync_ok"] is True
    assert e["last_sync_status"] == "2 new lines, 0 already here"
    assert e["needs_reconnect"] is False and e["paused"] is False
    assert isinstance(e["syncs_left_today"], int) and e["syncs_left_today"] > 0
    assert e["unmatched_count"] == 2
    assert e["bank_account_name"] == "Everyday Checking"


def test_the_short_status_has_shared_without_the_bank_account_name(crowd):
    s = crowd.editor.get("/api/bank/status").json()
    assert len(s["shared"]) == 1
    e = s["shared"][0]
    assert "bank_account_name" not in e
    assert set(e) == SHARED_KEYS
    assert e["account_id"] == crowd.acc and e["holder_name"] == HOLDER_NAME
    assert "bank_account_name" in crowd.editor.get("/api/bank").json()["shared"][0]


def test_the_holder_name_falls_back_to_the_email(crowd):
    name_the_holder(crowd.u["id"], None)
    e = shared_of(crowd.editor, crowd.acc)[0]
    assert e["holder_name"] == crowd.u["email"]


def test_read_only_people_and_strangers_get_no_shared_account(crowd):
    for who, c in crowd.no_access():
        assert c.get("/api/bank").json()["shared"] == [], who
        assert c.get("/api/bank/status").json()["shared"] == [], who


def test_the_holders_own_shared_list_is_empty(crowd):
    assert crowd.c.get("/api/bank").json()["shared"] == []
    assert crowd.c.get("/api/bank/status").json()["shared"] == []


def test_shared_says_nothing_of_the_connections_other_accounts(crowd):
    # The holder links a second bank account to an account the editor can't reach.
    other = make_account(crowd.c, "Savings account")
    link(crowd.c, crowd.status, other, name="Savings")
    for path in ("/api/bank", "/api/bank/status"):
        s = crowd.editor.get(path).json()
        assert [x["account_id"] for x in s["shared"]] == [crowd.acc], path
        text = str(s)
        assert str(other) not in {str(x) for x in s["shared"][0].values()}, path
        assert "linked_account_ids" not in text and "Savings" not in text, path
        assert "Test Bank" not in text, path


def test_shared_follows_the_accounts_own_latest_run(crowd, fake):
    fake.status = 500
    r = crowd.editor.post("/api/bank/sync", json={"account_id": crowd.acc})
    assert r.status_code >= 400
    fake.status = 200
    e = shared_of(crowd.editor, crowd.acc)[0]
    assert e["last_sync_ok"] is False and e["last_sync_status"]
    assert e["last_sync_at"].endswith("Z")


def test_shared_shows_a_paused_connection_and_a_changed_level(crowd, admin):
    a, _ = admin
    set_access(a, crowd.u["id"], [])
    e = shared_of(crowd.editor, crowd.acc)[0]
    assert e["paused"] is True and e["next_sync_at"] is None
    # Made an owner of the account too, the person sees it with that level.
    co, _ = register(crowd.editor.app)
    share_account(crowd.c, crowd.acc, "owner", invitee_client=co)
    assert shared_of(co, crowd.acc)[0]["level"] == "owner"


def test_an_archived_account_is_marked_in_shared(crowd):
    assert crowd.c.patch(f"/api/accounts/{crowd.acc}", json={"archived": True}).status_code == 200
    e = shared_of(crowd.editor, crowd.acc)[0]
    assert e["archived"] is True


def test_a_second_owner_works_the_account_like_an_editor(crowd):
    co, _ = register(crowd.editor.app)
    share_account(crowd.c, crowd.acc, "owner", invitee_client=co)
    assert co.get(f"/api/accounts/{crowd.acc}/bank-syncs").status_code == 200
    assert co.get(f"/api/accounts/{crowd.acc}/bank-unmatched").json()["count"] == 2
    assert forecast(co, crowd.acc)["bank_balance"]["balance"] == 1200.00
    r = co.post("/api/bank/sync", json={"account_id": crowd.acc})
    assert r.status_code == 200, r.text
    assert r.json()["account"]["level"] == "owner"


# ---------- What stays with the connection's person ----------

def test_linking_stays_with_the_owner(crowd):
    # An editor can't link their own bank account to the shared account…
    theirs = make_account(crowd.editor, "Theirs")
    r = crowd.editor.put("/api/bank/links", json={"links": [
        {"ref": ref_of(crowd.status, "Savings"), "account_id": crowd.acc}]})
    assert r.status_code == 404
    # …nor link the holder's bank account to one of theirs…
    r = crowd.editor.put("/api/bank/links", json={"links": [
        {"ref": ref_of(crowd.status, "Savings"), "account_id": theirs}]})
    assert r.status_code == 404
    # …and the holder can't link a bank account to one they only edit.
    other, _ = register(crowd.c.app)
    theirs2 = make_account(other, "Not mine")
    share_account(other, theirs2, "edit", invitee_client=crowd.c)
    r = crowd.c.put("/api/bank/links", json={"links": [
        {"ref": ref_of(crowd.status, "Savings"), "account_id": theirs2}]})
    assert r.status_code == 404
    assert [x["account_id"] for x in crowd.c.get("/api/bank").json()["accounts"]
            if x["account_id"] is not None] == [crowd.acc]


def test_an_editor_cant_use_the_holders_connection_id(crowd):
    conn = crowd.c.get("/api/bank").json()["connections"][0]["id"]
    before = len(crowd.c.get(f"/api/accounts/{crowd.acc}/bank-syncs").json())
    assert crowd.editor.post("/api/bank/sync", json={"connection_id": conn}).status_code == 404
    assert crowd.editor.post("/api/bank/disconnect", json={"connection_id": conn}).status_code in (400, 404)
    assert crowd.editor.put("/api/bank/categories", json={"connection_id": conn, "mappings": []}
                            ).status_code in (400, 404, 422)
    assert len(crowd.c.get(f"/api/accounts/{crowd.acc}/bank-syncs").json()) == before
    # The connection is still the holder's and still linked.
    assert crowd.c.get("/api/bank").json()["connected"] is True
    assert shared_of(crowd.editor, crowd.acc)


def test_a_plain_sync_by_an_editor_has_no_connection_to_sync(crowd):
    r = crowd.editor.post("/api/bank/sync")
    assert r.status_code == 404 and "No bank is connected" in r.json()["detail"]


def test_the_holder_disconnecting_takes_the_shared_entry_away(crowd):
    assert crowd.c.post("/api/bank/disconnect", json={}).status_code == 200
    assert crowd.editor.get("/api/bank").json()["shared"] == []
    assert crowd.editor.post("/api/bank/sync", json={"account_id": crowd.acc}).status_code == 400
    assert crowd.editor.get(f"/api/accounts/{crowd.acc}/bank-syncs").status_code == 200
