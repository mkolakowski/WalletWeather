"""Signing in an app (ios-app phase 1, #87): the /app-sign-in page, the
one-time code from POST /api/app-sign-in, swapping it for a token at
POST /api/app-sign-in/token, and handing the Cloudflare sign-in back."""
import base64
import hashlib
import secrets
from datetime import datetime, timedelta
from urllib.parse import parse_qs, urlsplit

from fastapi.testclient import TestClient

STATE = "state-1234"
# A JWT-shaped value, as Cloudflare puts in Cf-Access-Jwt-Assertion.
CF_JWT = "eyJhbGciOiJSUzI1NiJ9.eyJhdWQiOlsiYWJjIl19.c2lnbmF0dXJl"


def pkce():
    verifier = secrets.token_urlsafe(48)
    challenge = base64.urlsafe_b64encode(
        hashlib.sha256(verifier.encode()).digest()).rstrip(b"=").decode()
    return verifier, challenge


def allow(client, challenge, headers=None, **body):
    body = {"name": "iPhone Duo", "access": "full", "code_challenge": challenge,
            "state": STATE, **body}
    return client.post("/api/app-sign-in", json=body, headers=headers or {})


def callback(url):
    parts = urlsplit(url)
    return parts.scheme, parts.netloc, {k: v[0] for k, v in parse_qs(parts.query).items()}


def test_the_page_is_served(client):
    r = client.get("/app-sign-in?state=x")
    assert r.status_code == 200
    assert "text/html" in r.headers["content-type"]
    assert "/api/app-sign-in" in r.text


def test_allow_then_swap_gives_a_working_token_listed_in_settings(app_started, client, registered):
    verifier, challenge = pkce()
    r = allow(client, challenge)
    assert r.status_code == 200, r.text
    scheme, path, q = callback(r.json()["redirect_url"])
    assert (scheme, path) == ("walletweather", "signed-in")
    assert q["state"] == STATE and "cf" not in q
    app = TestClient(app_started)  # the app: no session cookie
    r = app.post("/api/app-sign-in/token", json={"code": q["code"], "code_verifier": verifier})
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["token"].startswith("ww_")
    assert body["name"] == "iPhone Duo" and body["access"] == "full"
    assert body["user"] == {"id": registered["id"], "email": registered["email"]}
    expires = datetime.fromisoformat(body["expires_at"].rstrip("Z"))
    assert timedelta(days=89) < expires - datetime.utcnow() <= timedelta(days=90)
    app.headers["Authorization"] = f"Bearer {body['token']}"
    assert app.get("/api/me").json()["email"] == registered["email"]
    [listed] = client.get("/api/tokens").json()
    assert listed["id"] == body["id"] and listed["name"] == "iPhone Duo"
    from app.db import AuditEvent, SessionLocal
    db = SessionLocal()
    try:
        ev = (db.query(AuditEvent).filter_by(user_id=registered["id"])
              .order_by(AuditEvent.id.desc()).first())
        assert (ev.event, ev.detail) == ("token_created", f"token #{body['id']}, full; by app sign-in")
    finally:
        db.close()
    # Revoking it in Settings signs the app out.
    assert client.delete(f"/api/tokens/{body['id']}").status_code == 200
    assert app.get("/api/me").status_code == 401


def test_read_only_is_kept(app_started, client, registered):
    verifier, challenge = pkce()
    _, _, q = callback(allow(client, challenge, access="read").json()["redirect_url"])
    body = TestClient(app_started).post(
        "/api/app-sign-in/token", json={"code": q["code"], "code_verifier": verifier}).json()
    assert body["access"] == "read"


def test_a_code_works_once(app_started, client, registered):
    verifier, challenge = pkce()
    _, _, q = callback(allow(client, challenge).json()["redirect_url"])
    app = TestClient(app_started)
    swap = {"code": q["code"], "code_verifier": verifier}
    assert app.post("/api/app-sign-in/token", json=swap).status_code == 200
    r = app.post("/api/app-sign-in/token", json=swap)
    assert r.status_code == 400 and "Sign in again" in r.json()["detail"]


