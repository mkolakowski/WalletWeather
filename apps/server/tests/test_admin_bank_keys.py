"""Admin → Users shows who has saved their own Teller and Plaid keys
(own-bank-keys phase 2, #277).

Set or not and the environment, nothing else: the response never carries a
key id, a secret, a certificate or a private key. Keys are saved as Settings
→ Bank sync leaves them (bank_keys rows, with no network call).
"""
import pytest

from test_bank_providers import PLAID_KEYS_SANDBOX, switched_on  # noqa: F401
from test_bank_sync import allow_bank, give_keys, register

PLAID_CLIENT_ID = "plaid_client_id_for_admin_test"
PLAID_SECRET = "plaid_secret_for_admin_test"
TELLER_APP_ID = "app_teller_id_for_admin_test"
TELLER_CERT = "-----BEGIN CERTIFICATE-----\nQ0VSVF9GT1JfQURNSU5fVEVTVA==\n-----END CERTIFICATE-----\n"
TELLER_KEY = "-----BEGIN PRIVATE KEY-----\nS0VZX0ZPUl9BRE1JTl9URVNU\n-----END PRIVATE KEY-----\n"
SECRETS = [PLAID_CLIENT_ID, PLAID_SECRET, TELLER_APP_ID, "BEGIN CERTIFICATE", "BEGIN PRIVATE KEY", "Q0VSVF9GT1JfQURNSU5fVEVTVA", "S0VZX0ZPUl9BRE1JTl9URVNU"]


@pytest.fixture
def admin(app_started):
    from app import main
    c, u = register(app_started, bank=False)
    main.ADMIN_EMAILS.add(u["email"])
    yield c, u
    main.ADMIN_EMAILS.discard(u["email"])


def own_keys(user_id, plaid=None, teller=None):
    from app import plaid as plaid_mod, teller as teller_mod
    if plaid:
        give_keys(plaid_mod.Keys(client_id=PLAID_CLIENT_ID, secret=PLAID_SECRET, environment=plaid), user_id)
    if teller:
        give_keys(teller_mod.Keys(app_id=TELLER_APP_ID, environment=teller,
                                  certificate=TELLER_CERT, private_key=TELLER_KEY), user_id)


def row_of(admin_client, user_id):
    r = admin_client.get("/api/admin/users")
    assert r.status_code == 200, r.text
    return next(x for x in r.json() if x["id"] == user_id), r.text


def test_the_list_shows_who_saved_their_own_keys_and_where(app_started, admin):
    a, _ = admin
    _, u = register(app_started, bank=False)
    allow_bank(u["id"], ["teller", "plaid"])
    own_keys(u["id"], plaid="production", teller="development")
    row, _ = row_of(a, u["id"])
    assert row["bank_keys"] == {"teller": {"environment": "development"},
                                "plaid": {"environment": "production"}}
    assert row["bank_access"] == ["plaid", "teller"]
    # What the Users table already reads is still there.
    assert row["email"] == u["email"] and row["bank_connected"] is False and row["is_admin"] is False


def test_a_ticked_person_without_keys_shows_null_and_one_service_can_be_set_alone(app_started, admin):
    a, _ = admin
    _, none = register(app_started, bank=False)
    allow_bank(none["id"], ["teller", "plaid"])
    _, half = register(app_started, bank=False)
    allow_bank(half["id"], ["teller", "plaid"])
    own_keys(half["id"], teller="sandbox")
    assert row_of(a, none["id"])[0]["bank_keys"] == {"teller": None, "plaid": None}
    assert row_of(a, half["id"])[0]["bank_keys"] == {"teller": {"environment": "sandbox"}, "plaid": None}


def test_the_list_never_carries_a_key_id_secret_certificate_or_private_key(app_started, admin):
    a, _ = admin
    _, u = register(app_started, bank=False)
    allow_bank(u["id"], ["teller", "plaid"])
    own_keys(u["id"], plaid="production", teller="development")
    row, text = row_of(a, u["id"])
    for secret in SECRETS:
        assert secret not in text
    assert set(row["bank_keys"]["teller"]) == {"environment"} and set(row["bank_keys"]["plaid"]) == {"environment"}


def test_the_list_stays_the_same_size_of_work_for_many_people(app_started, admin):
    """One query for everyone's keys, not one per person."""
    from sqlalchemy import event
    from app.db import engine
    a, _ = admin
    for _i in range(3):
        _, u = register(app_started, bank=False)
        own_keys(u["id"], plaid="sandbox")
    seen = []

    def count(conn, cursor, statement, *rest):
        if "bank_keys" in statement:
            seen.append(statement)

    event.listen(engine, "before_cursor_execute", count)
    try:
        assert a.get("/api/admin/users").status_code == 200
    finally:
        event.remove(engine, "before_cursor_execute", count)
    assert len(seen) == 1


def test_only_an_admin_sees_the_list(app_started, switched_on):
    c, u = register(app_started)
    own_keys(u["id"], plaid="sandbox")
    r = c.get("/api/admin/users")
    assert r.status_code == 403 and "bank_keys" not in r.text and PLAID_CLIENT_ID not in r.text
    from fastapi.testclient import TestClient
    assert TestClient(app_started).get("/api/admin/users").status_code in (401, 403)
