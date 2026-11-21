"""Security guards (#179): properties the server has today, pinned so a later
change that breaks one fails the Tests workflow.

What's here, and what each part is for:

- The route table: every route needs a sign-in unless it's on the short
  PUBLIC list, every Admin route needs an admin, and the token and password
  routes need a browser session. A new endpoint added without its sign-in
  check fails here by name, before anyone has to think of testing it.
- Sweeps over that table with no sign-in, with a non-admin, and with a
  read-only token.
- One user never reaching another's data, object by object.
- What a viewer and an editor of a shared account may not do.
- Cookies, error wording, what's stored in the database, redirects, file
  names, and a scan of the source for calls that have no place in it.

When a test here fails on a change you meant to make (a new public route,
say), change the list in this file in the same commit and say why there.
"""
import ast
from datetime import date
from pathlib import Path

import pytest
from fastapi.routing import APIRoute
from fastapi.testclient import TestClient
from sqlalchemy import text

from conftest import share_account, unique_email

PASSWORD = "correct-horse-battery"
TODAY = date.today()
APP_DIR = Path(__file__).resolve().parent.parent / "app"

# ---------- The route table ----------

# The dependencies that sign a request in (app/main.py, "Auth").
AUTH = {"current_user", "current_reader", "current_session_user",
        "current_session_admin", "current_admin"}
ADMIN = {"current_admin", "current_session_admin"}
SESSION_ONLY = {"current_session_user", "current_session_admin"}

# Every route that answers without a sign-in, and why. Adding to this list is
# a security decision: say why on the line.
PUBLIC = {
    ("GET", "/api/auth/config"): "the sign-in page needs it before anyone is signed in",
    ("GET", "/api/version"): "the healthcheck and the About dialog",
    ("POST", "/api/auth/register"): "registering",
    ("POST", "/api/auth/login"): "signing in",
    ("POST", "/api/auth/login/two-factor"): "the code step of signing in",
    ("POST", "/api/auth/token"): "an app signing in with a password",
    ("POST", "/api/app-sign-in/token"): "an app swapping its one-time code",
    ("GET", "/auth/login"): "starts Google sign-in",
    ("GET", "/auth/callback"): "Google sign-in returns here",
    ("POST", "/auth/logout"): "signing out; clears the caller's own session only",
    ("GET", "/app-sign-in/cloudflare"): "hands the app its own Cloudflare token",
    ("GET", "/app-sign-in"): "a static page; its script signs in",
    ("GET", "/bank/teller"): "a static page with its own Content-Security-Policy; its script "
                             "connects through Teller and posts to signed-in routes (#254)",
    ("GET", "/"): "the web app's page",
    ("GET", "/sw.js"): "the service worker",
    ("GET", "/manifest.webmanifest"): "the install manifest",
}

# Routes that must refuse an API token, whatever its access: managing
# tokens, the password, two-factor and remembered browsers, and letting an
# app in.
MUST_BE_SESSION_ONLY = {
    ("GET", "/api/tokens"), ("POST", "/api/tokens"), ("DELETE", "/api/tokens/{token_id}"),
    ("GET", "/api/admin/tokens"), ("DELETE", "/api/admin/tokens/{token_id}"),
    ("POST", "/api/me/password"),
    ("POST", "/api/me/sessions/end-others"),
    ("POST", "/api/me/two-factor/setup"), ("POST", "/api/me/two-factor/enable"),
    ("POST", "/api/me/two-factor/disable"), ("POST", "/api/me/two-factor/recovery-codes"),
    ("GET", "/api/me/remembered-browsers"), ("DELETE", "/api/me/remembered-browsers"),
    ("DELETE", "/api/me/remembered-browsers/{browser_id}"),
    ("POST", "/api/app-sign-in"),
    ("PUT", "/api/admin/two-factor"),
    # Bank sync (#194): connecting holds a bank's credentials. Sync now and
    # GET /api/bank/status are open to tokens since phase 3 (#195).
    ("GET", "/api/bank"), ("POST", "/api/bank/connect"), ("PUT", "/api/bank/links"),
    ("POST", "/api/bank/disconnect"), ("POST", "/api/bank/accounts"),
    # Teller and Plaid (#254): starting, checking back and handing over a
    # bank's access token are connecting too.
    ("POST", "/api/bank/connect/start"), ("POST", "/api/bank/connect/check"),
    ("GET", "/api/bank/teller/setup"), ("POST", "/api/bank/teller/enroll"),
    ("PUT", "/api/admin/bank-sync"),
    # Adjust to bank (#256) writes a line from a bank's balance: browser only.
    ("POST", "/api/accounts/{account_id}/bank-adjust"),
    # Where Teller's and Plaid's categories land (#255): a setting of the
    # account's own, changed from the browser.
    ("GET", "/api/bank/categories"), ("PUT", "/api/bank/categories"),
    # Email alerts (#206): a mailbox's sign-in can read mail, so connecting,
    # teaching and the log are browser-session only. GET /api/mail/status and
    # POST /api/mail/check (write tokens) are open to tokens since phase 2
    # (#207).
    ("GET", "/api/mail"), ("POST", "/api/mail/microsoft/device"),
    ("POST", "/api/mail/microsoft/device/poll"), ("POST", "/api/mail/microsoft/web"),
    ("GET", "/api/mail/microsoft/callback"), ("GET", "/api/mail/folders"),
    ("PUT", "/api/mail/settings"), ("GET", "/api/mail/messages"), ("POST", "/api/mail/preview"),
    ("POST", "/api/mail/senders"), ("PUT", "/api/mail/senders/{sender_id}"),
    ("DELETE", "/api/mail/senders/{sender_id}"),
    ("DELETE", "/api/mail/senders/{sender_id}/kinds/{kind_id}"),
    ("GET", "/api/mail/checks"), ("GET", "/api/mail/checks/{run_id}"), ("GET", "/api/mail/unread"),
    ("DELETE", "/api/mail/unread/{unread_id}"), ("POST", "/api/mail/disconnect"),
    ("PUT", "/api/admin/mail-alerts"),
}

