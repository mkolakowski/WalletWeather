---
title: "For the person who runs the server"
parent: Set up bank sync
nav_order: 1
---

# For the person who runs the server
{: .no_toc }

What the admin does once, so people can connect their banks: update, let the server reach the services, and switch bank sync on.
{: .fs-6 .fw-300 }

<details open markdown="block">
  <summary>On this page</summary>
  {: .text-delta }
1. TOC
{:toc}
</details>
## Update the server

Pull the latest image and restart. The database changes are made by
themselves when the app starts.

```
docker compose pull && docker compose up -d
```

## Make sure the server can reach SimpleFIN

The server (not the browser) calls SimpleFIN over HTTPS. If your server's
network limits what it can reach, allow outgoing HTTPS to:

```
bridge.simplefin.org
beta-bridge.simplefin.org
```

Nothing needs to reach your server from outside. It doesn't need a public
address.

## Teller and Plaid keys

From 1.95.0 each person adds their own Teller and Plaid keys in **Settings →
Bank sync** ([Teller and Plaid](teller-plaid.md#add-your-own-teller-or-plaid-keys)); the server's `.env`
isn't read for them. There's nothing to set up for Teller or Plaid on the
server beyond ticking who may use them in **Admin → Users**.

**Upgrading from an earlier version with keys in `.env`:** on the first start
of 1.95.0, the `TELLER_APP_ID`, `TELLER_ENV` and `PLAID_...` lines and
Teller's certificate in `TELLER_CERT_DIR` are copied, once, to everyone who
has a Teller or Plaid connection, as their own keys, and into each of those
connections, so they keep syncing. Keep those lines until you've started
1.95.0 once; **Admin → Bank and email → Bank sync** then says how many people they were copied
to, and you can remove them. If connections exist but the keys couldn't be
read on that start, the copy is tried again at the next one.

The server calls `api.teller.io`, and `production.plaid.com` or
`sandbox.plaid.com`. People connecting through Teller load Teller's script
from `cdn.teller.io` on WalletWeather's `/bank/teller` page, the only page
that loads it; through Plaid they sign in on Plaid's own site
(`secure.plaid.com`). No webhook and no public address are needed.

## Switch bank sync on

Bank sync is off until an admin switches it on. Sign in as an admin (an
address in `ADMIN_EMAILS`), open **Admin → Bank and email**, and in the **Bank sync** panel tick **Allow
bank sync**.

With it on, you then tick in **Admin → Users**, under **Bank sync**, who may
connect through each service (SimpleFIN, Teller, Plaid); nobody is ticked to
begin with, and admins always may. Teller and Plaid also need the person's own
keys. Nobody's bank is connected
until they do it themselves. The server calls a provider only for users who
have connected through it. Admin's user list shows a **bank connected** badge for each
of them.

Switching it off again stops connecting and syncing. Connections already made
stay until their users disconnect.

## Optional settings

- **`BACKUP_PASSPHRASE`** in `.env` (at least 12 characters). It isn't needed
  for bank sync itself, but it's needed for the scheduled system backups,
  which carry each user's bank connection, encrypted.
- **`SIMPLEFIN_HOSTS`** in `.env`. These are the only hosts a pasted token
  may point the server at, comma-separated. Leave it empty: it then means
  SimpleFIN Bridge. Change it only if you use another SimpleFIN server. If
  you do, the server's `docker-compose.yml` must pass it to the app with a
  line `SIMPLEFIN_HOSTS: ${SIMPLEFIN_HOSTS:-}` under `environment:`. The
  `docker-compose.yml` in this repository has that line from 1.69.0.
