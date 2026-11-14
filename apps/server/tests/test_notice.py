"""The "Important notice" (the disclaimer) each user acknowledges once."""
from datetime import datetime


def test_a_new_user_owes_the_notice(client, registered):
    me = client.get("/api/me").json()
    assert me["notice_required"] is True
    assert me["notice_acknowledged_at"] is None


def test_acknowledging_clears_it(client, registered):
    r = client.post("/api/me/acknowledge-notice")
    assert r.status_code == 200
    body = r.json()
    assert body["ok"] is True
    assert body["notice_required"] is False
    # An ISO time in UTC that a client can parse.
    assert body["notice_acknowledged_at"].endswith("Z")
    datetime.fromisoformat(body["notice_acknowledged_at"].rstrip("Z"))

    me = client.get("/api/me").json()
    assert me["notice_required"] is False
    assert me["notice_acknowledged_at"] == body["notice_acknowledged_at"]


def test_it_stays_acknowledged_after_signing_in_again(client, registered):
    client.post("/api/me/acknowledge-notice")
    client.cookies.clear()
    r = client.post("/api/auth/login",
                    json={"email": registered["email"],
                          "password": registered["password"]})
    assert r.status_code == 200
    assert client.get("/api/me").json()["notice_required"] is False


def test_acknowledging_twice_keeps_the_first_time(client, registered):
    first = client.post("/api/me/acknowledge-notice").json()
    second = client.post("/api/me/acknowledge-notice")
    assert second.status_code == 200
    assert second.json()["notice_acknowledged_at"] == first["notice_acknowledged_at"]


def test_acknowledging_needs_a_session(client):
    r = client.post("/api/me/acknowledge-notice")
    assert r.status_code == 401


def test_a_demo_user_is_never_asked():
    # The demo login is shared and reset hourly, so it never owes the notice.
    from app.db import User
    from app.main import _notice_required

    assert _notice_required(User(email="admin@demo.walletweather.local")) is False
    assert _notice_required(User(email="someone@example.test")) is True