# Writes a read-only token is allowed, because they change nothing or end
# only the token itself (current_reader).
READ_TOKEN_MAY = {
    ("POST", "/api/report/run"), ("POST", "/api/saved-reports/{report_id}/run"),
    ("DELETE", "/api/tokens/current"),
}


def _dependency_names(route: APIRoute) -> set[str]:
    names = set()

    def walk(dependant):
        for sub in dependant.dependencies:
            if sub.call is not None:
                names.add(getattr(sub.call, "__name__", ""))
            walk(sub)
    walk(route.dependant)
    return names


def _routes(app):
    """(method, path, dependency names) for every API route."""
    out = []
    for route in app.routes:
        if isinstance(route, APIRoute):
            for method in sorted(route.methods - {"HEAD", "OPTIONS"}):
                out.append((method, route.path, _dependency_names(route)))
    return out


def test_every_route_needs_a_sign_in_unless_listed_public(app_started):
    unguarded = sorted((m, p) for (m, p, deps) in _routes(app_started)
                       if not deps & AUTH and (m, p) not in PUBLIC)
    assert unguarded == [], (
        "These routes answer without a sign-in. Give each a current_user "
        "dependency (or one of its kin), or add it to PUBLIC with the reason: "
        f"{unguarded}")


def test_the_public_list_has_no_stale_or_guarded_entries(app_started):
    routes = {(m, p): deps for (m, p, deps) in _routes(app_started)}
    assert sorted(set(PUBLIC) - set(routes)) == [], "PUBLIC names routes that are gone"
    guarded = sorted(k for k in PUBLIC if routes[k] & AUTH)
    assert guarded == [], f"These need a sign-in now; take them off PUBLIC: {guarded}"


def test_every_admin_route_needs_an_admin(app_started):
    open_to_users = sorted((m, p) for (m, p, deps) in _routes(app_started)
                           if p.startswith("/api/admin") and not deps & ADMIN)
    assert open_to_users == [], f"Admin routes without current_admin: {open_to_users}"


def test_token_password_and_two_factor_routes_need_a_browser_session(app_started):
    routes = {(m, p): deps for (m, p, deps) in _routes(app_started)}
    assert sorted(MUST_BE_SESSION_ONLY - set(routes)) == [], "a listed route is gone"
    takes_tokens = sorted(k for k in MUST_BE_SESSION_ONLY if not routes[k] & SESSION_ONLY)
    assert takes_tokens == [], f"These accept an API token: {takes_tokens}"


def test_only_the_listed_writes_are_open_to_a_read_only_token(app_started):
    """current_reader lets a read-only token through on any method, so it
    belongs only on writes that change nothing."""
    uses_reader = {(m, p) for (m, p, deps) in _routes(app_started)
                   if m != "GET" and "current_reader" in deps
                   and not deps & (AUTH - {"current_reader"})}
    assert uses_reader == READ_TOKEN_MAY


# ---------- Sweeps over the route table ----------

def _fill(path: str) -> str:
    """A route's path with 1 for every parameter."""
    return "/".join("1" if part.startswith("{") else part for part in path.split("/"))


def _call(client, method, path, **kw):
    kw.setdefault("json", {} if method in ("POST", "PUT", "PATCH", "DELETE") else None)
    if kw["json"] is None:
        kw.pop("json")
    return client.request(method, _fill(path), **kw)


def register(app):
    c = TestClient(app)
    email = unique_email()
    r = c.post("/api/auth/register", json={"email": email, "password": PASSWORD})
    assert r.status_code == 200, r.text
    return c, {"email": email, "id": r.json()["id"]}


def test_without_a_sign_in_every_guarded_route_answers_401(app_started):
    c = TestClient(app_started)
    wrong = []
    for method, path, deps in _routes(app_started):
        if (method, path) in PUBLIC:
            continue
        r = _call(c, method, path)
        if r.status_code != 401:
            wrong.append((method, path, r.status_code))
    assert wrong == []


def test_a_made_up_token_gets_401_everywhere(app_started):
    c = TestClient(app_started)
    headers = {"Authorization": "Bearer ww_" + "A" * 43}
    wrong = []
    for method, path, deps in _routes(app_started):
        if (method, path) in PUBLIC or deps & SESSION_ONLY:
            continue
        r = _call(c, method, path, headers=headers)
        if r.status_code != 401:
            wrong.append((method, path, r.status_code))
    assert wrong == []


