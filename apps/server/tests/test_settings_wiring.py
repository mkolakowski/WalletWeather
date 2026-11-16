"""Every setting the server reads reaches it (#200).

docker-compose.yml hands the app container each setting by name, so one the
code reads but compose doesn't list never arrives, whatever is in .env:
1.68.0 shipped BACKUP_PASSPHRASE that way. This reads the server's code for
the settings it takes from the environment and checks each is passed through
in docker-compose.yml and documented in .env.example.
"""
import re
from pathlib import Path

import pytest

APP = Path(__file__).resolve().parent.parent / "app"
ROOT = Path(__file__).resolve().parents[3]
COMPOSE, EXAMPLE = ROOT / "docker-compose.yml", ROOT / ".env.example"

# Set by docker-compose.yml or the image itself, never by the operator.
NOT_OPERATOR_SETTINGS = {
    "DATABASE_URL": "compose builds it from DB_PASSWORD",
    "BACKUP_DIR": "a fixed path inside the container, on the data volume",
    "WEB_DIR": "where the image puts the web client",
}
_READ = re.compile(r'os\.(?:environ\.get|getenv)\(\s*"([A-Z][A-Z0-9_]+)"|os\.environ\[\s*"([A-Z][A-Z0-9_]+)"\s*\]')


def settings_read() -> set[str]:
    names = set()
    for f in APP.rglob("*.py"):
        for a, b in _READ.findall(f.read_text()):
            names.add(a or b)
    return names


@pytest.fixture(scope="module")
def files():
    if not COMPOSE.exists() or not EXAMPLE.exists():
        pytest.skip("docker-compose.yml / .env.example aren't mounted here")
    return COMPOSE.read_text(), EXAMPLE.read_text()


def test_the_scan_finds_settings():
    assert {"SESSION_SECRET", "ENCRYPTION_KEY", "BACKUP_PASSPHRASE"} <= settings_read()


def test_every_setting_is_passed_to_the_app_container(files):
    compose, _ = files
    missing = sorted(n for n in settings_read() - set(NOT_OPERATOR_SETTINGS)
                     if not re.search(rf"^\s+{n}:\s*\$\{{{n}[:}}]", compose, re.M))
    assert missing == [], (
        "The server reads these, but docker-compose.yml doesn't pass them to the "
        f"app container, so a value in .env never arrives: {missing}. Add "
        "`NAME: ${NAME:-default}` under the app's environment:.")


def test_every_setting_is_in_the_env_example(files):
    _, example = files
    missing = sorted(n for n in settings_read() - set(NOT_OPERATOR_SETTINGS)
                     if not re.search(rf"^#?\s?{n}=", example, re.M))
    assert missing == [], f".env.example doesn't list: {missing}"
