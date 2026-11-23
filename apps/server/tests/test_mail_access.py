"""Who may connect a mailbox for email alerts, and the account's share of it
(sync-access phase 5, #268).

Decided 2026-11-21: an admin ticks each person for Microsoft 365 in Admin →
Users; admins may always connect; the Email alerts switch stays as a kill
switch; unticking pauses a person's mailbox, kept, and ticking again carries
on; on upgrade, whoever has a mailbox is ticked, once. The accounts a mailbox
feeds show its state to their owners and editors, who can press Check now for
the account; a mailbox doesn't pass on (deleting its person removes it).

Every call goes to the stand-in Microsoft from test_mail_alerts.py.
"""
from datetime import datetime, timedelta

import pytest

from conftest import share_account
from test_mail_alerts import (BANK, TODAY, allow_mail, connect_with_code, connected, lines,  # noqa: F401
                              make_account, ms, register, set_switch, switched_on, taught, teach)
from test_mail_alerts import admin  # noqa: F401 (fixture)
from test_mail_alerts_daily import only_these_users_due, run_due

HOLDER_NAME = "Holly Holder"
SHARED_KEYS = {"account_id", "account_name", "archived", "level", "holder_name", "mine", "provider",
               "provider_name", "last_check_at", "last_check_ok", "needs_reconnect", "paused",
               "holder_disabled", "next_check_at", "unmatched_count"}


def set_access(admin_client, uid, providers):
    r = admin_client.put(f"/api/admin/users/{uid}/mail-access", json={"providers": providers})
    assert r.status_code == 200, r.text
    return r.json()


def name_the_holder(user_id, name=HOLDER_NAME):
    from app.db import SessionLocal, User
    db = SessionLocal()
    try:
        db.get(User, user_id).name = name
        db.commit()
    finally:
        db.close()


def set_disabled(user_id, disabled):
    from app.db import SessionLocal, User
    db = SessionLocal()
    try:
        db.get(User, user_id).disabled = disabled
        db.commit()
    finally:
        db.close()


def audit_details(event, user_id=None, like=None):
    from app.db import AuditEvent, SessionLocal
    db = SessionLocal()
    try:
        q = db.query(AuditEvent).filter(AuditEvent.event == event)
        if user_id is not None:
            q = q.filter(AuditEvent.user_id == user_id)
        if like:
            q = q.filter(AuditEvent.detail.like(like))
        return [e.detail for e in q.order_by(AuditEvent.id)]
    finally:
        db.close()


def shared_of(c, acc, path="/api/mail"):
    return [x for x in c.get(path).json()["shared"] if x["account_id"] == acc]


class Crowd:
    """The mailbox's person (`c`, who owns `acc` and `acc2`), an editor and a
    read-only person on `acc`, an editor on `acc2` (fed by a card), and a
    stranger. Alerts for card 1234 go to `acc`, card 9876 to `acc2`."""

    def __init__(self, c, u, acc, acc2, editor, viewer, card_editor, stranger):
        self.c, self.u, self.acc, self.acc2 = c, u, acc, acc2
        self.editor, self.viewer, self.card_editor, self.stranger = editor, viewer, card_editor, stranger

    def no_access(self):
        return [("read-only", self.viewer), ("stranger", self.stranger)]


def not_due_for_an_hour(user_id):
    """Keep the app's own scheduler (it checks due mailboxes every minute,
    in tests too) off this mailbox, so a test's Check now isn't refused as
    "checked a moment ago" when the scheduler got there first."""
    from app.db import MailConnection, SessionLocal
    db = SessionLocal()
    db.query(MailConnection).filter_by(user_id=user_id).update(
        {MailConnection.check_minutes: 60,
         MailConnection.last_check_at: datetime.utcnow() - timedelta(minutes=5)})
    db.commit()
    db.close()


@pytest.fixture
def crowd(app_started, taught, ms):
    c, u, acc = taught
    name_the_holder(u["id"])
    only_these_users_due(u["id"])
    not_due_for_an_hour(u["id"])
    acc2 = make_account(c, "Card 9876")
    sender = c.get("/api/mail").json()["senders"][0]
    r = c.put(f"/api/mail/senders/{sender['id']}", json={"cards": {"9876": acc2}})
    assert r.status_code == 200, r.text
    editor, _ = register(app_started)
    share_account(c, acc, "edit", invitee_client=editor)
    viewer, _ = register(app_started)
    share_account(c, acc, "read", invitee_client=viewer)
    card_editor, _ = register(app_started)
    share_account(c, acc2, "edit", invitee_client=card_editor)
    stranger, _ = register(app_started)
    return Crowd(c, u, acc, acc2, editor, viewer, card_editor, stranger)


