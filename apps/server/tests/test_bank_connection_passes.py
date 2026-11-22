"""The connection passes on (sync-access phase 3, #266).

Decided 2026-11-21: deleting a person hands each of their bank connections
that still feeds an account staying with another owner to the other owner of
the account it was linked to first (that account's longest-standing other
owner), with its links, the sync log and the category map; links to accounts
the new holder doesn't own stay, locked to that account's owners, who can
stop them with DELETE /api/accounts/{id}/bank-link. A connection with no
such account is deleted as before. Uses the stand-in SimpleFIN from
test_bank_sync.py (two bank accounts: Everyday Checking, Savings) and the
stand-in Teller from test_bank_providers.py.
"""
import pytest

from conftest import share_account
from test_bank_access import admin, set_access  # noqa: F401 (fixture)
from test_bank_providers import (connect_teller, linked, no_provider_keys, teller_fake,  # noqa: F401
                                 teller_user)
from test_bank_shared_sync import audit_details, crowd, shared_of  # noqa: F401 (fixture)
from test_bank_sync import (PASSWORD, TODAY, allow_bank, connected, epoch, fake, lines, link,  # noqa: F401
                            make_account, ref_of, register, switched_on)


class Scene:
    """`h` connected a SimpleFIN bank with two bank accounts. `acc1` (matched
    first, from Everyday Checking) has `h` and `o1` as owners (and `o1b`
    after it, when asked); `acc2` (from Savings, if `second`) has `h` and `o2`."""

    def __init__(self, **kw):
        self.__dict__.update(kw)


def _scene(app_started, fake, *, second=False, o1_on_acc2=None, o1b=False, o1_ticked=False):
    h, hu = register(app_started)
    acc1 = make_account(h, "First")
    r = h.post("/api/bank/connect", json={"token": fake.token()})
    assert r.status_code == 200, r.text
    status = r.json()
    conn = status["connections"][0]["id"]
    s = link(h, status, acc1)                              # first link
    acc2 = o2 = o2u = None
    if second:
        acc2 = make_account(h, "Second")
        s = link(h, status, acc2, name="Savings")          # second link
    assert h.post("/api/bank/sync").status_code == 200
    o1, o1u = register(app_started, bank=o1_ticked)
    share_account(h, acc1, "owner", invitee_client=o1)
    if o1b:
        o1b_c, o1bu = register(app_started, bank=False)
        share_account(h, acc1, "owner", invitee_client=o1b_c)
    else:
        o1b_c = o1bu = None
    if second:
        o2, o2u = register(app_started, bank=False)
        share_account(h, acc2, "owner", invitee_client=o2)
        if o1_on_acc2:
            share_account(h, acc2, o1_on_acc2, invitee_client=o1)
    return Scene(h=h, hu=hu, acc1=acc1, acc2=acc2, conn=conn, status=s, o1=o1, o1u=o1u,
                 o1b=o1b_c, o1bu=o1bu, o2=o2, o2u=o2u)


@pytest.fixture
def scene(app_started, fake, switched_on):
    return _scene(app_started, fake)


def remove(how, who, who_info, admin_pair):
    """Delete `who` by themselves ("self") or as an admin ("admin")."""
    if how == "self":
        return who.request("DELETE", "/api/me", json={"password": PASSWORD})
    return admin_pair[0].delete(f"/api/admin/users/{who_info['id']}")


def bank_of(c):
    r = c.get("/api/bank")
    assert r.status_code == 200, r.text
    return r.json()


def entry(c, name):
    return next(a for a in bank_of(c)["accounts"] if a["name"] == name)


def connection_ids():
    from app.db import BankConnection, SessionLocal
    db = SessionLocal()
    try:
        return {x.id for x in db.query(BankConnection)}
    finally:
        db.close()


def link_rows(conn_id):
    from app.db import BankAccountLink, SessionLocal
    db = SessionLocal()
    try:
        return sorted((l.account_id for l in db.query(BankAccountLink).filter_by(connection_id=conn_id)))
    finally:
        db.close()


