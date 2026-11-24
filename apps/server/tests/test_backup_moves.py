"""Moving between a server and the iPhone (Plans/standalone.md, phase 5, #236).

The iPhone app writes and opens this server's sealed backups itself, with
scrypt written in Swift. The files that make the trip are committed in the
iOS app's test samples (apps/ios/WalletWeatherKit/Tests/WalletWeatherKitTests/
Samples/moves/), so a change on either side that breaks a move fails here
or in `swift test`:

- vectors.json: scrypt keys and sealed-file headers. Python's own answers,
  checked here, and matched by the Swift code in ScryptTests and
  BackupTests.
- from-phone.json: a household's sealed backup, made on the phone, and
  forecast.json: that household's Forecasts on the phone. Imported here,
  it gives the same Forecasts.
- from-server.json: this server's sealed backup of the imported household.
  The phone imports it in BackupTests and gets the same Forecasts again:
  phone → server → phone.

Rewrite from-server.json after a deliberate change to the backup format with:
    docker compose -f docker-compose.test.yml run --rm -e WRITE_BACKUP_FIXTURES=1 tests tests/test_backup_moves.py
(from-phone.json and forecast.json: `WRITE_BACKUP_FIXTURES=1 swift test
--filter BackupTests` in apps/ios/WalletWeatherKit.)
"""
import base64
import json
import os
from pathlib import Path

import pytest

from app.backup import _header_bytes, _key, open_sealed
from test_encrypted_backups import register

SAMPLES = (Path(__file__).resolve().parents[3] / "apps" / "ios" / "WalletWeatherKit" / "Tests"
           / "WalletWeatherKitTests" / "Samples" / "moves")
# The fixtures' passphrase: a test value committed with them, not a secret.
PASSPHRASE = "move me to a server 2026"
MONTHS = [("2026-01-01", "2026-01-31"), ("2026-02-01", "2026-02-28"), ("2026-03-01", "2026-03-31")]


def _load(name):
    return json.loads((SAMPLES / f"{name}.json").read_text(encoding="utf-8"))


def normalized(forecast: dict) -> dict:
    """A Forecast without what differs between stores: ids become whether
    there is one, today's balance goes (BackupTests.normalized does the same),
    and so do the fields only the server has (the bank's: #255, #256)."""
    out = {k: v for k, v in forecast.items()
           if k not in ("current_balance", "bank_unmatched_count", "bank_balance")}
    out["rows"] = [{(f"has_{k[:-3]}" if k.endswith("_id") else k):
                    ([t["name"] for t in v] if k == "tags" else v is not None if k.endswith("_id") else v)
                    for k, v in row.items()} for row in forecast["rows"]]
    return out


def forecasts(client) -> dict:
    out = {}
    for acc in client.get("/api/accounts").json():
        out[acc["name"]] = [normalized(client.get(f"/api/accounts/{acc['id']}/forecast",
                                                  params={"start": s, "end": e}).json()) for s, e in MONTHS]
    return out


def test_scrypt_and_the_header_match_the_vectors():
    data = _load("vectors")
    for v in data["vectors"]:
        key = _key(v["passphrase"], base64.b64decode(v["salt"]), v["n"], v["r"], v["p"]) if v["length"] == 32 else None
        if key is not None:
            assert key.hex() == v["key"], v["name"]
    for h in data["headers"]:
        assert _header_bytes(h["header"]).decode() == h["bytes"]


@pytest.fixture
def imported(app_started):
    """The phone's household, imported into a new user."""
    client, _ = register(app_started)
    r = client.post("/api/backup/import", json={"payload": _load("from-phone"), "passphrase": PASSPHRASE,
                                                "mode": "replace"})
    assert r.status_code == 200, r.text
    return client, r.json()