# ---------- Connecting ----------

def test_an_unticked_person_is_offered_nothing_and_refused_everywhere(app_started, ms, switched_on):
    c, u = register(app_started, mail=False)
    for path in ("/api/mail", "/api/mail/status"):
        s = c.get(path).json()
        assert s["providers_allowed"] == [] and s["shared"] == [], path
    assert c.get("/api/mail").json()["available"] is True
    r = c.post("/api/mail/microsoft/device", json={})
    assert r.status_code == 403 and "Admin → Users" in r.json()["detail"]
    assert not any(x.url.host == "login.microsoftonline.com" for x in ms.requests)
    r = c.post("/api/mail/microsoft/device/poll")
    assert r.status_code == 403 and "Admin → Users" in r.json()["detail"]
    assert c.get("/api/mail").json()["connected"] is False


def test_the_web_connect_and_its_return_refuse_an_unticked_person(app_started, ms, switched_on, monkeypatch):
    monkeypatch.setenv("MS_CLIENT_SECRET", "test-secret")
    c, u = register(app_started, mail=False)
    r = c.post("/api/mail/microsoft/web", json={})
    assert r.status_code == 403 and "Admin → Users" in r.json()["detail"]
    # Ticked long enough to start, then unticked before coming back: not connected.
    allow_mail(u["id"])
    r = c.post("/api/mail/microsoft/web", json={})
    assert r.status_code == 200, r.text
    from urllib.parse import parse_qs, urlsplit
    state = parse_qs(urlsplit(r.json()["url"]).query)["state"][0]
    allow_mail(u["id"], [])
    r = c.get("/api/mail/microsoft/callback", params={"code": "good-code", "state": state},
              follow_redirects=False)
    assert r.status_code == 303
    assert c.get("/api/mail").json()["connected"] is False


def test_a_tick_taken_away_mid_sign_in_stops_it_finishing(app_started, ms, switched_on):
    c, u = register(app_started)
    assert c.post("/api/mail/microsoft/device", json={}).status_code == 200
    allow_mail(u["id"], [])
    ms.approved = True
    r = c.post("/api/mail/microsoft/device/poll")
    assert r.status_code == 403 and "Admin → Users" in r.json()["detail"]
    assert c.get("/api/mail").json()["connected"] is False


def test_a_tick_lets_a_person_connect(app_started, ms, switched_on):
    c, u = register(app_started, mail=False)
    allow_mail(u["id"])
    assert c.get("/api/mail").json()["providers_allowed"] == ["microsoft"]
    assert c.get("/api/mail/status").json()["providers_allowed"] == ["microsoft"]
    connect_with_code(c, ms)
    assert c.get("/api/mail").json()["connected"] is True


def test_the_microsoft_app_not_being_set_up_offers_nothing_even_when_ticked(
        app_started, ms, switched_on, monkeypatch):
    c, _ = register(app_started)
    assert c.get("/api/mail").json()["providers_allowed"] == ["microsoft"]
    monkeypatch.setenv("MS_CLIENT_ID", "")
    assert c.get("/api/mail").json()["providers_allowed"] == []
    assert c.get("/api/mail/status").json()["providers_allowed"] == []


def test_an_admin_may_always_connect(app_started, admin, ms, switched_on):
    c, u = admin
    allow_mail(u["id"], [])
    assert c.get("/api/mail").json()["providers_allowed"] == ["microsoft"]
    assert c.get("/api/mail/status").json()["providers_allowed"] == ["microsoft"]
    connect_with_code(c, ms)
    assert c.get("/api/mail/status").json().get("paused") is False


def test_the_switch_still_turns_everything_off(app_started, ms):
    c, _ = register(app_started)
    set_switch(False)
    s = c.get("/api/mail").json()
    assert s["enabled"] is False
    assert c.post("/api/mail/microsoft/device", json={}).status_code == 403


# ---------- Admin → Users ----------

