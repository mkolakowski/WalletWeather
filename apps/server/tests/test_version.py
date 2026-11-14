"""GET /api/version: public version info for the About dialog and footer."""
import re

from app.db import SCHEMA_VERSION
from app.main import APP_VERSION


def test_version_returns_app_and_schema_versions(client):
    r = client.get("/api/version")
    assert r.status_code == 200
    body = r.json()
    assert body == {"app_version": APP_VERSION, "schema_version": SCHEMA_VERSION}
    assert re.fullmatch(r"\d+\.\d+\.\d+", body["app_version"])


def test_version_rejects_other_methods(client):
    r = client.post("/api/version")
    assert r.status_code == 405
