"""Encrypted backups (bank-sync phase 1, #193).

Every backup is sealed with a passphrase: a user's own (POST
/api/backup/export), and BACKUP_PASSPHRASE for the scheduled and full-system
ones. Restoring needs the passphrase; a wrong one or a damaged file is refused
and nothing changes. Plain backup files from earlier versions still import,
and say so. GET /api/backup/export stays as "Download my data", a readable
copy.
"""
import base64
import json
from datetime import date

import pytest
from fastapi.testclient import TestClient

from conftest import register, unique_email

# About 1.5-2 s a test (the stand-ins, real scrypt): the slow tier (#274).
pytestmark = pytest.mark.slow

PASSWORD = "correct-horse-battery"
PASSPHRASE = "orange kettle window 42"


def make_account(c, name="Checking", balance=250.0):
    r = c.post("/api/accounts", json={
        "name": name, "starting_balance": balance,
        "starting_date": date.today().isoformat()})
    assert r.status_code == 200, r.text
    return r.json()["id"]


def account_names(c):
    return sorted(a["name"] for a in c.get("/api/accounts?include_archived=true").json())


@pytest.fixture
def source(app_started):
    """A user with two accounts, one holding a transaction."""
    c, u = register(app_started)
    acc = make_account(c, "Everyday checking")
    make_account(c, "Rainy day", 900.0)
    r = c.post(f"/api/accounts/{acc}/transactions", json={
        "description": "Groceries at the corner shop", "amount": -42.5,
        "forecast_date": date.today().isoformat()})
    assert r.status_code == 200, r.text
    return c, u, acc


# ---------- A user's own backup ----------

def test_an_encrypted_export_hides_the_data_and_restores_the_same(app_started, source):
    c, _, acc = source
    r = c.post("/api/backup/export", json={"passphrase": PASSPHRASE})
    assert r.status_code == 200, r.text
    assert "walletweather-backup-" in r.headers["content-disposition"]
    sealed = r.json()
    assert sealed["walletweather"] == "walletweather-encrypted-backup"
    assert sealed["format"] == 1 and sealed["kind"] == "user"
    assert sealed["kdf"]["name"] == "scrypt" and sealed["cipher"]["name"] == "AES-256-GCM"
    # Nothing readable: not the names, the description, or the email.
    for secret in ("Everyday checking", "Rainy day", "Groceries", source[1]["email"]):
        assert secret not in r.text

    other, _ = register(app_started)
    preview = other.post("/api/backup/preview", json={"payload": sealed, "passphrase": PASSPHRASE})
    assert preview.status_code == 200, preview.text
    assert preview.json()["encrypted"] is True
    assert sorted(preview.json()["accounts"]) == ["Everyday checking", "Rainy day"]

    r = other.post("/api/backup/import", json={"payload": sealed, "passphrase": PASSPHRASE})
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["encrypted"] is True
    assert body["imported"]["accounts"] == 2 and body["imported"]["transactions"] == 1
    assert account_names(other) == ["Everyday checking", "Rainy day"]
    # The same data as a readable copy of each side shows.
    mine = c.get("/api/backup/export").json()["accounts"]
    theirs = other.get("/api/backup/export").json()["accounts"]
    strip = lambda accs: sorted(({k: v for k, v in a.items() if k != "created_at"} for a in accs),
                                key=lambda a: a["name"])
    assert strip(mine) == strip(theirs)


def test_export_of_chosen_accounts_only(source):
    c, _, acc = source
    r = c.post("/api/backup/export", json={"passphrase": PASSPHRASE, "account_ids": [acc]})
    assert r.status_code == 200
    preview = c.post("/api/backup/preview", json={"payload": r.json(), "passphrase": PASSPHRASE})
    assert preview.json()["accounts"] == ["Everyday checking"]


@pytest.mark.parametrize("passphrase", ["", "short", "eleven char"])
def test_a_missing_or_short_passphrase_makes_no_backup(source, passphrase):
    c, u, _ = source
    r = c.post("/api/backup/export", json={"passphrase": passphrase})
    assert r.status_code == 400
    assert "passphrase" in r.json()["detail"].lower()


def test_the_passphrase_is_required_in_the_body(source):
    c, _, _ = source
    assert c.post("/api/backup/export", json={}).status_code == 422


def test_a_wrong_passphrase_is_refused_and_changes_nothing(app_started, source):
    c, _, _ = source
    sealed = c.post("/api/backup/export", json={"passphrase": PASSPHRASE}).json()
    other, _ = register(app_started)
    make_account(other, "Keep me")
    for mode in ("merge", "replace"):
        r = other.post("/api/backup/import", json={"payload": sealed, "mode": mode,
                                                   "passphrase": PASSPHRASE + "x"})
        assert r.status_code == 400
        assert r.json()["detail"] == "That passphrase doesn't open this backup. Nothing was changed."
    r = other.post("/api/backup/preview", json={"payload": sealed, "passphrase": "not the one at all"})
    assert r.status_code == 400
    assert account_names(other) == ["Keep me"]