def test_an_admin_ticks_and_unticks_microsoft(app_started, admin):
    a, _ = admin
    _, u = register(app_started, mail=False)
    assert set_access(a, u["id"], ["microsoft"]) == {"id": u["id"], "mail_access": ["microsoft"]}
    row = next(x for x in a.get("/api/admin/users").json() if x["id"] == u["id"])
    assert row["mail_access"] == ["microsoft"]
    assert set_access(a, u["id"], [])["mail_access"] == []
    row = next(x for x in a.get("/api/admin/users").json() if x["id"] == u["id"])
    assert row["mail_access"] == []
    assert audit_details("mail_access_changed", like=f"user #{u['id']}:%") == [
        f"user #{u['id']}: Microsoft 365", f"user #{u['id']}: none"]


def test_the_same_list_again_records_nothing(app_started, admin):
    a, _ = admin
    _, u = register(app_started, mail=False)
    set_access(a, u["id"], ["microsoft"])
    set_access(a, u["id"], ["microsoft"])
    assert len(audit_details("mail_access_changed", like=f"user #{u['id']}:%")) == 1
    set_access(a, u["id"], [])
    set_access(a, u["id"], [])
    assert len(audit_details("mail_access_changed", like=f"user #{u['id']}:%")) == 2


def test_mail_access_checks(app_started, admin):
    a, _ = admin
    _, u = register(app_started, mail=False)
    r = a.put(f"/api/admin/users/{u['id']}/mail-access", json={"providers": ["gmail"]})
    assert r.status_code == 400 and "gmail" in r.json()["detail"]
    assert a.put("/api/admin/users/999999999/mail-access", json={"providers": []}).status_code == 404
    assert a.put(f"/api/admin/users/{u['id']}/mail-access", json={}).status_code == 422
    assert audit_details("mail_access_changed", like=f"user #{u['id']}:%") == []


def test_the_demo_user_cant_be_ticked(app_started, admin):
    from app.db import SessionLocal, User
    a, _ = admin
    _, u = register(app_started, mail=False)
    db = SessionLocal()
    try:
        db.get(User, u["id"]).email = f"demo-{u['id']}@demo.walletweather.local"
        db.commit()
    finally:
        db.close()
    r = a.put(f"/api/admin/users/{u['id']}/mail-access", json={"providers": ["microsoft"]})
    assert r.status_code == 400 and "demo" in r.json()["detail"].lower()
    assert set_access(a, u["id"], [])["mail_access"] == []


def test_only_an_admin_in_a_browser_may_tick(app_started, admin):
    from fastapi.testclient import TestClient
    from app import main
    from app.db import SessionLocal
    a, _ = admin
    c, u = register(app_started, mail=False)
    assert c.put(f"/api/admin/users/{u['id']}/mail-access",
                 json={"providers": ["microsoft"]}).status_code == 403
    # An admin API token is refused too, like the Email alerts switch.
    r = a.post("/api/tokens", json={"name": "t", "access": "admin"})
    assert r.status_code == 200, r.text
    tok = TestClient(main.app, headers={"Authorization": f"Bearer {r.json()['token']}"})
    assert tok.put(f"/api/admin/users/{u['id']}/mail-access",
                   json={"providers": ["microsoft"]}).status_code == 403
    db = SessionLocal()
    try:
        assert main.mail_access(db, db.get(main.User, u["id"])) == set()
    finally:
        db.close()


# ---------- Unticking pauses ----------

def test_unticking_pauses_the_mailbox_and_ticking_again_carries_on(app_started, admin, taught, ms):
    a, _ = admin
    c, u, acc = taught
    only_these_users_due(u["id"])
    assert c.get("/api/mail/status").json()["paused"] is False
    assert c.get("/api/mail/status").json()["next_check_at"] is not None
    set_access(a, u["id"], [])
    for path in ("/api/mail", "/api/mail/status"):
        s = c.get(path).json()
        assert s["connected"] is True and s["paused"] is True and s["providers_allowed"] == [], path
        assert s["next_check_at"] is None, path
    # Kept, not deleted: the mailbox and its senders are still there.
    assert len(c.get("/api/mail").json()["senders"]) == 1
    r = c.post("/api/mail/check", json={})
    assert r.status_code == 403 and "paused" in r.json()["detail"]
    before = len(ms.requests)
    assert run_due()["checked"] == 0
    assert run_due(now=datetime.utcnow() + timedelta(days=1))["checked"] == 0
    assert len(ms.requests) == before        # the scheduled check left it alone
    assert lines(c, acc) == []
    # Tick again: it carries on.
    set_access(a, u["id"], ["microsoft"])
    s = c.get("/api/mail/status").json()
    assert s["paused"] is False and s["next_check_at"] is not None
    assert run_due()["checked"] == 1
    assert [t["description"] for t in lines(c, acc)] == ["STARBUCKS #123"]
    assert c.post("/api/mail/check", json={}).status_code in (200, 429)


