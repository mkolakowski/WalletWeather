"""Reconnecting a mailbox in place, keeping the banks taught (#394).

A sign-in that stopped working (a revoked app password, a lapsed Google or
Microsoft sign-in) is renewed on the same connection row: its senders,
kinds, cards, folder, start date, couldn't-read list and check log stay, the
address has to be the same one, and a two-factor code is needed as for
connecting. Every call goes to the stand-ins from test_mail_alerts.py (Microsoft),
test_mail_alerts_gmail.py (the IMAP server and Google), never the network.
"""
import json
from datetime import datetime, timezone
from urllib.parse import parse_qs, urlsplit

import httpx
import pytest
from fastapi.testclient import TestClient

from test_mail_alerts import (BANK, _age_last_check, allow_mail, connect_with_code,  # noqa: F401
                              connected, lines, make_account, ms, register, switched_on, taught, teach)
from test_mail_alerts_gmail import (CLEAN_PASSWORD, YESTERDAY, FakeGoogle, build_mail, connect_gmail,  # noqa: F401
                                    connect_imap, gmail_connected, google, imap, imap_connected,
                                    set_tokens, start_gmail, teach_mail)
from test_mail_access import audit_details

NEW_APP_PASSWORD = "wxyz wxyz wxyz wxyz"      # as Google shows it
NEW_CLEAN = "wxyzwxyzwxyzwxyz"


def row_of(user_id):
    from app.db import MailConnection, SessionLocal
    db = SessionLocal()
    try:
        r = db.query(MailConnection).filter_by(user_id=user_id).first()
        return None if r is None else (r.id, r.tokens_enc, r.folder_id, r.start_date, r.needs_reconnect)
    finally:
        db.close()


def stored(user_id) -> dict:
    from app.db import decrypt_str
    from test_mail_alerts import connection_row
    return json.loads(decrypt_str(connection_row(user_id).tokens_enc))


def senders_of(c):
    return [(s["address"], [k["fields"] for k in s["kinds"]]) for s in c.get("/api/mail").json()["senders"]]


def tick_all(user_id):
    allow_mail(user_id, ("microsoft", "gmail", "imap"))


# ---------- IMAP ----------

def test_imap_a_new_app_password_renews_in_place(imap_connected, imap):
    c, u, acc = imap_connected
    teach_mail(c, acc, imap.add("sample"))
    assert c.post("/api/mail/check", json={}).json()["added"] == 1
    # Google revokes the app password; the person makes a new one.
    imap.password = NEW_CLEAN
    _age_last_check(u["id"])
    r = c.post("/api/mail/check", json={})
    assert r.status_code == 409
    assert c.get("/api/mail").json()["needs_reconnect"] is True
    before = row_of(u["id"])
    senders, log = senders_of(c), c.get("/api/mail/checks").json()
    assert senders and log
    r = c.post("/api/mail/imap/password", json={"password": NEW_APP_PASSWORD})
    assert r.status_code == 200, r.text
    st = r.json()
    assert st["needs_reconnect"] is False and st["connected"] and st["provider"] == "imap"
    assert NEW_CLEAN not in r.text and "wxyz" not in r.text
    after = row_of(u["id"])
    # The same row, folder and start date; only the sign-in changed.
    assert after[0] == before[0] and after[2:4] == before[2:4] and after[4] is False
    assert after[1] != before[1]
    assert stored(u["id"]) == {"host": "imap.gmail.com", "user": "me@gmail.com", "password": NEW_CLEAN}
    assert b"wxyz" not in after[1]
    # What was taught, and the log, are kept.
    assert senders_of(c) == senders and c.get("/api/mail/checks").json() == log
    assert c.get("/api/mail/status").json()["next_check_at"] is not None
    assert len(audit_details("mail_reconnected", u["id"])) == 1
    # And an alert lands afterwards.
    imap.add("a2", amount="7.00", merchant="CAFE LUNA")
    _age_last_check(u["id"])
    r = c.post("/api/mail/check", json={})
    assert r.status_code == 200, r.text
    assert r.json()["added"] == 1
    assert sorted(t["amount"] for t in lines(c, acc)) == [-7.0, -4.5]


