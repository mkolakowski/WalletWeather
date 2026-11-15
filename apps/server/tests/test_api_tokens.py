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