def test_an_admin_is_never_paused(app_started, admin, ms, switched_on):
    c, u = admin
    connect_with_code(c, ms)
    allow_mail(u["id"], [])
    assert c.get("/api/mail/status").json()["paused"] is False


# ---------- The upgrade ----------

def test_the_upgrade_ticks_whoever_has_a_mailbox_once(app_started, connected, admin):
    from app import main
    from app.db import AdminSetting, SessionLocal, init_db
    a, _ = admin
    c, u, _ = connected
    _, bystander = register(app_started, mail=False)
    allow_mail(u["id"], [])          # as before the upgrade: no ticks at all
    db = SessionLocal()
    try:
        row = db.get(AdminSetting, "mail_access_seeded")
        if row:
            db.delete(row)
        db.commit()
    finally:
        db.close()
    init_db()
    db = SessionLocal()
    try:
        assert main.mail_access(db, db.get(main.User, u["id"])) == {"microsoft"}
        assert main.mail_access(db, db.get(main.User, bystander["id"])) == set()
    finally:
        db.close()
    # An admin unticks them; the next start doesn't tick them again.
    set_access(a, u["id"], [])
    init_db()
    db = SessionLocal()
    try:
        assert main.mail_access(db, db.get(main.User, u["id"])) == set()
    finally:
        db.close()


# ---------- Shared accounts: status ----------

def test_an_editor_sees_the_account_the_mailbox_feeds(crowd):
    for path in ("/api/mail", "/api/mail/status"):
        (e,) = shared_of(crowd.editor, crowd.acc, path)
        assert set(e) == SHARED_KEYS, path
        assert e["account_name"] == "Checking" and e["archived"] is False
        assert e["level"] == "edit" and e["mine"] is False
        assert e["holder_name"] == HOLDER_NAME
        assert e["provider"] == "microsoft" and e["provider_name"] == "Microsoft 365"
        # The crowd's mailbox was "checked" 5 minutes ago (not_due_for_an_hour),
        # with no result recorded.
        assert e["last_check_at"].endswith("Z") and e["last_check_ok"] is None
        assert e["needs_reconnect"] is False and e["paused"] is False
        assert e["holder_disabled"] is False and e["next_check_at"] is not None
        assert e["unmatched_count"] == 0
    # Only that account: the holder's card account isn't theirs to see.
    assert [x["account_id"] for x in crowd.editor.get("/api/mail").json()["shared"]] == [crowd.acc]


def test_an_editor_of_a_card_account_sees_it_too(crowd):
    (e,) = shared_of(crowd.card_editor, crowd.acc2)
    assert e["account_name"] == "Card 9876" and e["level"] == "edit" and e["holder_name"] == HOLDER_NAME
    assert [x["account_id"] for x in crowd.card_editor.get("/api/mail/status").json()["shared"]] == [crowd.acc2]


def test_shared_never_says_the_holders_senders_folder_or_address(crowd):
    for who in (crowd.editor, crowd.card_editor):
        for path in ("/api/mail", "/api/mail/status"):
            body = who.get(path).json()
            assert body["connected"] is False
            for key in ("senders", "folder", "address", "unread_count", "unmatched"):
                assert key not in body, (path, key)
            text = who.get(path).text
            assert BANK not in text and "me@outlook.example" not in text and "Bank alerts" not in text
            assert "Test Bank" not in text and "ALERTS" not in text


def test_read_only_people_and_strangers_get_no_shared_account(crowd):
    for who, c in crowd.no_access():
        assert c.get("/api/mail").json()["shared"] == [], who
        assert c.get("/api/mail/status").json()["shared"] == [], who


def test_the_holders_own_shared_list_is_empty(crowd):
    assert crowd.c.get("/api/mail").json()["shared"] == []
    assert crowd.c.get("/api/mail/status").json()["shared"] == []