def test_a_user_who_isnt_an_admin_gets_403_on_every_admin_route(app_started):
    c, _ = register(app_started)
    wrong = []
    for method, path, _deps in _routes(app_started):
        if path.startswith("/api/admin"):
            r = _call(c, method, path)
            if r.status_code != 403:
                wrong.append((method, path, r.status_code))
    assert wrong == []


def test_a_read_only_token_is_refused_on_every_write(app_started):
    c, _ = register(app_started)
    made = c.post("/api/tokens", json={"name": "reader", "access": "read"})
    assert made.status_code == 200, made.text
    reader = TestClient(app_started)
    headers = {"Authorization": "Bearer " + made.json()["token"]}
    wrong = []
    for method, path, _deps in _routes(app_started):
        if method == "GET" or (method, path) in PUBLIC or (method, path) in READ_TOKEN_MAY:
            continue
        r = _call(reader, method, path, headers=headers)
        if r.status_code != 403:
            wrong.append((method, path, r.status_code))
    assert wrong == []
    # And it still reads.
    assert reader.get("/api/accounts", headers=headers).status_code == 200


# ---------- One user never reaches another's data ----------

def make_account(c, name, balance=100):
    r = c.post("/api/accounts", json={"name": name, "starting_balance": balance,
                                      "starting_date": TODAY.isoformat()})
    assert r.status_code == 200, r.text
    return r.json()["id"]


def created(r):
    assert r.status_code == 200, r.text
    return r.json()["id"]


@pytest.fixture
def owner(app_started):
    """A user with one of everything, each named with a marker no other test
    uses."""
    c, user = register(app_started)
    marker = "zq" + unique_email()[5:17]
    acc = make_account(c, f"{marker} Checking")
    acc2 = make_account(c, f"{marker} Savings")
    cat = created(c.post("/api/categories", json={"name": f"{marker} cat", "color": "#112233"}))
    tag = created(c.post("/api/tags", json={"name": f"{marker} tag", "color": "#445566"}))
    # The rule's text is in no line below, so no rule adds to these lines.
    rule = created(c.post("/api/tag-rules", json={"description_pattern": f"{marker} rule",
                                                  "tag_id": tag}))
    rec = created(c.post(f"/api/accounts/{acc}/recurring", json={
        "description": f"{marker} rent", "amount": -500, "frequency": "monthly_day",
        "day_of_month": 1, "category_id": cat}))
    txn = created(c.post(f"/api/accounts/{acc}/transactions", json={
        "description": f"{marker} coffee", "amount": -4.5, "actual_date": TODAY.isoformat(),
        "forecast_date": TODAY.isoformat(), "is_actual": True, "category_id": cat,
        "notes": f"{marker} note", "tag_ids": [tag]}))
    transfer = created(c.post("/api/transfers", json={
        "from_account_id": acc, "to_account_id": acc2, "amount": 10,
        "transfer_date": TODAY.isoformat(), "description": f"{marker} move"}))
    r = c.post("/api/budgets", json={"category_id": cat, "amount": 50})
    assert r.status_code == 200, r.text
    report = created(c.post("/api/saved-reports", json={"name": f"{marker} report", "params": {}}))
    return {"c": c, **user, "marker": marker, "acc": acc, "acc2": acc2, "cat": cat, "tag": tag,
            "rule": rule, "rec": rec, "txn": txn, "transfer": transfer, "report": report}


def _snapshot(o):
    c = o["c"]
    return {
        "accounts": c.get("/api/accounts").json(),
        "categories": c.get("/api/categories").json(),
        "tags": c.get("/api/tags").json(),
        "rules": c.get("/api/tag-rules").json(),
        "recurring": c.get(f"/api/accounts/{o['acc']}/recurring").json(),
        "transactions": c.get(f"/api/accounts/{o['acc']}/transactions").json(),
        "transfers": c.get("/api/transfers").json(),
        "budgets": c.get("/api/budgets").json(),
        "reports": c.get("/api/saved-reports").json(),
        "permissions": c.get("/api/permissions").json()["permissions"],
    }


