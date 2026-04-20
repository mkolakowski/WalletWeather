# WalletWeather

A self-hosted personal finance forecasting app. Track your accounts, set up recurring transactions, forecast your balance into the future, and compare what you planned against what actually happened.

Built with FastAPI, PostgreSQL, and a single-page vanilla JS frontend. Runs on Docker — no build tools, no npm, no webpack. One `docker compose up` and you're running.

## Features

- **Dashboard** — at-a-glance view of all your accounts with monthly forecast vs actual highs and lows
- **Forecast view** — month-by-month or duration-based projection of your balance, with inline editing for actuals
- **Recurring transactions** — templates for paychecks, bills, subscriptions that auto-project into the forecast
- **Forecast vs actual tracking** — Δ columns show exactly where you're over or under budget
- **Categories** — tag transactions with color-coded categories, seeded with 13 common defaults
- **Reports** — category breakdown with pie charts, forecast vs actual comparison, CSV/JSON export
- **Multi-account** — checking, savings, credit cards, each with independent forecasts
- **Multi-user** — local auth (email/password with bcrypt) or Google OAuth
- **Permissions** — owner/edit/read/deny per account, with anti-takeover protections
- **Admin panel** — user management, permission overrides, scheduled system backups (for users listed in `ADMIN_EMAILS`)
- **Backup & restore** — per-account or full export/import as unencrypted JSON
- **Encryption at rest** — account names, balances, transaction amounts, descriptions, and notes are Fernet-encrypted in PostgreSQL
- **Mobile responsive** — 3-column grid layout on narrow screens
- **Archive accounts** — hide accounts without losing data

## Quick Start

```bash
git clone https://github.com/<your-username>/walletweather.git
cd walletweather
cp .env.example .env
# Edit .env — set DB_PASSWORD, SESSION_SECRET, ENCRYPTION_KEY
docker compose up -d
```

Open `http://localhost:8300`, register an account, and start adding your finances.

### Generate your secrets

```bash
# Database password (alphanumeric, no special chars)
tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 24; echo

# Session secret
python3 -c "import secrets; print(secrets.token_urlsafe(48))"

# Encryption key (Fernet — DO NOT LOSE THIS, it encrypts your data)
python3 -c "import base64, secrets; print(base64.urlsafe_b64encode(secrets.token_bytes(32)).decode())"
```

## Configuration

All configuration is via environment variables in `.env`:

| Variable | Required | Default | Description |
|---|---|---|---|
| `DB_PASSWORD` | Yes | — | PostgreSQL password |
| `SESSION_SECRET` | Yes | — | Cookie signing key |
| `ENCRYPTION_KEY` | Yes | — | Fernet key for field encryption. **Losing this means data loss.** |
| `APP_BASE_URL` | No | `http://localhost:8300` | Public URL (used for OAuth redirect) |
| `ALLOW_REGISTRATION` | No | `true` | Set `false` to lock out new signups |
| `ALLOWED_EMAILS` | No | — | Comma-separated allowlist for registration |
| `ADMIN_EMAILS` | No | — | Comma-separated admin emails (enables Admin panel) |
| `GOOGLE_CLIENT_ID` | No | — | Google OAuth client ID |
| `GOOGLE_CLIENT_SECRET` | No | — | Google OAuth client secret |

## Pulling from GitHub Container Registry

Instead of building locally, you can pull a pre-built image from GHCR.

1. Edit `docker-compose.yml`: comment out `build:` and uncomment `image:`:

```yaml
  web:
    # build: ./backend
    image: ghcr.io/<your-username>/walletweather:latest
```

2. If the package is private, authenticate Docker to GHCR:

```bash
echo "<your-PAT>" | docker login ghcr.io -u <your-username> --password-stdin
```

Use a Personal Access Token with `read:packages` scope.

3. Run:

```bash
docker compose pull web
docker compose up -d
```

## Updating

```bash
# If building from source:
git pull
docker compose up -d --build

# If pulling from GHCR:
docker compose pull web
docker compose up -d
```

## Architecture

```
walletweather/
├── .github/workflows/    # GitHub Actions for GHCR publishing
├── backend/
│   ├── Dockerfile        # Multi-stage Python 3.12-slim build (~110 MB)
│   ├── app/
│   │   ├── main.py       # FastAPI routes + admin endpoints
│   │   ├── db.py         # SQLAlchemy models + Fernet encryption
│   │   ├── forecast.py   # Forecast computation engine
│   │   └── backup.py     # Export/import logic
│   └── static/
│       └── index.html    # Single-page frontend (vanilla JS, no build step)
├── docker-compose.yml
├── .env.example
├── LICENSE               # MIT
└── README.md
```

**Stack:** FastAPI · SQLAlchemy · PostgreSQL 16 · bcrypt · Fernet (AES-128-CBC) · Vanilla JS · Docker

## Security Notes

- Passwords are hashed with bcrypt (work factor 12)
- Sensitive fields (account names, balances, amounts, descriptions, notes) are encrypted with Fernet (AES-128-CBC + HMAC-SHA256) and stored as BYTEA in PostgreSQL
- The `ENCRYPTION_KEY` is the master key — back it up securely. If lost, encrypted data is unrecoverable.
- Backup exports are **unencrypted JSON** — store them somewhere safe
- Session cookies use the `SESSION_SECRET` for signing
- Admin access is controlled by the `ADMIN_EMAILS` environment variable, not by database state — an admin cannot be created from the UI

## License

[MIT](LICENSE)
