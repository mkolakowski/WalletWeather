---
title: "What's stored and what's sent"
parent: Set up bank sync
nav_order: 9
---

# What's stored and what's sent
{: .no_toc }

What bank sync keeps on your server, what goes into backups, and what it sends.
{: .fs-6 .fw-300 }

- **Stored on your server:** for each connection, the access address
  SimpleFIN issues (which includes its credentials) or the access token
  Teller or Plaid issues, and (Teller and Plaid) a copy of the keys it was
  made with. Your own Teller and Plaid keys are kept too: the id and the
  environment as they are, the secret part (Plaid's secret, Teller's
  certificate and private key) encrypted. All of it is encrypted with the
  server's `ENCRYPTION_KEY` and is never shown in the app or written to a
  log; Teller's certificate is written to a file only the app can read for
  the moment a connection to Teller is opened, then removed. The server also keeps your bank accounts' names (encrypted), your
  matches, how the last sync went, and the times of the last day's syncs.
  Each synced line carries a fingerprint of the bank's id for it, and which
  sync brought it in; for Teller and Plaid, also their own category for it, as
  they gave it (not encrypted, like the line's category of yours), and the
  table of those categories and where they land. The balance the bank gave
  for each matched account at the last sync, and when (encrypted, like every
  amount). The sync log (when, how many, any error) is kept as
  long as the audit log.
- **In backups:** encrypted backups (Settings → Backup, and the system
  backups) carry the connection and your own Teller and Plaid keys, so a
  restore keeps them, but not the bank's balance, which the next sync brings
  again. The readable "Download my data" copy never carries the connection
  or the keys.
- **Sent:** when you connect and each time you sync, the server asks the
  service for your bank accounts and the posted transactions since a date,
  and when you disconnect it tells Teller or Plaid to end the connection.
  Plaid gets an identifier worked out from your user number, never your name
  or email. Nothing else about you is sent. The service and your bank see
  that the connection is used, and when.

The full details are in [`PRIVACY.md`](https://github.com/mkolakowski/WalletWeather/blob/main/PRIVACY.md)
under "What leaves the server".