def drop_connection(conn_id):
    """Remove a connection a test leaves behind that no sync has run on, so
    the daily sync (test_bank_access.py's run_due) doesn't pick it up later."""
    from app.db import BankConnection, SessionLocal
    db = SessionLocal()
    try:
        row = db.get(BankConnection, conn_id)
        if row:
            db.delete(row)
            db.commit()
    finally:
        db.close()


def holder_of(conn_id):
    from app.db import BankConnection, SessionLocal
    db = SessionLocal()
    try:
        row = db.get(BankConnection, conn_id)
        return row.user_id if row else None
    finally:
        db.close()


BOTH = pytest.mark.parametrize("how", ["self", "admin"])


# ---------- One other owner ----------

@BOTH
def test_the_other_owner_gets_the_connection(scene, admin, how):
    ids_before = {x["id"] for x in bank_of(scene.h)["connections"]}
    assert ids_before == {scene.conn}
    assert bank_of(scene.o1)["connected"] is False
    r = remove(how, scene.h, scene.hu, admin)
    assert r.status_code == 200, r.text
    assert scene.o1.get("/api/me").status_code == 200
    assert holder_of(scene.conn) == scene.o1u["id"]
    status = bank_of(scene.o1)
    assert status["connected"] is True
    assert [c["id"] for c in status["connections"]] == [scene.conn]
    conn = status["connections"][0]
    assert conn["provider"] == "simplefin" and conn["linked_account_ids"] == [scene.acc1]
    assert conn["paused"] is False
    mine = entry(scene.o1, "Everyday Checking")
    assert mine["account_id"] == scene.acc1 and mine["locked"] is False and mine["connection_id"] == scene.conn
    # The account stays with its other owner, and the sync log goes with it.
    assert scene.acc1 in [a["id"] for a in scene.o1.get("/api/accounts").json()]


@BOTH
def test_the_new_holder_is_ticked_for_the_provider(app_started, fake, switched_on, admin, how):
    s = _scene(app_started, fake, o1_ticked=False)
    before = bank_of(s.o1)
    assert before["providers_allowed"] == []
    assert remove(how, s.h, s.hu, admin).status_code == 200
    after = bank_of(s.o1)
    assert "simplefin" in after["providers_allowed"]
    assert next(p for p in after["providers"] if p["key"] == "simplefin")["allowed"] is True
    assert after["connections"][0]["paused"] is False
    # Someone already ticked stays ticked: nothing doubles up.
    s2 = _scene(app_started, fake, o1_ticked=True)
    assert remove(how, s2.h, s2.hu, admin).status_code == 200
    assert bank_of(s2.o1)["providers_allowed"].count("simplefin") == 1


@BOTH
def test_the_sync_carries_on_for_the_new_holder(scene, admin, fake, how):
    fake.accounts[0]["transactions"].append(
        {"id": "T-9", "posted": epoch(TODAY), "amount": "-3.00", "description": "BUS FARE"})
    assert remove(how, scene.h, scene.hu, admin).status_code == 200
    r = scene.o1.post("/api/bank/sync", json={"connection_id": scene.conn})
    assert r.status_code == 200, r.text
    assert (r.json()["added"], r.json()["skipped"]) == (1, 2)
    assert "BUS FARE" in [t["description"] for t in lines(scene.o1, scene.acc1)]
    # By account too, and with no body at all.
    fake.accounts[0]["transactions"].append(
        {"id": "T-10", "posted": epoch(TODAY), "amount": "-4.00", "description": "TRAM FARE"})
    r = scene.o1.post("/api/bank/sync", json={"account_id": scene.acc1})
    assert r.status_code == 200, r.text
    assert r.json()["added"] == 1
    assert "TRAM FARE" in [t["description"] for t in lines(scene.o1, scene.acc1)]
    assert scene.o1.post("/api/bank/sync").status_code == 200


