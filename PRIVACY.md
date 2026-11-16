# Privacy

WalletWeather is software you run yourself. This page says what it stores,
where that data goes, and who is responsible for it. It is not a privacy
policy for a hosted service, because the project doesn't host one.

## What the project collects

Nothing. WalletWeather has no analytics, no telemetry, no crash reporting and
no "phone home". The web client loads no fonts, scripts or images from other
sites. The people who write WalletWeather never see your instance or its
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
  to keep or take elsewhere, not encrypted. A user's bank connection goes
  into encrypted backups only, never into "Download my data".
- **Bank sync, for a user who connects a bank:** the address SimpleFIN
  issued for their connection, which holds its credentials (encrypted with
  `ENCRYPTION_KEY`, never shown or logged), the names of their bank
  accounts as SimpleFIN gives them (encrypted), which of their accounts each
  is matched to and from what date, when the last sync ran and how it went,
  and the times of the last day's calls to SimpleFIN (to stay within its
  limit). Each line it brings in is stored like any other, plus a hash of
  the bank's own id for it and which sync brought it in. A sync log for
  each matched account (when each sync ran, by schedule or by hand, how
  many lines came in or were already there, and any error), readable by
  the account's owner only and deleted after `AUDIT_RETENTION_DAYS` like
  the audit log. Disconnecting deletes the connection and the matches; the
  lines stay.
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

Nothing, with two exceptions the operator chooses:

- **Google sign-in:** when it's switched on (`GOOGLE_CLIENT_ID`), signing in
  with Google sends the user to Google, and Google tells the instance their
  email address, name and account identifier. Google's own privacy policy
  covers its side of that.
- **Bank sync:** when an admin switches it on (Admin → Bank sync, off by
  default), a user may connect their own SimpleFIN Bridge subscription. For
  that user only, the server calls SimpleFIN (only the hosts in
  `SIMPLEFIN_HOSTS`): once to claim the token they paste, then each time
  they sync, asking for their bank accounts and posted transactions since a
  date, about once a day by itself and whenever they press Sync now.
  Nothing about them goes the other way except that request and the
  credentials SimpleFIN issued. SimpleFIN and their bank see that the
  connection is used, and when; SimpleFIN's own privacy policy covers its
  side. Users who don't connect a bank cause no calls at all.

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
