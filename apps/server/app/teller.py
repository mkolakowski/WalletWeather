"""Calls out to Teller (bank-providers phase 1, #254).

Teller reaches a bank through its own connections. A person signs in to
their bank on Teller Connect (the separate /bank/teller page, the only page
that loads Teller's script); Connect hands back an access token for that one
bank login (an "enrollment"), which the server keeps encrypted. Every API
call is made over mutual TLS with a client certificate and the access token
as the Basic user name. Since own-bank-keys phase 1 (#276) the application
id, environment, certificate and key are each person's own (`Keys`, from
the database: a connection's copy, or its person's), never `.env`; Teller's
sandbox needs no certificate. API: https://teller.io/docs/api (checked
2026-11-20).

Only posted transactions come in. Teller's docs call `amount` "signed"
without saying which way; it is taken as Teller gives it, money out being
negative, the way SimpleFIN's is. Errors come back as TellerError with a
plain message; the token, the certificate and the key never appear in one.
Bank text is data: cut to size and stored or shown escaped, never acted on.
"""
import contextlib
import os
import secrets
import shutil
import ssl
from dataclasses import dataclass
from datetime import date

import httpx

from .simplefin import BankError, DESCRIPTION_MAX, NAME_MAX, _amount, _text, category_key

API = "https://api.teller.io"
VERSION = "2020-10-12"
ENVIRONMENTS = ("sandbox", "development", "production")
TIMEOUT = 30.0
PAGE = 250          # transactions asked for per page
MAX_PAGES = 20      # 5,000 lines per account per sync at most

# Where the certificate and key are written while a client is made: the
# container's file system is read-only apart from a tmpfs here.
TMP_ROOT = "/tmp"

# Tests put an httpx.MockTransport here as the stand-in Teller.
_transport: httpx.BaseTransport | None = None


class TellerError(BankError):
    pass


@dataclass(frozen=True)
class Keys:
    """One set of Teller keys: the application id, the environment, and the
    client certificate and private key in PEM ("" in the sandbox)."""
    app_id: str
    environment: str = "development"
    certificate: str = ""
    private_key: str = ""

    def __repr__(self) -> str:   # never the certificate or key in a log line
        return f"teller.Keys(app_id={self.app_id!r}, environment={self.environment!r})"


def environment_of(value) -> str:
    env = str(value or "").strip().lower() or "development"
    return env if env in ENVIRONMENTS else "development"


def available(keys: Keys | None) -> bool:
    """Whether these keys can reach Teller: an application id, and a
    certificate and key unless it's Teller's sandbox."""
    return bool(keys and keys.app_id) and (
        keys.environment == "sandbox" or bool(keys.certificate and keys.private_key))


NO_KEYS = TellerError("There are no Teller keys for this connection. Add your Teller keys in "
                      "Settings → Bank sync.", status=409)


def _write_private(folder: str, name: str, text: str) -> str:
    path = os.path.join(folder, name)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(text)
    return path


@contextlib.contextmanager
def cert_files(keys: Keys):
    """The certificate and key written to files only this process's user can
    read, in a fresh folder under the temp directory (/tmp, the container's
    one writable place), for as long as the `with` block runs; then removed.
    httpx reads them once, when a client is made. The folder's name is
    random and made fresh (mkdir fails rather than reuse one), mode 0700."""
    folder = os.path.join(TMP_ROOT, "teller-" + secrets.token_hex(16))
    os.mkdir(folder, 0o700)
    try:
        yield (_write_private(folder, "certificate.pem", keys.certificate),
               _write_private(folder, "private_key.pem", keys.private_key))
    finally:
        shutil.rmtree(folder, ignore_errors=True)


def _client(keys: Keys) -> httpx.Client:
    if not available(keys):
        raise NO_KEYS
    try:
        if keys.certificate and keys.private_key and _transport is None:
            with cert_files(keys) as cert:
                # The files are read here and gone once the block ends.
                return httpx.Client(base_url=API, timeout=TIMEOUT, follow_redirects=False,
                                    headers={"Teller-Version": VERSION}, cert=cert)
        return httpx.Client(base_url=API, timeout=TIMEOUT, follow_redirects=False,
                            transport=_transport, headers={"Teller-Version": VERSION})
    except (OSError, ValueError):   # ssl.SSLError is an OSError
        raise TellerError("These Teller keys can't be used: the certificate and private key don't "
                          "read as a matching pair. Replace them in Settings → Bank sync.")


