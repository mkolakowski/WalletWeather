---
title: Set up bank sync
nav_order: 2
---

# Set up bank sync
{: .no_toc }

Bring transactions into WalletWeather straight from your bank, instead of
uploading a CSV file.
{: .fs-6 .fw-300 }

Bank sync works through one of three services, picked per bank:

- **[SimpleFIN Bridge](https://bridge.simplefin.org/)**, a service you
  subscribe to yourself (about $15 a year). Nothing to set up on the server.
- **[Teller](https://teller.io/)** (from 1.86.0), once the server has
  Teller's keys. Teller's development tier is free up to 100 bank logins.
- **[Plaid](https://plaid.com/)** (from 1.86.0), once the server has
  Plaid's keys. Plaid's Trial plan is free for 10 bank logins.

Each reads your bank's transactions and balances. None can move money. If
your bank won't connect through one, try another: each reaches banks its own
way. You can have as many connections as you like, from any mix of them.

{: .important }
> - **WalletWeather 1.69.0 or later**, 1.70.0 for the daily sync and the sync log, 1.73.0 for bills paid by a sync, 1.86.0 for Teller, Plaid and more than one connection. The version is in the app's footer.
> - **An admin switches bank sync on** once for the server ([below](#for-the-person-who-runs-the-server)).
> - **Each person connects their own banks** ([Connect your bank](#connect-your-bank)).

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

### Set up Teller (optional)

1. Make a developer account at [teller.io](https://teller.io/) and an
   application. Its **application id** (it starts `app_`) is on the
   dashboard.
2. Download the application's **certificate**. Teller gives a zip with
   `certificate.pem` and `private_key.pem`. Put both in a folder next to
   your `docker-compose.yml` called `secrets/teller` (or name another folder
   in `TELLER_CERT_DIR`). It's mounted into the server read-only. The private
   key is a secret: don't put it in git or share it.
3. In `.env`:

   ```
   TELLER_APP_ID=app_...
   TELLER_ENV=development
   ```

   `development` reaches your real banks and is free up to 100 bank logins.
   `sandbox` uses Teller's made-up banks and needs no certificate, for a
   try. `production` needs Teller to approve your account.
4. The server calls `api.teller.io`. People connecting load Teller's script
   from `cdn.teller.io` in their browser, on WalletWeather's
   `/bank/teller` page, the only page that loads it.

### Set up Plaid (optional)

1. Make an account at [dashboard.plaid.com](https://dashboard.plaid.com/).
   The free **Trial** plan allows 10 bank logins, Chase, Bank of America and
   Wells Fargo included. Applying for full production later ends the Trial
   plan for good.
2. On the dashboard's **Keys** page, copy the client id and the secret for
   the environment you'll use. In `.env`:

   ```
   PLAID_CLIENT_ID=...
   PLAID_SECRET=...
   PLAID_ENV=production
   ```

   `production` reaches your real banks (on the Trial plan too); `sandbox`
   uses Plaid's made-up banks with the sandbox secret. The secret is a
   secret: keep it out of git.
3. The server calls `production.plaid.com` (or `sandbox.plaid.com`). People
   connecting sign in to their bank on Plaid's own site (`secure.plaid.com`),
   in a new tab. No webhook and no public address are needed: the server
   checks back with Plaid.

Restart after changing `.env` (`docker compose up -d`). **Admin → Bank sync**
then lists Teller and Plaid as offered.

### Switch bank sync on

Bank sync is off until an admin switches it on. Sign in as an admin (an
address in `ADMIN_EMAILS`), open **Admin → Bank sync** and tick **Allow bank
sync**.

With it on, each user can connect their own banks, through SimpleFIN and
through Teller or Plaid when their keys are set. Nobody's bank is connected
until they do it themselves. The server calls a provider only for users who
have connected through it. Admin's user list shows a **bank connected** badge for each
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

Open **Settings → Bank sync**. If there's no Bank sync tab, bank sync isn't
switched on yet: ask whoever runs the server (see [For the person who runs
the server](#for-the-person-who-runs-the-server)). Under **Connect a bank**
are the services your server offers. With two-factor sign-in on, type the
code from your authenticator app first.

### Through Teller or Plaid

1. Press **Connect with Teller** or **Connect with Plaid**. A new tab opens:
   Plaid's own site, or WalletWeather's Teller page with Teller Connect.
2. Pick your bank and sign in to it there. You sign in on Teller's or Plaid's
   pages, not WalletWeather's; WalletWeather never sees your bank password.
3. When it says you're connected, close that tab. Settings → Bank sync
   notices by itself within a few seconds and lists the bank's accounts.

Each bank login is a connection of its own: for three banks, connect three
times. A connection that lists the same bank accounts as one you already
have from the same service (a new SimpleFIN token from the same Bridge
account, say) takes the old one's place instead, keeping your matches. If the new tab didn't open, your browser blocked it: use the link
that appears under the buttons.

### From the iPhone app

From iOS 0.30.0 with server 1.89.0, Teller and Plaid can be connected from
the phone: Settings → Bank sync → **Connect a bank**.

1. The phone's sign-in sheet opens your server's connect page. If it asks,
   sign in as you do in the web app; it shares Safari's sign-in, so usually
   you're signed in already.
2. Pick **Teller** or **Plaid** (only the ones your server has keys for), and
   type your two-factor code if it's on: connecting a bank always takes a
   fresh one.
3. Sign in to your bank on Teller's or Plaid's page. When it's done the sheet
   closes by itself and the card says which bank was connected.
4. Match its accounts to yours in the web app, Settings → Bank sync, as for a
   connection made there.

The phone never holds anything that reads your bank: the page runs in the
sheet under your browser sign-in, as Settings does, and hands the app only
"connected" and the connection's number. SimpleFIN is still connected in
the web app, since it means pasting a setup token. A bank that would hand
off to its own app (Plaid's app-to-app sign-in) shows its web sign-in in the
sheet instead, so there's no Universal Link to set up.

### Through SimpleFIN

#### Get a setup token from SimpleFIN

1. Go to [SimpleFIN Bridge](https://bridge.simplefin.org/simplefin/create)
   and subscribe.
2. Link your bank there. You sign in to your bank on SimpleFIN's pages, not
   in WalletWeather; WalletWeather never sees your bank password.
3. Make a **setup token** for a new app and copy it. It's a long line of
   letters and numbers.

{: .note }
A setup token works **once**. If connecting fails after the token was
accepted, or you connect again later, make a new one.

#### Connect it in WalletWeather

1. Open **Paste a SimpleFIN token** under **Connect a bank**.
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
  account only, across all your connections: if SimpleFIN and Teller both
  reach your checking account, match it on one of them. A second match is
  refused, naming the connection that has it, so no line comes in twice.
- **New account…** (from 1.76.0): for a bank account you haven't set up in
  WalletWeather yet. Pick it, check the name (it starts as the bank's own),
  and press **Save matches**: WalletWeather makes the account, matches it
  from the "Bring in from" date and syncs straight away. Its starting
  balance is worked out from the bank's balance and the lines that come in,
  so its balance today is the bank's. If the sync can't run, nothing is made
  and you can try again. If the bank sends no balance, the account starts at
  0: set it in Settings → Accounts. It uses one of the day's 20 syncs.
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

### Categories from your banks

Teller and Plaid give each line a category of their own, such as `groceries`
or `FOOD_AND_DRINK`. SimpleFIN gives none, so this is only for lines that
come through Teller or Plaid. From 1.87.0 they're turned into your own
categories as lines land, by a table at the bottom of the Bank sync tab:

- **One row for each category seen so far.** A row appears the first time a
  sync brings in a line with that category, so the table is empty until
  then. Teller's and Plaid's categories are separate rows.
- **Each row says which of your categories it lands in.** It's filled in by
  itself where one of your categories has the same name, ignoring case and
  punctuation (Plaid's `FOOD_AND_DRINK` matches your "Food & Drink"; your
  default Groceries and Income match Teller's). Otherwise it's blank, and the
  line lands **Uncategorized**. Pick another category, or Uncategorized, and
  press **Save categories**.
- **Only lines that come in afterwards use a change.** Lines already here
  keep the category they landed with; change those by hand as usual. A
  category you add later isn't matched to a row that's already there: pick it
  in the table.
- **A line that pays a planned bill keeps the bill's category**, whatever its
  row says ([Bills paid by a sync](#bills-paid-by-a-sync)).
- **Your auto-tag rules run after the category is set,** so a rule limited
  to a category applies to lines that land in it.

### Your bank's balance next to yours

From 1.88.0, under **Current balance** on an account's Forecast tab, a linked
account shows the balance your bank reported at the last sync:

> Bank: $1,234.56 as of Nov 21, 2026, 9:05 AM

It's compared with **Current balance**, which counts only lines dated up to
today. When the two agree it says **Matches your bank**. When they don't, it
says **Bank differs by** the amount, in amber (positive when the bank has
more than you), with an **Adjust to bank** button:

- **Adjust to bank** adds one paid line named "Adjust to bank", dated today,
  for exactly the difference, so the two balances agree. It checks that the
  difference is still the one you were shown, and says so instead of adding
  a line if a sync or an edit has changed it.
- **Undo** appears in its place afterwards and deletes that line. It's an
  ordinary line, so you can also delete or edit it from the Forecast table
  like any other.
- **A gap usually means something is missing or doubled,** such as a line the
  bank hasn't posted yet, a pending line you entered by hand, or the account's
  starting balance. Adjust to bank is the quick fix when you'd rather not hunt
  for it; the correction line stays visible in the table as what it is.
- **Planned lines that aren't paid yet are named.** Your balance counts a
  planned bill dated today or earlier at its planned amount, which the bank
  can't have posted yet. When there are any, the tile says how many and how
  much, and Adjust to bank asks you to confirm, since a correction made now
  would be wrong once the bank posts them.
- **Two taps count once:** a second Adjust to bank for the same gap is refused,
  and **Undo** only shows while the bank balance is the one you adjusted
  against.

Where it comes from: SimpleFIN and Plaid send each account's balance with
every sync, and a bank account with no balance shows none. A credit card's
or loan's balance counts against you, as it does in your own account.
**Teller bills for each balance it's asked for in production,** so WalletWeather
asks only when the balance has likely moved: at the first sync of a linked
account, when the sync brings in a line it hasn't seen, or when the balance it
has is a week old. Pressing Sync now twice, or a quiet day, makes no billed
call, and the balance shown keeps the time it was read. If Teller can't give
the balance, the last good one stays unless new lines came in (it wouldn't
include them), and it's tried again at most once a day, not at every sync.
A balance that can't be read never stops the lines from coming in.

Only you see it, as the owner of the connection: people an account is shared
with don't see the bank's balance and can't adjust. It isn't shown while an
admin has bank sync switched off, and it goes when you disconnect or move the
match to another bank account. It isn't in backups; the next sync brings it
again.

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
- **Teller's and Plaid's category is mapped onto yours** (from 1.87.0): see
  [Categories from your banks](#categories-from-your-banks).
- **The bank's balance is kept** for each matched account (from 1.88.0): see
  [Your bank's balance next to yours](#your-banks-balance-next-to-yours).
- **Your auto-tag rules run** on each new line, as they do for a CSV import,
  after its category is set, so a rule limited to a category sees it.
- **Nothing comes in twice.** A line already brought in is recognised by the
  bank's own id. A paid line you added by CSV or by hand, with the same date,
  amount and description, is recognised too and isn't doubled.
- **Late postings are caught.** Each sync looks back 14 days before the
  last one, for lines a bank posts late.
- **At most 20 syncs in 24 hours, per connection.** SimpleFIN disables a connection that asks
  much more often than about 24 times a day, so Sync now stops at 20 and
  says when it can run again. The tab shows how many are left. SimpleFIN
  itself refreshes from banks about once a day, so syncing more often rarely
  brings anything new.

## Disconnecting

Each connection has its own **Disconnect** button in Settings → Bank sync.
It forgets the connection and its matches. Lines already brought in stay.
With two-factor sign-in on, it asks for a code. A Teller or Plaid connection
is ended at Teller or Plaid too, so it stops reading your bank; if the
service can't be reached at that moment, the connection is forgotten here
anyway and the message says to remove it in that service's dashboard.

{: .warning }
For SimpleFIN, disconnecting stops WalletWeather asking. To stop SimpleFIN
reading your bank too, disable the app's access at [SimpleFIN Bridge](https://bridge.simplefin.org/).

Deleting your WalletWeather user removes your connections too, and ends them
at Teller and Plaid.

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
| *Teller or Plaid isn't set up on this instance* | The server needs that service's keys in `.env`: see "Set up Teller" and "Set up Plaid". |
| *Teller didn't accept this server's certificate* | Check `certificate.pem` and `private_key.pem` are in the folder `TELLER_CERT_DIR` names, and that they're the ones for `TELLER_APP_ID`. |
| *Plaid didn't accept this server's keys* | Check `PLAID_CLIENT_ID`, and that `PLAID_SECRET` is the secret for `PLAID_ENV` (sandbox and production have different secrets). |
| *Plaid is still gathering your bank's history* | Plaid fetches your history after you connect. Sync again in a few minutes. |
| *Your bank wants you to sign in again* / *Plaid no longer reaches this bank* | Disconnect that bank and connect it again, then match its accounts again. |
| *That account already takes lines from …* | That account is matched to a bank account on another connection. Leave one of them out. |
| *Bank sync has asked SimpleFIN 20 times in the last 24 hours* | Wait for the time it gives. The daily sync counts toward the 20 too. |
| *A sync is already running* | The daily sync was running at that moment. Try again in a minute. |
| *Match at least one bank account to one of your accounts first* | Pick an account for at least one bank account and press Save matches. |
| Sync says *0 new lines* the first time | The "Bring in from" date is today, so only new transactions come in. Move it back and Save matches. |
| A bank account is missing from the list | Check it's linked at SimpleFIN Bridge, then press Sync now. The list is refreshed on each sync. |

## What's stored and what's sent

- **Stored on your server:** for each connection, the access address
  SimpleFIN issues (which includes its credentials) or the access token
  Teller or Plaid issues. It's encrypted with the server's `ENCRYPTION_KEY`
  and is never shown in the app or written to a log. The server also keeps your bank accounts' names (encrypted), your
  matches, how the last sync went, and the times of the last day's syncs.
  Each synced line carries a fingerprint of the bank's id for it, and which
  sync brought it in; for Teller and Plaid, also their own category for it, as
  they gave it (not encrypted, like the line's category of yours), and the
  table of those categories and where they land. The balance the bank gave
  for each matched account at the last sync, and when (encrypted, like every
  amount). The sync log (when, how many, any error) is kept as
  long as the audit log.
- **In backups:** encrypted backups (Settings → Backup, and the system
  backups) carry the connection, so a restore keeps it, but not the bank's
  balance, which the next sync brings again. The readable
  "Download my data" copy never carries the connection.
- **Sent:** when you connect and each time you sync, the server asks the
  service for your bank accounts and the posted transactions since a date,
  and when you disconnect it tells Teller or Plaid to end the connection.
  Plaid gets an identifier worked out from your user number, never your name
  or email. Nothing else about you is sent. The service and your bank see
  that the connection is used, and when.

The full details are in [`PRIVACY.md`](https://github.com/mkolakowski/WalletWeather/blob/main/PRIVACY.md)
under "What leaves the server".
