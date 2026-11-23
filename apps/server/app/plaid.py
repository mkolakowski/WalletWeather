"""Calls out to Plaid (bank-providers phase 1, #254).

Connecting uses Hosted Link: the server asks Plaid for a link token with a
`hosted_link` object, the person opens the link Plaid gives on Plaid's own
site in a new tab, and the server asks /link/token/get for the result (no
webhook, so no public address). The public token in that result is swapped
once for an access token for that one bank login (an "Item"), kept
encrypted. Lines come from /transactions/sync with a cursor kept per
connection. API: https://plaid.com/docs/api/ (checked 2026-11-20).

Plaid's amounts are positive when money leaves the account; they're turned
round here, so money out is negative as everywhere else. Pending lines are
left out. Since own-bank-keys phase 1 (#276) the client id, secret and
environment are each person's own (`Keys`, from the database: a
connection's copy, or its person's), never `.env`. Errors come back as
PlaidError with a plain message; the keys and tokens never appear in one. Bank text is data: cut to size and stored or
shown escaped, never acted on.
"""
from dataclasses import dataclass
from datetime import date, datetime, timedelta

import httpx

from .simplefin import BankError, DESCRIPTION_MAX, NAME_MAX, _amount, _text, category_key

HOSTS = {"sandbox": "https://sandbox.plaid.com", "production": "https://production.plaid.com"}
TIMEOUT = 30.0
SYNC_PAGE = 500
MAX_PAGES = 40
LINK_MINUTES = 30   # how long a Hosted Link stays usable (Plaid's own default)

# Tests put an httpx.MockTransport here as the stand-in Plaid.
_transport: httpx.BaseTransport | None = None

# The connection is gone or needs the person at Plaid again.
REVOKED = {"ITEM_LOGIN_REQUIRED", "ITEM_NOT_FOUND", "ACCESS_NOT_GRANTED", "INVALID_ACCESS_TOKEN",
           "USER_PERMISSION_REVOKED", "NO_ACCOUNTS"}
BAD_KEYS = {"INVALID_API_KEYS", "INVALID_SECRET", "INVALID_CLIENT_ID", "UNAUTHORIZED_ENVIRONMENT"}
AT_THE_BANK = {"PASSWORD_RESET_REQUIRED", "USER_SETUP_REQUIRED", "ITEM_LOCKED"}


class PlaidError(BankError):
    def __init__(self, message: str, status: int = 502, revoked: bool = False, code: str = ""):
        super().__init__(message, status, revoked)
        self.code = code


@dataclass(frozen=True)
class Keys:
    """One set of Plaid keys: the client id, the secret, the environment."""
    client_id: str
    secret: str
    environment: str = "production"

    def __repr__(self) -> str:   # never the secret in a log line
        return f"plaid.Keys(client_id={self.client_id!r}, environment={self.environment!r})"


def environment_of(value) -> str:
    env = str(value or "").strip().lower() or "production"
    return env if env in HOSTS else "production"


def available(keys: Keys | None) -> bool:
    return bool(keys and keys.client_id and keys.secret)


def _post(keys: Keys | None, path: str, body: dict) -> dict:
    if not available(keys):
        raise PlaidError("There are no Plaid keys for this connection. Add your Plaid keys in "
                         "Settings → Bank sync.", status=409)
    try:
        with httpx.Client(base_url=HOSTS[environment_of(keys.environment)], timeout=TIMEOUT,
                          follow_redirects=False, transport=_transport) as c:
            r = c.post(path, json=body, headers={"PLAID-CLIENT-ID": keys.client_id,
                                                 "PLAID-SECRET": keys.secret})
    except httpx.HTTPError:
        raise PlaidError("Couldn't reach Plaid. Try again in a while.")
    try:
        data = r.json()
    except ValueError:
        data = None
    if r.status_code == 200 and isinstance(data, dict):
        return data
    code = str((data or {}).get("error_code") or "") if isinstance(data, dict) else ""
    kind = str((data or {}).get("error_type") or "") if isinstance(data, dict) else ""
    e = _error(r.status_code, code, kind)
    e.code = code
    raise e


