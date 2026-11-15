"""A token ending itself: DELETE /api/tokens/current (#145), which the iOS
app calls when it signs out."""
from fastapi.testclient import TestClient


def make(client, access="full"):
    r = client.post("/api/tokens", json={"name": "iPhone", "access": access})
    assert r.status_code == 200, r.text
    return r.json()


def bearer(app, token):
    c = TestClient(app)
    c.headers["Authorization"] = f"Bearer {token}"
    return c


def test_a_token_ends_itself(app_started, client, registered):
    made = make(client)
    app = bearer(app_started, made["token"])
    r = app.delete("/api/tokens/current")
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["id"] == made["id"] and body["revoked_at"]
    assert "token" not in body
    # It's dead from then on, and Settings shows it revoked.
    assert app.get("/api/me").status_code == 401
    [listed] = client.get("/api/tokens").json()
    assert listed["id"] == made["id"] and listed["revoked_at"]
    from app.db import AuditEvent, SessionLocal
    db = SessionLocal()
    try:
        ev = (db.query(AuditEvent).filter_by(user_id=registered["id"])
              .order_by(AuditEvent.id.desc()).first())
        assert (ev.event, ev.detail) == ("token_revoked", f"token #{made['id']}; by itself")
    finally:
        db.close()


def test_a_read_only_token_can_end_itself(app_started, client, registered):
    made = make(client, "read")
    app = bearer(app_started, made["token"])
    assert app.delete("/api/tokens/current").status_code == 200
    assert app.get("/api/me").status_code == 401


def test_it_ends_only_itself(app_started, client, registered):
    one, two = make(client), make(client)
    assert bearer(app_started, one["token"]).delete("/api/tokens/current").status_code == 200
    assert bearer(app_started, two["token"]).get("/api/me").status_code == 200
    # Revoking by number still needs a browser session.
    r = bearer(app_started, two["token"]).delete(f"/api/tokens/{two['id']}")
    assert r.status_code == 403


def test_a_browser_session_has_nothing_to_end(client, registered):
    r = client.delete("/api/tokens/current")
    assert r.status_code == 400
    assert client.get("/api/me").status_code == 200


def test_signed_out_and_dead_tokens_get_401(app_started, client, registered):
    assert TestClient(app_started).delete("/api/tokens/current").status_code == 401
    made = make(client)
    app = bearer(app_started, made["token"])
    assert app.delete("/api/tokens/current").status_code == 200
    assert app.delete("/api/tokens/current").status_code == 401