def test_a_wrong_verifier_fails_and_spends_the_code(app_started, client, registered):
    verifier, challenge = pkce()
    _, _, q = callback(allow(client, challenge).json()["redirect_url"])
    app = TestClient(app_started)
    assert app.post("/api/app-sign-in/token",
                    json={"code": q["code"], "code_verifier": "not-it"}).status_code == 400
    assert app.post("/api/app-sign-in/token",
                    json={"code": q["code"], "code_verifier": verifier}).status_code == 400


def test_an_expired_code_fails(app_started, client, registered):
    from app.db import AppSignInCode, SessionLocal
    verifier, challenge = pkce()
    _, _, q = callback(allow(client, challenge).json()["redirect_url"])
    db = SessionLocal()
    try:
        row = db.query(AppSignInCode).filter_by(
            code_hash=hashlib.sha256(q["code"].encode()).hexdigest()).one()
        row.expires_at = datetime.utcnow() - timedelta(seconds=1)
        db.commit()
    finally:
        db.close()
    r = TestClient(app_started).post("/api/app-sign-in/token",
                                     json={"code": q["code"], "code_verifier": verifier})
    assert r.status_code == 400


def test_an_unknown_code_fails(client):
    r = client.post("/api/app-sign-in/token", json={"code": "nope", "code_verifier": "x"})
    assert r.status_code == 400


def test_allowing_needs_a_browser_session(app_started, client, registered):
    _, challenge = pkce()
    assert allow(TestClient(app_started), challenge).status_code == 401
    token = client.post("/api/tokens", json={"name": "t", "access": "full"}).json()["token"]
    r = allow(TestClient(app_started), challenge, headers={"Authorization": f"Bearer {token}"})
    assert r.status_code == 403


def test_allowing_checks_what_it_is_sent(client, registered):
    _, challenge = pkce()
    assert allow(client, challenge, access="admin").status_code == 400
    assert allow(client, challenge, name="  ").status_code == 400
    assert allow(client, "short").status_code == 400
    assert allow(client, challenge, state="bad state!").status_code == 400


def test_the_cloudflare_sign_in_comes_back_with_the_code(client, registered):
    _, challenge = pkce()
    r = allow(client, challenge, headers={"Cf-Access-Jwt-Assertion": CF_JWT})
    _, _, q = callback(r.json()["redirect_url"])
    assert q["cf"] == CF_JWT and q["code"]


def test_the_cloudflare_page_hands_back_only_the_cloudflare_sign_in(client):
    r = client.get(f"/app-sign-in/cloudflare?state={STATE}",
                   headers={"Cf-Access-Jwt-Assertion": CF_JWT}, follow_redirects=False)
    assert r.status_code in (302, 307)
    scheme, path, q = callback(r.headers["location"])
    assert (scheme, path) == ("walletweather", "cloudflare")
    assert q == {"state": STATE, "cf": CF_JWT}


def test_the_cloudflare_page_says_when_there_is_no_cloudflare(client):
    r = client.get(f"/app-sign-in/cloudflare?state={STATE}", follow_redirects=False)
    _, path, q = callback(r.headers["location"])
    assert path == "cloudflare" and q == {"state": STATE, "error": "no-cloudflare"}
    # Something that isn't a JWT isn't passed on.
    r = client.get(f"/app-sign-in/cloudflare?state={STATE}",
                   headers={"Cf-Access-Jwt-Assertion": "<script>"}, follow_redirects=False)
    assert callback(r.headers["location"])[2]["error"] == "no-cloudflare"


def test_google_sign_in_returns_only_to_the_app_page():
    from app.main import _safe_next
    assert _safe_next("/app-sign-in?state=abc") == "/app-sign-in?state=abc"
    assert _safe_next("/app-sign-in") == "/app-sign-in"
    for bad in (None, "", "/", "https://evil.test/", "//evil.test", "/app-sign-inx",
                "/settings", "/app-sign-in?\\evil"):
        assert _safe_next(bad) is None
