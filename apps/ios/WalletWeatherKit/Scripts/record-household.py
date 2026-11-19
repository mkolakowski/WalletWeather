"""Records the demo household's rows for "Try the demo" (#234): the rows the
shared core works the demo's Forecast, Calendar and Dashboard out from, in
place of recorded answers.

It seeds the server's demo data (apps/server/app/demo.py) for the day the
other samples were recorded, on a fresh test database, so the ids match
theirs, and writes Sources/WalletWeatherKit/Demo/household.json. Run from
the repo root:

    docker compose -f docker-compose.test.yml down
    docker compose -f docker-compose.test.yml run --rm \
      -v "$PWD/apps/ios/WalletWeatherKit:/kit" --entrypoint sh tests -c \
      "pip install -q -r requirements-dev.txt && python /kit/Scripts/record-household.py"
    docker compose -f docker-compose.test.yml down

Then run `swift test` in apps/ios/WalletWeatherKit: DemoTests checks the
household against the recorded samples.
"""
import base64
import datetime as dt
import hashlib
import json
import os
import sys
import tempfile

RECORDED = dt.date(2026, 11, 15)
OUT = "/kit/Sources/WalletWeatherKit/Demo/household.json"

url = os.environ["TEST_DATABASE_URL"]
os.environ.update({
    "DATABASE_URL": url, "DEMO_MODE": "false", "ALLOW_REGISTRATION": "true",
    "ENCRYPTION_KEY": base64.urlsafe_b64encode(hashlib.sha256(("walletweather-tests " + url).encode()).digest()).decode(),
    "SESSION_SECRET": "record-household-" + "x" * 40, "BACKUP_DIR": tempfile.mkdtemp(),
    "BACKUP_PASSPHRASE": "record-household-passphrase",
})
sys.path.insert(0, "/src/apps/server")

from fastapi.testclient import TestClient  # noqa: E402

import app.demo as demo  # noqa: E402
from app.db import Account, Category, SessionLocal, User  # noqa: E402
from app.forecast import rows_for_forecast  # noqa: E402
from app.main import _user_visible_accounts, app, seed_default_categories  # noqa: E402


class _RecordedDay(dt.date):
    @classmethod
    def today(cls):
        return RECORDED


with TestClient(app):
    pass  # the app's startup: the tables
db = SessionLocal()
assert db.query(Account).count() == 0, "use a fresh test database (docker compose ... down first)"
demo.date = _RecordedDay
demo.seed_demo_data(db, seed_default_categories)
user = db.query(User).filter_by(email=demo.DEMO_ADMIN_EMAIL).one()
household = {
    "recorded": RECORDED.isoformat(),
    "categories": [{"id": c.id, "name": c.name, "color": c.color}
                   for c in db.query(Category).filter_by(owner_id=user.id).order_by(Category.id)],
    "accounts": [{"id": a.id, "name": a.name, **rows_for_forecast(db, a)}
                 for a in _user_visible_accounts(db, user)],
}
with open(OUT, "w") as f:
    json.dump(household, f, indent=1, ensure_ascii=False)
    f.write("\n")
print("wrote", OUT, "with", sum(len(a["transactions"]) for a in household["accounts"]), "lines and",
      sum(len(a["recurring"]) for a in household["accounts"]), "bills")
db.rollback()
db.close()
