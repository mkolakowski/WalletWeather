"""API tokens (#42): managing them (GET/POST/DELETE /api/tokens, browser
session only) and signing in with `Authorization: Bearer <token>`."""
import pytest
from fastapi.testclient import TestClient

from conftest import unique_email


def make_token(client, access="full", name="script"):
    r = client.post("/api/tokens", json={"name": name, "access": access})
    assert r.status_code == 200, r.text
    return r.json()


def bearer(app, token):
    """A client with no session cookie that sends only the token."""
    c = TestClient(app)
    c.headers["Authorization"] = f"Bearer {token}"
    return c


@pytest.fixture
def admin_user(client, registered):
    """The registered user, made an admin (ADMIN_EMAILS is read at start-up,
    so the test adds the address and takes it out again)."""
    from app import main
    main.ADMIN_EMAILS.add(registered["email"])
    yield registered
    main.ADMIN_EMAILS.discard(registered["email"])


# ---------- Managing tokens ----------

def test_create_shows_the_token_once_and_list_never_does(client, registered):
    made = make_token(client, "read", "phone")
    assert made["token"].startswith("ww_") and len(made["token"]) > 40
    assert made["name"] == "phone" and made["access"] == "read"
    assert made["created_at"] and made["revoked_at"] is None

    r = client.get("/api/tokens")
    assert r.status_code == 200
    [listed] = r.json()
    assert listed["id"] == made["id"]
    assert listed["name"] == "phone" and listed["access"] == "read"
    assert "token" not in listed and "token_hash" not in listed


def test_list_shows_only_your_own_tokens(app_started, client, registered):
    make_token(client)
    other = TestClient(app_started)
    other.post("/api/auth/register",
               json={"email": unique_email(), "password": "correct-horse-battery"})
    assert other.get("/api/tokens").json() == []


def test_create_rejects_a_blank_name_and_an_unknown_access(client, registered):
    assert client.post("/api/tokens", json={"name": "  ", "access": "full"}).status_code == 400
    assert client.post("/api/tokens", json={"name": "x", "access": "owner"}).status_code == 400
    assert client.post("/api/tokens", json={"name": "x" * 81, "access": "full"}).status_code == 422
    assert client.post("/api/tokens", json={"access": "full"}).status_code == 422


def test_only_an_admin_can_make_an_admin_token(client, registered):
    r = client.post("/api/tokens", json={"name": "ops", "access": "admin"})
    assert r.status_code == 403
    assert client.get("/api/tokens").json() == []


def test_token_endpoints_need_a_session(client):
    assert client.get("/api/tokens").status_code == 401
    assert client.post("/api/tokens", json={"name": "x", "access": "full"}).status_code == 401


def test_revoking_someone_elses_or_an_unknown_token_is_404(app_started, client, registered):
    made = make_token(client)
    other = TestClient(app_started)
    other.post("/api/auth/register",
               json={"email": unique_email(), "password": "correct-horse-battery"})
    assert other.delete(f"/api/tokens/{made['id']}").status_code == 404
    assert client.delete("/api/tokens/999999999").status_code == 404


# ---------- Signing in with a token ----------

def test_a_full_token_reads_and_writes(app_started, client, registered):
    tok = bearer(app_started, make_token(client, "full")["token"])
    r = tok.get("/api/accounts")
    assert r.status_code == 200 and r.json() == []
    r = tok.post("/api/accounts", json={"name": "Checking", "starting_balance": 10,
                                        "starting_date": "2026-01-01"})
    assert r.status_code == 200
    assert [a["name"] for a in tok.get("/api/accounts").json()] == ["Checking"]
    assert tok.get("/api/me").json()["email"] == registered["email"]


def test_a_read_only_token_is_refused_on_a_write(app_started, client, registered):
    tok = bearer(app_started, make_token(client, "read")["token"])
    assert tok.get("/api/accounts").status_code == 200
    r = tok.post("/api/accounts", json={"name": "Nope", "starting_balance": 0,
                                        "starting_date": "2026-01-01"})
    assert r.status_code == 403
    assert client.get("/api/accounts").json() == []
    # Running a report is a POST that changes nothing, so it's allowed.
    assert tok.post("/api/report/run", json={}).status_code == 200


def test_a_full_token_is_refused_on_the_admin_endpoints_even_for_an_admin(
        app_started, client, admin_user):
    tok = bearer(app_started, make_token(client, "full")["token"])
    assert client.get("/api/admin/users").status_code == 200  # the session is fine
    assert tok.get("/api/admin/users").status_code == 403


