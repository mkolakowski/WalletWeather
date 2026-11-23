"""Each person's own Teller and Plaid keys (own-bank-keys phase 1, #276).

Every call goes to the stand-in Teller or Plaid from test_bank_providers.py,
never the network. Covers saving, replacing and removing keys (checked with
the provider first, never sent back), the refusal while connections use
them, which keys each call is made with (a connection's own copy, or the
person's own for a new connection), the one-time copy of .env's keys on the
upgrade to schema 38, sealed backups carrying the keys and plain exports
not, Teller's certificate reaching httpx through app-only files, and no
response, audit line or log line carrying a secret.
"""
import base64
import io
import json
import logging
import os
import stat
import zipfile
from datetime import datetime, timedelta

import httpx
import pytest

from test_bank_providers import (BACKUP_PASSPHRASE, FakePlaid, PLAID_KEYS_SANDBOX, TELLER_TOKEN,  # noqa: F401
                                 connect_plaid, connect_teller, linked, no_provider_keys, plaid_fake,
                                 switched_on, teller_fake)
from test_bank_sync import allow_bank, give_keys, register, set_switch

PLAID_SECRET = "plaid_secret"
ROTATED_SECRET = "plaid_secret_rotated"


# ---------- Helpers ----------

def make_pair():
    """A self-signed certificate and its private key, in PEM, as Teller's
    zip holds them."""
    from cryptography import x509
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import ec
    from cryptography.x509.oid import NameOID
    key = ec.generate_private_key(ec.SECP256R1())
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "walletweather-test")])
    now = datetime.utcnow()
    cert = (x509.CertificateBuilder().subject_name(name).issuer_name(name)
            .public_key(key.public_key()).serial_number(x509.random_serial_number())
            .not_valid_before(now - timedelta(days=1)).not_valid_after(now + timedelta(days=30))
            .sign(key, hashes.SHA256()))
    return (cert.public_bytes(serialization.Encoding.PEM).decode(),
            key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                              serialization.NoEncryption()).decode())


def teller_zip(cert, key, folder="teller/") -> str:
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as z:
        if cert is not None:
            z.writestr(folder + "certificate.pem", cert)
        if key is not None:
            z.writestr(folder + "private_key.pem", key)
    return base64.b64encode(buf.getvalue()).decode()


def save_plaid(c, client_id="plaid_client", secret=PLAID_SECRET, environment="sandbox", **extra):
    return c.put("/api/bank/keys/plaid", json={"client_id": client_id, "secret": secret,
                                               "environment": environment, **extra})


def save_teller(c, **body):
    body.setdefault("application_id", "app_mine")
    return c.put("/api/bank/keys/teller", json=body)


def remove_keys(c, provider, **extra):
    return c.post("/api/bank/keys/remove", json={"provider": provider, **extra})


def events(email):
    from app.db import AuditEvent, SessionLocal
    db = SessionLocal()
    try:
        return [(r.event, r.detail) for r in
                db.query(AuditEvent).filter_by(email=email.lower()).order_by(AuditEvent.id)]
    finally:
        db.close()


def own_row(user_id, provider):
    from app.db import BankKeys, SessionLocal
    db = SessionLocal()
    try:
        row = db.get(BankKeys, (user_id, provider))
        if row is not None:
            db.expunge(row)
        return row
    finally:
        db.close()


def connection_copy(connection_id):
    """A connection's own copy of its keys, as bank_keys reads it."""
    from app import bank_keys
    from app.db import BankConnection, SessionLocal
    db = SessionLocal()
    try:
        conn = db.get(BankConnection, connection_id)
        return bank_keys._from_json(conn.provider, bank_keys.decrypt_str(conn.keys_enc)) \
            if conn.keys_enc else None
    finally:
        db.close()


@pytest.fixture
def fresh(app_started, switched_on):
    """A signed-in person ticked for every provider, with no keys."""
    return register(app_started)


@pytest.fixture
def plaid_stand_in(monkeypatch):
    """The stand-in Plaid without handing anyone keys."""
    from app import plaid
    f = FakePlaid()
    monkeypatch.setattr(plaid, "_transport", httpx.MockTransport(f.handler))
    return f


