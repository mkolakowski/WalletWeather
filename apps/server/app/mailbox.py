"""Calls out to Microsoft for email alerts (bank-alert-emails phase 1, #206).

Signing in uses the Microsoft identity platform's OAuth 2.0 endpoints, either
way (decided 2026-11-16, open question 1): the device code flow (a short code
typed at microsoft.com/devicelogin, no return address or client secret
needed) or the authorization code flow with PKCE and a client secret, for an
instance reached over https://. Mail is read with Microsoft Graph v1.0, with
read-only access (Mail.Read), from one folder.

Endpoints checked 2026-11-16 against learn.microsoft.com:
  v2-oauth2-device-code: POST {login}/{tenant}/oauth2/v2.0/devicecode, then
    poll /token with grant_type urn:ietf:params:oauth:grant-type:device_code
    (authorization_pending, authorization_declined, expired_token, slow_down).
  graph user-list-messages: GET /me/mailFolders/{id}/messages with $filter,
    $orderby (the same property as $filter), $select, $top up to 1000, pages
    by @odata.nextLink.

The server only ever talks to the two hosts below, over https, without
following redirects; a nextLink pointing anywhere else is refused. Errors
come back as MailboxError with a plain message; no token ever appears in one.
Mail text is data: see alerts.py for how it's read.
"""
import base64
import hashlib
import os
import re
import secrets
from datetime import datetime, timezone
from urllib.parse import quote, urlencode, urlsplit

import httpx

LOGIN_HOST = "login.microsoftonline.com"
GRAPH_HOST = "graph.microsoft.com"
GRAPH = f"https://{GRAPH_HOST}/v1.0"
SCOPES = "offline_access User.Read Mail.Read"
TIMEOUT = 30.0
DEVICE_GRANT = "urn:ietf:params:oauth:grant-type:device_code"
# Ids stay the same when a message is moved between folders.
_ID_HEADER = 'IdType="ImmutableId"'
_TENANT = re.compile(r"^[A-Za-z0-9][A-Za-z0-9.\-]{0,99}$")

# Tests put an httpx.MockTransport here as the stand-in Microsoft.
_transport: httpx.BaseTransport | None = None


class MailboxError(Exception):
    """A reason in plain words. `status` is the HTTP status to answer with;
    `revoked` means the sign-in no longer works and has to be made again."""

    def __init__(self, message: str, status: int = 502, revoked: bool = False):
        super().__init__(message)
        self.status = status
        self.revoked = revoked


def client_id() -> str:
    return os.environ.get("MS_CLIENT_ID", "").strip()


def client_secret() -> str:
    return os.environ.get("MS_CLIENT_SECRET", "").strip()


def tenant() -> str:
    t = os.environ.get("MS_TENANT", "").strip() or "common"
    return t if _TENANT.fullmatch(t) else "common"


def available() -> bool:
    return bool(client_id())


def _login(path: str) -> str:
    return f"https://{LOGIN_HOST}/{tenant()}/oauth2/v2.0/{path}"


def _client() -> httpx.Client:
    return httpx.Client(timeout=TIMEOUT, follow_redirects=False, transport=_transport)


def _token_error(r: httpx.Response) -> str:
    try:
        return str(r.json().get("error") or "")
    except ValueError:
        return ""


def _tokens(r: httpx.Response, refresh: str | None = None) -> dict:
    try:
        data = r.json()
    except ValueError:
        data = None
    if not isinstance(data, dict) or not isinstance(data.get("access_token"), str):
        raise MailboxError("Microsoft sent something this server can't read. Try again in a while.")
    expires = data.get("expires_in")
    expires = int(expires) if isinstance(expires, (int, str)) and str(expires).isdigit() else 3600
    new_refresh = data.get("refresh_token") if isinstance(data.get("refresh_token"), str) else refresh
    if not new_refresh:
        raise MailboxError("Microsoft didn't allow staying signed in. Connect again and accept "
                           "every permission asked for.")
    return {"access": data["access_token"], "refresh": new_refresh,
            "expires_at": int(datetime.now(timezone.utc).timestamp()) + max(60, expires) - 60}


