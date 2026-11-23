"""Each person's own Teller and Plaid keys (own-bank-keys phase 1, #276).

Decided 2026-11-23 (docs/dev/decisions/bank-sync.md): a person who syncs a
bank through Teller or Plaid uses their own developer keys, saved under their
own account (`bank_keys`), and every connection keeps an encrypted copy of
the keys it was made with (`bank_connections.keys_enc`), so it goes on
syncing whatever its person later does with theirs, and for whoever it's
passed on to (#266).

The secret part (Plaid's secret, Teller's certificate and private key) is
encrypted with ENCRYPTION_KEY and never logged, never sent to a browser,
and never written anywhere else, apart from Teller's certificate and key
reaching httpx through app-only temporary files (teller.cert_files).

`.env` is read for Teller and Plaid only once, on the upgrade to schema 38
(copy_env_keys).
"""
import io
import json
import logging
import os
import zipfile
from datetime import datetime

from sqlalchemy.orm import Session

from . import plaid, teller
from .db import AdminSetting, BankConnection, BankKeys, decrypt_str, encrypt_str

log = logging.getLogger("walletweather.bank_keys")

PROVIDERS = ("teller", "plaid")
PEM_MAX = 20_000          # one PEM file, characters
ZIP_MAX = 100_000         # Teller's zip, bytes (it's a few KB)
COPIED_KEY = "bank_keys_copied_{}"   # admin_settings, once per provider

Keys = teller.Keys | plaid.Keys


# ---------- Keys to and from the database ----------

def _to_json(keys: Keys) -> str:
    if isinstance(keys, teller.Keys):
        return json.dumps({"provider": "teller", "id": keys.app_id, "environment": keys.environment,
                           "certificate": keys.certificate, "private_key": keys.private_key})
    return json.dumps({"provider": "plaid", "id": keys.client_id, "environment": keys.environment,
                       "secret": keys.secret})


def _from_json(provider: str, text: str | None) -> Keys | None:
    try:
        d = json.loads(text) if text else None
    except ValueError:
        return None
    if not isinstance(d, dict):
        return None
    return _build(provider, str(d.get("id") or ""), d.get("environment"), d)


def _build(provider: str, key_id: str, environment, secret: dict) -> Keys | None:
    if provider == "teller":
        return teller.Keys(app_id=key_id, environment=teller.environment_of(environment),
                           certificate=str(secret.get("certificate") or ""),
                           private_key=str(secret.get("private_key") or ""))
    if provider == "plaid":
        return plaid.Keys(client_id=key_id, secret=str(secret.get("secret") or ""),
                          environment=plaid.environment_of(environment))
    return None


def key_id(keys: Keys) -> str:
    return keys.app_id if isinstance(keys, teller.Keys) else keys.client_id


def encrypt_copy(keys: Keys) -> bytes:
    """A connection's copy of the keys it was made with."""
    return encrypt_str(_to_json(keys))


def row_keys(row: BankKeys | None) -> Keys | None:
    """The keys a bank_keys row holds."""
    if row is None:
        return None
    try:
        secret = json.loads(decrypt_str(row.secret_enc)) if row.secret_enc else {}
    except Exception:
        secret = {}
    return _build(row.provider, row.key_id, row.environment, secret if isinstance(secret, dict) else {})


def own_row(db: Session, user_id: int, provider: str) -> BankKeys | None:
    return db.get(BankKeys, (user_id, provider))


def own_keys(db: Session, user_id: int, provider: str) -> Keys | None:
    """A person's own keys for a provider, or None."""
    return row_keys(own_row(db, user_id, provider))


def connection_keys(db: Session, conn: BankConnection) -> Keys | None:
    """The keys a connection is used with: its own copy, or (one made before
    copies, the .env keys missing at the upgrade) its holder's own keys."""
    provider = conn.provider
    if provider not in PROVIDERS:
        return None
    if conn.keys_enc:
        try:
            keys = _from_json(provider, decrypt_str(conn.keys_enc))
        except Exception:
            keys = None
        if keys is not None:
            return keys
    return own_keys(db, conn.user_id, provider)


def uses(db: Session, conn: BankConnection, keys: Keys) -> bool:
    """Whether a connection uses these keys: its copy names the same id, or
    it has no copy and so falls back on its holder's own keys."""
    if not conn.keys_enc:
        return True
    copy = connection_keys(db, conn)
    return copy is None or key_id(copy) == key_id(keys)


def save(db: Session, user_id: int, keys: Keys, checked: bool) -> BankKeys:
    """Save (or replace) a person's own keys for one provider."""
    provider = "teller" if isinstance(keys, teller.Keys) else "plaid"
    secret = ({"certificate": keys.certificate, "private_key": keys.private_key}
              if provider == "teller" else {"secret": keys.secret})
    now = datetime.utcnow()
    row = own_row(db, user_id, provider)
    if row is None:
        row = BankKeys(user_id=user_id, provider=provider)
        db.add(row)
    row.environment = keys.environment
    row.key_id = key_id(keys)[:200]
    row.secret_enc = encrypt_str(json.dumps(secret))
    row.saved_at = now
    row.checked_at = now if checked else None
    db.flush()
    return row