@BOTH
def test_the_sync_log_stays_with_the_account(scene, admin, how):
    before = scene.h.get(f"/api/accounts/{scene.acc1}/bank-syncs").json()
    assert len(before) >= 1
    assert remove(how, scene.h, scene.hu, admin).status_code == 200
    after = scene.o1.get(f"/api/accounts/{scene.acc1}/bank-syncs")
    assert after.status_code == 200, after.text
    assert [x["id"] for x in after.json()] == [x["id"] for x in before]
    # The new holder's own syncs join it.
    assert scene.o1.post("/api/bank/sync", json={"account_id": scene.acc1}).status_code == 200
    assert len(scene.o1.get(f"/api/accounts/{scene.acc1}/bank-syncs").json()) == len(before) + 1


@BOTH
def test_passing_on_is_recorded_under_the_new_holder(scene, admin, how):
    assert remove(how, scene.h, scene.hu, admin).status_code == 200
    assert audit_details("bank_connection_passed", scene.o1u["id"]) == [
        f"connection #{scene.conn} (SimpleFIN) from deleted user #{scene.hu['id']}"]


def test_the_longest_standing_owner_gets_it(app_started, fake, switched_on, admin):
    s = _scene(app_started, fake, o1b=True)
    assert remove("self", s.h, s.hu, admin).status_code == 200
    # o1 accepted before o1b did.
    assert holder_of(s.conn) == s.o1u["id"]
    assert bank_of(s.o1b)["connected"] is False
    assert audit_details("bank_connection_passed", s.o1bu["id"]) == []


# ---------- Two accounts on one connection, two other owners ----------

@BOTH
def test_the_first_linked_accounts_owner_gets_it_and_the_other_link_stays(
        app_started, fake, switched_on, admin, how):
    s = _scene(app_started, fake, second=True)
    assert remove(how, s.h, s.hu, admin).status_code == 200
    # o1 owns the first-linked account.
    assert holder_of(s.conn) == s.o1u["id"]
    assert bank_of(s.o2)["connected"] is False
    assert link_rows(s.conn) == sorted([s.acc1, s.acc2])
    assert audit_details("bank_connection_passed", s.o1u["id"]) == [
        f"connection #{s.conn} (SimpleFIN) from deleted user #{s.hu['id']}"]
    assert audit_details("bank_connection_passed", s.o2u["id"]) == []
    # o2 owns the account whose link stays: it takes lines from o1's connection.
    shared = shared_of(s.o2, s.acc2)
    assert len(shared) == 1 and shared[0]["level"] == "owner" and shared[0]["mine"] is False
    # And o2 can stop it with the new route; the connection stays o1's.
    r = s.o2.delete(f"/api/accounts/{s.acc2}/bank-link")
    assert r.status_code == 200, r.text
    assert shared_of(s.o2, s.acc2) == []
    assert holder_of(s.conn) == s.o1u["id"]
    assert link_rows(s.conn) == [s.acc1]
    assert entry(s.o1, "Savings")["account_id"] is None
    assert entry(s.o1, "Savings")["locked"] is False
    assert audit_details("bank_link_removed", s.o2u["id"]) == [f"account #{s.acc2}, connection #{s.conn}"]


def test_a_link_to_an_account_the_new_holder_cant_see_is_locked_and_blank(app_started, fake, switched_on, admin):
    s = _scene(app_started, fake, second=True)
    assert remove("self", s.h, s.hu, admin).status_code == 200
    saved = entry(s.o1, "Savings")
    assert saved["locked"] is True
    assert saved["account_id"] is None and saved["account_name"] is None
    assert saved["start_date"] is not None
    # The new holder's own match is not locked, and names no account name.
    mine = entry(s.o1, "Everyday Checking")
    assert mine["locked"] is False and mine["account_id"] == s.acc1 and mine["account_name"] is None