def test_another_users_objects_are_404_and_untouched(app_started, owner):
    o = owner
    before = _snapshot(o)
    x, intruder = register(app_started)
    own_acc = make_account(x, "Mine")
    own_acc2 = make_account(x, "Mine too")
    own_tag = created(x.post("/api/tags", json={"name": "mine"}))
    day = TODAY.isoformat()
    line = {"description": "x", "amount": -1, "actual_date": day, "forecast_date": day,
            "is_actual": True}
    bill = {"description": "x", "amount": -1, "frequency": "weekly", "anchor_date": day}
    move = {"amount": 1, "transfer_date": day}
    csv_body = {"csv_text": "Date,Description,Amount\n2026-01-01,x,-1\n",
                "mapping": {"date": 0, "description": 1, "amount": 2}}
    tries = [
        ("GET", f"/api/accounts/{o['acc']}/transactions", None),
        ("GET", f"/api/accounts/{o['acc']}/recurring", None),
        ("GET", f"/api/accounts/{o['acc']}/forecast", None),
        ("GET", f"/api/accounts/{o['acc']}/import/template", None),
        ("GET", f"/api/recurring?account_id={o['acc']}", None),
        ("GET", f"/api/transactions/search?account_id={o['acc']}", None),
        ("GET", f"/api/calendar?start={day}&end={day}&account_id={o['acc']}", None),
        ("GET", f"/api/backup/export?account_ids={o['acc']}", None),
        ("POST", "/api/backup/export", {"passphrase": "a long passphrase",
                                        "account_ids": [o["acc"]]}),
        ("GET", f"/api/report?account_id={o['acc']}", None),
        ("PATCH", f"/api/accounts/{o['acc']}", {"name": "taken"}),
        ("PATCH", f"/api/accounts/{o['acc']}", {"archived": True}),
        ("DELETE", f"/api/accounts/{o['acc']}", None),
        ("POST", f"/api/accounts/{o['acc']}/transactions", line),
        ("POST", f"/api/accounts/{o['acc']}/recurring", bill),
        ("POST", f"/api/accounts/{o['acc']}/forecast/actual",
         {"transaction_id": o["txn"], "actual_amount": -999, "actual_date": day}),
        ("POST", f"/api/accounts/{o['acc']}/import/preview", csv_body),
        ("POST", f"/api/accounts/{o['acc']}/import/commit", csv_body),
        ("PATCH", f"/api/transactions/{o['txn']}", line),
        ("DELETE", f"/api/transactions/{o['txn']}", None),
        ("PATCH", f"/api/recurring/{o['rec']}", bill),
        ("DELETE", f"/api/recurring/{o['rec']}", None),
        ("POST", f"/api/recurring/{o['rec']}/skip", {"skip_date": day}),
        ("DELETE", f"/api/recurring/{o['rec']}/skips", None),
        ("PATCH", f"/api/categories/{o['cat']}", {"name": "taken"}),
        ("DELETE", f"/api/categories/{o['cat']}", None),
        ("PATCH", f"/api/tags/{o['tag']}", {"name": "taken"}),
        ("DELETE", f"/api/tags/{o['tag']}", None),
        ("PATCH", f"/api/tag-rules/{o['rule']}", {"description_pattern": "xx", "tag_id": own_tag}),
        ("DELETE", f"/api/tag-rules/{o['rule']}", None),
        ("POST", "/api/tag-rules", {"description_pattern": "xx", "tag_id": o["tag"]}),
        ("POST", "/api/tag-rules", {"description_pattern": "xx", "tag_id": own_tag,
                                    "category_id": o["cat"]}),
        ("PATCH", f"/api/transfers/{o['transfer']}",
         {**move, "from_account_id": own_acc, "to_account_id": own_acc2}),
        ("DELETE", f"/api/transfers/{o['transfer']}", None),
        ("POST", "/api/transfers", {**move, "from_account_id": own_acc, "to_account_id": o["acc"]}),
        ("POST", "/api/transfers", {**move, "from_account_id": o["acc"], "to_account_id": own_acc}),
        ("POST", "/api/budgets", {"category_id": o["cat"], "amount": 1}),
        ("DELETE", f"/api/budgets/{o['cat']}", None),
        ("PATCH", f"/api/saved-reports/{o['report']}", {"name": "taken", "params": {}}),
        ("DELETE", f"/api/saved-reports/{o['report']}", None),
        ("POST", f"/api/saved-reports/{o['report']}/run", None),
        ("POST", "/api/permissions",
         {"account_id": o["acc"], "user_id": intruder["id"], "level": "owner"}),
        ("POST", "/api/permissions",
         {"account_id": o["acc"], "user_id": o["id"], "level": "deny"}),
        # Their own account, someone else's category, tag or search filter.
        ("POST", f"/api/accounts/{own_acc}/transactions", {**line, "category_id": o["cat"]}),
        ("POST", f"/api/accounts/{own_acc}/transactions", {**line, "tag_ids": [o["tag"]]}),
        ("POST", f"/api/accounts/{own_acc}/recurring", {**bill, "category_id": o["cat"]}),
        ("POST", f"/api/accounts/{own_acc}/recurring", {**bill, "tag_ids": [o["tag"]]}),
        ("POST", f"/api/accounts/{own_acc}/import/commit",
         {**csv_body, "default_category_id": o["cat"]}),
        ("GET", f"/api/transactions/search?tag_id={o['tag']}", None),
        ("POST", "/api/transactions/bulk-tag",
         {"transaction_ids": [o["txn"]], "add_tag_ids": [o["tag"]]}),
        ("POST", "/api/recurring/bulk-update",
         {"recurring_ids": [o["rec"]], "category_id": o["cat"]}),
    ]
    wrong = []
    for method, path, body in tries:
        r = x.request(method, path, json=body) if body is not None else x.request(method, path)
        if r.status_code != 404:
            wrong.append((method, path, r.status_code, r.text[:120]))
    assert wrong == []

    # The bulk routes skip what the caller can't edit rather than refuse.
    r = x.post("/api/transactions/bulk-tag",
               json={"transaction_ids": [o["txn"]], "add_tag_ids": [own_tag]})
    assert r.status_code == 200 and r.json() == {"applied": 0, "skipped": 1}
    r = x.post("/api/recurring/bulk-update", json={"recurring_ids": [o["rec"]], "amount_abs": 1})
    assert r.status_code == 200 and r.json() == {"updated": 0, "skipped": 1}
    r = x.post("/api/recurring/bulk-delete", json={"recurring_ids": [o["rec"]]})
    assert r.status_code == 200 and r.json() == {"deleted": 0, "skipped": 1}

    assert _snapshot(o) == before