def test_an_account_no_mailbox_feeds_isnt_listed(crowd):
    loose = make_account(crowd.c, "Not fed")
    share_account(crowd.c, loose, "edit", invitee_client=crowd.editor)
    assert shared_of(crowd.editor, loose) == []


def test_shared_follows_a_pause_and_a_disabled_holder(crowd, admin):
    a, _ = admin
    set_access(a, crowd.u["id"], [])
    (e,) = shared_of(crowd.editor, crowd.acc)
    assert e["paused"] is True and e["next_check_at"] is None
    set_access(a, crowd.u["id"], ["microsoft"])
    set_disabled(crowd.u["id"], True)
    try:
        (e,) = shared_of(crowd.editor, crowd.acc)
        assert e["holder_disabled"] is True and e["paused"] is False
    finally:
        set_disabled(crowd.u["id"], False)
    assert shared_of(crowd.editor, crowd.acc)[0]["holder_disabled"] is False


def test_shared_says_how_the_last_check_went_and_the_unmatched_count(crowd, ms):
    ms.alert("a1", amount="12.00", merchant="SHELL OIL 5566")
    assert crowd.c.post("/api/mail/check", json={}).status_code == 200
    (e,) = shared_of(crowd.editor, crowd.acc)
    assert e["last_check_ok"] is True and e["last_check_at"].endswith("Z")
    assert e["unmatched_count"] == 2          # both alert lines paid no bill
    assert shared_of(crowd.editor, crowd.acc, "/api/mail/status")[0]["unmatched_count"] == 2


def test_a_changed_level_shows_in_shared(crowd):
    share_account(crowd.c, crowd.acc2, "edit", invitee_client=crowd.viewer)
    assert shared_of(crowd.viewer, crowd.acc2)[0]["level"] == "edit"
    assert shared_of(crowd.viewer, crowd.acc) == []


def test_an_archived_account_is_marked_in_shared(crowd):
    r = crowd.c.patch(f"/api/accounts/{crowd.acc}", json={"archived": True})
    assert r.status_code == 200, r.text
    assert shared_of(crowd.editor, crowd.acc)[0]["archived"] is True


# ---------- Check now by account ----------

def test_an_editor_checks_the_account_and_only_its_lines_are_counted(crowd, ms):
    ms.alert("a1", amount="12.00", merchant="SHELL OIL 5566", card="1234")
    ms.alert("a2", amount="7.25", merchant="CORNER GROCERY", card="9876")
    r = crowd.editor.post("/api/mail/check", json={"account_id": crowd.acc})
    assert r.status_code == 200, r.text
    body = r.json()
    assert (body["added"], body["matched"]) == (2, 0)      # the sample and a1: not a2
    assert body["status"]["shared"][0]["account_id"] == crowd.acc
    assert body["status"]["connected"] is False
    entry = body["account"]
    assert set(entry) == SHARED_KEYS
    assert entry["account_id"] == crowd.acc and entry["level"] == "edit" and entry["mine"] is False
    assert entry["last_check_ok"] is True and entry["holder_name"] == HOLDER_NAME
    # The check read the whole mailbox, as its person: a2 landed in the card account.
    assert sorted(t["description"] for t in lines(crowd.c, crowd.acc)) == ["SHELL OIL 5566", "STARBUCKS #123"]
    assert [t["description"] for t in lines(crowd.c, crowd.acc2)] == ["CORNER GROCERY"]
    # And it is the mailbox's log, with the holder's name on nothing of the editor's.
    (run,) = crowd.c.get("/api/mail/checks").json()
    assert (run["added"], run["trigger"]) == (3, "manual")


def test_an_editor_of_the_card_account_counts_only_that_accounts_lines(crowd, ms):
    ms.alert("a2", amount="7.25", merchant="CORNER GROCERY", card="9876")
    r = crowd.card_editor.post("/api/mail/check", json={"account_id": crowd.acc2})
    assert r.status_code == 200, r.text
    assert r.json()["added"] == 1 and r.json()["account"]["account_id"] == crowd.acc2
    assert len(lines(crowd.c, crowd.acc)) == 1          # the sample landed there too


def test_the_owner_can_check_by_account_too(crowd):
    r = crowd.c.post("/api/mail/check", json={"account_id": crowd.acc})
    assert r.status_code == 200, r.text
    assert r.json()["added"] == 1 and r.json()["account"]["mine"] is True