def test_a_link_to_an_account_they_can_read_is_locked_and_names_it(app_started, fake, switched_on, admin):
    s = _scene(app_started, fake, second=True, o1_on_acc2="read")
    assert remove("self", s.h, s.hu, admin).status_code == 200
    saved = entry(s.o1, "Savings")
    assert saved["locked"] is True
    assert saved["account_id"] == s.acc2 and saved["account_name"] == "Second"


def test_the_holder_cant_change_or_clear_a_locked_link(app_started, fake, switched_on, admin):
    s = _scene(app_started, fake, second=True, o1_on_acc2="read")
    assert remove("self", s.h, s.hu, admin).status_code == 200
    ref = ref_of(bank_of(s.o1), "Savings")
    mine = make_account(s.o1, "Mine")
    start = TODAY.isoformat()
    for account_id in (None, mine):
        r = s.o1.put("/api/bank/links", json={"links": [
            {"ref": ref, "account_id": account_id, "start_date": start}]})
        assert r.status_code == 403, (account_id, r.text)
        assert "don't own" in r.json()["detail"]
        assert link_rows(s.conn) == sorted([s.acc1, s.acc2])
    # Even with their own match in the same request, nothing is saved.
    own = ref_of(bank_of(s.o1), "Everyday Checking")
    r = s.o1.put("/api/bank/links", json={"links": [
        {"ref": own, "account_id": s.acc1, "start_date": start},
        {"ref": ref, "account_id": None}]})
    assert r.status_code == 403, r.text
    assert entry(s.o1, "Savings")["account_id"] == s.acc2
    # Leaving the locked ref out keeps it, and their own can still change.
    r = s.o1.put("/api/bank/links", json={"links": [
        {"ref": own, "account_id": s.acc1, "start_date": start}]})
    assert r.status_code == 200, r.text
    assert link_rows(s.conn) == sorted([s.acc1, s.acc2])
    saved = next(a for a in r.json()["accounts"] if a["ref"] == ref)
    assert saved["locked"] is True and saved["account_id"] == s.acc2
    r = s.o1.put("/api/bank/links", json={"links": [{"ref": own, "account_id": None}]})
    assert r.status_code == 200, r.text
    assert link_rows(s.conn) == [s.acc2]


def test_an_owner_who_unlinks_frees_the_holder_to_relink(app_started, fake, switched_on, admin):
    s = _scene(app_started, fake, second=True)
    assert remove("self", s.h, s.hu, admin).status_code == 200
    assert s.o2.delete(f"/api/accounts/{s.acc2}/bank-link").status_code == 200
    mine = make_account(s.o1, "Mine")
    r = s.o1.put("/api/bank/links", json={"links": [
        {"ref": ref_of(bank_of(s.o1), "Savings"), "account_id": mine, "start_date": TODAY.isoformat()}]})
    assert r.status_code == 200, r.text
    assert entry(s.o1, "Savings")["account_id"] == mine


# ---------- No other owner ----------

@BOTH
def test_a_connection_with_no_other_owner_is_deleted(app_started, fake, switched_on, admin, how):
    h, hu = register(app_started)
    acc = make_account(h, "Mine alone")
    r = h.post("/api/bank/connect", json={"token": fake.token()})
    conn = r.json()["connections"][0]["id"]
    link(h, r.json(), acc)
    assert conn in connection_ids()
    check = h.get("/api/me/deletion-check").json()
    assert check["bank_connections_passed"] == []
    assert check["bank_connections_deleted"] == [
        {"id": conn, "name": check["bank_connections_deleted"][0]["name"], "provider_name": "SimpleFIN"}]
    assert remove(how, h, hu, admin).status_code == 200
    assert conn not in connection_ids()
    assert link_rows(conn) == []