def test_another_users_data_is_in_none_of_your_lists_or_searches(app_started, owner):
    x, _ = register(app_started)
    make_account(x, "Mine")
    marker = owner["marker"]
    day = TODAY.isoformat()
    for path in ("/api/accounts", "/api/accounts?include_archived=true", "/api/categories",
                 "/api/tags", "/api/tag-rules", "/api/recurring", "/api/recurring?archived=true",
                 "/api/transfers", "/api/budgets", "/api/budgets/progress", "/api/saved-reports",
                 "/api/dashboard", "/api/dashboard/charts", "/api/networth", "/api/subscriptions",
                 f"/api/calendar?start={day}&end={day}", "/api/report", "/api/backup/export",
                 f"/api/transactions/search?q={marker}",
                 "/api/transactions/search", "/api/me/deletion-check"):
        r = x.get(path)
        assert r.status_code == 200, (path, r.text)
        assert marker not in r.text, path
    r = x.post("/api/report/run", json={})
    assert r.status_code == 200 and marker not in r.text
    # /api/search repeats the query, so look at what it found.
    found = x.get("/api/search", params={"q": marker}).json()
    assert [found[g]["total"] for g in
            ("transactions", "recurring", "accounts", "categories", "tags", "reports")] == [0] * 6
    # The Permissions panel shows only the accounts the caller can edit.
    perms = x.get("/api/permissions").json()
    assert owner["acc"] not in {a["id"] for a in perms["accounts"]}
    assert owner["acc"] not in {p["account_id"] for p in perms["permissions"]}


# ---------- Shared accounts: what each level may not do ----------

def share(o, invitee_client, level):
    share_account(o["c"], o["acc"], level, invitee_client)


def test_a_viewer_reads_and_changes_nothing(app_started, owner):
    o = owner
    v, viewer = register(app_started)
    share(o, v, "read")
    before = _snapshot(o)
    day = TODAY.isoformat()
    assert v.get(f"/api/accounts/{o['acc']}/transactions").status_code == 200
    line = {"description": "x", "amount": -1, "actual_date": day, "is_actual": True}
    bill = {"description": "x", "amount": -1, "frequency": "weekly", "anchor_date": day}
    for method, path, body in [
        ("POST", f"/api/accounts/{o['acc']}/transactions", line),
        ("PATCH", f"/api/transactions/{o['txn']}", line),
        ("DELETE", f"/api/transactions/{o['txn']}", None),
        ("POST", f"/api/accounts/{o['acc']}/recurring", bill),
        ("PATCH", f"/api/recurring/{o['rec']}", bill),
        ("DELETE", f"/api/recurring/{o['rec']}", None),
        ("POST", f"/api/recurring/{o['rec']}/skip", {"skip_date": day}),
        ("PATCH", f"/api/accounts/{o['acc']}", {"archived": True}),
        ("DELETE", f"/api/accounts/{o['acc']}", None),
        ("DELETE", f"/api/transfers/{o['transfer']}", None),
        ("POST", f"/api/accounts/{o['acc']}/import/commit",
         {"csv_text": "Date,Description,Amount\n2026-01-01,x,-1\n",
          "mapping": {"date": 0, "description": 1, "amount": 2}}),
    ]:
        r = v.request(method, path, json=body) if body is not None else v.request(method, path)
        assert r.status_code == 404, (method, path, r.status_code, r.text[:120])
    # Who has access is the owner's to change: a viewer who asks is told so.
    for body in ({"account_id": o["acc"], "user_id": viewer["id"], "level": "edit"},
                 {"account_id": o["acc"], "user_id": o["id"], "level": "deny"}):
        assert v.post("/api/permissions", json=body).status_code == 403
    r = v.post("/api/invitations", json={"account_id": o["acc"], "email": unique_email(),
                                         "level": "read"})
    assert r.status_code == 403
    # A viewer's backup holds only accounts they can edit: not this one.
    assert o["marker"] not in v.get("/api/backup/export").text
    assert _snapshot(o) == before


def test_an_editor_cant_take_over_rename_or_delete_the_account(app_started, owner):
    o = owner
    e, editor = register(app_started)
    share(o, e, "edit")

    def perm(user_id, level):
        return e.post("/api/permissions", json={
            "account_id": o["acc"], "user_id": user_id, "level": level})
    assert perm(editor["id"], "owner").status_code == 403    # promote themselves
    assert perm(o["id"], "edit").status_code == 403          # demote the owner
    assert perm(o["id"], "deny").status_code == 403          # remove the owner
    assert e.patch(f"/api/accounts/{o['acc']}", json={"name": "taken"}).status_code == 403
    assert e.delete(f"/api/accounts/{o['acc']}").status_code == 404
    levels = {p["user_id"]: p["level"] for p in o["c"].get("/api/permissions").json()["permissions"]
              if p["account_id"] == o["acc"]}
    assert levels == {o["id"]: "owner", editor["id"]: "edit"}


