"""The profile picture (account-picker phase 1, #377): PUT, GET and DELETE
/api/me/picture, `picture_updated_at` in GET /api/me, and the copy of a
Google picture at sign-in while there's none."""
import asyncio
import uuid

from fastapi.testclient import TestClient

from conftest import register, unique_email

# Only the first bytes are checked, so a signature and some bytes will do.
PNG = b"\x89PNG\r\n\x1a\n" + b"\x00\x00\x00\rIHDR" + bytes(range(64))
JPEG = b"\xff\xd8\xff\xe0" + b"\x00\x10JFIF\x00" + bytes(range(64))
WEBP = b"RIFF\x24\x00\x00\x00WEBPVP8 " + bytes(range(64))


def put(c, data):
    return c.put("/api/me/picture", content=data, headers={"Content-Type": "application/octet-stream"})


# ---------- Happy path ----------

def test_no_picture_at_first(client, registered):
    assert client.get("/api/me").json()["picture_updated_at"] is None
    assert client.get("/api/me/picture").status_code == 404


def test_set_read_and_remove_a_picture(client, registered):
    r = put(client, PNG)
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["ok"] is True and body["picture_updated_at"]
    assert client.get("/api/me").json()["picture_updated_at"] == body["picture_updated_at"]

    got = client.get("/api/me/picture")
    assert got.status_code == 200
    assert got.content == PNG
    assert got.headers["content-type"] == "image/png"
    assert got.headers["x-content-type-options"] == "nosniff"
    etag = got.headers["etag"]
    assert etag.startswith('"') and etag.endswith('"')
    # The caller already has it.
    again = client.get("/api/me/picture", headers={"If-None-Match": etag})
    assert again.status_code == 304 and again.content == b""

    r = client.delete("/api/me/picture")
    assert r.status_code == 200 and r.json() == {"ok": True, "picture_updated_at": None}
    assert client.get("/api/me/picture").status_code == 404
    assert client.get("/api/me").json()["picture_updated_at"] is None


def test_a_new_picture_replaces_the_old_and_changes_its_tag(client, registered):
    put(client, PNG)
    first = client.get("/api/me/picture").headers["etag"]
    assert put(client, JPEG).status_code == 200
    got = client.get("/api/me/picture", headers={"If-None-Match": first})
    assert got.status_code == 200
    assert got.content == JPEG and got.headers["content-type"] == "image/jpeg"
    assert got.headers["etag"] != first


def test_webp_is_taken(client, registered):
    assert put(client, WEBP).status_code == 200
    assert client.get("/api/me/picture").headers["content-type"] == "image/webp"


def test_the_picture_is_kept_encrypted(client, registered):
    from app.db import SessionLocal, User
    put(client, PNG)
    with SessionLocal() as db:
        user = db.get(User, registered["id"])
        assert user.picture_enc and PNG not in user.picture_enc
        assert user.picture == PNG and user.picture_type == "image/png"


def test_each_person_sees_only_their_own(app_started):
    a, _ = register(app_started)
    b, _ = register(app_started)
    put(a, PNG)
    assert b.get("/api/me/picture").status_code == 404
    assert b.get("/api/me").json()["picture_updated_at"] is None


# ---------- Refusals ----------

def test_anything_but_png_jpeg_or_webp_is_refused(client, registered):
    put(client, PNG)
    for bad in (b"", b"GIF89a" + bytes(32), b"<svg xmlns='http://www.w3.org/2000/svg'/>",
                b"RIFF\x00\x00\x00\x00WAVEfmt ", b"not an image at all"):
        r = put(client, bad)
        assert r.status_code == 415, (bad[:12], r.text)
    # The one there stays.
    assert client.get("/api/me/picture").content == PNG


def test_a_picture_over_256_kb_is_refused(client, registered):
    from app import main
    big = PNG + bytes(main.PICTURE_MAX_BYTES)
    r = put(client, big)
    assert r.status_code == 413, r.text
    assert client.get("/api/me/picture").status_code == 404
    # Exactly at the limit is fine.
    at_limit = PNG + bytes(main.PICTURE_MAX_BYTES - len(PNG))
    assert put(client, at_limit).status_code == 200