@pytest.fixture
def teller_stand_in(monkeypatch):
    from app import teller
    from test_bank_providers import FakeTeller
    f = FakeTeller()
    monkeypatch.setattr(teller, "_transport", httpx.MockTransport(f.handler))
    return f


# ---------- Saving Plaid keys ----------

def test_saving_plaid_keys_checks_them_and_never_sends_the_secret_back(fresh, plaid_stand_in):
    c, u = fresh
    r = save_plaid(c)
    assert r.status_code == 200, r.text
    assert PLAID_SECRET not in r.text
    got = r.json()["keys"]["plaid"]
    assert got["id"] == "plaid_client" and got["environment"] == "sandbox"
    assert got["checked_at"].endswith("Z") and got["saved_at"].endswith("Z") and got["in_use"] == []
    assert r.json()["keys"]["teller"] is None
    # Checked with Plaid, with these keys.
    assert plaid_stand_in.bodies_for("/institutions/get")
    assert plaid_stand_in.keys_seen[-1] == ("plaid_client", PLAID_SECRET)
    st = c.get("/api/bank")
    assert PLAID_SECRET not in st.text and st.json()["keys"]["plaid"]["id"] == "plaid_client"
    assert "plaid" in c.get("/api/bank/status").json()["providers_allowed"]
    assert ("bank_keys_saved", "Plaid, sandbox") in events(u["email"])


def test_plaid_keys_plaid_refuses_are_not_saved(fresh, plaid_stand_in):
    c, u = fresh
    r = save_plaid(c, secret="wrong_secret")
    assert r.status_code == 400 and "didn't accept" in r.json()["detail"]
    assert "wrong_secret" not in r.text
    assert own_row(u["id"], "plaid") is None
    assert "plaid" not in c.get("/api/bank/status").json()["providers_allowed"]


@pytest.mark.parametrize("body", [
    {"client_id": "plaid_client"},                                       # no secret
    {"client_id": "", "secret": "x"},                                    # empty id
    {"client_id": "plaid_client", "secret": "x", "environment": "dev"},  # not an environment
    {"client_id": "plaid client", "secret": "x"},                        # not an id
])
def test_plaid_keys_that_dont_read_as_keys_are_refused(fresh, plaid_stand_in, body):
    c, _ = fresh
    assert c.put("/api/bank/keys/plaid", json=body).status_code == 422
    assert plaid_stand_in.requests == []


def test_keys_need_the_switch_and_a_tick(app_started, plaid_stand_in):
    c, u = register(app_started)
    set_switch(False)
    r = save_plaid(c)
    assert r.status_code == 403 and "switched off" in r.json()["detail"]
    set_switch(True)
    try:
        allow_bank(u["id"], ["simplefin"])
        r = save_plaid(c)
        assert r.status_code == 403 and "Admin → Users" in r.json()["detail"]
        assert plaid_stand_in.requests == []
    finally:
        set_switch(False)


def test_keys_need_a_fresh_two_factor_code(fresh, plaid_stand_in):
    from test_two_factor_actions import fresh_code, turn_on
    c, u = fresh
    secret, _ = turn_on(c, u)
    r = save_plaid(c)
    assert r.status_code == 403 and own_row(u["id"], "plaid") is None
    r = save_plaid(c, code=fresh_code(u["email"], secret))
    assert r.status_code == 200, r.text
    r = remove_keys(c, "plaid")
    assert r.status_code == 403 and own_row(u["id"], "plaid") is not None
    assert remove_keys(c, "plaid", code=fresh_code(u["email"], secret)).status_code == 200


# ---------- Saving Teller keys ----------

def test_teller_keys_from_the_zip(fresh, teller_stand_in):
    c, u = fresh
    cert, key = make_pair()
    r = save_teller(c, environment="development", zip_base64=teller_zip(cert, key))
    assert r.status_code == 200, r.text
    assert "BEGIN" not in r.text
    got = r.json()["keys"]["teller"]
    assert got["id"] == "app_mine" and got["environment"] == "development"
    # Checked with Teller: one call, no access token.
    assert [q.url.path for q in teller_stand_in.requests] == ["/accounts"]
    assert "authorization" not in teller_stand_in.requests[0].headers
    row = own_row(u["id"], "teller")
    assert b"BEGIN" not in row.secret_enc   # encrypted at rest
    from app import bank_keys
    keys = bank_keys.row_keys(row)
    assert keys.certificate.strip() == cert.strip() and keys.private_key.strip() == key.strip()
    assert "teller" in c.get("/api/bank/status").json()["providers_allowed"]
    assert ("bank_keys_saved", "Teller, development") in events(u["email"])