def test_the_last_owner_cant_be_removed(owner):
    o = owner
    for level in ("edit", "read", "deny"):
        r = o["c"].post("/api/permissions", json={
            "account_id": o["acc"], "user_id": o["id"], "level": level})
        assert r.status_code == 400, level


def test_access_ends_when_the_share_is_removed(app_started, owner):
    o = owner
    v, viewer = register(app_started)
    share(o, v, "read")
    assert v.get(f"/api/accounts/{o['acc']}/transactions").status_code == 200
    r = o["c"].post("/api/permissions", json={
        "account_id": o["acc"], "user_id": viewer["id"], "level": "deny"})
    assert r.status_code == 200, r.text
    assert v.get(f"/api/accounts/{o['acc']}/transactions").status_code == 404
    assert o["marker"] not in v.get("/api/accounts").text


# ---------- Sign-in, cookies and what an answer gives away ----------

def test_a_wrong_password_and_an_unknown_email_get_the_same_answer(app_started):
    _, user = register(app_started)
    c = TestClient(app_started)
    wrong = c.post("/api/auth/login", json={"email": user["email"], "password": "not-the-one"})
    unknown = c.post("/api/auth/login", json={"email": unique_email(), "password": "not-the-one"})
    assert wrong.status_code == unknown.status_code == 401
    assert wrong.json() == unknown.json()


def test_the_session_cookie_is_hidden_from_scripts_and_same_site(app_started):
    c = TestClient(app_started)
    r = c.post("/api/auth/register", json={"email": unique_email(), "password": PASSWORD})
    cookie = r.headers["set-cookie"].lower()
    assert cookie.startswith("session=")
    assert "httponly" in cookie and "samesite=lax" in cookie
    # The cookie is signed, not readable-and-forgeable: a changed one is no sign-in.
    name, value = "session", c.cookies.get("session")
    forged = TestClient(app_started)
    forged.cookies.set(name, value[:-2] + ("AA" if not value.endswith("AA") else "BB"))
    assert forged.get("/api/me").status_code == 401


def test_signing_out_ends_the_session(app_started):
    c, _ = register(app_started)
    assert c.get("/api/me").status_code == 200
    assert c.post("/auth/logout").status_code == 200
    assert c.get("/api/me").status_code == 401


def test_a_disabled_user_is_signed_out_and_cant_sign_in(app_started):
    from app import main
    admin, admin_user = register(app_started)
    c, user = register(app_started)
    main.ADMIN_EMAILS.add(admin_user["email"])
    try:
        r = admin.patch(f"/api/admin/users/{user['id']}", json={"disabled": True})
        assert r.status_code == 200, r.text
    finally:
        main.ADMIN_EMAILS.discard(admin_user["email"])
    assert c.get("/api/me").status_code == 403
    assert c.get("/api/accounts").status_code == 401   # the session was cleared
    r = TestClient(app_started).post("/api/auth/login",
                                     json={"email": user["email"], "password": PASSWORD})
    assert r.status_code == 403


SECRET_KEYS = {"password", "password_hash", "totp_secret", "totp_secret_enc", "token_hash",
               "code_hash", "google_sub", "secret"}


def _keys(value):
    if isinstance(value, dict):
        for k, v in value.items():
            yield k
            yield from _keys(v)
    elif isinstance(value, list):
        for v in value:
            yield from _keys(v)


def test_no_answer_about_users_carries_a_hash_or_a_key(app_started):
    from app import main
    c, user = register(app_started)
    c.post("/api/tokens", json={"name": "t", "access": "read"})
    main.ADMIN_EMAILS.add(user["email"])
    try:
        for path in ("/api/me", "/api/tokens", "/api/permissions", "/api/admin/users",
                     "/api/admin/tokens", "/api/admin/permissions", "/api/admin/audit",
                     "/api/me/remembered-browsers", "/api/me/deletion-check"):
            r = c.get(path)
            assert r.status_code == 200, path
            assert not SECRET_KEYS & set(_keys(r.json())), path
            assert "$2b$" not in r.text, path
    finally:
        main.ADMIN_EMAILS.discard(user["email"])


def test_other_sites_get_no_cors_permission(app_started):
    c, _ = register(app_started)
    r = c.get("/api/me", headers={"Origin": "https://evil.example"})
    assert "access-control-allow-origin" not in r.headers
    r = c.options("/api/me", headers={"Origin": "https://evil.example",
                                      "Access-Control-Request-Method": "GET"})
    assert "access-control-allow-origin" not in r.headers


# ---------- What's stored ----------

