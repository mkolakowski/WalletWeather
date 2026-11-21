"""Who may connect a bank, per person and provider (sync-access phase 1, #264).

Decided 2026-11-21: an admin ticks each person for each provider in Admin →
Users; admins may always connect; the Admin → Bank sync switch stays as a
kill switch; unticking a provider pauses that person's connections of it,
kept, and ticking again carries on; on upgrade, whoever has a connection is
ticked for its provider, once.

Every call goes to a stand-in SimpleFIN, Teller or Plaid, never the network.
"""
import pytest
from fastapi.testclient import TestClient

from test_bank_providers import (connect_teller, no_provider_keys, plaid_fake, start,  # noqa: F401
                                 teller_fake)
from test_bank_sync import (allow_bank, connected, fake, link, make_account, register,  # noqa: F401
                            set_switch, switched_on)


@pytest.fixture
def admin(app_started):
    from app import main
    c, u = register(app_started, bank=False)
    main.ADMIN_EMAILS.add(u["email"])
    yield c, u
    main.ADMIN_EMAILS.discard(u["email"])


def set_access(admin_client, uid, providers):
    r = admin_client.put(f"/api/admin/users/{uid}/bank-access", json={"providers": providers})
    assert r.status_code == 200, r.text
    return r.json()


def run_due():
    from app import main
    from app.db import SessionLocal
    db = SessionLocal()
    try:
        return main.run_due_bank_syncs(db)
    finally:
        db.close()


# ---------- Connecting ----------

def test_an_unticked_person_is_offered_nothing_and_refused_everywhere(
        app_started, fake, teller_fake, plaid_fake, switched_on):
    c, _ = register(app_started, bank=False)
    s = c.get("/api/bank").json()
    assert s["enabled"] is True and s["providers_allowed"] == []
    assert {p["key"]: (p["available"], p["allowed"]) for p in s["providers"]} == {
        "simplefin": (True, False), "teller": (True, False), "plaid": (True, False)}
    r = c.post("/api/bank/connect", json={"token": fake.token()})
    assert r.status_code == 403 and "Admin → Users" in r.json()["detail"]
    assert fake.claimed == set()
    for provider in ("teller", "plaid"):
        r = start(c, provider)
        assert r.status_code == 403 and "Admin → Users" in r.json()["detail"], provider
    assert c.get("/api/bank").json()["connected"] is False


def test_a_tick_opens_only_that_provider(app_started, fake, teller_fake, plaid_fake, switched_on):
    c, u = register(app_started, bank=False)
    allow_bank(u["id"], ["teller"])
    s = c.get("/api/bank").json()
    assert s["providers_allowed"] == ["teller"]
    assert c.post("/api/bank/connect", json={"token": fake.token()}).status_code == 403
    assert start(c, "plaid").status_code == 403
    connect_teller(c)
    assert c.get("/api/bank").json()["connected"] is True


def test_a_tick_taken_away_mid_connection_stops_it_finishing(app_started, teller_fake, switched_on):
    c, u = register(app_started, bank=False)
    allow_bank(u["id"], ["teller"])
    attempt = start(c, "teller").json()["attempt"]
    allow_bank(u["id"], [])
    r = c.post("/api/bank/teller/enroll", json={"attempt": attempt, "access_token": "teller_tok_one"})
    assert r.status_code == 403
    assert c.post("/api/bank/connect/check", json={"attempt": attempt}).status_code == 403
    assert c.get("/api/bank/teller/setup", params={"attempt": attempt}).status_code == 403


def test_a_provider_without_keys_isnt_allowed_even_when_ticked(app_started, switched_on):
    c, u = register(app_started)   # ticked for all three; no Teller or Plaid keys here
    s = c.get("/api/bank").json()
    assert s["providers_allowed"] == ["simplefin"]
    assert start(c, "teller").status_code == 400


def test_an_admin_may_always_connect(app_started, admin, fake, teller_fake, switched_on):
    c, _ = admin
    s = c.get("/api/bank").json()
    assert s["providers_allowed"] == ["simplefin", "teller"]
    assert c.post("/api/bank/connect", json={"token": fake.token()}).status_code == 200


def test_the_switch_still_turns_everything_off(app_started, fake):
    c, _ = register(app_started)
    set_switch(False)
    s = c.get("/api/bank").json()
    assert s["enabled"] is False
    assert c.post("/api/bank/connect", json={"token": fake.token()}).status_code == 403


# ---------- Admin → Users ----------

def test_an_admin_ticks_and_unticks_providers(app_started, admin):
    from app.db import AuditEvent, SessionLocal
    a, _ = admin
    _, u = register(app_started, bank=False)
    assert set_access(a, u["id"], ["plaid", "simplefin"]) == {"id": u["id"], "bank_access": ["simplefin", "plaid"]}
    row = next(x for x in a.get("/api/admin/users").json() if x["id"] == u["id"])
    assert row["bank_access"] == ["plaid", "simplefin"]
    assert set_access(a, u["id"], [])["bank_access"] == []
    db = SessionLocal()
    try:
        details = [e.detail for e in db.query(AuditEvent)
                   .filter(AuditEvent.event == "bank_access_changed",
                           AuditEvent.detail.like(f"user #{u['id']}:%"))
                   .order_by(AuditEvent.id)]
    finally:
        db.close()
    assert details == [f"user #{u['id']}: SimpleFIN, Plaid", f"user #{u['id']}: none"]