def test_an_admin_token_reaches_the_admin_endpoints_until_its_owner_stops_being_admin(
        app_started, client, admin_user):
    from app import main
    tok = bearer(app_started, make_token(client, "admin", "ops")["token"])
    assert tok.get("/api/admin/users").status_code == 200
    assert tok.get("/api/accounts").status_code == 200  # full access elsewhere

    main.ADMIN_EMAILS.discard(admin_user["email"])
    assert tok.get("/api/admin/users").status_code == 403
    assert tok.get("/api/accounts").status_code == 200


def test_a_read_only_token_of_an_admin_is_refused_on_the_admin_endpoints(
        app_started, client, admin_user):
    tok = bearer(app_started, make_token(client, "read")["token"])
    assert tok.get("/api/admin/users").status_code == 403


def test_a_revoked_token_stops_working_at_once(app_started, client, registered):
    made = make_token(client)
    tok = bearer(app_started, made["token"])
    assert tok.get("/api/accounts").status_code == 200

    r = client.delete(f"/api/tokens/{made['id']}")
    assert r.status_code == 200 and r.json()["revoked_at"]
    assert tok.get("/api/accounts").status_code == 401
    # Revoking again keeps the first time.
    assert client.delete(f"/api/tokens/{made['id']}").json()["revoked_at"] == r.json()["revoked_at"]
    assert client.get("/api/tokens").json()[0]["revoked_at"] == r.json()["revoked_at"]


def test_a_disabled_owners_token_gets_401(app_started, client, registered):
    from app.db import SessionLocal, User
    tok = bearer(app_started, make_token(client)["token"])
    db = SessionLocal()
    try:
        db.get(User, registered["id"]).disabled = True
        db.commit()
        assert tok.get("/api/accounts").status_code == 401
    finally:
        db.get(User, registered["id"]).disabled = False
        db.commit()
        db.close()


def test_an_unknown_or_empty_token_gets_401(app_started):
    assert bearer(app_started, "ww_not-a-real-token").get("/api/accounts").status_code == 401
    c = TestClient(app_started)
    c.headers["Authorization"] = "Bearer "
    assert c.get("/api/accounts").status_code == 401


@pytest.mark.parametrize("access", ["read", "full"])
def test_a_token_cant_manage_tokens(app_started, client, registered, access):
    made = make_token(client, access)
    tok = bearer(app_started, made["token"])
    assert tok.get("/api/tokens").status_code == 403
    assert tok.post("/api/tokens", json={"name": "more", "access": "read"}).status_code == 403
    assert tok.delete(f"/api/tokens/{made['id']}").status_code == 403


def test_an_admin_token_cant_manage_tokens_either(app_started, client, admin_user):
    made = make_token(client, "admin")
    tok = bearer(app_started, made["token"])
    assert tok.get("/api/tokens").status_code == 403
    assert tok.post("/api/tokens", json={"name": "more", "access": "admin"}).status_code == 403
    assert tok.delete(f"/api/tokens/{made['id']}").status_code == 403


def test_a_token_wins_over_a_session_cookie(client, registered):
    """With both, the token decides: a read-only token can't write even from a
    signed-in client."""
    made = make_token(client, "read")
    r = client.post("/api/accounts",
                    headers={"Authorization": f"Bearer {made['token']}"},
                    json={"name": "Nope", "starting_balance": 0, "starting_date": "2026-01-01"})
    assert r.status_code == 403


# ---------- Expiry and last used (#43) ----------

def set_token_times(token_id, **fields):
    """Set columns on a token row directly (the API only moves them forward
    in real time)."""
    from app.db import ApiToken, SessionLocal
    db = SessionLocal()
    try:
        row = db.get(ApiToken, token_id)
        for k, v in fields.items():
            setattr(row, k, v)
        db.commit()
    finally:
        db.close()


def test_a_token_made_without_expiry_never_expires(client, registered):
    made = make_token(client)
    assert made["expires_at"] is None and made["expired"] is False
    assert made["last_used_at"] is None


@pytest.mark.parametrize("days", [30, 90, 365])
def test_expiry_is_that_many_days_ahead(client, registered, days):
    from datetime import datetime, timedelta
    r = client.post("/api/tokens", json={"name": "x", "access": "read",
                                         "expires_in_days": days})
    assert r.status_code == 200, r.text
    expires = datetime.fromisoformat(r.json()["expires_at"].rstrip("Z"))
    assert abs(expires - (datetime.utcnow() + timedelta(days=days))) < timedelta(minutes=1)
    assert r.json()["expired"] is False


@pytest.mark.parametrize("days", [0, 7, -1, 366])
def test_an_expiry_that_isnt_offered_is_refused(client, registered, days):
    r = client.post("/api/tokens", json={"name": "x", "access": "read",
                                         "expires_in_days": days})
    assert r.status_code == 400
    assert client.get("/api/tokens").json() == []