@BOTH
def test_a_connection_with_no_links_is_deleted_too(app_started, fake, switched_on, admin, how):
    h, hu = register(app_started)
    r = h.post("/api/bank/connect", json={"token": fake.token()})
    conn = r.json()["connections"][0]["id"]
    assert remove(how, h, hu, admin).status_code == 200
    assert conn not in connection_ids()


def test_an_account_that_goes_with_the_user_doesnt_pass_the_connection(app_started, fake, switched_on, admin):
    # The shared account is the only one that stays; the connection feeds
    # only an account that goes, so it goes too.
    h, hu = register(app_started)
    private = make_account(h, "Private")
    other, ou = register(app_started)
    shared = make_account(h, "Shared")
    share_account(h, shared, "owner", invitee_client=other)
    r = h.post("/api/bank/connect", json={"token": fake.token()})
    conn = r.json()["connections"][0]["id"]
    link(h, r.json(), private)
    check = h.get("/api/me/deletion-check").json()
    assert check["bank_connections_passed"] == []
    assert [c["id"] for c in check["bank_connections_deleted"]] == [conn]
    assert remove("self", h, hu, admin).status_code == 200
    assert conn not in connection_ids()
    assert bank_of(other)["connected"] is False


def test_a_person_with_two_connections_passes_one_and_ends_the_other(app_started, fake, switched_on, admin):
    h, hu = register(app_started)
    shared, private = make_account(h, "Shared"), make_account(h, "Private")
    other, ou = register(app_started, bank=False)
    share_account(h, shared, "owner", invitee_client=other)
    first = h.post("/api/bank/connect", json={"token": fake.token()}).json()
    conn1 = first["connections"][0]["id"]
    link(h, first, shared)
    fake.accounts = [{**fake.accounts[0], "id": "ACT-OTHER", "name": "Other Bank Checking"}]
    second = h.post("/api/bank/connect", json={"token": fake.token()}).json()
    conn2 = next(c["id"] for c in second["connections"] if c["id"] != conn1)
    r = h.put("/api/bank/links", json={"links": [{
        "ref": ref_of(second, "Other Bank Checking"), "account_id": private,
        "start_date": TODAY.isoformat()}]})
    assert r.status_code == 200, r.text
    check = h.get("/api/me/deletion-check").json()
    assert [c["id"] for c in check["bank_connections_passed"]] == [conn1]
    assert [c["id"] for c in check["bank_connections_deleted"]] == [conn2]
    assert remove("self", h, hu, admin).status_code == 200
    assert holder_of(conn1) == ou["id"]
    assert conn2 not in connection_ids()
    drop_connection(conn1)


# ---------- Teller: the tick, the category map and the audit text ----------