def check(keys: Keys) -> None:
    """Whether Plaid accepts these keys, before they're saved: one call to
    /institutions/get, which needs only the client id and secret. Raises
    PlaidError saying what's wrong."""
    if not keys.client_id or not keys.secret:
        raise PlaidError("Enter your Plaid client id and secret.", status=400)
    try:
        _post(keys, "/institutions/get", {"count": 1, "offset": 0, "country_codes": ["US"]})
    except PlaidError as e:
        if e.code in BAD_KEYS:
            raise PlaidError(f"Plaid didn't accept this client id and secret for {keys.environment}. "
                             "Check them on Plaid's dashboard (Developers → Keys).", status=400,
                             code=e.code)
        raise


def _error(status: int, code: str, kind: str) -> PlaidError:
    if code in REVOKED:
        return PlaidError("Plaid no longer reaches this bank: you may need to sign in to it again. "
                          "Disconnect this bank, then connect it again.", status=409, revoked=True)
    if code in AT_THE_BANK:
        return PlaidError("Your bank wants something from you on its own website first (a new "
                          "password, a locked login or a setup step). Sort that out there, then sync again.",
                          status=409)
    if kind == "RATE_LIMIT_EXCEEDED" or status == 429:
        return PlaidError("Plaid asked this server to slow down. Try again in a few minutes.", status=429)
    if code in BAD_KEYS:
        return PlaidError("Plaid didn't accept the keys this connection was made with. Check your "
                          "Plaid keys in Settings → Bank sync.")
    if kind == "INSTITUTION_ERROR":
        return PlaidError("Your bank isn't answering Plaid right now. Try again in a while.")
    return PlaidError(f"Plaid answered with an error ({(code or 'HTTP ' + str(status))[:60]}). "
                      "Try again in a while.")


def create_link(keys: Keys, user_ref: str, client_name: str, days: int, completion_uri: str | None = None) -> dict:
    """A Hosted Link for one bank login: {"link_token", "url", "expires_at"}.
    `completion_uri` is where Plaid sends the browser when the person is done
    or gives up (a connection started from the iPhone app, #258): the
    server's own /app-connect-bank page, which checks how it went. Plaid
    needs no registration for it. `is_mobile_app` is left off on purpose
    (decided 2026-11-21): it would need a registered Universal Link."""
    hosted = {"url_lifetime_seconds": LINK_MINUTES * 60}
    if completion_uri:
        hosted["completion_redirect_uri"] = completion_uri
    data = _post(keys, "/link/token/create", {
        "client_name": (client_name or "WalletWeather")[:30],
        "language": "en",
        "country_codes": ["US"],
        "user": {"client_user_id": user_ref},
        "products": ["transactions"],
        "transactions": {"days_requested": max(30, min(730, days))},
        "hosted_link": hosted,
    })
    token, url = data.get("link_token"), data.get("hosted_link_url")
    if not isinstance(token, str) or not isinstance(url, str) or not url.startswith("https://"):
        raise PlaidError("Plaid didn't send a link to connect with. Try again in a while.")
    return {"link_token": token, "url": url,
            "expires_at": datetime.utcnow() + timedelta(minutes=LINK_MINUTES)}


def link_result(keys: Keys, link_token: str) -> dict:
    """How the Hosted Link went: {"state": "waiting" | "done" | "exited",
    "public_token", "institution"}. Plaid keeps a finished session's result
    for six hours."""
    data = _post(keys, "/link/token/get", {"link_token": link_token})
    sessions = data.get("link_sessions") or []
    finished = False
    for s in sessions if isinstance(sessions, list) else []:
        if not isinstance(s, dict):
            continue
        results = s.get("results") if isinstance(s.get("results"), dict) else {}
        for item in results.get("item_add_results") or []:
            if isinstance(item, dict) and isinstance(item.get("public_token"), str):
                inst = item.get("institution") if isinstance(item.get("institution"), dict) else {}
                return {"state": "done", "public_token": item["public_token"],
                        "institution": _text(inst.get("name"), NAME_MAX)}
        if s.get("finished_at"):
            finished = True
    return {"state": "exited" if finished else "waiting", "public_token": None, "institution": ""}


def exchange(keys: Keys, public_token: str) -> str:
    data = _post(keys, "/item/public_token/exchange", {"public_token": public_token})
    token = data.get("access_token")
    if not isinstance(token, str) or not token:
        raise PlaidError("Plaid didn't finish connecting the bank. Try connecting again.")
    return token