def test_imap_a_wrong_new_password_changes_nothing(imap_connected, imap):
    c, u, acc = imap_connected
    teach_mail(c, acc, imap.add("sample"))
    imap.password = NEW_CLEAN
    assert c.post("/api/mail/check", json={}).status_code == 409
    before = row_of(u["id"])
    r = c.post("/api/mail/imap/password", json={"password": "still the old one"})
    assert r.status_code == 400
    assert "didn't accept the address and app password" in r.json()["detail"]
    assert "stilltheoldone" not in r.text and "still the old one" not in r.text
    assert row_of(u["id"]) == before and before[4] is True
    assert stored(u["id"])["password"] == CLEAN_PASSWORD
    assert c.get("/api/mail").json()["needs_reconnect"] is True
    assert audit_details("mail_reconnected", u["id"]) == []


def test_imap_password_with_no_mailbox_or_a_microsoft_one(app_started, imap, ms, switched_on, connected):
    c0, u0 = register(app_started, mail=False)
    tick_all(u0["id"])
    r = c0.post("/api/mail/imap/password", json={"password": NEW_APP_PASSWORD})
    assert r.status_code == 404 and imap.factory_calls == []
    c, u, acc = connected                      # a Microsoft mailbox
    tick_all(u["id"])
    before = row_of(u["id"])
    r = c.post("/api/mail/imap/password", json={"password": NEW_APP_PASSWORD})
    assert r.status_code == 409 and imap.factory_calls == []
    assert row_of(u["id"]) == before


# ---------- Microsoft ----------

def _other_address(monkeypatch, module, base_handler, path, payload, on: dict):
    """The stand-in answers `path` with another address while on["on"]."""
    def handler(request):
        if on["on"] and request.url.path == path:
            return httpx.Response(200, json=payload)
        return base_handler(request)
    monkeypatch.setattr(module, "_transport", httpx.MockTransport(handler))


def _lapse_microsoft(c, u, ms):
    set_tokens(u["id"], {"access": ms.access, "refresh": ms.refresh, "expires_at": 0})
    ms.revoked = True
    r = c.post("/api/mail/check", json={})
    assert r.status_code == 409, r.text
    assert c.get("/api/mail").json()["needs_reconnect"] is True


def test_microsoft_a_new_sign_in_with_a_code_renews_in_place(taught, ms, monkeypatch):
    from app import mailbox
    import app.main as main
    c, u, acc = taught
    _lapse_microsoft(c, u, ms)
    before = row_of(u["id"])
    senders, log = senders_of(c), c.get("/api/mail/checks").json()
    other = {"on": True}
    _other_address(monkeypatch, mailbox, ms.handler, "/v1.0/me",
                   {"mail": "someone.else@outlook.example", "userPrincipalName": "x@outlook.example"}, other)
    # Signing in to a different address is refused at the poll, and nothing changes.
    r = c.post("/api/mail/microsoft/device", json={"reconnect": True})
    assert r.status_code == 200, r.text
    ms.approved, ms.revoked = True, False
    r = c.post("/api/mail/microsoft/device/poll")
    assert r.status_code == 409
    assert "someone.else@outlook.example" in r.json()["detail"] and "Nothing was changed" in r.json()["detail"]
    assert "disconnect" in r.json()["detail"]
    assert row_of(u["id"]) == before
    assert senders_of(c) == senders
    # The right one renews it.
    other["on"] = False
    assert c.post("/api/mail/microsoft/device", json={"reconnect": True}).status_code == 200
    main._mail_pending[u["id"]]["next"] = 0
    r = c.post("/api/mail/microsoft/device/poll")
    assert r.status_code == 200 and r.json()["status"] == "connected", r.text
    assert r.json()["needs_reconnect"] is False and r.json()["address"] == "me@outlook.example"
    after = row_of(u["id"])
    assert after[0] == before[0] and after[2:4] == before[2:4] and after[4] is False and after[1] != before[1]
    assert senders_of(c) == senders and c.get("/api/mail/checks").json() == log
    assert len(audit_details("mail_reconnected", u["id"])) == 1
    ms.alert("a1", amount="3.00", merchant="CAFE LUNA")
    _age_last_check(u["id"])
    assert c.post("/api/mail/check", json={}).status_code == 200
    assert any(t["amount"] == -3.0 for t in lines(c, acc))