def _post_token(form: dict) -> httpx.Response:
    try:
        with _client() as c:
            return c.post(_login("token"), data=form)
    except httpx.HTTPError:
        raise MailboxError("Couldn't reach Microsoft. Try again in a while.")


# ---------- Signing in with a code (device code flow) ----------

def start_device() -> dict:
    """Ask Microsoft for a code to show. Returns user_code, verification_uri,
    expires_in, interval and device_code (kept on the server, never shown)."""
    try:
        with _client() as c:
            r = c.post(_login("devicecode"), data={"client_id": client_id(), "scope": SCOPES})
    except httpx.HTTPError:
        raise MailboxError("Couldn't reach Microsoft. Try again in a while.")
    if r.status_code != 200:
        err = _token_error(r)
        if err in ("invalid_client", "unauthorized_client"):
            raise MailboxError("Microsoft doesn't accept this server's app for signing in with a "
                               "code. In the Entra portal, turn on \"Allow public client flows\" "
                               "for the app (see the setup guide).", status=400)
        raise MailboxError(f"Microsoft didn't start the sign-in (HTTP {r.status_code}). "
                           "Try again in a while.")
    try:
        data = r.json()
    except ValueError:
        data = None
    if not isinstance(data, dict) or not all(isinstance(data.get(k), str) for k in
                                             ("device_code", "user_code", "verification_uri")):
        raise MailboxError("Microsoft sent something this server can't read. Try again in a while.")
    uri = data["verification_uri"]
    if urlsplit(uri).scheme != "https":
        raise MailboxError("Microsoft sent something this server can't read. Try again in a while.")

    def num(key, default):
        v = data.get(key)
        return int(v) if isinstance(v, int) and 0 < v < 7200 else default

    return {"device_code": data["device_code"], "user_code": data["user_code"][:20],
            "verification_uri": uri[:200], "expires_in": num("expires_in", 900),
            "interval": num("interval", 5)}


def poll_device(device_code: str) -> dict | None:
    """One poll. The tokens once signed in; None while still waiting."""
    r = _post_token({"grant_type": DEVICE_GRANT, "client_id": client_id(),
                     "device_code": device_code})
    if r.status_code == 200:
        return _tokens(r)
    err = _token_error(r)
    if err in ("authorization_pending", "slow_down"):
        return None
    if err == "authorization_declined":
        raise MailboxError("The sign-in was declined at Microsoft. Start again to try once more.",
                           status=400)
    if err in ("expired_token", "bad_verification_code", "code_expired"):
        raise MailboxError("The code ran out before the sign-in finished. Start again for a new "
                           "one.", status=400)
    raise MailboxError(f"Microsoft didn't finish the sign-in ({err or 'HTTP ' + str(r.status_code)}). "
                       "Start again.", status=400)


# ---------- Signing in with the Connect button (authorization code + PKCE) ----------

def web_available(redirect_uri: str) -> bool:
    parts = urlsplit(redirect_uri)
    secure = parts.scheme == "https" or (parts.scheme == "http" and parts.hostname == "localhost")
    return bool(client_id() and client_secret() and secure)


def start_web(redirect_uri: str) -> dict:
    """The address to send the browser to, with the state and the PKCE
    verifier the callback needs (kept in the user's own session)."""
    state = secrets.token_urlsafe(24)
    verifier = secrets.token_urlsafe(48)
    challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).decode().rstrip("=")
    query = urlencode({"client_id": client_id(), "response_type": "code",
                       "redirect_uri": redirect_uri, "response_mode": "query",
                       "scope": SCOPES, "state": state, "prompt": "select_account",
                       "code_challenge": challenge, "code_challenge_method": "S256"})
    return {"url": _login("authorize") + "?" + query, "state": state, "verifier": verifier}


def finish_web(code: str, verifier: str, redirect_uri: str) -> dict:
    r = _post_token({"grant_type": "authorization_code", "client_id": client_id(),
                     "client_secret": client_secret(), "code": code,
                     "redirect_uri": redirect_uri, "code_verifier": verifier, "scope": SCOPES})
    if r.status_code != 200:
        raise MailboxError(f"Microsoft didn't finish the sign-in "
                           f"({_token_error(r) or 'HTTP ' + str(r.status_code)}). Try again.",
                           status=400)
    return _tokens(r)


