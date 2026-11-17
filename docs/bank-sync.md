---
title: Set up bank sync
nav_order: 2
---

# Set up bank sync
{: .no_toc }

Bring transactions into WalletWeather straight from your bank, instead of
uploading a CSV file.
{: .fs-6 .fw-300 }

Bank sync works through [SimpleFIN Bridge](https://bridge.simplefin.org/), a
service you subscribe to yourself (about $15 a year). SimpleFIN reads your
bank's transactions and balances. It can't move money.

{: .important }
> - **WalletWeather 1.69.0 or later**, 1.70.0 for the daily sync and the sync log, 1.73.0 for bills paid by a sync. The version is in the app's footer.
> - **An admin switches bank sync on** once for the server ([below](#for-the-person-who-runs-the-server)).
> - **Each person connects their own bank** with their own SimpleFIN
>   subscription ([Connect your bank](#connect-your-bank)).

<details open markdown="block">
  <summary>On this page</summary>
  {: .text-delta }
1. TOC
{:toc}
</details>

## For the person who runs the server

### Update the server

Pull the latest image and restart. The database changes are made by
themselves when the app starts.

```
docker compose pull && docker compose up -d
```

### Make sure the server can reach SimpleFIN

The server (not the browser) calls SimpleFIN over HTTPS. If your server's
network limits what it can reach, allow outgoing HTTPS to:

```
bridge.simplefin.org
beta-bridge.simplefin.org
```

Nothing needs to reach your server from outside. It doesn't need a public
address.

### Switch bank sync on

Bank sync is off until an admin switches it on. Sign in as an admin (an
address in `ADMIN_EMAILS`), open **Admin → Bank sync** and tick **Allow bank
sync**.

With it on, each user can connect their own bank. Nobody's bank is connected
until they do it themselves. The server calls SimpleFIN only for users who
have connected. Admin's user list shows a **bank connected** badge for each
of them.

Switching it off again stops connecting and syncing. Connections already made
stay until their users disconnect.

### Optional settings

- **`BACKUP_PASSPHRASE`** in `.env` (at least 12 characters). It isn't needed
  for bank sync itself, but it's needed for the scheduled system backups,
  which carry each user's bank connection, encrypted.
- **`SIMPLEFIN_HOSTS`** in `.env`. These are the only hosts a pasted token
  may point the server at, comma-separated. Leave it empty: it then means
  SimpleFIN Bridge. Change it only if you use another SimpleFIN server. If
  you do, the server's `docker-compose.yml` must pass it to the app with a
  line `SIMPLEFIN_HOSTS: ${SIMPLEFIN_HOSTS:-}` under `environment:`. The
  `docker-compose.yml` in this repository has that line from 1.69.0.

## Connect your bank

### Get a setup token from SimpleFIN

1. Go to [SimpleFIN Bridge](https://bridge.simplefin.org/simplefin/create)
   and subscribe.
2. Link your bank there. You sign in to your bank on SimpleFIN's pages, not
   in WalletWeather; WalletWeather never sees your bank password.
3. Make a **setup token** for a new app and copy it. It's a long line of
   letters and numbers.

{: .note }
A setup token works **once**. If connecting fails after the token was
accepted, or you connect again later, make a new one.

### Connect it in WalletWeather

1. Open **Settings → Bank sync**. If there's no Bank sync tab, bank sync
   isn't switched on yet: ask whoever runs the server (see [For the person who runs the server](#for-the-person-who-runs-the-server)).
2. Paste the setup token and press **Connect**. If you have two-factor
   sign-in on, type the code from your authenticator app too.
3. Your bank accounts are listed, as SimpleFIN names them.

Connecting works in a browser only. An API token or the iPhone app can't
connect a bank.

### Match your accounts

For each bank account:

- **Your account:** pick the WalletWeather account its transactions go into,
  or **Leave out**. Only accounts you own can be picked, not ones someone
  shares with you, and each of your accounts can be matched to one bank
  account only.
- **Bring in from:** the first date to bring in. It starts at today, which
  means only new transactions come in. Set it back up to 90 days to bring in
  recent history. Anything older is best brought in with a CSV import.

Press **Save matches**.

### Sync

Press **Sync now** for the first sync. The message says how many lines came
in and how many were already there.

After that, WalletWeather syncs by itself **about once a day** (from 1.70.0);
the tab says when the next one is due. **Sync now** still works whenever you
want one sooner.

### Read the sync log

Each matched bank account has a **Sync log** button: every sync of that
account, newest first, whether it ran by itself (Daily) or by **Sync now**,
how many lines came in, how many were already there, and any error. **Show
lines** lists the lines a sync brought in. Only you, the account's owner, see
it; people you share the account with don't. Entries are kept as long as the
server keeps its audit log (180 days unless its admin changed it).

### Bills paid by a sync

From 1.73.0, a synced line that looks like one of your planned bills or
paychecks pays it instead of landing as a second line. The bill's line in
Forecast is marked paid, at the bank's date and amount, with a **Bank sync**
mark. A line looks like a bill when it's on the same account, goes the same
way (money out for a bill, in for income), and is close to one of the bill's
dates that isn't paid yet:

- **within 5 days** either side, and
- **within 10%** of the planned amount.

Each bill has its own two settings in its editor in Bills & income: change
them for a bill that's often late or varies a lot, or set them to 0 for one
that must match exactly. When two dates are equally close, nothing is
matched, so you choose.

**Un-match** a line that was matched wrongly, from its row in Forecast: the
bill goes back to planned and the bank's line stays as its own paid line. It
isn't matched again.

### The Unmatched list

Synced lines that didn't pay a bill are kept on an **Unmatched** list, with a
count beside the account on the Bank sync tab. For each one:

- **Match…** shows the account's planned lines that aren't paid yet, nearest
  in date first (whatever the bill's settings say). Pick one: it's marked paid
  with the bank's date and amount, and the separate line goes away.
- **Leave as its own line** takes it off the list.

Lines synced before 1.73.0 are on the list too, so you can match any that
duplicate a bill you hadn't marked paid.

### If sync keeps failing

The Dashboard shows a warning when bank sync has been failing for more than a
day, or when SimpleFIN no longer accepts the connection. The daily sync
retries a failed sync about 6 hours later, and stops altogether once
SimpleFIN has stopped accepting the connection, until you connect again.

## What a sync does

- **Posted transactions only.** A transaction your bank still shows as
  pending comes in on a later sync, once the bank has posted it. A line never
  changes after it arrives.
- **Each one pays a planned bill, or lands as a paid line** on the matched
  account, dated the day the bank posted it ([Bills paid by a
  sync](#bills-paid-by-a-sync)). A line's name is the bank's description,
  shortened to the company when the bank sends a whole ACH record (from
  1.71.0), with the full text in its notes.
- **Your auto-tag rules run** on each new line, as they do for a CSV import.
  SimpleFIN gives no categories.
- **Nothing comes in twice.** A line already brought in is recognised by the
  bank's own id. A paid line you added by CSV or by hand, with the same date,
  amount and description, is recognised too and isn't doubled.
- **Late postings are caught.** Each sync looks back 14 days before the
  last one, for lines a bank posts late.
- **At most 20 syncs in 24 hours.** SimpleFIN disables a connection that asks
  much more often than about 24 times a day, so Sync now stops at 20 and
  says when it can run again. The tab shows how many are left. SimpleFIN
  itself refreshes from banks about once a day, so syncing more often rarely
  brings anything new.

## Disconnecting

**Settings → Bank sync → Disconnect** forgets the connection and your
matches. Lines already brought in stay. With two-factor sign-in on, it asks
for a code.

{: .warning }
Disconnecting stops WalletWeather asking. To stop SimpleFIN reading your bank
too, disable the app's access at [SimpleFIN Bridge](https://bridge.simplefin.org/).

Deleting your WalletWeather user removes your connection too.

## If something goes wrong

| The message says | What to do |
| --- | --- |
| *Bank sync is switched off on this instance* | An admin switches it on in Admin → Bank sync. |
| *That doesn't look like a SimpleFIN setup token* | Copy the token again from SimpleFIN Bridge, all of it. |
| *That token points at …, which isn't SimpleFIN* | The token isn't from SimpleFIN Bridge, or the server's `SIMPLEFIN_HOSTS` doesn't include the host it came from. Nothing was sent to that host. |
| *SimpleFIN says this token was already used or doesn't exist* | Make a new setup token. If you didn't use the old one yourself, disable it at SimpleFIN Bridge. |
| *Couldn't reach SimpleFIN* | SimpleFIN may be down, or the server can't reach it: see "Make sure the server can reach SimpleFIN". |
| *SimpleFIN says your subscription needs paying* | Renew at SimpleFIN Bridge, then sync again. |
| *SimpleFIN no longer accepts this connection* | It was disabled at SimpleFIN or ran out. Disconnect, make a new setup token and connect again. |
| *Bank sync has asked SimpleFIN 20 times in the last 24 hours* | Wait for the time it gives. The daily sync counts toward the 20 too. |
| *A sync is already running* | The daily sync was running at that moment. Try again in a minute. |
| *Match at least one bank account to one of your accounts first* | Pick an account for at least one bank account and press Save matches. |
| Sync says *0 new lines* the first time | The "Bring in from" date is today, so only new transactions come in. Move it back and Save matches. |
| A bank account is missing from the list | Check it's linked at SimpleFIN Bridge, then press Sync now. The list is refreshed on each sync. |

## What's stored and what's sent

- **Stored on your server:** the access address SimpleFIN issues for your
  connection, which includes its credentials. It's encrypted with the
  server's `ENCRYPTION_KEY` and is never shown in the app or written to a
  log. The server also keeps your bank accounts' names (encrypted), your
  matches, how the last sync went, and the times of the last day's syncs.
  Each synced line carries a fingerprint of the bank's id for it, and which
  sync brought it in. The sync log (when, how many, any error) is kept as
  long as the audit log.
- **In backups:** encrypted backups (Settings → Backup, and the system
  backups) carry the connection, so a restore keeps it. The readable
  "Download my data" copy never does.
- **Sent:** when you connect and each time you sync, the server asks SimpleFIN
  for your bank accounts and the posted transactions since a date. Nothing
  else about you is sent. SimpleFIN and your bank see that the connection is
  used, and when.

The full details are in [`PRIVACY.md`](https://github.com/mkolakowski/WalletWeather/blob/main/PRIVACY.md)
under "What leaves the server".