def test_a_teller_connection_passes_with_its_category_map(teller_user, app_started, admin):
    from app.db import BankCategoryMap, Category, SessionLocal
    h, hu, conn = teller_user
    acc = linked(h, conn, "Teller Checking")
    other, ou = register(app_started, bank=False)
    share_account(h, acc, "owner", invitee_client=other)

    def make_category(c, name):
        assert c.post("/api/categories", json={"name": name}).status_code == 200
        return next(x["id"] for x in c.get("/api/categories").json() if x["name"] == name)

    dining = make_category(h, "Eating Out")
    travel = make_category(h, "Trips")
    groceries_h = make_category(h, "Supermarket")
    their_dining = make_category(other, "eating OUT")
    their_groceries = make_category(other, "Own groceries")
    db = SessionLocal()
    try:
        for key, cat in (("dining", dining), ("travel", travel), ("groceries", groceries_h), ("misc", None)):
            db.add(BankCategoryMap(user_id=hu["id"], provider="teller", key=key, category_id=cat))
        # The new holder already has a row for "groceries": it stays as it is.
        db.add(BankCategoryMap(user_id=ou["id"], provider="teller", key="groceries",
                               category_id=their_groceries))
        # A row for another provider isn't copied across.
        db.add(BankCategoryMap(user_id=hu["id"], provider="plaid", key="food", category_id=dining))
        db.commit()
    finally:
        db.close()
    assert bank_of(other)["providers_allowed"] == []
    check = h.get("/api/me/deletion-check").json()
    assert check["bank_connections_passed"] == [{
        "id": conn, "name": check["bank_connections_passed"][0]["name"], "provider_name": "Teller",
        "new_holder_email": ou["email"]}]
    assert remove("self", h, hu, admin).status_code == 200
    assert "teller" in bank_of(other)["providers_allowed"]
    rows = {r["key"]: r for r in other.get("/api/bank/categories").json()["rows"]
            if r["provider"] == "teller"}
    assert rows["dining"]["category_id"] == their_dining       # same name, any case
    assert rows["travel"]["category_id"] is None               # no category of that name
    assert rows["groceries"]["category_id"] == their_groceries  # theirs kept
    assert rows["misc"]["category_id"] is None
    assert not [r for r in other.get("/api/bank/categories").json()["rows"] if r["provider"] == "plaid"]
    assert audit_details("bank_connection_passed", ou["id"]) == [
        f"connection #{conn} (Teller) from deleted user #{hu['id']}"]
    # The deleted person's rows went with them.
    db = SessionLocal()
    try:
        assert db.query(BankCategoryMap).filter_by(user_id=hu["id"]).count() == 0
        assert db.query(Category).filter_by(owner_id=hu["id"]).count() == 0
    finally:
        db.close()
    drop_connection(conn)


# ---------- The deletion check ----------

def test_the_deletion_check_lists_what_passes(scene):
    check = scene.h.get("/api/me/deletion-check").json()
    assert check["can_delete"] is True
    assert check["bank_connections_deleted"] == []
    [passed] = check["bank_connections_passed"]
    assert set(passed) == {"id", "name", "provider_name", "new_holder_email"}
    assert passed["id"] == scene.conn and passed["provider_name"] == "SimpleFIN"
    assert passed["new_holder_email"] == scene.o1u["email"]
    assert isinstance(passed["name"], str)
    assert [a["id"] for a in check["accounts_kept"]] == [scene.acc1]
    # Nothing was changed by looking.
    assert holder_of(scene.conn) == scene.hu["id"]


def test_a_user_with_no_bank_has_empty_lists(app_started):
    c, _ = register(app_started)
    check = c.get("/api/me/deletion-check").json()
    assert check["bank_connections_passed"] == [] and check["bank_connections_deleted"] == []


def test_a_refused_deletion_still_lists_the_connections(scene, admin):
    # A read-only person on a second account blocks the deletion.
    joint = make_account(scene.h, "Joint")
    viewer, vu = register(_app(), bank=False)
    share_account(scene.h, joint, "read", invitee_client=viewer)
    check = scene.h.get("/api/me/deletion-check").json()
    assert check["can_delete"] is False
    r = scene.h.request("DELETE", "/api/me", json={"password": PASSWORD})
    assert r.status_code == 409
    detail = r.json()["detail"]
    assert [c["id"] for c in detail["bank_connections_passed"]] == [scene.conn]
    assert detail["bank_connections_passed"][0]["new_holder_email"] == scene.o1u["email"]
    assert detail["bank_connections_deleted"] == []
    r = admin[0].delete(f"/api/admin/users/{scene.hu['id']}")
    assert r.status_code == 409
    assert [c["id"] for c in r.json()["detail"]["bank_connections_passed"]] == [scene.conn]
    # Nothing moved.
    assert holder_of(scene.conn) == scene.hu["id"]
    assert bank_of(scene.h)["connected"] is True


def _app():
    from app.main import app
    return app


def test_the_admin_deletion_check(scene, admin):
    a, _ = admin
    r = a.get(f"/api/admin/users/{scene.hu['id']}/deletion-check")
    assert r.status_code == 200, r.text
    body = r.json()
    own = scene.h.get("/api/me/deletion-check").json()
    assert body == {k: v for k, v in own.items() if k not in ("has_password", "is_demo")}
    assert [c["id"] for c in body["bank_connections_passed"]] == [scene.conn]
    assert body["bank_connections_passed"][0]["new_holder_email"] == scene.o1u["email"]
    assert holder_of(scene.conn) == scene.hu["id"]


