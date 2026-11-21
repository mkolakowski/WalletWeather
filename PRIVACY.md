# Privacy

WalletWeather is software you run yourself. This page says what it stores,
where that data goes, and who is responsible for it. It is not a privacy
policy for a hosted service, because the project doesn't host one.

## What the project collects

Nothing. WalletWeather has no analytics, no telemetry, no crash reporting and
no "phone home". The web client loads no fonts, scripts or images from other
sites, with one exception an operator chooses: the page that connects a bank
through Teller (`/bank/teller`, only when Teller is set up and a user opens
it to connect) loads Teller's own script from `cdn.teller.io`, as Teller
requires. No other page loads it. The people who write WalletWeather never see your instance or its
data.

## What an instance stores

Everything stays in the PostgreSQL database and the backup folder of the
server it runs on:

- **About each user:** email address, display name, a bcrypt hash of the
  password (never the password), display preferences, and a Google account
  identifier if they signed in with Google. If they switch on two-factor
  sign-in: the key their authenticator app shares with the server (encrypted
  with the instance's `ENCRYPTION_KEY`), when it was switched on, and their
  recovery codes as hashes (never the codes). If they tick "Don't ask on
  this browser", each remembered browser's short name worked out from the
  browser (like "Safari on iPhone", never the full browser string), when it
  was remembered and last used, when it runs out (30 days), and a hash of
  the cookie that browser keeps. Switching it off deletes the key, the codes
  and the remembered browsers; changing the password deletes the remembered
  browsers.
- **What users enter:** accounts, balances, transactions, recurring
  transactions, transfers, budgets, categories, tags and notes. Account
  names, balances, amounts, descriptions and notes are encrypted in the
  database with the instance's `ENCRYPTION_KEY`.
- **Backups:** backups a user downloads and the scheduled system backups
  contain all of the above, email addresses included, encrypted with a
  passphrase: the user's own, or the instance's `BACKUP_PASSPHRASE`.
  "Download my data" is the exception: a plain, readable file for the user
  to keep or take elsewhere, not encrypted. A user's bank connection and
  mailbox sign-in go into encrypted backups only, never into "Download my
  data".
- **Email alerts, for a user who connects a mailbox:** Microsoft's sign-in
  for it (encrypted with `ENCRYPTION_KEY`, never shown or logged), the
  mailbox's address (encrypted), the folder they picked and the day to read
  from. For each bank they teach: its sender address, the name they gave
  it, which account its lines go to and which card digits go to which
  account, and for each kind of alert how its subject starts, the text
  around each value and the sample alert's text (both encrypted). Alerts
  from a taught bank that didn't become lines, with their subject and text
  (encrypted), until they're dismissed or older than `AUDIT_RETENTION_DAYS`
  (180 days unless changed). Each line an alert brings in is stored like any
  other, plus a hash of the email's own id and which check brought it in. A
  log of the mailbox's checks that brought something in or failed (when, by
  itself or by hand, how many lines came in, were already there or couldn't
  be read, and any error), readable by the user only and kept as long as the
  audit log. Other mail is never stored.
- **Bank sync, for a user who connects a bank:** for each of their
  connections, which provider it's through (SimpleFIN, Teller or Plaid) and
  what that provider issued for it, which reads the bank: SimpleFIN's access
  address or Teller's or Plaid's access token (encrypted with
  `ENCRYPTION_KEY`, never shown or logged); the names of their bank
  accounts and their banks as the provider gives them (encrypted), which of
  their accounts each is matched to and from what date, when the last sync
  ran and how it went, the times of the last day's calls to the provider
  (to stay within SimpleFIN's limit), and for Plaid where its next sync
  starts. While a Teller or Plaid connection is being made, a short-lived
  record of it (for Plaid, its link token, encrypted), kept a day at most. Each line it brings in is stored like any other, plus a hash of
  the bank's own id for it, which sync brought it in and, for Teller and
  Plaid, the category the provider gave it (a short word such as
  `groceries` or `FOOD_AND_DRINK`, not encrypted, like the line's own
  category). The table of those categories and which of the user's
  categories each lands in is kept too, and deleted with the user. Disconnecting keeps both. A sync log for
  each matched account (when each sync ran, by schedule or by hand, how
  many lines came in or were already there, and any error), readable by
  the account's owner only and deleted after `AUDIT_RETENTION_DAYS` like
  the audit log. Disconnecting deletes the connection and the matches (and
  ends it at Teller or Plaid); the lines stay.
- **Logs:** the web server's access log, which records the address and path
  of each request, goes to the container's output. The app also keeps a
  sign-in log in the database: each sign-in, failed sign-in and blocked
  sign-in, with the email that was typed (even one with no account), the
  address it came from, the user if there is one, and when. Never a password.
  It's what the sign-in rate limit counts. The same log records account and
  admin actions: password changes and resets, an admin disabling, enabling
  or deleting a user or changing a permission, the instance title or the
  backup settings, backups made, downloaded, restored, exported or imported,
  a user downloading their data, a bank connected or disconnected and each
  sync (how many lines, or that it failed),
  a user deleting themselves, API tokens made or revoked, and two-factor
  sign-in switched on or off, a recovery code used, recovery codes remade
  and browsers remembered or forgotten (never a code). Each says who
  did it and from which address; a user an action was done to is named by
  number, not email. No amounts, account names or other financial data. Admins can read it in Admin → Audit log.
  Entries are deleted once they're older than `AUDIT_RETENTION_DAYS` (180
  days unless you change it), checked once a day. Deleting a user keeps
  their entries but removes both the link to the user and the email address
  from them, failed attempts on that email included.
