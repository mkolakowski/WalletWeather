"""Calls out to SimpleFIN Bridge (bank-sync phase 2, #194).

The only place the server talks to another service on a user's behalf. A
setup token is a base64 URL that is claimed once (POST) for an access URL with
Basic credentials in it; GET <access URL>/accounts then lists the bank
accounts with their posted transactions. Protocol: https://www.simplefin.org/protocol.html
(checked 2026-11-16; both the v1 "org" and the v2 "connections" shapes are
read). Bridge allows 90 days per request and about 24 requests a day.

Every URL, the one inside a pasted token and the access URL SimpleFIN hands
back, must be https on a host in SIMPLEFIN_HOSTS, and redirects are never
followed, so a token can't point the server anywhere else. Errors come back
as SimpleFINError with a plain message; the access URL never appears in one.
Bank text (names, descriptions, messages) is data: it's cut to size and stored
or shown escaped, never acted on.
"""
import base64
import binascii
import os
import re
from datetime import date, datetime, timezone
from decimal import Decimal, InvalidOperation
from urllib.parse import unquote, urlsplit, urlunsplit

import httpx

DEFAULT_HOSTS = "bridge.simplefin.org,beta-bridge.simplefin.org"
TIMEOUT = 30.0
MAX_DAYS_PER_REQUEST = 90
NAME_MAX, DESCRIPTION_MAX, MESSAGE_MAX = 120, 500, 200

# Tests put an httpx.MockTransport here as the stand-in SimpleFIN.
_transport: httpx.BaseTransport | None = None

_CONTROL = re.compile(r"[\x00-\x1f\x7f]")


# "Withdrawal Example Internet / TYPE: … ID: … CO: … ACH Trace Number: …":
# some banks put the whole ACH record in a line's description (#213).
_DIRECTION = re.compile(r"^(?:(?:ACH|POS|Debit Card|Online|Mobile|External)\s+)?(?:Withdrawal|Deposit)(?:\s+|$)",
                        re.IGNORECASE)


def short_name(text: str | None) -> str | None:
    """A synced line's name when the bank's text carries more than a name:
    the part before " / ", without a leading "Withdrawal" or "Deposit"
    (decided 2026-11-16, #213). None when there's nothing to shorten. A
    short name has no " / " in it, so shortening twice changes nothing."""
    if not text or " / " not in text:
        return None
    head = _DIRECTION.sub("", text.split(" / ", 1)[0].strip()).strip()
    return head[:NAME_MAX] if head else None


class BankError(Exception):
    """A provider's failure in plain words (SimpleFIN, Teller or Plaid,
    bank-providers phase 1, #254). `status` is the HTTP status to answer
    with; `revoked` means the connection no longer works and has to be made
    again. Never carries a token or an access address."""

    def __init__(self, message: str, status: int = 502, revoked: bool = False):
        super().__init__(message)
        self.status = status
        self.revoked = revoked


class SimpleFINError(BankError):
    pass


def allowed_hosts() -> set[str]:
    raw = os.environ.get("SIMPLEFIN_HOSTS", "") or DEFAULT_HOSTS
    return {h.strip().lower() for h in raw.split(",") if h.strip()}


def _text(value, limit: int) -> str:
    return _CONTROL.sub(" ", str(value if value is not None else "")).strip()[:limit]


CATEGORY_MAX = 60


def category_key(value) -> str | None:
    """A provider's own category for a line ("FOOD_AND_DRINK", "dining") as
    the key it's kept and mapped by: trimmed, lowercased, cut to size
    (#255). None when there's none to keep."""
    text = _text(value, CATEGORY_MAX).lower() if isinstance(value, str) else ""
    return text or None


def _checked(url: str):
    """The URL split, if it's https on an allowed host and the default port."""
    try:
        parts = urlsplit(url)
        port = parts.port
    except ValueError:
        raise SimpleFINError("That doesn't look like a SimpleFIN setup token. "
                             "Copy it again from SimpleFIN Bridge.", status=400)
    host = (parts.hostname or "").lower()
    if parts.scheme != "https" or not host or port not in (None, 443):
        raise SimpleFINError("That token doesn't point at SimpleFIN over a secure "
                             "connection. Nothing was sent.", status=400)
    if host not in allowed_hosts():
        raise SimpleFINError(f"That token points at {host[:80]}, which isn't SimpleFIN. "
                             "Nothing was sent to it.", status=400)
    return parts


def _client() -> httpx.Client:
    return httpx.Client(timeout=TIMEOUT, follow_redirects=False, transport=_transport)


def claim(setup_token: str) -> str:
    """Exchange a setup token for its access URL. A token works once."""
    token = "".join((setup_token or "").split())
    try:
        url = base64.b64decode(token + "=" * (-len(token) % 4), validate=True).decode("ascii")
    except (binascii.Error, ValueError):
        raise SimpleFINError("That doesn't look like a SimpleFIN setup token. "
                             "Copy it again from SimpleFIN Bridge.", status=400)
    parts = _checked(url)
    if parts.username or parts.password:
        raise SimpleFINError("That doesn't look like a SimpleFIN setup token. "
                             "Copy it again from SimpleFIN Bridge.", status=400)
    try:
        with _client() as c:
            r = c.post(url, content=b"")
    except httpx.HTTPError:
        raise SimpleFINError("Couldn't reach SimpleFIN. Try again in a while.")
    if r.status_code == 403:
        raise SimpleFINError(
            "SimpleFIN says this token was already used or doesn't exist. If you didn't "
            "use it yourself, disable it at SimpleFIN Bridge, then make a new one.", status=400)
    if r.status_code != 200:
        raise SimpleFINError(f"SimpleFIN didn't accept the token (HTTP {r.status_code}). "
                             "Try again in a while.")
    access = r.text.strip()
    _split_access(access)   # checks the host SimpleFIN sent back, too
    return access


