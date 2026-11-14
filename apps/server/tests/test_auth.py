"""Local sign-in: register, log in, and what a signed-out client can reach."""
from conftest import unique_email


def test_register_signs_the_new_user_in(client, registered):
    assert isinstance(registered["id"], int)
    # The register call set the session cookie, so a protected endpoint works.
    r = client.get("/api/accounts")
    assert r.status_code == 200
    assert r.json() == []


def test_register_rejects_a_duplicate_email(client, registered):
    r = client.post("/api/auth/register",
                    json={"email": registered["email"].upper(),
                          "password": "another-password"})
    assert r.status_code == 409


def test_register_rejects_a_short_password(client):
    r = client.post("/api/auth/register",
                    json={"email": unique_email(), "password": "short"})
    assert r.status_code == 422


def test_login_with_the_right_password(client, registered):
    client.cookies.clear()
    r = client.post("/api/auth/login",
                    json={"email": registered["email"],
                          "password": registered["password"]})
    assert r.status_code == 200
    assert r.json() == {"id": registered["id"], "email": registered["email"]}
    assert client.get("/api/accounts").status_code == 200


def test_login_with_the_wrong_password(client, registered):
    client.cookies.clear()
    r = client.post("/api/auth/login",
                    json={"email": registered["email"], "password": "wrong-password"})
    assert r.status_code == 401
    assert client.get("/api/accounts").status_code == 401


def test_protected_endpoint_needs_a_session(client):
    r = client.get("/api/accounts")
    assert r.status_code == 401
