---
title: "Disconnect and troubleshoot"
parent: Set up bank sync
nav_order: 8
---

# Disconnect and troubleshoot
{: .no_toc }

Ending a connection, and what to do about each message bank sync can show.
{: .fs-6 .fw-300 }

## Disconnecting

Each connection has its own **Disconnect** button in Settings → Bank sync.
It forgets the connection and its matches. Lines already brought in stay.
With two-factor sign-in on, it asks for a code. A Teller or Plaid connection
is ended at Teller or Plaid too, so it stops reading your bank; if the
service can't be reached at that moment, the connection is forgotten here
anyway and the message says to remove it in that service's dashboard.

{: .warning }
For SimpleFIN, disconnecting stops WalletWeather asking. To stop SimpleFIN
reading your bank too, disable the app's access at [SimpleFIN Bridge](https://beta-bridge.simplefin.org/my-account).

Deleting your WalletWeather user removes your connections and ends them at
Teller and Plaid, except a connection that feeds an account another owner
keeps: that passes to them (see [When the person who connected
leaves](shared.md#when-the-person-who-connected-leaves)).

## If something goes wrong

| The message says | What to do |
| --- | --- |
| *Bank sync is switched off on this instance* | An admin switches it on in Admin → Bank and email → Bank sync. |
| *That doesn't look like a SimpleFIN setup token* | Copy the token again from SimpleFIN Bridge, all of it. |
| *That token points at …, which isn't SimpleFIN* | The token isn't from SimpleFIN Bridge, or the server's `SIMPLEFIN_HOSTS` doesn't include the host it came from. Nothing was sent to that host. |
| *SimpleFIN says this token was already used or doesn't exist* | Make a new setup token. If you didn't use the old one yourself, disable it at SimpleFIN Bridge. |
| *Couldn't reach SimpleFIN* | SimpleFIN may be down, or the server can't reach it: see [Make sure the server can reach SimpleFIN](server.md#make-sure-the-server-can-reach-simplefin). |
| *SimpleFIN says your subscription needs paying* | Renew at SimpleFIN Bridge, then sync again. |
| *SimpleFIN no longer accepts this connection* | It was disabled at SimpleFIN or ran out. Disconnect, make a new setup token and connect again. |
| *Add your own Teller keys first* (or Plaid) | Add them on the card in Settings → Bank sync: see [Add your own Teller or Plaid keys](teller-plaid.md#add-your-own-teller-or-plaid-keys). |
| *Teller didn't accept this certificate* / *don't read as a matching pair* | Use `certificate.pem` and `private_key.pem` from the same `teller.zip`, made for this application and environment. |
| *Plaid didn't accept this client id and secret* | Check the client id, and that the secret is the one for the environment you picked (sandbox and production have different secrets). |
| *Your Teller keys are in use by …* | A different application or client id, or removing your keys, waits until those connections are disconnected. |
| *Plaid is still gathering your bank's history* | Plaid fetches your history after you connect. Sync again in a few minutes. |
| *Your bank wants you to sign in again* / *Plaid no longer reaches this bank* | Disconnect that bank and connect it again, then match its accounts again. |
| *That account already takes lines from …* | That account is matched to a bank account on another connection. Leave one of them out. |
| *Bank sync has asked SimpleFIN (or Teller, or Plaid) 20 times in the last 24 hours* | Wait for the time it gives. The daily sync counts toward the 20 too. |
| *A sync is already running* | The daily sync was running at that moment. Try again in a minute. |
| *Match at least one bank account to one of your accounts first* | Pick an account for at least one bank account and press Save matches. |
| Sync says *0 new lines* the first time | The "Bring in from" date is today, so only new transactions come in. Move it back and Save matches. |
| A bank account is missing from the list | Check it's linked at SimpleFIN Bridge, then press Sync now. The list is refreshed on each sync. |