def _split_access(access: str) -> tuple[str, tuple[str, str]]:
    """(the access URL without its credentials, (user, password))."""
    parts = _checked(access)
    if not parts.username or not parts.password:
        raise SimpleFINError("SimpleFIN sent back something that isn't an access address. "
                             "Try connecting again with a new token.")
    base = urlunsplit(("https", parts.hostname, parts.path.rstrip("/"), "", ""))
    return base, (unquote(parts.username), unquote(parts.password))


def _epoch(d: date) -> int:
    return int(datetime(d.year, d.month, d.day, tzinfo=timezone.utc).timestamp())


def fetch_accounts(access: str, start: date | None = None, balances_only: bool = False) -> dict:
    """The bank accounts and, unless balances_only, their posted transactions
    since `start`. One request: the caller keeps `start` within 90 days."""
    base, auth = _split_access(access)
    params = {}
    if balances_only:
        params["balances-only"] = "1"
    if start is not None:
        params["start-date"] = str(_epoch(start))
    try:
        with _client() as c:
            r = c.get(base + "/accounts", params=params, auth=auth)
    except httpx.HTTPError:
        raise SimpleFINError("Couldn't reach SimpleFIN. Try again in a while.")
    if r.status_code == 402:
        raise SimpleFINError("SimpleFIN says your subscription needs paying. Renew it at "
                             "SimpleFIN Bridge, then sync again.", status=402)
    if r.status_code == 403:
        raise SimpleFINError("SimpleFIN no longer accepts this connection: it may have been "
                             "disabled there. Disconnect, then connect again with a new token.",
                             status=409, revoked=True)
    if r.status_code != 200:
        raise SimpleFINError(f"SimpleFIN answered with an error (HTTP {r.status_code}). "
                             "Try again in a while.")
    try:
        data = r.json()
    except ValueError:
        data = None
    if not isinstance(data, dict) or not isinstance(data.get("accounts"), list):
        raise SimpleFINError("SimpleFIN sent something this server can't read. Try again in a while.")
    return parse(data)


def _amount(value) -> Decimal | None:
    try:
        d = Decimal(str(value))
    except (InvalidOperation, ValueError):
        return None
    if not d.is_finite() or abs(d) > Decimal("1e12"):
        return None
    return d.quantize(Decimal("0.01"))


def _balance_at(value) -> datetime | None:
    """SimpleFIN's balance-date (epoch seconds) as a naive UTC time, or None
    when it's missing, nonsense or in the future."""
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
        return None
    try:
        at = datetime.fromtimestamp(value, tz=timezone.utc).replace(tzinfo=None)
    except (OverflowError, OSError, ValueError):
        return None
    return at if at <= datetime.utcnow() else None


def parse(data: dict) -> dict:
    """SimpleFIN's account set as {"accounts": [...], "messages": [...]},
    keeping only what WalletWeather uses. Pending transactions are left out
    (decided 2026-11-16: sync waits until the bank posts them)."""
    orgs = {}
    for conn in data.get("connections") or []:
        if isinstance(conn, dict) and conn.get("conn_id") is not None:
            orgs[str(conn["conn_id"])] = conn.get("name")
    accounts = []
    for a in data["accounts"]:
        if not isinstance(a, dict) or not isinstance(a.get("id"), (str, int)):
            continue
        org = orgs.get(str(a.get("conn_id"))) or ((a.get("org") or {}).get("name")
                                                  if isinstance(a.get("org"), dict) else None)
        txns = []
        for t in a.get("transactions") or []:
            if not isinstance(t, dict) or t.get("pending") is True:
                continue
            posted, amount = t.get("posted"), _amount(t.get("amount"))
            if (not isinstance(t.get("id"), (str, int)) or isinstance(posted, bool)
                    or not isinstance(posted, int) or posted <= 0 or amount is None):
                continue
            try:
                day = datetime.fromtimestamp(posted, tz=timezone.utc).date()
            except (OverflowError, OSError, ValueError):
                continue
            txns.append({"id": str(t["id"]), "date": day, "amount": amount,
                         "description": _text(t.get("description"), DESCRIPTION_MAX) or "Bank transaction"})
        accounts.append({"id": str(a["id"]), "name": _text(a.get("name"), NAME_MAX) or "Bank account",
                         "org": _text(org, NAME_MAX), "transactions": txns,
                         # The bank's balance when it last looked (#215); None if it sent none.
                         "balance": _amount(a.get("balance")),
                         # When the bank had it (balance-date), if it said (#256).
                         "balance_at": _balance_at(a.get("balance-date"))})
    messages = []
    for e in data.get("errlist") or []:
        if isinstance(e, dict) and e.get("msg"):
            messages.append(_text(e["msg"], MESSAGE_MAX))
    for e in data.get("errors") or []:
        if isinstance(e, str) and e.strip():
            messages.append(_text(e, MESSAGE_MAX))
    return {"accounts": accounts, "messages": messages[:5]}
