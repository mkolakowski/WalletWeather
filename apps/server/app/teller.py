"""Calls out to Teller (bank-providers phase 1, #254).

Teller reaches a bank through its own connections. A person signs in to
their bank on Teller Connect (the separate /bank/teller page, the only page
that loads Teller's script); Connect hands back an access token for that one
bank login (an "enrollment"), which the server keeps encrypted. Every API
call is made over mutual TLS with the instance's own client certificate
(TELLER_CERT_FILE and TELLER_KEY_FILE; Teller's sandbox doesn't need one)
and the access token as the Basic user name. API: https://teller.io/docs/api
(checked 2026-11-20).

Only posted transactions come in. Teller's docs call `amount` "signed"
without saying which way; it is taken as Teller gives it, money out being
negative, the way SimpleFIN's is. Errors come back as TellerError with a
plain message; the token never appears in one. Bank text is data: cut to
size and stored or shown escaped, never acted on.
"""
import os
from datetime import date

import httpx

from .simplefin import BankError, DESCRIPTION_MAX, NAME_MAX, _amount, _text, category_key

API = "https://api.teller.io"
VERSION = "2020-10-12"
ENVIRONMENTS = ("sandbox", "development", "production")
TIMEOUT = 30.0
PAGE = 250          # transactions asked for per page
MAX_PAGES = 20      # 5,000 lines per account per sync at most

# Tests put an httpx.MockTransport here as the stand-in Teller.
_transport: httpx.BaseTransport | None = None


class TellerError(BankError):
    pass


def app_id() -> str:
    return os.environ.get("TELLER_APP_ID", "").strip()


def environment() -> str:
    env = os.environ.get("TELLER_ENV", "").strip().lower() or "development"
    return env if env in ENVIRONMENTS else "development"


def _cert() -> tuple[str, str] | None:
    cert = os.environ.get("TELLER_CERT_FILE", "").strip()
    key = os.environ.get("TELLER_KEY_FILE", "").strip()
    if cert and key and os.path.isfile(cert) and os.path.isfile(key):
        return cert, key
    return None


def available() -> bool:
    """Whether this instance can offer Teller: an application id, and a
    certificate and key unless it's Teller's sandbox."""
    return bool(app_id()) and (environment() == "sandbox" or _cert() is not None)


def _client() -> httpx.Client:
    kw = {}
    cert = _cert()
    if cert and _transport is None:
        kw["cert"] = cert
    try:
        return httpx.Client(base_url=API, timeout=TIMEOUT, follow_redirects=False,
                            transport=_transport, headers={"Teller-Version": VERSION}, **kw)
    except (OSError, ValueError):   # ssl.SSLError is an OSError
        raise TellerError("This server can't read its Teller certificate and key. Check the files "
                          "in TELLER_CERT_DIR and that they're readable.")


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
        return TellerError("Teller didn't accept this server's certificate. Check TELLER_CERT_FILE "
                           "and TELLER_KEY_FILE in .env.")
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


def fetch_accounts(token: str) -> list[dict]:
    """The bank accounts this enrollment reaches: id, name, org, type."""
    with _client() as c:
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
    r = _get(c, f"/accounts/{account['id']}/balances", token)
    if r.status_code != 200:
        return None
    data = _json(r)
    value = _amount(data.get("ledger")) if isinstance(data, dict) else None
    if value is not None and account.get("type") == "credit":
        value = -value
    return value


def fetch(token: str, starts: dict[str, date], balances_for: set[str] = frozenset(),
          balance_if=None) -> dict:
    """{"accounts": [...], "messages": [...]} in SimpleFIN's shape: every
    account the enrollment reaches, with posted transactions since its date
    in `starts` for the ones asked for. The billed balance call is made for
    an account in `balances_for`, or when `balance_if(account_id,
    transactions)` says so after its lines are read (#256): the caller knows
    whether anything new came in, and a balance that nothing has moved is
    not worth paying for."""
    accounts = fetch_accounts(token)
    messages = []
    with _client() as c:
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


def remove(token: str) -> None:
    """End the enrollment at Teller, so it stops reading the bank. A token
    Teller no longer knows counts as removed."""
    try:
        with _client() as c:
            r = c.delete("/accounts", auth=(token, ""))
    except httpx.HTTPError:
        raise TellerError("Couldn't reach Teller to remove the connection there.")
    if r.status_code in (200, 202, 204, 401, 403, 404):
        return
    raise _error(r)