def test_teller_keys_from_the_two_files_text(fresh, teller_stand_in):
    c, u = fresh
    cert, key = make_pair()
    r = save_teller(c, environment="production", certificate=cert, private_key=key)
    assert r.status_code == 200, r.text
    assert own_row(u["id"], "teller").environment == "production"


def test_teller_sandbox_needs_no_certificate(fresh, teller_stand_in):
    c, _ = fresh
    r = save_teller(c, environment="sandbox")
    assert r.status_code == 200, r.text
    assert r.json()["keys"]["teller"]["environment"] == "sandbox"


@pytest.mark.parametrize("make, says", [
    (lambda cert, key: {"environment": "development"}, "need your certificate"),
    (lambda cert, key: {"environment": "development", "zip_base64": teller_zip(cert, None)},
     "doesn't hold certificate.pem and private_key.pem"),
    (lambda cert, key: {"environment": "development",
                        "zip_base64": base64.b64encode(b"not a zip").decode()}, "isn't a zip"),
    (lambda cert, key: {"environment": "development", "zip_base64": "%%%"}, "couldn't be read"),
    (lambda cert, key: {"environment": "development", "certificate": "hello", "private_key": key},
     "-----BEGIN"),
    (lambda cert, key: {"environment": "development", "zip_base64": teller_zip(cert, make_pair()[1])},
     "matching pair"),
])
def test_teller_keys_that_wont_work_are_refused_with_a_reason(fresh, teller_stand_in, make, says):
    c, u = fresh
    cert, key = make_pair()
    r = save_teller(c, **make(cert, key))
    assert r.status_code == 400 and says in r.json()["detail"], r.text
    assert "BEGIN" not in r.json()["detail"] or says == "-----BEGIN"
    assert own_row(u["id"], "teller") is None


def test_a_certificate_teller_doesnt_know_is_refused(fresh, monkeypatch):
    from app import teller
    c, u = fresh
    monkeypatch.setattr(teller, "_transport", httpx.MockTransport(lambda q: httpx.Response(
        400, json={"error": {"code": "invalid_certificate", "message": "unknown certificate"}})))
    cert, key = make_pair()
    r = save_teller(c, environment="development", certificate=cert, private_key=key)
    assert r.status_code == 400 and "didn't accept this certificate" in r.json()["detail"]
    assert own_row(u["id"], "teller") is None


def test_teller_certificate_files_are_the_apps_alone_and_gone_after(monkeypatch, tmp_path):
    from app import teller
    monkeypatch.setattr(teller, "TMP_ROOT", str(tmp_path))
    cert, key = make_pair()
    keys = teller.Keys(app_id="app_x", environment="development", certificate=cert, private_key=key)
    with teller.cert_files(keys) as (cert_path, key_path):
        folder = os.path.dirname(cert_path)
        assert os.path.dirname(folder) == str(tmp_path)
        assert stat.S_IMODE(os.stat(folder).st_mode) & 0o077 == 0
        for path in (cert_path, key_path):
            assert stat.S_IMODE(os.stat(path).st_mode) & 0o077 == 0
        assert open(key_path).read() == key
    assert not os.path.exists(folder) and os.listdir(tmp_path) == []
    # A real client loads them once and leaves nothing behind.
    monkeypatch.setattr(teller, "_transport", None)
    teller._client(keys).close()
    assert os.listdir(tmp_path) == []
    assert cert not in repr(keys) and key not in repr(keys)


# ---------- In use: refused, or carried over ----------

