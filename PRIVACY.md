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
  identifier if they signed in with Google.
- **What users enter:** accounts, balances, transactions, recurring
  transactions, transfers, budgets, categories, tags and notes. Account
  names, balances, amounts, descriptions and notes are encrypted in the
  database with the instance's `ENCRYPTION_KEY`.
- **Backups:** exports and scheduled system backups are unencrypted JSON
  files that contain all of the above, email addresses included.
- **Logs:** the web server's access log, which records the address and path
  of each request, goes to the container's output. The app also keeps a
  sign-in log in the database: each sign-in, failed sign-in and blocked
  sign-in, with the email that was typed (even one with no account), the
  address it came from, the user if there is one, and when. Never a password.
  It's what the sign-in rate limit counts. The same log records account and
  admin actions: password changes and resets, an admin disabling, enabling
  or deleting a user or changing a permission, the instance title or the
  backup settings, backups made, downloaded, restored, exported or imported,
  a user deleting themselves, and API tokens made or revoked. Each says who
  did it and from which address; a user an action was done to is named by
  number, not email. No amounts, account names or other financial data. Admins can read it in Admin → Audit log.
  Entries are deleted once they're older than `AUDIT_RETENTION_DAYS` (180
  days unless you change it), checked once a day. Deleting a user keeps
  their entries but removes both the link to the user and the email address
  from them, failed attempts on that email included.
- **In the browser:** one signed session cookie that keeps the user signed
  in. No tracking cookies.

## What leaves the server

Nothing, with one exception the operator chooses: when Google sign-in is
switched on (`GOOGLE_CLIENT_ID`), signing in with Google sends the user to
Google, and Google tells the instance their email address, name and account
identifier. Google's own privacy policy covers its side of that.

## If you run an instance for other people

You are the one holding their data, not the WalletWeather project. Depending
on where you and they live, privacy law (the GDPR in Europe, state laws in
the US) may apply to you. In practice:

- Tell the people using it who runs it and that an admin can manage their
  user. Admins are the addresses in `ADMIN_EMAILS`.
- Keep the instance off the public internet, or behind something that
  checks who's asking before the app does (a VPN, a private tunnel).
- Treat backup files and the `.env` file like the data itself: anyone with a
  backup can read everything, and anyone with the database and the
  `ENCRYPTION_KEY` can too.
- **A copy of their data:** each user can export their own data as JSON from
  the app.
- **Deleting their data:** each user can delete their own user from
  Settings ("Delete my account"), which removes them and everything only
  they own; an account they share stays if it has another owner. An admin
  can also delete a user from the Admin panel. Old backup files still
  contain deleted users until you remove those files. The sign-in log keeps
  their past entries without their email address.

## Changes

This page is updated when what the app stores or sends changes. The
changelog records each change.
