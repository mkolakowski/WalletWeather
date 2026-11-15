"""Installable web app (#41): the manifest and the service worker routes."""
import pytest


def test_manifest_shape_and_headers(client):
    r = client.get("/manifest.webmanifest")
    assert r.status_code == 200
    assert r.headers["content-type"].startswith("application/manifest+json")
    assert r.headers["cache-control"] == "no-cache"
    m = r.json()
    assert m["name"] == m["short_name"] == "WalletWeather"
    assert m["start_url"] == "/" and m["scope"] == "/"
    assert m["display"] == "standalone"
    assert m["theme_color"].startswith("#") and m["background_color"].startswith("#")
    sizes = {(i["sizes"], i["purpose"]) for i in m["icons"]}
    assert {("192x192", "any"), ("512x512", "any"), ("512x512", "maskable")} <= sizes


def test_manifest_needs_no_sign_in(client):
    # Browsers fetch it before anyone signs in.
    client.cookies.clear()
    assert client.get("/manifest.webmanifest").status_code == 200


def test_every_manifest_icon_is_served_as_a_png(client):
    for icon in client.get("/manifest.webmanifest").json()["icons"]:
        r = client.get(icon["src"])
        assert r.status_code == 200, icon["src"]
        assert r.headers["content-type"] == "image/png"
        assert r.content[:8] == b"\x89PNG\r\n\x1a\n"
    r = client.get("/static/icons/apple-touch-icon.png")
    assert r.status_code == 200 and r.headers["content-type"] == "image/png"


@pytest.fixture
def custom_title(app_started):
    """An admin's custom title, removed again afterwards."""
    from app.db import AdminSetting, SessionLocal
    from app.main import APP_TITLE_KEY
    db = SessionLocal()
    db.merge(AdminSetting(key=APP_TITLE_KEY, value="Family Money"))
    db.commit()
    yield "Family Money"
    row = db.get(AdminSetting, APP_TITLE_KEY)
    if row:
        db.delete(row)
        db.commit()
    db.close()


def test_manifest_takes_the_custom_title(client, custom_title):
    m = client.get("/manifest.webmanifest").json()
    assert m["name"] == m["short_name"] == custom_title


def test_service_worker_is_served_from_the_root(client):
    client.cookies.clear()
    r = client.get("/sw.js")
    assert r.status_code == 200
    assert r.headers["content-type"].startswith("text/javascript")
    assert r.headers["cache-control"] == "no-cache"
    assert "addEventListener('fetch'" in r.text


@pytest.mark.parametrize("path", ["/sw.js", "/manifest.webmanifest"])
def test_only_get_is_allowed(client, path):
    assert client.post(path).status_code == 405
