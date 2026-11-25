---
title: "Teller and Plaid"
parent: Set up bank sync
nav_order: 2
---

# Teller and Plaid
{: .no_toc }

Add keys from a Teller or Plaid account of your own, then connect a bank through them.
{: .fs-6 .fw-300 }

## Add your own Teller or Plaid keys

Teller and Plaid each need keys from a developer account of your own (from
1.95.0), so your bank logins count against your own account there. If an
admin has ticked you for Teller or Plaid, Settings → Bank sync has a card for
each under **Your Teller and Plaid keys**. Saving checks the keys with the
service first and says what's wrong if they don't work. Once saved, the card
shows the id, the environment and when they were checked, never the secret.

**Teller:**

1. Make a developer account at [teller.io](https://teller.io/) and an
   application ([Teller's quickstart](https://teller.io/docs/guides/quickstart)
   shows how). Copy its **application id** (it starts `app_`) from
   Application Settings.
2. Under **Certificates** ([about certificates](https://teller.io/docs/api/authentication)),
   make a certificate. Teller downloads it as
   `teller.zip`, holding `certificate.pem` and `private_key.pem`. The private
   key is a secret: don't share it.
3. On the **Your Teller keys** card, enter the application id, pick the
   environment and pick `teller.zip`, then press **Check and save**. If
   picking the zip doesn't work, **Or pick the two files** and **Or paste
   their text** take the two files instead. `development` reaches your real
   banks and is free up to 100 bank logins; `sandbox` uses Teller's made-up
   banks and needs no certificate; `production` needs Teller to approve your
   account.

**Plaid:**

1. Make an account at [dashboard.plaid.com](https://dashboard.plaid.com/).
   The free **Trial** plan allows 10 bank logins, Chase, Bank of America and
   Wells Fargo included. Applying for full production later ends the Trial
   plan for good.
2. Open the [Keys page](https://dashboard.plaid.com/developers/keys) (under
   Developers), and copy the client id and the secret for the environment
   you'll use.
3. On the **Your Plaid keys** card, enter them, pick the environment and
   press **Check and save**. `production` reaches your real banks (on the
   Trial plan too); `sandbox` uses Plaid's made-up banks with the sandbox
   secret.

**Replace and Remove:** a renewed Teller certificate or a new Plaid secret for
the same id can replace the old one any time, and your connections carry on
with it. A different application or client id, or removing your keys, waits
until the connections using them are disconnected: the card names them. Each
connection keeps its own encrypted copy of the keys it was made with, so it
keeps syncing for whoever it passes to if you delete your account.

## Through Teller or Plaid

1. On the **Teller** or **Plaid** card, press **Connect with Teller** or
   **Connect with Plaid**. A new tab opens:
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