- **In the browser:** one signed session cookie that keeps the user signed
  in. No tracking cookies.

## What leaves the server

Nothing, with three exceptions the operator chooses:

- **Google sign-in:** when it's switched on (`GOOGLE_CLIENT_ID`), signing in
  with Google sends the user to Google, and Google tells the instance their
  email address, name and account identifier. Google's own privacy policy
  covers its side of that.
- **Bank sync:** when an admin switches it on (Admin → Bank sync, off by
  default), a user may connect their banks through SimpleFIN Bridge (their
  own subscription), Teller or Plaid (Teller and Plaid only when the
  operator has put that provider's keys in `.env`). For that user only, the
  server calls the provider they chose: SimpleFIN (only the hosts in
  `SIMPLEFIN_HOSTS`), Teller (`api.teller.io`, with the instance's own
  client certificate) or Plaid (`production.plaid.com` or
  `sandbox.plaid.com`, with the instance's keys). It calls when they
  connect, then each time they sync, asking for their bank accounts and
  posted transactions, about once a day by itself and whenever they press
  Sync now, and once more when they disconnect, to end the connection at
  Teller or Plaid. Plaid is given an identifier worked out from the user's
  number on the instance, never their name or email.
  Connecting happens on the provider's own page, so the user's bank sign-in
  goes to the provider, never through the instance: Plaid's Hosted Link opens
  on Plaid's site, and Teller Connect runs on the one page that loads
  Teller's script. The provider and their bank see their accounts and
  transactions and when the connection is used; the provider's own privacy
  policy covers its side. Users who don't connect a bank cause no calls at
  all.
- **Email alerts:** when an admin switches them on (Admin → Email alerts,
  off by default) and has registered a Microsoft app (`MS_CLIENT_ID`), a
  user may connect their own Microsoft 365 or Outlook.com mailbox. For that
  user only, the server calls Microsoft (login.microsoftonline.com and
  graph.microsoft.com, nothing else): to sign in, to renew the sign-in, and
  each time they check, to list the folder's mail since the last check and
  open the alerts from banks they've taught. It asks for read-only access
  and never changes the mailbox. By itself it looks every 5, 15 or 60
  minutes, as the user chose. Nothing about them goes the other way
  except those requests and the sign-in. Microsoft sees that the mailbox is
  read, and when; its own privacy policy covers its side. Users who don't
  connect a mailbox cause no calls at all.

## If you run an instance for other people

You are the one holding their data, not the WalletWeather project. Depending
on where you and they live, privacy law (the GDPR in Europe, state laws in
the US) may apply to you. In practice:

- Tell the people using it who runs it and that an admin can manage their
  user. Admins are the addresses in `ADMIN_EMAILS`.
- Keep the instance off the public internet, or behind something that
  checks who's asking before the app does (a VPN, a private tunnel).
- Treat backup passphrases, "Download my data" files and the `.env` file
  like the data itself: anyone with a backup and its passphrase can read
  everything, anyone with a "Download my data" file can read that user's
  data, and anyone with the database and the `ENCRYPTION_KEY` can too.
  Backup files from before version 1.68.0 aren't encrypted: delete them
  once you have new ones.
- **A copy of their data:** each user can download their own data as
  readable JSON from the app (Settings → Your account → Download my data).
- **Deleting their data:** each user can delete their own user from
  Settings ("Delete my account"), which removes them and everything only
  they own; an account they share stays if it has another owner. An admin
  can also delete a user from the Admin panel. Old backup files still
  contain deleted users until you remove those files. The sign-in log keeps
  their past entries without their email address.

## Changes

This page is updated when what the app stores or sends changes. The
changelog records each change.
