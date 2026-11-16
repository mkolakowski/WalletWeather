"""Shared test setup: a real app against a throwaway PostgreSQL database.

The app reads its settings from the environment when it's imported, so they
are set here first. TEST_DATABASE_URL is required on purpose, and the tests
never fall back to DATABASE_URL: they create users, and must not be pointed
at a database with real data in it by accident.

Run them with `docker compose -f docker-compose.test.yml run --rm tests`
from the repo root (see README "Tests").
"""
import base64
import hashlib
import os
import secrets
import sys
import tempfile
import uuid
from pathlib import Path

import pytest

_test_db = os.environ.get("TEST_DATABASE_URL")
if not _test_db:
    pytest.exit(
        "Set TEST_DATABASE_URL to a throwaway PostgreSQL database, or run "
        "`docker compose -f docker-compose.test.yml run --rm tests` from the "
        "repo root.",
        returncode=2,
    )

os.environ["DATABASE_URL"] = _test_db
# The same test database gets the same key on every run (#147): rows an earlier
# run left behind, until `docker compose -f docker-compose.test.yml down`,
# still decrypt. A random key per run made the system backup, which reads
# every user, fail on them.
os.environ.setdefault("ENCRYPTION_KEY", base64.urlsafe_b64encode(
    hashlib.sha256(("walletweather-tests " + _test_db).encode()).digest()).decode())
os.environ.setdefault("SESSION_SECRET", secrets.token_urlsafe(48))
os.environ.setdefault("BACKUP_DIR", tempfile.mkdtemp(prefix="ww-test-backups-"))
os.environ["DEMO_MODE"] = "false"
os.environ["ALLOW_REGISTRATION"] = "true"
os.environ["ALLOWED_EMAILS"] = ""
os.environ["ADMIN_EMAILS"] = ""

# Make `import app` work however pytest is started.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from fastapi.testclient import TestClient  # noqa: E402

from app.main import app  # noqa: E402


@pytest.fixture(scope="session")
def app_started():
    """Run the app's startup (database setup) once for the whole run."""
    with TestClient(app):
        yield app


@pytest.fixture
def client(app_started):
    """A fresh client per test, so session cookies don't leak between tests.

    Not used as a context manager: that would run the app's startup (and its
    background threads) again for every test.
    """
    return TestClient(app_started)


def unique_email() -> str:
    return f"test-{uuid.uuid4().hex[:12]}@example.test"


@pytest.fixture
def registered(client):
    """A new user registered through the API; the client is signed in as them."""
    email, password = unique_email(), "correct-horse-battery"
    r = client.post("/api/auth/register",
                    json={"email": email, "password": password})
    assert r.status_code == 200, r.text
    return {"email": email, "password": password, "id": r.json()["id"]}