def test_microsoft_the_connect_button_renews_in_place(taught, ms, monkeypatch):
    c, u, acc = taught
    monkeypatch.setenv("MS_CLIENT_SECRET", "test-secret")
    _lapse_microsoft(c, u, ms)
    ms.revoked = False
    before = row_of(u["id"])
    senders = senders_of(c)
    r = c.post("/api/mail/microsoft/web", json={"reconnect": True})
    assert r.status_code == 200, r.text
    state = parse_qs(urlsplit(r.json()["url"]).query)["state"][0]
    r = c.get("/api/mail/microsoft/callback", params={"code": "good-code", "state": state},
              follow_redirects=False)
    assert r.status_code == 303 and r.headers["location"] == "/#settings/mail"
    st = c.get("/api/mail").json()
    assert "connect_error" not in st and st["needs_reconnect"] is False and st["auth_mode"] == "web"
    after = row_of(u["id"])
    assert after[0] == before[0] and after[1] != before[1] and after[2] == before[2]
    assert senders_of(c) == senders
    assert len(audit_details("mail_reconnected", u["id"])) == 1


# ---------- Gmail ----------

def _lapse_gmail(c, u, google):
    set_tokens(u["id"], {"access": "stale", "refresh": "grefresh-0", "expires_at": 0})
    google.invalid_grant = True
    r = c.post("/api/mail/check", json={})
    assert r.status_code == 409, r.text
    assert c.get("/api/mail").json()["needs_reconnect"] is True
    google.invalid_grant = False


def test_gmail_connect_renews_in_place_after_a_lapsed_sign_in(gmail_connected, google):
    c, u, acc = gmail_connected
    teach_mail(c, acc, google.add("sample"))
    _lapse_gmail(c, u, google)
    before = row_of(u["id"])
    senders, log = senders_of(c), c.get("/api/mail/checks").json()
    _, q = start_gmail_reconnect(c)
    r = c.get("/api/mail/gmail/callback", params={"code": "good-code", "state": q["state"][0]},
              follow_redirects=False)
    assert r.status_code == 303 and r.headers["location"] == "/#settings/mail"
    st = c.get("/api/mail").json()
    assert "connect_error" not in st and st["needs_reconnect"] is False and st["provider"] == "gmail"
    after = row_of(u["id"])
    assert after[0] == before[0] and after[1] != before[1] and after[2:4] == before[2:4] and after[4] is False
    assert stored(u["id"])["refresh"] == "grefresh-0" and stored(u["id"])["access"] == google.access
    assert senders_of(c) == senders and c.get("/api/mail/checks").json() == log
    assert len(audit_details("mail_reconnected", u["id"])) == 1
    _age_last_check(u["id"])
    r = c.post("/api/mail/check", json={})
    assert r.status_code == 200, r.text
    assert r.json()["added"] == 1 and [t["amount"] for t in lines(c, acc)] == [-4.5]


def start_gmail_reconnect(c):
    r = c.post("/api/mail/gmail/web", json={"reconnect": True})
    assert r.status_code == 200, r.text
    return r.json()["url"], parse_qs(urlsplit(r.json()["url"]).query)


def test_gmail_a_different_google_address_is_refused(gmail_connected, google, monkeypatch):
    from app import gmail
    c, u, acc = gmail_connected
    teach_mail(c, acc, google.add("sample"))
    _lapse_gmail(c, u, google)
    before = row_of(u["id"])
    senders = senders_of(c)
    _other_address(monkeypatch, gmail, google.handler, "/gmail/v1/users/me/profile",
                   {"emailAddress": "someone.else@gmail.example"}, {"on": True})
    _, q = start_gmail_reconnect(c)
    r = c.get("/api/mail/gmail/callback", params={"code": "good-code", "state": q["state"][0]},
              follow_redirects=False)
    assert r.status_code == 303
    st = c.get("/api/mail").json()
    assert "someone.else@gmail.example" in st["connect_error"] and "Nothing was changed" in st["connect_error"]
    assert st["needs_reconnect"] is True
    assert row_of(u["id"]) == before and senders_of(c) == senders
    assert audit_details("mail_reconnected", u["id"]) == []


# ---------- Which mailbox ----------