def test_money_and_words_are_encrypted_in_the_database(owner):
    """Names, descriptions, notes and amounts are stored encrypted; passwords
    and tokens as hashes only."""
    from app.db import SessionLocal
    o = owner
    token = o["c"].post("/api/tokens", json={"name": "t", "access": "read"}).json()["token"]
    marker = o["marker"].encode()
    db = SessionLocal()
    try:
        def cell(sql, **kw):
            return db.execute(text(sql), kw).scalar_one()
        for sql, key in (
            ("SELECT name_enc FROM accounts WHERE id = :i", "acc"),
            ("SELECT starting_balance_enc FROM accounts WHERE id = :i", "acc"),
            ("SELECT description_enc FROM transactions WHERE id = :i", "txn"),
            ("SELECT notes_enc FROM transactions WHERE id = :i", "txn"),
            ("SELECT amount_enc FROM transactions WHERE id = :i", "txn"),
            ("SELECT description_enc FROM recurring_transactions WHERE id = :i", "rec"),
            ("SELECT amount_enc FROM recurring_transactions WHERE id = :i", "rec"),
            ("SELECT description_enc FROM transfers WHERE id = :i", "transfer"),
        ):
            raw = bytes(cell(sql, i=o[key]))
            assert raw.startswith(b"gAAAA"), sql        # a Fernet token
            assert marker not in raw, sql
        hashed = cell("SELECT password_hash FROM users WHERE id = :i", i=o["id"])
        assert hashed.startswith("$2b$12$") and PASSWORD not in hashed
        stored = db.execute(text("SELECT token_hash FROM api_tokens WHERE owner_id = :i"),
                            {"i": o["id"]}).scalars().all()
        assert stored and all(len(h) == 64 and token not in h and "ww_" not in h for h in stored)
    finally:
        db.close()


# ---------- Redirects and file names ----------

@pytest.mark.parametrize("path", [
    "//evil.example", "https://evil.example", "/\\evil.example", "/app-sign-in\\@evil.example",
    "/app-sign-in.evil.example", "/app-sign-in/../x", "/app-sign-inx", "/", "", None,
    "javascript:alert(1)", " /app-sign-in",
])
def test_sign_in_returns_only_to_the_app_sign_in_page(path):
    from app.main import _safe_next
    assert _safe_next(path) is None


def test_the_app_sign_in_page_is_an_allowed_return():
    from app.main import _safe_next
    assert _safe_next("/app-sign-in") == "/app-sign-in"
    assert _safe_next("/app-sign-in?state=abc") == "/app-sign-in?state=abc"


@pytest.mark.parametrize("state", ["short", "a" * 129, "has space", "x/../../y", "<script>", "a&b=c12345"])
def test_the_cloudflare_hand_back_refuses_an_odd_state(app_started, state):
    r = TestClient(app_started).get("/app-sign-in/cloudflare", params={"state": state},
                                    follow_redirects=False)
    assert r.status_code == 400


def test_the_cloudflare_hand_back_only_ever_goes_to_the_app(app_started):
    r = TestClient(app_started).get("/app-sign-in/cloudflare", params={"state": "a" * 16},
                                    follow_redirects=False)
    assert r.status_code in (302, 307)
    assert r.headers["location"].startswith("walletweather://cloudflare?")


@pytest.mark.parametrize("name", [
    "..%2F..%2Fetc%2Fpasswd", "%2e%2e", "system-backup-..%2F..%2Fetc%2Fpasswd",
    "passwd", "system-backup-nope.json", ".env",
])
def test_backup_file_names_cant_reach_outside_the_backup_folder(app_started, name):
    from app import main
    c, user = register(app_started)
    main.ADMIN_EMAILS.add(user["email"])
    try:
        assert c.get(f"/api/admin/backups/download/{name}").status_code == 404
        assert c.post(f"/api/admin/backups/restore/{name}").status_code == 404
    finally:
        main.ADMIN_EMAILS.discard(user["email"])


@pytest.mark.parametrize("path", [
    "/static/..%2Fserver/app/main.py", "/static/%2e%2e/server/app/main.py",
    "/static/..%2F..%2F..%2Fetc/passwd", "/static/../server/requirements.txt",
    "/static//etc/passwd",
])
def test_static_files_stay_inside_the_web_folder(app_started, path):
    r = TestClient(app_started).get(path)
    assert r.status_code == 404, r.text[:80]


def test_the_audit_search_treats_wildcards_as_text(app_started):
    """`email=%` must match addresses containing a percent sign, not every row."""
    from app import main
    c, user = register(app_started)
    main.ADMIN_EMAILS.add(user["email"])
    try:
        r = c.get("/api/admin/audit", params={"email": "%%%nobody-has-this%%%"})
        assert r.status_code == 200 and r.json()["events"] == []
        r = c.get("/api/admin/audit", params={"email": "' OR '1'='1"})
        assert r.status_code == 200 and r.json()["events"] == []
    finally:
        main.ADMIN_EMAILS.discard(user["email"])


@pytest.mark.parametrize("q", ["' OR '1'='1", "%", "_", "\\", "'; DROP TABLE users; --"])
def test_search_text_is_only_ever_text(app_started, owner, q):
    x, _ = register(app_started)
    make_account(x, "Mine")
    for path in ("/api/search", "/api/transactions/search"):
        r = x.get(path, params={"q": q})
        assert r.status_code == 200 and owner["marker"] not in r.text, path


# ---------- The source itself ----------

# Modules with no place in a web app's request path: each can run commands
# or build objects from bytes a caller sent. If one is truly needed, add it
# here with the reason, in the commit that adds it.
FORBIDDEN_IMPORTS = {"subprocess", "pickle", "marshal", "shelve", "telnetlib", "ftplib",
                     "xml", "yaml", "random", "tempfile", "ctypes"}