def test_an_expired_token_is_refused_and_listed_as_expired(app_started, client, registered):
    from datetime import datetime, timedelta
    made = make_token(client)
    tok = bearer(app_started, made["token"])
    assert tok.get("/api/accounts").status_code == 200

    set_token_times(made["id"], expires_at=datetime.utcnow() - timedelta(seconds=1))
    r = tok.get("/api/accounts")
    assert r.status_code == 401 and "expired" in r.json()["detail"]
    [listed] = client.get("/api/tokens").json()
    assert listed["expired"] is True and listed["revoked_at"] is None


def test_a_token_works_until_it_expires(app_started, client, registered):
    from datetime import datetime, timedelta
    made = make_token(client)
    set_token_times(made["id"], expires_at=datetime.utcnow() + timedelta(hours=1))
    assert bearer(app_started, made["token"]).get("/api/accounts").status_code == 200


def test_last_used_is_set_on_use_and_not_rewritten_within_a_minute(
        app_started, client, registered):
    from datetime import datetime, timedelta
    made = make_token(client)
    tok = bearer(app_started, made["token"])
    assert client.get("/api/tokens").json()[0]["last_used_at"] is None

    assert tok.get("/api/accounts").status_code == 200
    first = client.get("/api/tokens").json()[0]["last_used_at"]
    assert first
    # A second request straight away leaves it alone.
    assert tok.get("/api/accounts").status_code == 200
    assert client.get("/api/tokens").json()[0]["last_used_at"] == first
    # Once it's over a minute old, the next request moves it forward.
    set_token_times(made["id"], last_used_at=datetime.utcnow() - timedelta(minutes=5))
    old = client.get("/api/tokens").json()[0]["last_used_at"]
    assert tok.get("/api/accounts").status_code == 200
    assert client.get("/api/tokens").json()[0]["last_used_at"] > old


def test_a_refused_token_does_not_count_as_used(app_started, client, registered):
    made = make_token(client)
    client.delete(f"/api/tokens/{made['id']}")
    assert bearer(app_started, made["token"]).get("/api/accounts").status_code == 401
    assert client.get("/api/tokens").json()[0]["last_used_at"] is None


# ---------- Admin panel: everyone's tokens (#43) ----------

def test_an_admin_lists_every_users_tokens(app_started, client, admin_user):
    other = TestClient(app_started)
    o = other.post("/api/auth/register",
                   json={"email": unique_email(), "password": "correct-horse-battery"})
    other_email = o.json()["email"]
    theirs = make_token(other, "full", "their script")
    mine = make_token(client, "read", "my script")

    r = client.get("/api/admin/tokens")
    assert r.status_code == 200
    by_id = {t["id"]: t for t in r.json()}
    assert by_id[theirs["id"]]["owner_email"] == other_email
    assert by_id[theirs["id"]]["name"] == "their script"
    assert by_id[mine["id"]]["owner_email"] == admin_user["email"]
    for t in by_id.values():
        assert "token" not in t and "token_hash" not in t
        assert {"access", "created_at", "expires_at", "last_used_at",
                "revoked_at", "expired", "owner_id"} <= set(t)


def test_an_admin_revokes_another_users_token_at_once(app_started, client, admin_user):
    other = TestClient(app_started)
    other.post("/api/auth/register",
               json={"email": unique_email(), "password": "correct-horse-battery"})
    theirs = make_token(other, "full")
    tok = bearer(app_started, theirs["token"])
    assert tok.get("/api/accounts").status_code == 200

    r = client.delete(f"/api/admin/tokens/{theirs['id']}")
    assert r.status_code == 200 and r.json()["revoked_at"]
    assert tok.get("/api/accounts").status_code == 401
    assert other.get("/api/tokens").json()[0]["revoked_at"] == r.json()["revoked_at"]
    assert client.delete(f"/api/admin/tokens/{theirs['id']}").json()["revoked_at"] == r.json()["revoked_at"]


def test_admin_token_endpoints_refuse_a_non_admin_and_an_unknown_token(client, registered):
    assert client.get("/api/admin/tokens").status_code == 403
    assert client.delete("/api/admin/tokens/1").status_code == 403


def test_revoking_an_unknown_token_as_admin_is_404(client, admin_user):
    assert client.delete("/api/admin/tokens/999999999").status_code == 404


def test_admin_token_endpoints_need_a_session(client):
    assert client.get("/api/admin/tokens").status_code == 401


@pytest.mark.parametrize("access", ["read", "full", "admin"])
def test_no_token_manages_tokens_through_the_admin_endpoints(
        app_started, client, admin_user, access):
    made = make_token(client, access)
    tok = bearer(app_started, made["token"])
    assert tok.get("/api/admin/tokens").status_code == 403
    assert tok.delete(f"/api/admin/tokens/{made['id']}").status_code == 403
    assert client.get("/api/tokens").json()[0]["revoked_at"] is None