def test_keys_in_use_cant_be_removed_or_changed_to_another_id(fresh, plaid_stand_in):
    c, u = fresh
    assert save_plaid(c).status_code == 200
    conn = connect_plaid(c, plaid_stand_in)
    st = c.get("/api/bank").json()["keys"]["plaid"]
    assert st["in_use"] == ["Plaid Bank"]
    r = remove_keys(c, "plaid")
    assert r.status_code == 409 and "Plaid Bank" in r.json()["detail"] and "Disconnect" in r.json()["detail"]
    plaid_stand_in.accepted_keys.add(("other_client", "other_secret"))
    r = save_plaid(c, client_id="other_client", secret="other_secret")
    assert r.status_code == 409 and "Plaid Bank" in r.json()["detail"]
    assert own_row(u["id"], "plaid").key_id == "plaid_client"
    # Once disconnected, both are allowed.
    assert c.post("/api/bank/disconnect", json={"connection_id": conn}).status_code == 200
    assert save_plaid(c, client_id="other_client", secret="other_secret").status_code == 200
    r = remove_keys(c, "plaid")
    assert r.status_code == 200 and r.json()["keys"]["plaid"] is None
    assert ("bank_keys_removed", "Plaid, sandbox") in events(u["email"])
    assert remove_keys(c, "plaid").status_code == 404


def test_a_rotated_secret_for_the_same_id_carries_over_to_the_connections(fresh, plaid_stand_in):
    c, _ = fresh
    assert save_plaid(c).status_code == 200
    conn = connect_plaid(c, plaid_stand_in)
    acc = linked(c, conn, "Plaid Checking")
    plaid_stand_in.accepted_keys = {("plaid_client", ROTATED_SECRET)}
    r = save_plaid(c, secret=ROTATED_SECRET)
    assert r.status_code == 200, r.text
    assert connection_copy(conn).secret == ROTATED_SECRET
    r = c.post("/api/bank/sync", json={"connection_id": conn})
    assert r.status_code == 200, r.text
    assert plaid_stand_in.keys_seen[-1] == ("plaid_client", ROTATED_SECRET)
    assert acc


def test_a_connection_syncs_with_its_own_copy_and_new_ones_use_your_keys(fresh, plaid_stand_in):
    """The keys a connection was made with go with it (#276): the person's
    own keys changing underneath doesn't move it; a new connection uses the
    person's keys as they are now."""
    from app import bank_keys, plaid
    from app.db import SessionLocal
    c, u = fresh
    assert save_plaid(c).status_code == 200
    conn = connect_plaid(c, plaid_stand_in)
    assert connection_copy(conn) == plaid.Keys(**PLAID_KEYS_SANDBOX)
    # The person's own keys change underneath (as if a different id had
    # been allowed): the connection keeps its copy.
    db = SessionLocal()
    try:
        bank_keys.save(db, u["id"], plaid.Keys(client_id="new_client", secret="new_secret",
                                               environment="sandbox"), checked=True)
        db.commit()
    finally:
        db.close()
    plaid_stand_in.accepted_keys.add(("new_client", "new_secret"))
    linked(c, conn, "Plaid Checking")
    plaid_stand_in.keys_seen.clear()
    assert c.post("/api/bank/sync", json={"connection_id": conn}).status_code == 200
    assert set(plaid_stand_in.keys_seen) == {("plaid_client", PLAID_SECRET)}
    plaid_stand_in.keys_seen.clear()
    r = c.post("/api/bank/connect/start", json={"provider": "plaid"})
    assert r.status_code == 200, r.text
    assert plaid_stand_in.keys_seen == [("new_client", "new_secret")]
    # Disconnecting ends it at Plaid with its own copy.
    plaid_stand_in.keys_seen.clear()
    assert c.post("/api/bank/disconnect", json={"connection_id": conn}).status_code == 200
    assert plaid_stand_in.keys_seen == [("plaid_client", PLAID_SECRET)]


def test_teller_calls_use_the_keys_the_connection_was_made_with(fresh, teller_stand_in):
    c, u = fresh
    assert save_teller(c, environment="sandbox", application_id="app_mine").status_code == 200
    setup_attempt = c.post("/api/bank/connect/start", json={"provider": "teller"}).json()["attempt"]
    r = c.get("/api/bank/teller/setup", params={"attempt": setup_attempt})
    assert r.json()["application_id"] == "app_mine" and r.json()["environment"] == "sandbox"
    conn = connect_teller(c)
    assert connection_copy(conn).app_id == "app_mine"


# ---------- The one-time copy of .env's keys ----------

def _connection_without_copy(user_id, provider, token):
    from app.db import BankConnection, SessionLocal, encrypt_str
    db = SessionLocal()
    try:
        conn = BankConnection(user_id=user_id, provider=provider, access_url_enc=encrypt_str(token),
                              accounts_enc=encrypt_str("[]"), calls_json="[]")
        db.add(conn)
        db.commit()
        return conn.id
    finally:
        db.close()