def test_signed_out_gets_nothing(app_started):
    c = TestClient(app_started)
    assert c.get("/api/me/picture").status_code == 401
    assert put(c, PNG).status_code == 401
    assert c.delete("/api/me/picture").status_code == 401


def test_a_read_only_token_may_read_but_not_change_it(client, registered, app_started):
    put(client, PNG)
    r = client.post("/api/tokens", json={"name": "phone", "access": "read"})
    assert r.status_code == 200, r.text
    reader = TestClient(app_started)
    reader.headers["Authorization"] = f"Bearer {r.json()['token']}"
    got = reader.get("/api/me/picture")
    assert got.status_code == 200 and got.content == PNG
    assert put(reader, JPEG).status_code == 403
    assert reader.delete("/api/me/picture").status_code == 403
    assert client.get("/api/me/picture").content == PNG


def test_the_demo_account_cant_change_its_picture(client, registered, monkeypatch):
    from app import main
    monkeypatch.setattr(main, "is_demo_email", lambda email: True)
    assert put(client, PNG).status_code == 403
    assert client.delete("/api/me/picture").status_code == 403
    assert client.get("/api/me/picture").status_code == 404


# ---------- Google's picture at sign-in ----------

def _google(monkeypatch, userinfo, fetched):
    from app import main
    calls = []

    class FakeGoogle:
        async def authorize_access_token(self, request):
            return {"userinfo": userinfo}

    class FakeOAuth:
        google = FakeGoogle()

    async def fake_fetch(url):
        calls.append(url)
        return fetched

    monkeypatch.setattr(main, "GOOGLE_ENABLED", True)
    monkeypatch.setattr(main, "oauth", FakeOAuth())
    monkeypatch.setattr(main, "_fetch_google_picture", fake_fetch)
    return calls


def _info(address, picture="https://lh3.googleusercontent.com/a/abc=s96-c"):
    return {"sub": "sub-" + uuid.uuid4().hex, "email": address, "email_verified": True,
            "name": "New Person", "picture": picture}


def test_google_sign_in_copies_the_picture_when_there_is_none(app_started, monkeypatch):
    calls = _google(monkeypatch, _info(unique_email()), PNG)
    c = TestClient(app_started)
    r = c.get("/auth/callback", follow_redirects=False)
    assert r.status_code in (302, 307), r.text
    assert calls == ["https://lh3.googleusercontent.com/a/abc=s96-c"]
    assert c.get("/api/me").json()["picture_updated_at"]
    assert c.get("/api/me/picture").content == PNG


def test_google_never_replaces_a_picture_already_set(app_started, monkeypatch):
    c, user = register(app_started)
    put(c, JPEG)
    calls = _google(monkeypatch, _info(user["email"]), PNG)
    g = TestClient(app_started)
    r = g.get("/auth/callback", follow_redirects=False)
    assert r.status_code in (302, 307), r.text
    assert calls == []
    assert g.get("/api/me/picture").content == JPEG


def test_a_failed_fetch_still_signs_in(app_started, monkeypatch):
    address = unique_email()
    _google(monkeypatch, _info(address), None)
    c = TestClient(app_started)
    r = c.get("/auth/callback", follow_redirects=False)
    assert r.status_code in (302, 307), r.text
    me = c.get("/api/me").json()
    assert me["email"] == address and me["picture_updated_at"] is None


def test_the_fetch_goes_only_to_googles_picture_host():
    from app import main
    for url in ("http://lh3.googleusercontent.com/a/abc=s96-c",   # not https
                "https://evil.example/a.png",
                "https://googleusercontent.com.evil.example/a.png",
                "https://localhost/a.png", "file:///etc/passwd", "not a url"):
        assert asyncio.run(main._fetch_google_picture(url)) is None, url
