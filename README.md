# WalletWeather

## !!WARNING!! : DO NOT DEPLOY TO THE PUBLIC INTERNET

A self-hosted personal finance forecasting app. Track your accounts, set up recurring transactions, forecast your balance into the future, and compare what you planned against what actually happened.

Built with FastAPI, PostgreSQL, and a single-page vanilla JS frontend. Runs on Docker — no build tools, no npm, no webpack. One `docker compose up` and you're running.

<img width="1527" height="603" alt="image" src="https://github.com/user-attachments/assets/67f00eb6-dcf6-4f49-a04e-b0ee5953c765" />

<img width="1519" height="1681" alt="image" src="https://github.com/user-attachments/assets/db8c397c-7137-433d-a5ee-463b96c86a83" />


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
- **Installable** — add it to your phone's home screen to open it full screen with its own icon; offline it says so (nothing is stored on the phone)
- **Archive accounts** — hide accounts without losing data

## Quick Start

```bash
git clone https://github.com/mkolakowski/walletweather.git
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
| `LOGIN_MAX_FAILURES` | No | `5` | Wrong passwords for one email from one address before sign-in is paused |
| `LOGIN_WINDOW_MINUTES` | No | `15` | How long those failures count, and how long the pause lasts after the last one |
| `TRUST_PROXY_HEADERS` | No | `false` | Set `true` behind a Cloudflare Tunnel to take the visitor's address from `CF-Connecting-IP`. Only when the server can be reached **only** through Cloudflare, or the header can be forged. |
| `DEMO_MODE` | No | `false` | Set to `true` to boot with a pre-seeded demo admin, sample data, the "WalletWeather Demo" title, and an hourly auto-reset of edited demo data. |

## Demo mode

Demo mode is **off by default** — a fresh install boots empty so a
production deployment doesn't accidentally expose the demo admin login.
Flip it on by setting `DEMO_MODE=true` in your `.env` and restarting.
When it's on, WalletWeather loads a pre-seeded admin user and a set of
realistic sample accounts, recurring transactions, and actual postings
so you can explore the app immediately.

- **Demo admin:** `admin@demo.walletweather.local` / `demo1234`
- **App title override:** the UI is branded **"WalletWeather Demo"** while
  demo mode is on (browser tab, login card, and header), regardless of any
  admin-customized app title. It's obvious at a glance that the instance
  is ephemeral.
- **Hourly auto-reset:** a background daemon checks once an hour whether
  the demo data has been edited since the last seed. If something has
  changed, the demo users and their data are wiped and re-seeded; if
  nothing has changed, the reset is skipped. Content is fingerprinted via
  SHA-256 over every demo-owned account, category, recurring template,
  transaction, transfer, and budget.
- **What's seeded:** three accounts (Checking, Savings, Credit Card), a
  paycheck / rent / bill / subscription schedule, and a few weeks of actual
  transactions.
- **Turning it off:** set `DEMO_MODE=false` in your `.env` (or just remove
  the line) and restart the container. On the next start the demo user and
  all data owned by any `@demo.walletweather.local` address is deleted.
  Accounts you created for yourself under real email addresses are never
  touched.
- **Turning it back on later:** set `DEMO_MODE=true` and restart. The demo
  user and sample data will be re-seeded.

The login screen shows the demo credentials while demo mode is on, and has
a "Fill demo credentials" button so you don't have to type them.

## Pulling from GitHub Container Registry

Instead of building locally, you can pull a pre-built image from GHCR.
An image is published for each release, so `latest` is the newest released
version (not the newest commit on `main`).

1. Edit `docker-compose.yml`: comment out `build:` and uncomment `image:`:

```yaml
  web:
    # build:
    #   context: .
    #   dockerfile: apps/server/Dockerfile
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
├── .github/workflows/    # GitHub Actions: builds the container and pushes it to GHCR
├── apps/
│   ├── server/           # FastAPI API server (Python)
│   │   ├── Dockerfile    # Multi-stage Python 3.12-slim build; context is the repo root
│   │   ├── requirements.txt
│   │   ├── requirements-dev.txt # Test-only dependencies (pytest)
│   │   ├── tests/        # API tests (pytest + FastAPI test client)
│   │   └── app/
│   │       ├── main.py   # FastAPI routes + admin endpoints
│   │       ├── db.py     # SQLAlchemy models + Fernet encryption
│   │       ├── forecast.py # Forecast computation engine
│   │       ├── backup.py # Export/import logic
│   │       └── demo.py   # Demo-mode seeding and hourly reset
│   ├── web/              # Single-page web client (vanilla JS, no build step), served by the server
│   │   ├── index.html
│   │   └── favicon.svg
│   ├── ios/              # Placeholder for a native iOS app (see its README)
│   └── android/          # Placeholder for a native Android app (see its README)
├── docs/                 # Public pages (GitHub Pages: the apps' privacy policy) and dev/decisions
├── .dockerignore         # Keeps everything but apps/server and apps/web out of the image
├── docker-compose.yml
├── docker-compose.test.yml # Runs the tests against a throwaway database
├── .env.example
├── LICENSE               # MIT
├── THIRD_PARTY_NOTICES.md # Licences of the software shipped in the image
├── SECURITY.md           # How to report a security problem
├── PRIVACY.md            # What an instance stores, and who is responsible for it
├── CONTRIBUTING.md
└── README.md
```

The container image bundles `apps/server` and `apps/web`; it's built from the
repo root (`docker build -f apps/server/Dockerfile .`). Changes that only
touch `apps/ios`, `apps/android` or Markdown files don't rebuild or republish
the image. Mobile apps talk to the same `/api/...` endpoints as the web
client; a running server documents them at `/docs`.

**Stack:** FastAPI · SQLAlchemy · PostgreSQL 16 · bcrypt · Fernet (AES-128-CBC) · Vanilla JS · Docker

## Using the API with a token

Scripts and apps can call the same `/api/...` endpoints the web client uses
(a running server lists them at `/docs`). Make a token under
**Settings → Your account → API tokens** and copy it when it's shown; it
isn't shown again. Then send it as a Bearer token:

```bash
curl -H "Authorization: Bearer ww_..." https://walletweather.example.com/api/accounts
```

Each token has an access level, chosen when it's made:

| Access | Reaches |
| --- | --- |
| Read-only | `GET` requests (and running a report). Anything that changes data gets `403`. |
| Full access | Everything you can do signed in, except the Admin endpoints (`/api/admin/*`, `403`). |
| Admin | Full access plus `/api/admin/*`. Only admins can make one, and it gets `403` there as soon as its owner is no longer in `ADMIN_EMAILS`. |

No token can list, make or revoke tokens (`/api/tokens` answers `403`); that
needs a signed-in browser. A revoked or expired token, or one whose owner is
disabled, gets `401`. Only a SHA-256 fingerprint of each token is stored.

A token can expire: choose 30 days, 90 days, a year or never when you make it
(over the API, `"expires_in_days": 30`, `90` or `365`; leave it out for never).
Settings shows each token's expiry and when it was last used, and an admin
can see and revoke everyone's tokens on the Admin page.

**From an app, with a password.** An app can swap an email and password for a
token, without Settings. It gets `read` or `full` access (never admin), and
expires in 90 days unless you send `"expires_in_days"` (`30`, `365` or `null`
for never). Wrong passwords count toward the same sign-in limit as the web
sign-in, and accounts that only use Google have no password to send:

```bash
curl -H "Content-Type: application/json" \
     -d '{"email": "you@example.com", "password": "…", "name": "iPhone", "access": "full"}' \
     https://walletweather.example.com/api/auth/token
```

The answer holds the token (`"token": "ww_…"`), shown this once.

**Behind Cloudflare Access.** If the server sits behind a Cloudflare Tunnel
with Zero Trust rules, Cloudflare turns away a request that hasn't signed in
to Cloudflare before WalletWeather sees the token. There are two ways
through:

- **A Cloudflare service token sent with the WalletWeather token.** Create a
  service token in Zero Trust, allow it in the application's policy (a
  *Service Auth* rule), and send its two headers alongside the Bearer token:

  ```bash
  curl -H "CF-Access-Client-Id: <id>.access" \
       -H "CF-Access-Client-Secret: <secret>" \
       -H "Authorization: Bearer ww_..." \
       https://walletweather.example.com/api/accounts
  ```

- **An Access rule that lets `/api/*` through.** Add a separate Access
  application for the `/api/` path with a *Bypass* policy, so the WalletWeather
  token is the only check on the API. Simpler for scripts, but the API is
  then reachable from the internet with nothing in front of it but the token.

## Tests

The API tests live in `apps/server/tests/` and run against a real
PostgreSQL that exists only for the run (in memory, nothing saved). From the
repo root, with Docker:

```bash
docker compose -f docker-compose.test.yml run --rm tests
docker compose -f docker-compose.test.yml down
```

Anything after `tests` goes to pytest, e.g. `... run --rm tests -k auth -v`.
To run them with your own Python 3.12 instead, point `TEST_DATABASE_URL` at a
throwaway database (never one with real data: the tests create users) and run
`pip install -r requirements-dev.txt && pytest` in `apps/server`. GitHub
runs them on every pull request and every push to `main` (the **Tests**
workflow).

## Security Notes

- Passwords are hashed with bcrypt (work factor 12)
- Sensitive fields (account names, balances, amounts, descriptions, notes) are encrypted with Fernet (AES-128-CBC + HMAC-SHA256) and stored as BYTEA in PostgreSQL
- The `ENCRYPTION_KEY` is the master key — back it up securely. If lost, encrypted data is unrecoverable.
- Backup exports are **unencrypted JSON** — store them somewhere safe
- Session cookies use the `SESSION_SECRET` for signing
- Admin access is controlled by the `ADMIN_EMAILS` environment variable, not by database state — an admin cannot be created from the UI

### What the encryption does and doesn't cover

"Encryption at rest" protects the listed fields if someone gets a copy of the
database alone (a stolen volume or database dump). It does not protect
against someone who can read the server's `.env` file, where the
`ENCRYPTION_KEY` sits beside the database, and email addresses, dates,
categories and tags are stored unencrypted. Other limits to know about
before you decide where to run it:

- Backups are unencrypted (roadmap item 12).
- There is no self-serve password reset (item 13) and no two-factor sign-in
  (item 14). Wrong passwords are rate limited and sign-ins are logged, but
  the log can't be read in the app yet and doesn't cover other actions
  (item 15).
- Session cookies are not marked HTTPS-only, so serve the app over HTTPS
  yourself (a reverse proxy or private tunnel) if it leaves your own machine.

This is why the warning at the top says not to put WalletWeather on the
public internet. To report a security problem, see [SECURITY.md](SECURITY.md).

## Privacy

WalletWeather sends nothing to its authors or to anyone else: no analytics,
no telemetry. If you run it for other people, you are the one holding their
data. [PRIVACY.md](PRIVACY.md) lists what an instance stores and what that
means for you. The privacy policy for the mobile apps is at
<https://mkolakowski.github.io/WalletWeather/privacy>.

## Disclaimer

WalletWeather is a planning tool. Its forecasts are estimates calculated from
data you enter and may be inaccurate or incomplete.

WalletWeather does not provide financial, tax, legal or investment advice.
You are solely responsible for decisions you make using it.

The software is provided "as is", without warranty of any kind, and its
authors accept no liability for losses arising from its use. See the
[MIT licence](LICENSE).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE). The published container image also contains other people's
software under their own licences, listed in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