# ---------- Teller's certificate as the web sends it ----------

class KeysInputError(ValueError):
    pass


def _pem(text, kind: str) -> str:
    text = (text or "").strip()
    if not text:
        return ""
    if len(text) > PEM_MAX or "-----BEGIN" not in text:
        raise KeysInputError(f"That doesn't look like Teller's {kind}: it should start with "
                             "-----BEGIN.")
    return text + "\n"


def teller_pems(zip_bytes: bytes | None, certificate: str | None, private_key: str | None) -> tuple[str, str]:
    """Teller's certificate and private key, from the zip Teller downloads
    (certificate.pem and private_key.pem inside, perhaps in a folder) or
    from the two files' text."""
    if zip_bytes:
        if len(zip_bytes) > ZIP_MAX:
            raise KeysInputError("That file is too big to be Teller's zip.")
        try:
            z = zipfile.ZipFile(io.BytesIO(zip_bytes))
            found = {}
            for info in z.infolist():
                name = info.filename.rsplit("/", 1)[-1].lower()
                if name in ("certificate.pem", "private_key.pem") and not info.is_dir():
                    if info.file_size > PEM_MAX:
                        raise KeysInputError("A file in that zip is too big to be Teller's.")
                    found[name] = z.read(info).decode("utf-8", "replace")
        except (zipfile.BadZipFile, RuntimeError, OSError, EOFError):
            raise KeysInputError("That file isn't a zip that can be read. Pick the teller.zip Teller "
                                 "downloaded, or the two files inside it.")
        if set(found) != {"certificate.pem", "private_key.pem"}:
            raise KeysInputError("That zip doesn't hold certificate.pem and private_key.pem. Pick the "
                                 "teller.zip Teller downloaded, or the two files inside it.")
        return _pem(found["certificate.pem"], "certificate"), _pem(found["private_key.pem"], "private key")
    return _pem(certificate, "certificate"), _pem(private_key, "private key")


# ---------- The one-time copy of .env's keys (schema 38) ----------

def _env(name: str) -> str:
    return os.environ.get(name, "").strip()


def _read(path: str) -> str:
    try:
        if path and os.path.isfile(path):
            with open(path, encoding="utf-8") as f:
                return f.read(PEM_MAX + 1)[:PEM_MAX]
    except OSError:
        pass
    return ""


def env_keys(provider: str) -> Keys | None:
    """The keys `.env` held before schema 38, as the server read them, or
    None. Read only by the copy below."""
    if provider == "teller":
        keys = teller.Keys(app_id=_env("TELLER_APP_ID"), environment=teller.environment_of(_env("TELLER_ENV")),
                           certificate=_read(_env("TELLER_CERT_FILE")),
                           private_key=_read(_env("TELLER_KEY_FILE")))
        if keys.environment == "sandbox" and not (keys.certificate and keys.private_key):
            keys = teller.Keys(app_id=keys.app_id, environment="sandbox")
        return keys if teller.available(keys) else None
    keys = plaid.Keys(client_id=_env("PLAID_CLIENT_ID"), secret=_env("PLAID_SECRET"),
                      environment=plaid.environment_of(_env("PLAID_ENV")))
    return keys if plaid.available(keys) else None


def copy_env_keys(db: Session) -> dict[str, int]:
    """Once per provider: the keys in `.env` saved as their own for everyone
    with a connection of it who has none, and as the copy on each such
    connection without one. Nothing is deleted or replaced. A provider with
    connections but no usable keys in `.env` is tried again at the next
    start. Returns how many people got keys, per provider."""
    out = {}
    for provider in PROVIDERS:
        marker = COPIED_KEY.format(provider)
        if db.get(AdminSetting, marker) is not None:
            continue
        conns = db.query(BankConnection).filter_by(provider=provider).all()
        keys = env_keys(provider)
        if conns and keys is None:
            log.warning("%s connections exist but .env has no usable %s keys to copy to their "
                        "people; trying again at the next start.", provider.title(), provider.title())
            continue
        people = 0
        for conn in conns:
            if own_row(db, conn.user_id, provider) is None:
                save(db, conn.user_id, keys, checked=False)
                people += 1
            if not conn.keys_enc:
                conn.keys_enc = encrypt_copy(keys)
        db.add(AdminSetting(key=marker, value=json.dumps({
            "at": datetime.utcnow().isoformat() + "Z", "people": people, "connections": len(conns)})))
        db.commit()
        out[provider] = people
        if conns:
            log.info("Copied the %s keys from .env to %d people and %d connections.",
                     provider.title(), people, len(conns))
    return out


def env_copied(db: Session) -> dict[str, dict | None]:
    """For Admin → Bank sync: per provider, when the copy ran and to how
    many people and connections ({"at", "people", "connections"}), or None
    while it hasn't."""
    out = {}
    for provider in PROVIDERS:
        row = db.get(AdminSetting, COPIED_KEY.format(provider))
        try:
            got = json.loads(row.value) if row and row.value else None
        except ValueError:
            got = None
        out[provider] = ({"at": got.get("at"), "people": int(got.get("people") or 0),
                          "connections": int(got.get("connections") or 0)}
                         if isinstance(got, dict) else None)
    return out