FORBIDDEN_CALLS = {"eval", "exec", "compile", "__import__"}
FORBIDDEN_ATTRS = {("os", "system"), ("os", "popen"), ("hashlib", "md5")}
# hashlib.sha1 is what authenticator apps use (RFC 6238); nowhere else.
SHA1_ALLOWED_IN = {"twofactor.py"}


def _source_trees():
    for path in sorted(APP_DIR.glob("*.py")):
        yield path, ast.parse(path.read_text(), filename=str(path))


def _is_built_string(node) -> bool:
    """An f-string, a + or % expression, or a .format() call: SQL put
    together from pieces."""
    if isinstance(node, ast.JoinedStr):
        return True
    if isinstance(node, ast.BinOp) and isinstance(node.op, (ast.Add, ast.Mod)):
        return True
    return (isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
            and node.func.attr == "format")


def test_the_source_has_no_dangerous_calls():
    found = []
    for path, tree in _source_trees():
        for node in ast.walk(tree):
            where = f"{path.name}:{getattr(node, 'lineno', '?')}"
            if isinstance(node, ast.Import):
                found += [f"{where} import {a.name}" for a in node.names
                          if a.name.split(".")[0] in FORBIDDEN_IMPORTS]
            elif isinstance(node, ast.ImportFrom):
                if (node.module or "").split(".")[0] in FORBIDDEN_IMPORTS and node.level == 0:
                    found.append(f"{where} from {node.module} import ...")
            elif isinstance(node, ast.Call):
                f = node.func
                if isinstance(f, ast.Name) and f.id in FORBIDDEN_CALLS:
                    found.append(f"{where} {f.id}()")
                for kw in node.keywords:
                    if kw.arg == "shell" and getattr(kw.value, "value", None) is True:
                        found.append(f"{where} shell=True")
                    if kw.arg == "verify" and getattr(kw.value, "value", None) is False:
                        found.append(f"{where} verify=False (TLS checking off)")
                    if kw.arg == "allow_origins":
                        found.append(f"{where} allow_origins (CORS): review, then list it here")
            elif isinstance(node, ast.Attribute) and isinstance(node.value, ast.Name):
                pair = (node.value.id, node.attr)
                if pair in FORBIDDEN_ATTRS:
                    found.append(f"{where} {pair[0]}.{pair[1]}")
                if pair == ("hashlib", "sha1") and path.name not in SHA1_ALLOWED_IN:
                    found.append(f"{where} hashlib.sha1")
    assert found == []


def test_javascript_only_runs_from_the_core_file():
    """quickjs-ng runs the shared core (#233). Only app/jscore.py may touch
    the engine, and it loads the core file shipped in the image; requests
    reach it as a function name and JSON, never as code."""
    found = []
    for path, tree in _source_trees():
        for node in ast.walk(tree):
            names = ([a.name for a in node.names] if isinstance(node, ast.Import)
                     else [node.module or ""] if isinstance(node, ast.ImportFrom) and node.level == 0
                     else [])
            if any(n.split(".")[0] == "quickjs" for n in names) and path.name != "jscore.py":
                found.append(f"{path.name}:{node.lineno}")
    assert found == []
    source = (APP_DIR / "jscore.py").read_text()
    assert "CORE.read_text(" in source and source.count("quickjs.Function(") == 1


def test_sql_is_never_built_from_pieces():
    """Queries go through SQLAlchemy's query builder, or text() with a
    constant string and bound parameters. An f-string or a + inside text()
    or execute() is how SQL injection gets in."""
    found = []
    for path, tree in _source_trees():
        for node in ast.walk(tree):
            if not isinstance(node, ast.Call):
                continue
            name = (node.func.id if isinstance(node.func, ast.Name)
                    else node.func.attr if isinstance(node.func, ast.Attribute) else "")
            if name in ("text", "execute", "exec_driver_sql") and node.args \
                    and _is_built_string(node.args[0]):
                found.append(f"{path.name}:{node.lineno} {name}() with a built string")
    assert found == []


def test_secrets_come_from_the_secrets_module():
    """Tokens, codes and keys are made with `secrets`; the session and the
    remember cookie stay HttpOnly."""
    main_src = (APP_DIR / "main.py").read_text()
    two_src = (APP_DIR / "twofactor.py").read_text()
    assert "secrets.token_urlsafe(32)" in main_src
    assert "secrets.token_bytes(20)" in two_src and "secrets.choice(" in two_src
    assert "httponly=True" in main_src and "httponly=False" not in main_src
    assert 'same_site="lax"' in main_src or 'same_site="strict"' in main_src


def test_passwords_are_hashed_with_bcrypt_at_cost_12_or_more():
    import bcrypt
    from app.main import hash_password, verify_password
    hashed = hash_password("a password")
    assert hashed.startswith("$2b$") and int(hashed.split("$")[2]) >= 12
    assert verify_password("a password", hashed) and not verify_password("another", hashed)
    assert not verify_password("a password", "not-a-hash")
    assert bcrypt.checkpw(b"a password", hashed.encode())