def _account(a: dict, org: str) -> dict | None:
    if not isinstance(a, dict) or not isinstance(a.get("account_id"), str):
        return None
    name = _text(a.get("name") or a.get("official_name"), NAME_MAX) or "Bank account"
    if a.get("mask"):
        name = f"{name} ··{_text(a.get('mask'), 4)}"
    balances = a.get("balances") if isinstance(a.get("balances"), dict) else {}
    balance = _amount(balances.get("current")) if balances.get("current") is not None else None
    # A card's or loan's current balance is what's owed: it counts against you.
    if balance is not None and a.get("type") in ("credit", "loan"):
        balance = -balance
    return {"id": a["account_id"][:200], "name": name, "org": org, "balance": balance}


def fetch_accounts(keys: Keys, access_token: str) -> tuple[list[dict], str]:
    """The bank accounts this Item reaches, and the bank's name."""
    data = _post(keys, "/accounts/get", {"access_token": access_token})
    item = data.get("item") if isinstance(data.get("item"), dict) else {}
    org = _text(item.get("institution_name"), NAME_MAX)
    accounts = [a for a in (_account(x, org) for x in data.get("accounts") or []) if a]
    return accounts, org


def fetch(keys: Keys, access_token: str, cursor: str | None, org: str = "") -> dict:
    """New posted lines since `cursor` ("" or None for everything Plaid
    has), in SimpleFIN's shape plus "cursor" (where the next sync starts).
    Raises a PlaidError while Plaid is still gathering the first history."""
    start = cursor or ""
    for _attempt in range(3):
        added, accounts, cur, status = [], {}, start, ""
        try:
            for _ in range(MAX_PAGES):
                body = {"access_token": access_token, "count": SYNC_PAGE}
                if cur:
                    body["cursor"] = cur
                data = _post(keys, "/transactions/sync", body)
                for a in data.get("accounts") or []:
                    acc = _account(a, org)
                    if acc:
                        accounts[acc["id"]] = acc
                added.extend(t for t in data.get("added") or [] if isinstance(t, dict))
                status = str(data.get("transactions_update_status") or "")
                cur = data.get("next_cursor") if isinstance(data.get("next_cursor"), str) else cur
                if not data.get("has_more"):
                    break
        except PlaidError as e:
            if e.code == "TRANSACTIONS_SYNC_MUTATION_DURING_PAGINATION":
                continue   # Plaid's rule: start the whole update again
            raise
        break
    else:
        raise PlaidError("Plaid's data kept changing while it was read. Try again in a few minutes.")
    by_account: dict[str, list] = {}
    for t in added:
        if t.get("pending") is True or not isinstance(t.get("transaction_id"), str) \
                or not isinstance(t.get("account_id"), str):
            continue
        amount = _amount(t.get("amount"))
        try:
            day = date.fromisoformat(str(t.get("date"))[:10])
        except ValueError:
            continue
        if amount is None:
            continue
        by_account.setdefault(t["account_id"], []).append({
            "id": t["transaction_id"][:200], "date": day, "amount": -amount,
            "description": _text(t.get("name") or t.get("merchant_name"), DESCRIPTION_MAX)
                           or "Bank transaction",
            "category": category_key((t.get("personal_finance_category") or {}).get("primary")
                                     if isinstance(t.get("personal_finance_category"), dict) else None)})
    out = []
    for acc_id, acc in accounts.items():
        out.append({**acc, "transactions": by_account.pop(acc_id, [])})
    for acc_id, txns in by_account.items():   # lines for an account the page didn't list
        out.append({"id": acc_id[:200], "name": "Bank account", "org": org, "balance": None,
                    "transactions": txns})
    if status == "NOT_READY" and not start and not added:
        raise PlaidError("Plaid is still gathering your bank's history. Sync again in a few minutes.",
                         status=409)
    return {"accounts": out, "messages": [], "cursor": cur}


def remove(keys: Keys, access_token: str) -> None:
    """Remove the Item at Plaid: it stops reading the bank (and billing). An
    Item Plaid no longer knows counts as removed."""
    try:
        _post(keys, "/item/remove", {"access_token": access_token})
    except PlaidError as e:
        if e.revoked:
            return
        raise