def check_pair(keys: Keys) -> None:
    """Whether the certificate and private key load as a matching pair, the
    way httpx will load them. Raises TellerError (400) when they don't."""
    try:
        with cert_files(keys) as (cert, key):
            ssl.create_default_context().load_cert_chain(cert, key)
    except (OSError, ValueError):   # ssl.SSLError is an OSError
        raise TellerError("The certificate and private key don't read as a matching pair. Use the "
                          "two files from the same Teller zip.", status=400)


def check(keys: Keys) -> None:
    """Whether Teller accepts these keys, before they're saved: the
    certificate and key are loaded as a pair, then one call is made with
    them and no access token. Teller answers a known certificate with 401
    (no token) and an unknown one with a certificate error. Raises
    TellerError saying what's wrong."""
    if not keys.app_id:
        raise TellerError("Enter your Teller application id.", status=400)
    if keys.environment != "sandbox" and not (keys.certificate and keys.private_key):
        raise TellerError("Teller's development and production need your certificate and private "
                          "key.", status=400)
    if keys.certificate or keys.private_key:
        check_pair(keys)
    with _client(keys) as c:
        try:
            r = c.get("/accounts")
        except httpx.HTTPError:
            raise TellerError("Couldn't reach Teller to check these keys. Try again in a while.")
    if r.status_code in (200, 401):
        return
    code = ""
    try:
        code = str(((r.json() or {}).get("error") or {}).get("code") or "")
    except (ValueError, AttributeError):
        pass
    if r.status_code in (400, 403) and ("certificate" in code.lower() or "certificate" in r.text[:300].lower()):
        raise TellerError("Teller didn't accept this certificate. Check it's the one from your "
                          "Teller application, for this environment.", status=400)
    raise TellerError(f"Teller answered with an error (HTTP {r.status_code}) while checking these "
                      "keys. Try again in a while.")


def _error(r: httpx.Response) -> TellerError:
    try:
        err = (r.json() or {}).get("error") or {}
        code = str(err.get("code") or "")
    except (ValueError, AttributeError):
        code = ""
    if code.startswith("enrollment.disconnected"):
        return TellerError("Your bank wants you to sign in again before Teller can read it. "
                           "Disconnect this bank, then connect it again.", status=409, revoked=True)
    if r.status_code in (401, 403):
        return TellerError("Teller no longer accepts this connection: it may have been removed "
                           "there. Disconnect, then connect the bank again.", status=409, revoked=True)
    if r.status_code == 400 and "certificate" in code + str(r.text[:300]).lower():
        return TellerError("Teller didn't accept the certificate this connection was made with. "
                           "Check your Teller keys in Settings → Bank sync.")
    if r.status_code == 429:
        return TellerError("Teller asked this server to slow down. Try again in a while.", status=429)
    if r.status_code == 502:
        return TellerError("Your bank isn't answering Teller right now. Try again in a while.")
    return TellerError(f"Teller answered with an error (HTTP {r.status_code}). Try again in a while.")


def _get(c: httpx.Client, path: str, token: str, params: dict | None = None):
    try:
        r = c.get(path, params=params, auth=(token, ""))
    except httpx.HTTPError:
        raise TellerError("Couldn't reach Teller. Try again in a while.")
    return r


def _json(r: httpx.Response):
    try:
        return r.json()
    except ValueError:
        raise TellerError("Teller sent something this server can't read. Try again in a while.")


def _account(a: dict) -> dict | None:
    if not isinstance(a, dict) or not isinstance(a.get("id"), str):
        return None
    inst = a.get("institution") if isinstance(a.get("institution"), dict) else {}
    name = _text(a.get("name"), NAME_MAX) or "Bank account"
    if a.get("last_four"):
        name = f"{name} ··{_text(a.get('last_four'), 4)}"
    return {"id": a["id"][:200], "name": name, "org": _text(inst.get("name"), NAME_MAX),
            "type": _text(a.get("type"), 20), "closed": a.get("status") == "closed"}