def test_the_same_list_again_records_nothing(app_started, admin):
    from app.db import AuditEvent, SessionLocal
    a, _ = admin
    _, u = register(app_started, bank=False)
    set_access(a, u["id"], ["simplefin"])
    set_access(a, u["id"], ["simplefin"])
    db = SessionLocal()
    try:
        n = (db.query(AuditEvent).filter(AuditEvent.event == "bank_access_changed",
                                         AuditEvent.detail.like(f"user #{u['id']}:%")).count())
    finally:
        db.close()
    assert n == 1


def test_bank_access_checks(app_started, admin):
    a, _ = admin
    _, u = register(app_started, bank=False)
    r = a.put(f"/api/admin/users/{u['id']}/bank-access", json={"providers": ["mint"]})
    assert r.status_code == 400 and "mint" in r.json()["detail"]
    assert a.put("/api/admin/users/999999999/bank-access", json={"providers": []}).status_code == 404
    assert a.put(f"/api/admin/users/{u['id']}/bank-access", json={}).status_code == 422


def test_only_an_admin_in_a_browser_may_tick(app_started, admin):
    from app import main
    from app.db import SessionLocal
    a, admin_user = admin
    c, u = register(app_started, bank=False)
    assert c.put(f"/api/admin/users/{u['id']}/bank-access",
                 json={"providers": ["simplefin"]}).status_code == 403
    # An admin API token is refused too, like the Bank sync switch.
    r = a.post("/api/tokens", json={"name": "t", "access": "admin"})
    assert r.status_code == 200, r.text
    tok = TestClient(main.app, headers={"Authorization": f"Bearer {r.json()['token']}"})
    assert tok.put(f"/api/admin/users/{u['id']}/bank-access",
                   json={"providers": ["simplefin"]}).status_code == 403
    db = SessionLocal()
    try:
        assert main.bank_access(db, db.get(main.User, u["id"])) == set()
    finally:
        db.close()


# ---------- Unticking pauses ----------

def test_unticking_pauses_a_connection_and_ticking_again_carries_on(app_started, admin, connected, fake):
    a, _ = admin
    c, u, acc, status = connected
    link(c, status, acc)
    set_access(a, u["id"], [])
    s = c.get("/api/bank").json()
    assert s["connected"] is True and s["providers_allowed"] == []
    conn = s["connections"][0]
    assert conn["paused"] is True and conn["next_sync_at"] is None
    assert c.get("/api/bank/status").json()["connections"][0]["paused"] is True
    r = c.post("/api/bank/sync", json={})
    assert r.status_code == 403 and "paused" in r.json()["detail"]
    r = c.post("/api/bank/sync", json={"connection_id": conn["id"]})
    assert r.status_code == 403
    before = len(fake.requests)
    run_due()
    assert len(fake.requests) == before   # the daily sync left it alone
    # Kept, not deleted: disconnecting still works while paused, but first tick again.
    set_access(a, u["id"], ["simplefin"])
    s = c.get("/api/bank").json()
    assert s["connections"][0]["paused"] is False
    r = c.post("/api/bank/sync", json={})
    assert r.status_code == 200, r.text


def test_a_paused_connection_doesnt_make_a_new_account(app_started, connected):
    c, u, _, status = connected
    allow_bank(u["id"], [])
    ref = status["accounts"][0]["ref"]
    r = c.post("/api/bank/accounts", json={"ref": ref, "name": "From the bank"})
    assert r.status_code == 403
    assert all(x["name"] != "From the bank" for x in c.get("/api/accounts").json())


def test_unticking_one_provider_leaves_the_others_syncing(app_started, connected, fake, teller_fake):
    c, u, acc, status = connected
    link(c, status, acc)
    connect_teller(c)
    allow_bank(u["id"], ["simplefin"])
    s = c.get("/api/bank/status").json()
    paused = {x["provider"]: x["paused"] for x in s["connections"]}
    assert paused == {"simplefin": False, "teller": True}
    assert c.post("/api/bank/sync", json={}).status_code == 200


# ---------- The upgrade ----------

def test_the_upgrade_ticks_whoever_has_a_connection_once(app_started, connected, admin):
    from app.db import AdminSetting, SessionLocal, init_db
    from app import main
    a, _ = admin
    c, u, _, _ = connected
    _, bystander = register(app_started, bank=False)
    allow_bank(u["id"], [])          # as before the upgrade: no ticks at all
    db = SessionLocal()
    try:
        row = db.get(AdminSetting, "bank_access_seeded")
        if row:
            db.delete(row)
        db.commit()
    finally:
        db.close()
    init_db()
    db = SessionLocal()
    try:
        assert main.bank_access(db, db.get(main.User, u["id"])) == {"simplefin"}
        assert main.bank_access(db, db.get(main.User, bystander["id"])) == set()
    finally:
        db.close()
    # An admin unticks them; the next start doesn't tick them again.
    set_access(a, u["id"], [])
    init_db()
    db = SessionLocal()
    try:
        assert main.bank_access(db, db.get(main.User, u["id"])) == set()
    finally:
        db.close()