def test_the_run_is_the_mailboxs_and_manual(crowd):
    assert crowd.editor.post("/api/mail/check", json={"account_id": crowd.acc}).status_code == 200
    assert crowd.c.get("/api/mail/checks").json()[0]["trigger"] == "manual"
    assert crowd.c.get("/api/mail").json()["last_check_ok"] is True


def test_read_only_and_strangers_cant_check_the_account(crowd, ms):
    before = len(ms.requests)
    for who, c in crowd.no_access():
        r = c.post("/api/mail/check", json={"account_id": crowd.acc})
        assert r.status_code in (403, 404), who
    assert len(ms.requests) == before
    assert crowd.c.get("/api/mail/checks").json() == []
    # An editor of the card account can't use the other account.
    assert crowd.card_editor.post("/api/mail/check", json={"account_id": crowd.acc}).status_code in (403, 404)


def test_an_account_no_mailbox_feeds_is_a_400(crowd):
    loose = make_account(crowd.editor, "Not fed")
    r = crowd.editor.post("/api/mail/check", json={"account_id": loose})
    assert r.status_code == 400 and "No mailbox" in r.json()["detail"]


def test_an_unknown_account_is_refused(crowd):
    assert crowd.editor.post("/api/mail/check", json={"account_id": 999999999}).status_code in (403, 404)


def test_a_disabled_holder_refuses_the_editor(crowd, ms):
    set_disabled(crowd.u["id"], True)
    try:
        before = len(ms.requests)
        r = crowd.editor.post("/api/mail/check", json={"account_id": crowd.acc})
        assert r.status_code == 403 and "can't sign in" in r.json()["detail"]
        assert len(ms.requests) == before
    finally:
        set_disabled(crowd.u["id"], False)


def test_a_paused_mailbox_refuses_the_editor_and_names_the_holder(crowd, admin, ms):
    a, _ = admin
    set_access(a, crowd.u["id"], [])
    before = len(ms.requests)
    r = crowd.editor.post("/api/mail/check", json={"account_id": crowd.acc})
    assert r.status_code == 403
    assert HOLDER_NAME in r.json()["detail"] and "paused" in r.json()["detail"]
    r = crowd.c.post("/api/mail/check", json={"account_id": crowd.acc})
    assert r.status_code == 403 and "paused" in r.json()["detail"] and HOLDER_NAME not in r.json()["detail"]
    assert len(ms.requests) == before
    set_access(a, crowd.u["id"], ["microsoft"])
    assert crowd.editor.post("/api/mail/check", json={"account_id": crowd.acc}).status_code == 200


def test_the_switch_being_off_refuses_the_editor(crowd):
    set_switch(False)
    r = crowd.editor.post("/api/mail/check", json={"account_id": crowd.acc})
    assert r.status_code == 403 and "switched off" in r.json()["detail"]


def test_the_holders_gap_between_checks_applies_to_the_editor(crowd):
    assert crowd.editor.post("/api/mail/check", json={"account_id": crowd.acc}).status_code == 200
    r = crowd.editor.post("/api/mail/check", json={"account_id": crowd.acc})
    assert r.status_code == 429 and r.headers["Retry-After"]


def test_an_editors_plain_check_has_no_mailbox_to_check(crowd):
    r = crowd.editor.post("/api/mail/check", json={})
    assert r.status_code in (400, 404)


# ---------- A mailbox doesn't pass on ----------

def test_deleting_the_holder_takes_the_shared_entry_away(app_started, taught, ms):
    c, u, acc = taught
    editor, _ = register(app_started)
    # An account the editor owns (the holder an owner of it too), fed by the holder's card.
    mine = make_account(editor, "Editor's own")
    share_account(editor, mine, "owner", invitee_client=c)
    sender = c.get("/api/mail").json()["senders"][0]
    r = c.put(f"/api/mail/senders/{sender['id']}", json={"cards": {"5555": mine}})
    assert r.status_code == 200, r.text
    assert shared_of(editor, mine)
    r = c.request("DELETE", "/api/me", json={"password": u["password"]})
    assert r.status_code == 200, r.text
    assert shared_of(editor, mine) == []
    assert shared_of(editor, mine, "/api/mail/status") == []
    r = editor.post("/api/mail/check", json={"account_id": mine})
    assert r.status_code == 400 and "No mailbox" in r.json()["detail"]