# ---------- Staying signed in ----------

def fresh(tokens: dict, mode: str) -> dict:
    """The tokens with an access token good for at least a minute, renewed
    with the refresh token when needed. Returns the same dict when nothing
    changed, so the caller can tell whether to store it again."""
    if tokens.get("access") and int(tokens.get("expires_at") or 0) > datetime.now(timezone.utc).timestamp():
        return tokens
    form = {"grant_type": "refresh_token", "client_id": client_id(),
            "refresh_token": tokens.get("refresh") or "", "scope": SCOPES}
    if mode == "web":
        form["client_secret"] = client_secret()
    r = _post_token(form)
    if r.status_code != 200:
        if _token_error(r) in ("invalid_grant", "interaction_required", "invalid_client",
                               "unauthorized_client"):
            raise MailboxError("Microsoft no longer accepts this sign-in: it may have lapsed after "
                               "90 days unused, or the app's access was removed. Disconnect, then "
                               "connect again.", status=409, revoked=True)
        raise MailboxError(f"Microsoft didn't renew the sign-in (HTTP {r.status_code}). "
                           "Try again in a while.")
    return _tokens(r, tokens.get("refresh"))


# ---------- Reading mail (Microsoft Graph) ----------

def _graph(access: str, url: str, params: dict | None = None) -> dict:
    parts = urlsplit(url)
    if parts.scheme != "https" or (parts.hostname or "").lower() != GRAPH_HOST or parts.port not in (None, 443):
        raise MailboxError("Microsoft pointed this server somewhere it doesn't go. Nothing was sent.")
    try:
        with _client() as c:
            r = c.get(url, params=params, headers={"Authorization": f"Bearer {access}",
                                                   "Prefer": _ID_HEADER})
    except httpx.HTTPError:
        raise MailboxError("Couldn't reach Microsoft. Try again in a while.")
    if r.status_code == 401:
        raise MailboxError("Microsoft no longer accepts this sign-in. Disconnect, then connect "
                           "again.", status=409, revoked=True)
    if r.status_code == 403:
        raise MailboxError("Microsoft won't let this sign-in read mail. Connect again and allow "
                           "reading your mail.", status=409, revoked=True)
    if r.status_code == 404:
        raise MailboxError("That folder or message isn't in the mailbox any more.", status=404)
    if r.status_code in (429, 503, 504):
        raise MailboxError("Microsoft is busy. Try again in a few minutes.", status=503)
    if r.status_code != 200:
        raise MailboxError(f"Microsoft answered with an error (HTTP {r.status_code}). "
                           "Try again in a while.")
    try:
        data = r.json()
    except ValueError:
        data = None
    if not isinstance(data, dict):
        raise MailboxError("Microsoft sent something this server can't read. Try again in a while.")
    return data


def _clean(value, limit: int) -> str:
    return re.sub(r"[\x00-\x1f\x7f]", " ", str(value if value is not None else "")).strip()[:limit]


def mailbox_address(access: str) -> str:
    data = _graph(access, f"{GRAPH}/me", {"$select": "mail,userPrincipalName"})
    return _clean(data.get("mail") or data.get("userPrincipalName"), 320)


def folders(access: str) -> list[dict]:
    """The mailbox's folders, with the ones directly inside them (where a mail
    rule usually files bank alerts): id, name, and the parent's name."""
    sel = {"$top": "100", "$select": "id,displayName,childFolderCount"}
    top = _graph(access, f"{GRAPH}/me/mailFolders", sel).get("value") or []
    out = []
    for f in top[:100]:
        if not isinstance(f, dict) or not isinstance(f.get("id"), str):
            continue
        name = _clean(f.get("displayName"), 200) or "Folder"
        out.append({"id": f["id"][:400], "name": name, "parent": None})
        if isinstance(f.get("childFolderCount"), int) and f["childFolderCount"] > 0 and len(out) < 300:
            kids = _graph(access, f"{GRAPH}/me/mailFolders/{quote(f['id'], safe='')}/childFolders",
                          sel).get("value") or []
            for k in kids[:100]:
                if isinstance(k, dict) and isinstance(k.get("id"), str):
                    out.append({"id": k["id"][:400], "name": _clean(k.get("displayName"), 200) or "Folder",
                                "parent": name})
    return out