def _forget_copied(provider):
    from app import bank_keys
    from app.db import AdminSetting, SessionLocal
    db = SessionLocal()
    try:
        db.query(AdminSetting).filter_by(key=bank_keys.COPIED_KEY.format(provider)).delete()
        db.commit()
    finally:
        db.close()


def _copy():
    from app import bank_keys
    from app.db import SessionLocal
    db = SessionLocal()
    try:
        return bank_keys.copy_env_keys(db)
    finally:
        db.close()


def test_the_upgrade_copies_envs_plaid_keys_once_to_the_people_using_them(app_started, monkeypatch):
    from app import bank_keys
    c, u = register(app_started)
    other, ou = register(app_started)
    has_own, hu = register(app_started)
    give_keys(bank_keys.plaid.Keys(client_id="mine_already", secret="kept", environment="sandbox"),
              hu["id"])
    conn = _connection_without_copy(u["id"], "plaid", "access-old-1")
    kept_conn = _connection_without_copy(hu["id"], "plaid", "access-old-2")
    _forget_copied("plaid")
    monkeypatch.setenv("PLAID_CLIENT_ID", "env_client")
    monkeypatch.setenv("PLAID_SECRET", "env_secret")
    monkeypatch.setenv("PLAID_ENV", "sandbox")
    assert _copy()["plaid"] >= 1
    assert own_row(u["id"], "plaid").key_id == "env_client"
    assert connection_copy(conn).client_id == "env_client"
    assert own_row(ou["id"], "plaid") is None                    # no connection, no keys
    assert own_row(hu["id"], "plaid").key_id == "mine_already"  # never replaced
    assert connection_copy(kept_conn).client_id == "env_client"  # its connection still gets .env's
    # Once only: .env isn't read again.
    monkeypatch.setenv("PLAID_CLIENT_ID", "env_client_later")
    conn2 = _connection_without_copy(ou["id"], "plaid", "access-old-3")
    assert "plaid" not in _copy()
    assert own_row(ou["id"], "plaid") is None and connection_copy(conn2) is None
    assert own_row(u["id"], "plaid").key_id == "env_client"
    from app.db import SessionLocal
    db = SessionLocal()
    try:
        copied = bank_keys.env_copied(db)
    finally:
        db.close()
    assert copied["plaid"]["at"].endswith("Z") and copied["plaid"]["people"] >= 1


def test_the_upgrade_copies_tellers_certificate_from_its_files(app_started, monkeypatch, tmp_path):
    c, u = register(app_started)
    cert, key = make_pair()
    (tmp_path / "certificate.pem").write_text(cert)
    (tmp_path / "private_key.pem").write_text(key)
    conn = _connection_without_copy(u["id"], "teller", "teller_tok_old")
    _forget_copied("teller")
    monkeypatch.setenv("TELLER_APP_ID", "app_env")
    monkeypatch.setenv("TELLER_ENV", "development")
    monkeypatch.setenv("TELLER_CERT_FILE", str(tmp_path / "certificate.pem"))
    monkeypatch.setenv("TELLER_KEY_FILE", str(tmp_path / "private_key.pem"))
    _copy()
    from app import bank_keys
    keys = bank_keys.row_keys(own_row(u["id"], "teller"))
    assert keys.app_id == "app_env" and keys.environment == "development"
    assert keys.certificate == cert and keys.private_key == key
    assert connection_copy(conn).certificate == cert


def test_the_upgrade_waits_when_env_has_no_keys_for_connections_that_need_them(app_started, monkeypatch):
    from app import bank_keys
    from app.db import AdminSetting, SessionLocal
    c, u = register(app_started)
    conn = _connection_without_copy(u["id"], "teller", "teller_tok_waiting")
    _forget_copied("teller")
    assert "teller" not in _copy()
    db = SessionLocal()
    try:
        assert db.get(AdminSetting, bank_keys.COPIED_KEY.format("teller")) is None
    finally:
        db.close()
    assert connection_copy(conn) is None
    # Put back the way the rest of the run found it.
    monkeypatch.setenv("TELLER_APP_ID", "app_env")
    monkeypatch.setenv("TELLER_ENV", "sandbox")
    _copy()