def test_the_admin_deletion_check_errors(scene, admin):
    a, _ = admin
    assert a.get("/api/admin/users/999999999/deletion-check").status_code == 404
    path = f"/api/admin/users/{scene.hu['id']}/deletion-check"
    assert scene.o1.get(path).status_code == 403
    assert scene.h.get(path).status_code == 403          # even their own
    from fastapi.testclient import TestClient
    assert TestClient(_app()).get(path).status_code == 401


# ---------- Unlinking an account ----------

def test_an_owner_who_isnt_the_holder_unlinks(crowd):
    co, cou = register(_app(), bank=False)
    share_account(crowd.c, crowd.acc, "owner", invitee_client=co)
    conn = crowd.status["connections"][0]["id"]
    assert [x["account_id"] for x in bank_of(co)["shared"]] == [crowd.acc]
    r = co.delete(f"/api/accounts/{crowd.acc}/bank-link")
    assert r.status_code == 200, r.text
    assert r.json() == {"ok": True}
    assert bank_of(co)["shared"] == []
    assert audit_details("bank_link_removed", cou["id"]) == [f"account #{crowd.acc}, connection #{conn}"]
    # The connection is still its person's, and the account is free of it.
    assert holder_of(conn) == crowd.u["id"]
    assert bank_of(crowd.c)["connected"] is True
    assert link_rows(conn) == []
    assert entry(crowd.c, "Everyday Checking")["account_id"] is None
    # Lines already in stay.
    assert "PAYROLL ACME" in [t["description"] for t in lines(crowd.c, crowd.acc)]
    # Nothing left to remove.
    assert co.delete(f"/api/accounts/{crowd.acc}/bank-link").status_code == 404
    assert crowd.c.delete(f"/api/accounts/{crowd.acc}/bank-link").status_code == 404


def test_the_holder_unlinks_their_own_account_too(crowd):
    r = crowd.c.delete(f"/api/accounts/{crowd.acc}/bank-link")
    assert r.status_code == 200, r.text
    assert entry(crowd.c, "Everyday Checking")["account_id"] is None
    assert audit_details("bank_link_removed", crowd.u["id"]) == [
        f"account #{crowd.acc}, connection #{crowd.status['connections'][0]['id']}"]


def test_an_editor_a_reader_and_a_stranger_cant_unlink(crowd):
    conn = crowd.status["connections"][0]["id"]
    for who, c in [("editor", crowd.editor)] + crowd.no_access():
        r = c.delete(f"/api/accounts/{crowd.acc}/bank-link")
        assert r.status_code == 404, (who, r.text)
    assert link_rows(conn) == [crowd.acc]
    assert audit_details("bank_link_removed", crowd.u["id"]) == []


def test_unlinking_an_account_with_no_link_or_an_unknown_one_is_404(crowd):
    loose = make_account(crowd.c, "Loose")
    assert crowd.c.delete(f"/api/accounts/{loose}/bank-link").status_code == 404
    assert crowd.c.delete("/api/accounts/999999999/bank-link").status_code == 404
    assert audit_details("bank_link_removed", crowd.u["id"]) == []


def test_unlinking_needs_a_session(app_started):
    from fastapi.testclient import TestClient
    assert TestClient(app_started).delete("/api/accounts/1/bank-link").status_code == 401


def test_a_holders_own_match_isnt_locked(crowd):
    mine = entry(crowd.c, "Everyday Checking")
    assert mine["locked"] is False and mine["account_id"] == crowd.acc and mine["account_name"] is None
    assert entry(crowd.c, "Savings")["locked"] is False
    assert entry(crowd.c, "Savings")["account_id"] is None