def test_the_phones_backup_imports_with_the_same_forecast(imported):
    client, answer = imported
    assert answer["encrypted"] is True
    counts = answer["imported"]
    assert (counts["accounts"], counts["recurring"], counts["transactions"], counts["transfers"]) == (2, 6, 6, 1)
    transfer = client.get("/api/transfers").json()["transfers"][0]
    assert (transfer["from_account_name"], transfer["to_account_name"], transfer["amount"]) == ("Checking", "Épargne 🍕", 250.0)
    assert forecasts(client) == _load("forecast")
    # Tags and their rule came too (phone-tags phase 1, #250).
    assert [(t["name"], t["color"]) for t in client.get("/api/tags").json()] == [("Holiday ✈️", "#e3b341"), ("work", None)]
    rules = client.get("/api/tag-rules").json()
    assert [(r["description_pattern"], r["tag_name"] if "tag_name" in r else r["tag_id"] is not None) for r in rules] \
        in ([("café", "Holiday ✈️")], [("café", True)])


def test_the_servers_backup_of_it_is_committed_for_the_phone(imported):
    client, _ = imported
    if os.environ.get("WRITE_BACKUP_FIXTURES") == "1":
        sealed = client.post("/api/backup/export", json={"passphrase": PASSPHRASE}).json()
        (SAMPLES / "from-server.json").write_text(json.dumps(sealed, ensure_ascii=False) + "\n", encoding="utf-8")
        pytest.skip("from-server.json rewritten")
    committed = open_sealed(_load("from-server"), PASSPHRASE)
    fresh = client.get("/api/backup/export").json()

    def comparable(payload):
        out = {k: v for k, v in payload.items() if k not in ("exported_at", "user")}
        out["accounts"] = [{k: v for k, v in a.items() if k != "created_at"} for a in payload["accounts"]]
        return out

    assert comparable(committed) == comparable(fresh), "rewrite from-server.json (see this file's docstring)"


# Copy to a server (#328): the iPhone sends the backup Export for a server
# seals (from-phone.json is that file, made from BackupTests.household()),
# unsealed, as {"mode": ..., "payload": ...} with no passphrase, under the
# app's full token (CopyToServerTests checks the request on the phone's
# side). The app reads `imported`'s accounts, recurring, transactions and
# transfers.
def _phone(app, browser, access):
    from fastapi.testclient import TestClient
    r = browser.post("/api/tokens", json={"name": "iPhone", "access": access})
    assert r.status_code == 200, r.text
    phone = TestClient(app)
    phone.headers["Authorization"] = f"Bearer {r.json()['token']}"
    return phone


def _copy(phone, payload, mode):
    return phone.post("/api/backup/import", json={"mode": mode, "payload": payload})


def test_copy_to_a_server_imports_the_plain_backup_with_merge_and_replace(app_started):
    browser, _ = register(app_started)
    phone = _phone(app_started, browser, "full")
    payload = open_sealed(_load("from-phone"), PASSPHRASE)
    assert "walletweather" not in payload  # the backup itself, not the sealed file

    # Add to what's there, onto an empty account.
    r = _copy(phone, payload, "merge")
    assert r.status_code == 200, r.text
    answer = r.json()
    assert answer["ok"] is True and answer["encrypted"] is False
    counts = answer["imported"]
    assert (counts["accounts"], counts["recurring"], counts["transactions"], counts["transfers"]) == (2, 6, 6, 1)
    assert all(isinstance(counts[k], int) for k in ("categories", "tags"))
    assert forecasts(phone) == _load("forecast")

    # Again: added beside what's there.
    r = _copy(phone, payload, "merge")
    assert r.status_code == 200, r.text
    assert r.json()["imported"]["accounts"] == 2
    assert len(phone.get("/api/accounts").json()) == 4

    # Replace what's there: the accounts, categories and tags go first.
    r = _copy(phone, payload, "replace")
    assert r.status_code == 200, r.text
    counts = r.json()["imported"]
    assert (counts["accounts"], counts["recurring"], counts["transactions"], counts["transfers"]) == (2, 6, 6, 1)
    assert sorted(a["name"] for a in phone.get("/api/accounts").json()) == ["Checking", "Épargne 🍕"]
    assert forecasts(phone) == _load("forecast")


def test_copy_to_a_server_is_refused_to_a_read_only_token(app_started):
    browser, _ = register(app_started)
    reader = _phone(app_started, browser, "read")
    r = _copy(reader, open_sealed(_load("from-phone"), PASSPHRASE), "merge")
    assert r.status_code == 403, r.text
    assert browser.get("/api/accounts").json() == []