def test_an_encrypted_file_without_a_passphrase_asks_for_one(source):
    c, _, _ = source
    sealed = c.post("/api/backup/export", json={"passphrase": PASSPHRASE}).json()
    for path in ("/api/backup/preview", "/api/backup/import"):
        r = c.post(path, json={"payload": sealed})
        assert r.status_code == 400
        assert "Enter its passphrase" in r.json()["detail"]


def _flip(b64: str) -> str:
    raw = bytearray(base64.b64decode(b64))
    raw[len(raw) // 2] ^= 0x01
    return base64.b64encode(bytes(raw)).decode()


def test_a_damaged_file_is_refused_and_changes_nothing(app_started, source):
    c, _, _ = source
    sealed = c.post("/api/backup/export", json={"passphrase": PASSPHRASE}).json()
    other, _ = register(app_started)
    make_account(other, "Keep me")
    damaged = [
        {**sealed, "ciphertext": _flip(sealed["ciphertext"])},       # a changed byte
        {**sealed, "ciphertext": sealed["ciphertext"][:40]},         # cut short
        {**sealed, "ciphertext": "not base64 at all!"},
        {**sealed, "kind": "system"},                                # an edited header
        {**sealed, "kdf": {**sealed["kdf"], "n": 2 ** 30}},          # a cost too high to try
        {**sealed, "kdf": {**sealed["kdf"], "n": 1000}},             # not a power of two
        {k: v for k, v in sealed.items() if k != "cipher"},
    ]
    for payload in damaged:
        r = other.post("/api/backup/import", json={"payload": payload, "mode": "replace",
                                                   "passphrase": PASSPHRASE})
        assert r.status_code == 400, payload
    r = other.post("/api/backup/import", json={"payload": {**sealed, "format": 2},
                                               "passphrase": PASSPHRASE})
    assert r.status_code == 400 and "newer version" in r.json()["detail"]
    assert account_names(other) == ["Keep me"]


def test_a_plain_backup_from_an_earlier_version_still_imports(app_started, source):
    """Today's readable copy has the same shape as the plain backups earlier
    versions wrote, so it stands in for one."""
    c, _, _ = source
    plain = c.get("/api/backup/export").json()
    assert "walletweather" not in plain and plain["accounts"]
    other, _ = register(app_started)
    preview = other.post("/api/backup/preview", json={"payload": plain})
    assert preview.status_code == 200 and preview.json()["encrypted"] is False
    r = other.post("/api/backup/import", json={"payload": plain})
    assert r.status_code == 200, r.text
    assert r.json()["encrypted"] is False
    assert account_names(other) == ["Everyday checking", "Rainy day"]


def test_download_my_data_is_readable_and_named_as_such(source):
    c, _, _ = source
    r = c.get("/api/backup/export")
    assert r.status_code == 200
    assert "walletweather-my-data-" in r.headers["content-disposition"]
    assert "Everyday checking" in r.text


def test_the_sealing_itself():
    from app.backup import seal, open_sealed, BackupLocked
    payload = {"version": 4, "accounts": [{"name": "ünïcode ✓"}]}
    a, b = seal(payload, PASSPHRASE), seal(payload, PASSPHRASE)
    # A fresh salt and nonce every time.
    assert a["kdf"]["salt"] != b["kdf"]["salt"] and a["ciphertext"] != b["ciphertext"]
    assert open_sealed(json.loads(json.dumps(a)), PASSPHRASE) == payload
    with pytest.raises(BackupLocked):
        open_sealed(a, "wrong passphrase here")
    with pytest.raises(ValueError):
        seal(payload, "short")


# ---------- System backups ----------

def test_a_system_backup_is_encrypted_and_restores(app_started, admin, source):
    from app import main
    ac, _ = admin
    made = ac.post("/api/admin/backups/now")
    assert made.status_code == 200, made.text
    filename = made.json()["filename"]
    text = (main.BACKUP_DIR / filename).read_text()
    assert "Everyday checking" not in text and source[1]["email"] not in text
    sealed = json.loads(text)
    assert sealed["walletweather"] == "walletweather-encrypted-backup" and sealed["kind"] == "system"
    listed = {f["filename"]: f for f in ac.get("/api/admin/backups").json()}
    assert listed[filename]["encrypted"] is True
    # The download is the sealed file as it is on disk.
    got = ac.get(f"/api/admin/backups/download/{filename}")
    assert got.status_code == 200 and got.json() == sealed
    (main.BACKUP_DIR / filename).unlink()


def test_an_encrypted_system_backup_restores(app_started, admin, source):
    """Restoring the whole made backup would replace every test user's data,
    so a sealed file holding one user stands in for it."""
    import uuid
    from app import main
    from app.backup import seal
    ac, _ = admin
    udata = source[0].get("/api/backup/export").json()
    filename = f"system-backup-test-{uuid.uuid4().hex[:8]}.json"
    sealed = seal({"system_backup": True, "version": 4, "users": [udata]},
                  main.BACKUP_PASSPHRASE, kind="system")
    (main.BACKUP_DIR / filename).write_text(json.dumps(sealed))
    try:
        r = ac.post(f"/api/admin/backups/restore/{filename}")
        assert r.status_code == 200, r.text
        assert r.json()["encrypted"] is True and r.json()["restored"]["users"] == 1
        assert account_names(source[0]) == ["Everyday checking", "Rainy day"]
    finally:
        (main.BACKUP_DIR / filename).unlink()


def test_a_system_backup_under_another_passphrase_is_refused(app_started, admin, monkeypatch):
    from app import main
    ac, _ = admin
    import uuid
    from app.backup import seal
    filename = f"system-backup-test-{uuid.uuid4().hex[:8]}.json"
    (main.BACKUP_DIR / filename).write_text(json.dumps(
        seal({"system_backup": True, "version": 4, "users": []}, main.BACKUP_PASSPHRASE, "system")))
    try:
        monkeypatch.setattr(main, "BACKUP_PASSPHRASE", "a different passphrase")
        r = ac.post(f"/api/admin/backups/restore/{filename}")
        assert r.status_code == 400
        assert "doesn't open this backup" in r.json()["detail"]
    finally:
        (main.BACKUP_DIR / filename).unlink()


@pytest.mark.parametrize("value", ["", "too short"])
def test_no_system_backup_without_a_usable_passphrase(app_started, admin, monkeypatch, value):
    from app import main
    ac, _ = admin
    monkeypatch.setattr(main, "BACKUP_PASSPHRASE", value)
    before = set(main.BACKUP_DIR.glob("system-backup-*.json"))
    r = ac.post("/api/admin/backups/now")
    assert r.status_code == 400
    assert "BACKUP_PASSPHRASE" in r.json()["detail"]
    assert set(main.BACKUP_DIR.glob("system-backup-*.json")) == before
    cfg = ac.get("/api/admin/backup-config").json()
    assert cfg["passphrase_set"] is False and "BACKUP_PASSPHRASE" in cfg["passphrase_problem"]


def test_admin_says_when_the_passphrase_is_set(admin):
    ac, _ = admin
    cfg = ac.get("/api/admin/backup-config").json()
    assert cfg["passphrase_set"] is True and cfg["passphrase_problem"] is None


def test_the_scheduled_backup_seals_with_the_passphrase(app_started):
    """The scheduler calls _run_system_backup; called directly here, since
    the tests don't start the 30-minute thread."""
    from app import main
    from app.backup import open_sealed
    filename = main._run_system_backup()
    try:
        sealed = json.loads((main.BACKUP_DIR / filename).read_text())
        data = open_sealed(sealed, main.BACKUP_PASSPHRASE)
        assert data["system_backup"] is True and isinstance(data["users"], list)
    finally:
        (main.BACKUP_DIR / filename).unlink()


def test_the_scheduled_backup_refuses_without_the_passphrase(app_started, monkeypatch):
    from app import main
    monkeypatch.setattr(main, "BACKUP_PASSPHRASE", "")
    before = set(main.BACKUP_DIR.glob("system-backup-*.json"))
    with pytest.raises(main.BackupPassphraseMissing):
        main._run_system_backup()
    assert set(main.BACKUP_DIR.glob("system-backup-*.json")) == before


def test_a_plain_system_backup_from_an_earlier_version_still_restores(app_started, admin, source):
    import uuid
    from app import main
    ac, _ = admin
    udata = source[0].get("/api/backup/export").json()
    filename = f"system-backup-test-{uuid.uuid4().hex[:8]}.json"
    (main.BACKUP_DIR / filename).write_text(json.dumps({"system_backup": True, "users": [udata]}))
    try:
        listed = {f["filename"]: f for f in ac.get("/api/admin/backups").json()}
        assert listed[filename]["encrypted"] is False
        r = ac.post(f"/api/admin/backups/restore/{filename}")
        assert r.status_code == 200, r.text
        assert r.json()["encrypted"] is False
    finally:
        (main.BACKUP_DIR / filename).unlink()


def test_the_new_routes_need_a_sign_in(app_started):
    anon = TestClient(app_started)
    assert anon.post("/api/backup/export", json={"passphrase": PASSPHRASE}).status_code == 401
    assert anon.post("/api/backup/preview", json={"payload": {}}).status_code == 401