def _sender(m: dict) -> str:
    addr = ((m.get("from") or {}).get("emailAddress") or {}).get("address") if isinstance(m.get("from"), dict) else None
    return _clean(addr, 320).lower()


def _received(m: dict) -> datetime | None:
    raw = m.get("receivedDateTime")
    if not isinstance(raw, str):
        return None
    try:
        d = datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except ValueError:
        return None
    return d.astimezone(timezone.utc).replace(tzinfo=None)


def _summary(m: dict) -> dict | None:
    if not isinstance(m, dict) or not isinstance(m.get("id"), str):
        return None
    received = _received(m)
    if received is None:
        return None
    return {"id": m["id"][:400], "message_id": _clean(m.get("internetMessageId") or m["id"], 400),
            "sender": _sender(m), "subject": _clean(m.get("subject"), 300), "received": received}


def recent(access: str, folder_id: str, count: int = 25) -> list[dict]:
    data = _graph(access, f"{GRAPH}/me/mailFolders/{quote(folder_id, safe='')}/messages",
                  {"$orderby": "receivedDateTime desc", "$top": str(count),
                   "$select": "id,internetMessageId,receivedDateTime,from,subject"})
    return [s for s in (_summary(m) for m in (data.get("value") or [])[:count]) if s]


def since(access: str, folder_id: str, after: datetime, limit: int) -> list[dict]:
    """Messages received at or after `after` (UTC), oldest first, at most
    `limit` of them, without their bodies."""
    url = f"{GRAPH}/me/mailFolders/{quote(folder_id, safe='')}/messages"
    params = {"$filter": f"receivedDateTime ge {after.strftime('%Y-%m-%dT%H:%M:%SZ')}",
              "$orderby": "receivedDateTime asc", "$top": "100",
              "$select": "id,internetMessageId,receivedDateTime,from,subject"}
    out: list[dict] = []
    while url and len(out) < limit:
        data = _graph(access, url, params)
        out.extend(s for s in (_summary(m) for m in data.get("value") or []) if s)
        nxt = data.get("@odata.nextLink")
        url, params = (nxt, None) if isinstance(nxt, str) else (None, None)
    return out[:limit]


def message(access: str, message_id: str) -> dict:
    """One message with its body (HTML or text, as sent) and the
    Authentication-Results headers, in the order the mail carries them."""
    m = _graph(access, f"{GRAPH}/me/messages/{quote(message_id, safe='')}",
               {"$select": "id,internetMessageId,receivedDateTime,from,subject,body,internetMessageHeaders"})
    s = _summary(m)
    if s is None:
        raise MailboxError("Microsoft sent something this server can't read. Try again in a while.")
    body = m.get("body") if isinstance(m.get("body"), dict) else {}
    content = body.get("content") if isinstance(body.get("content"), str) else ""
    headers = []
    for h in m.get("internetMessageHeaders") or []:
        if isinstance(h, dict) and str(h.get("name", "")).lower() == "authentication-results":
            headers.append(str(h.get("value") or "")[:2000])
    s.update({"html": (body.get("contentType") or "").lower() == "html",
              "body": content[:400_000], "auth_results": headers[:10]})
    return s


class Reader:
    """The calls above in the shape every kind of mailbox has (#208): opened
    for a `with` block, with the access token and the folder's id."""

    def __init__(self, access: str, folder: str | None = None):
        self.access = access
        self.folder = folder

    def open(self) -> "Reader":
        return self

    def close(self) -> None:
        pass

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False

    def address(self) -> str:
        return mailbox_address(self.access)

    def folders(self) -> list[dict]:
        return folders(self.access)

    def recent(self, count: int = 25) -> list[dict]:
        return recent(self.access, self.folder or "", count)

    def since(self, after: datetime, limit: int, senders=None) -> list[dict]:
        return since(self.access, self.folder or "", after, limit)

    def message(self, message_id: str) -> dict:
        return message(self.access, message_id)