def fetch_accounts(keys: Keys, token: str) -> list[dict]:
    """The bank accounts this enrollment reaches: id, name, org, type."""
    with _client(keys) as c:
        r = _get(c, "/accounts", token)
        if r.status_code != 200:
            raise _error(r)
        data = _json(r)
    if not isinstance(data, list):
        raise TellerError("Teller sent something this server can't read. Try again in a while.")
    return [a for a in (_account(x) for x in data) if a]


def _transactions(c: httpx.Client, token: str, account_id: str, start: date) -> list[dict]:
    out, from_id = [], None
    for _ in range(MAX_PAGES):
        params = {"count": PAGE, "start_date": start.isoformat()}
        if from_id:
            params["from_id"] = from_id
        r = _get(c, f"/accounts/{account_id}/transactions", token, params)
        if r.status_code != 200:
            raise _error(r)
        page = _json(r)
        if not isinstance(page, list):
            raise TellerError("Teller sent something this server can't read. Try again in a while.")
        for t in page:
            if not isinstance(t, dict) or not isinstance(t.get("id"), str):
                continue
            if t.get("status") != "posted":
                continue   # decided 2026-11-16: lines come in once posted
            amount = _amount(t.get("amount"))
            try:
                day = date.fromisoformat(str(t.get("date"))[:10])
            except ValueError:
                continue
            if amount is None or day < start:
                continue
            details = t.get("details") if isinstance(t.get("details"), dict) else {}
            out.append({"id": t["id"][:200], "date": day, "amount": amount,
                        "description": _text(t.get("description"), DESCRIPTION_MAX) or "Bank transaction",
                        "category": category_key(details.get("category"))})
        if len(page) < PAGE:
            break
        last = page[-1].get("id") if isinstance(page[-1], dict) else None
        if not isinstance(last, str) or last == from_id:
            break
        from_id = last
    return out


def _balance(c: httpx.Client, token: str, account: dict):
    """The bank's posted balance. Teller bills this call in production, so
    the sync asks only when it needs one (#215, #256; see fetch). A credit
    card's balance is what's owed, so it counts against you."""
    try:
        r = _get(c, f"/accounts/{account['id']}/balances", token)
        if r.status_code != 200:
            return None
        data = _json(r)
    except TellerError:
        # A balance that can't be read leaves the lines already read to land
        # (#256); the caller keeps or clears the balance it had.
        return None
    value = _amount(data.get("ledger")) if isinstance(data, dict) else None
    if value is not None and account.get("type") == "credit":
        value = -value
    return value


def fetch(keys: Keys, token: str, starts: dict[str, date], balances_for: set[str] = frozenset(),
          balance_if=None) -> dict:
    """{"accounts": [...], "messages": [...]} in SimpleFIN's shape: every
    account the enrollment reaches, with posted transactions since its date
    in `starts` for the ones asked for. The billed balance call is made for
    an account in `balances_for`, or when `balance_if(account_id,
    transactions)` says so after its lines are read (#256): the caller knows
    whether anything new came in, and a balance that nothing has moved is
    not worth paying for."""
    accounts = fetch_accounts(keys, token)
    messages = []
    with _client(keys) as c:
        for a in accounts:
            a["transactions"], a["balance"] = [], None
            start = starts.get(a["id"])
            if start is None:
                continue
            if a.pop("closed", False):
                messages.append(f"{a['name']} is closed at the bank.")
                continue
            a["transactions"] = _transactions(c, token, a["id"], start)
            if a["id"] in balances_for or (balance_if and balance_if(a["id"], a["transactions"])):
                a["balance"] = _balance(c, token, a)
                a["asked_balance"] = True
    for a in accounts:
        a.pop("closed", None)
    return {"accounts": accounts, "messages": messages[:5]}


def remove(keys: Keys, token: str) -> None:
    """End the enrollment at Teller, so it stops reading the bank. A token
    Teller no longer knows counts as removed."""
    try:
        with _client(keys) as c:
            r = c.delete("/accounts", auth=(token, ""))
    except httpx.HTTPError:
        raise TellerError("Couldn't reach Teller to remove the connection there.")
    if r.status_code in (200, 202, 204, 401, 403, 404):
        return
    raise _error(r)