# ---------- Backups ----------

def test_a_sealed_backup_carries_the_keys_and_a_plain_export_never(fresh, app_started, plaid_stand_in):
    from app.backup import open_sealed
    c, u = fresh
    assert save_plaid(c).status_code == 200
    conn = connect_plaid(c, plaid_stand_in)
    linked(c, conn, "Plaid Checking")
    plain = c.get("/api/backup/export")
    assert plain.status_code == 200
    assert PLAID_SECRET not in plain.text and "bank_keys" not in plain.text
    sealed = c.post("/api/backup/export", json={"passphrase": BACKUP_PASSPHRASE})
    assert sealed.status_code == 200 and PLAID_SECRET not in sealed.text
    inside = open_sealed(sealed.json(), BACKUP_PASSPHRASE)
    assert inside["bank_keys"] == [{"provider": "plaid", "id": "plaid_client", "environment": "sandbox",
                                    "secret": PLAID_SECRET}]
    assert inside["bank_connections"][0]["keys"]["secret"] == PLAID_SECRET
    # Restored for someone else: their own keys and the connection's copy.
    c2, u2 = register(app_started)
    r = c2.post("/api/backup/import", json={"payload": sealed.json(), "passphrase": BACKUP_PASSPHRASE,
                                            "mode": "merge"})
    assert r.status_code == 200, r.text
    assert r.json()["imported"]["bank_keys"] == 1
    assert own_row(u2["id"], "plaid").key_id == "plaid_client"
    restored = c2.get("/api/bank").json()["connections"]
    assert len(restored) == 1 and connection_copy(restored[0]["id"]).secret == PLAID_SECRET


def test_an_older_sealed_backup_without_keys_restores_as_before(fresh, app_started):
    from app.backup import seal
    c, u = fresh
    old = {"version": 5, "accounts": [], "bank_connections": [
        {"provider": "plaid", "access_token": "access-from-before", "accounts": [], "links": []}]}
    r = c.post("/api/backup/import", json={"payload": seal(old, BACKUP_PASSPHRASE),
                                           "passphrase": BACKUP_PASSPHRASE, "mode": "merge"})
    assert r.status_code == 200, r.text
    assert r.json()["imported"]["bank_keys"] == 0 and r.json()["imported"]["bank_connection"] == 1
    conn = c.get("/api/bank").json()["connections"][0]["id"]
    assert connection_copy(conn) is None and own_row(u["id"], "plaid") is None


def test_keys_in_a_backup_that_dont_read_as_keys_are_left_out(fresh):
    from app.backup import seal
    c, u = fresh
    data = {"version": 5, "accounts": [], "bank_keys": [
        {"provider": "plaid", "id": "has spaces", "secret": "x", "environment": "sandbox"},
        {"provider": "teller", "id": "app_ok", "environment": "development"},   # no certificate
        "nonsense"]}
    r = c.post("/api/backup/import", json={"payload": seal(data, BACKUP_PASSPHRASE),
                                           "passphrase": BACKUP_PASSPHRASE, "mode": "merge"})
    assert r.status_code == 200 and r.json()["imported"]["bank_keys"] == 0
    assert own_row(u["id"], "plaid") is None and own_row(u["id"], "teller") is None


# ---------- Secrets stay secret ----------

def test_no_response_audit_line_or_log_line_carries_a_secret(fresh, plaid_stand_in, teller_stand_in,
                                                             caplog):
    caplog.set_level(logging.DEBUG)
    c, u = fresh
    cert, key = make_pair()
    texts = [save_plaid(c).text,
             save_teller(c, environment="development", zip_base64=teller_zip(cert, key)).text,
             c.get("/api/bank").text, c.get("/api/bank/status").text]
    conn = connect_plaid(c, plaid_stand_in)
    linked(c, conn, "Plaid Checking")
    texts.append(c.post("/api/bank/sync", json={"connection_id": conn}).text)
    texts.append(save_plaid(c, secret="refused_secret").text)
    secrets_ = [PLAID_SECRET, "refused_secret", "BEGIN", cert.splitlines()[1], key.splitlines()[1]]
    for text in texts + [caplog.text, json.dumps(events(u["email"]))]:
        for s in secrets_:
            assert s not in text