def test_reconnecting_with_no_mailbox_is_a_404(app_started, imap, ms, google, switched_on, monkeypatch):
    monkeypatch.setenv("MS_CLIENT_SECRET", "test-secret")
    c, u = register(app_started, mail=False)
    tick_all(u["id"])
    for path in ("/api/mail/microsoft/device", "/api/mail/microsoft/web", "/api/mail/gmail/web"):
        r = c.post(path, json={"reconnect": True})
        assert r.status_code == 404, (path, r.text)
        assert "No mailbox" in r.json()["detail"]
    assert ms.requests == [] and google.requests == []


def test_reconnecting_a_mailbox_connected_another_way_is_a_409(imap_connected, imap, ms, google, monkeypatch):
    monkeypatch.setenv("MS_CLIENT_SECRET", "test-secret")
    c, u, acc = imap_connected
    tick_all(u["id"])
    before = row_of(u["id"])
    for path in ("/api/mail/gmail/web", "/api/mail/microsoft/device", "/api/mail/microsoft/web"):
        r = c.post(path, json={"reconnect": True})
        assert r.status_code == 409, (path, r.text)
        assert "connected through" in r.json()["detail"]
    assert ms.requests == [] and google.requests == []
    assert row_of(u["id"]) == before


# ---------- Two-factor, and who may ----------

def test_with_two_factor_on_the_imap_password_needs_a_code(imap_connected, imap):
    from test_two_factor_actions import fresh_code, turn_on
    c, u, acc = imap_connected
    secret, _ = turn_on(c, u)
    imap.password = NEW_CLEAN
    n = len(imap.factory_calls)
    r = c.post("/api/mail/imap/password", json={"password": NEW_APP_PASSWORD})
    assert r.status_code == 403 and len(imap.factory_calls) == n
    assert stored(u["id"])["password"] == CLEAN_PASSWORD
    r = c.post("/api/mail/imap/password", json={"password": NEW_APP_PASSWORD,
                                                "code": fresh_code(u["email"], secret)})
    assert r.status_code == 200, r.text
    assert stored(u["id"])["password"] == NEW_CLEAN


def test_with_two_factor_on_reconnecting_gmail_needs_a_code(gmail_connected, google):
    from test_two_factor_actions import fresh_code, turn_on
    c, u, acc = gmail_connected
    secret, _ = turn_on(c, u)
    n = len(google.requests)
    assert c.post("/api/mail/gmail/web", json={"reconnect": True}).status_code == 403
    assert len(google.requests) == n
    r = c.post("/api/mail/gmail/web", json={"reconnect": True, "code": fresh_code(u["email"], secret)})
    assert r.status_code == 200, r.text
    assert urlsplit(r.json()["url"]).hostname == "accounts.google.com"


def test_an_api_token_cannot_change_the_app_password(imap_connected, imap, app_started):
    c, u, acc = imap_connected
    tok = c.post("/api/tokens", json={"name": "t", "access": "full", "expires_in_days": 30}).json()["token"]
    bearer = TestClient(app_started, headers={"Authorization": f"Bearer {tok}"})
    n, before = len(imap.factory_calls), row_of(u["id"])
    assert bearer.post("/api/mail/imap/password", json={"password": NEW_APP_PASSWORD}).status_code == 403
    assert len(imap.factory_calls) == n and row_of(u["id"]) == before


def test_the_demo_user_cannot_change_the_app_password(imap_connected, imap, monkeypatch):
    import app.main as main
    c, u, acc = imap_connected
    monkeypatch.setattr(main, "is_demo_email", lambda e: e == u["email"])
    n, before = len(imap.factory_calls), row_of(u["id"])
    r = c.post("/api/mail/imap/password", json={"password": NEW_APP_PASSWORD})
    assert r.status_code == 403 and "demo" in r.json()["detail"]
    assert len(imap.factory_calls) == n and row_of(u["id"]) == before


def test_someone_not_ticked_for_imap_cannot_change_the_app_password(imap_connected, imap):
    c, u, acc = imap_connected
    allow_mail(u["id"], ("microsoft",))
    n, before = len(imap.factory_calls), row_of(u["id"])
    r = c.post("/api/mail/imap/password", json={"password": NEW_APP_PASSWORD})
    assert r.status_code == 403
    assert len(imap.factory_calls) == n and row_of(u["id"]) == before
