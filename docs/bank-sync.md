---
title: Set up bank sync
nav_order: 2
has_children: true
has_toc: false
---

# Set up bank sync
{: .no_toc }

Bring transactions into WalletWeather straight from your bank, instead of
uploading a CSV file.
{: .fs-6 .fw-300 }

Bank sync works through one of three services, picked per bank:

- **[SimpleFIN Bridge](https://beta-bridge.simplefin.org/)**, a service you
  subscribe to yourself (about $15 a year). Nothing to set up on the server.
- **[Teller](https://teller.io/)** (from 1.86.0), with keys from a Teller
  developer account of your own (from 1.95.0). Teller's development tier is
  free up to 100 bank logins.
- **[Plaid](https://plaid.com/)** (from 1.86.0), with keys from a Plaid
  account of your own (from 1.95.0). Plaid's Trial plan is free for 10 bank

Each reads your bank's transactions and balances. None can move money. If
your bank won't connect through one, try another: each reaches banks its own
way. You can have as many connections as you like, from any mix of them.

{: .important }
> - **WalletWeather 1.69.0 or later**, 1.70.0 for the daily sync and the sync log, 1.73.0 for bills paid by a sync, 1.86.0 for Teller, Plaid and more than one connection. The version is in the app's footer.
> - **An admin switches bank sync on** once for the server ([For the person who runs the server](bank-sync/server.md)).
> - **Each person connects their own banks** ([Connect your bank](#connect-your-bank)).

## The guides

In the order you'll need them:

1. **[For the person who runs the server](bank-sync/server.md):** update,
   let the server reach the services, switch bank sync on and tick who may
   use each service.
2. **[Teller and Plaid](bank-sync/teller-plaid.md):** add keys of your own,
   then connect.
3. **[SimpleFIN](bank-sync/simplefin.md):** make a setup token and paste it.
4. **[On the iPhone](bank-sync/iphone.md):** connect Teller or Plaid from the
   app, or SimpleFIN on an iPhone used without a server.
5. **[Match and sync](bank-sync/match-and-sync.md):** match bank accounts to
   yours, sync, read the sync log, and what a sync does.
6. **[Bills, categories and balances](bank-sync/bills-and-balances.md):**
   bills a sync pays, the Unmatched list, your banks' categories and the
   bank's balance next to yours.
7. **[Shared accounts](bank-sync/shared.md):** syncing an account shared with
   you, and when the person who connected leaves.
8. **[Disconnect and troubleshoot](bank-sync/troubleshooting.md):** ending a
   connection, and what each message means.
9. **[What's stored and what's sent](bank-sync/stored-and-sent.md)**

## Connect your bank

Open **Settings → Bank sync**. If there's no Bank sync tab, bank sync isn't
switched on yet: ask whoever runs the server. Under **Connect a bank** each
service your server offers has a card of its own, with its links and its
connect button. With two-factor sign-in on, type the code from your
authenticator app first.

### Add your own Teller or Plaid keys

Teller and Plaid each need keys from a developer account of your own (from
1.95.0), added once on the cards under **Your Teller and Plaid keys**.
[Step by step for Teller and for Plaid](bank-sync/teller-plaid.md#add-your-own-teller-or-plaid-keys).

### Through Teller or Plaid

Press **Connect with Teller** or **Connect with Plaid**, pick your bank and
sign in to it in the tab that opens, then close that tab. Each bank login is
a connection of its own. [More](bank-sync/teller-plaid.md#through-teller-or-plaid).

### Through SimpleFIN

Make a setup token at SimpleFIN Bridge, then paste it under **Paste a
SimpleFIN token**. A token works once. [Step by step](bank-sync/simplefin.md).

### From the iPhone app

From iOS 0.30.0 with server 1.89.0, Teller and Plaid connect from
**Settings → Bank sync → Connect a bank** in the app; an iPhone used on its
own (from iOS 0.32.0) connects SimpleFIN. [Step by step](bank-sync/iphone.md).

Then [match your accounts and sync](bank-sync/match-and-sync.md).

## Service pages

Where to sign in, set up and read each service's own help. They open on the
service's own site, and the app's setup steps link to the same pages.

| Service | Sign in and set up | Help |
| --- | --- | --- |
| **SimpleFIN Bridge** | [Home](https://beta-bridge.simplefin.org/) · [Sign in](https://beta-bridge.simplefin.org/auth/login) · [Your account](https://beta-bridge.simplefin.org/my-account) · [Make a setup token](https://beta-bridge.simplefin.org/simplefin/create) | [simplefin.org](https://www.simplefin.org/) · [How WalletWeather uses it](bank-sync/simplefin.md) |
| **Teller** | [Teller dashboard](https://teller.io/) (application id under Application Settings; certificates) | [Quickstart](https://teller.io/docs/guides/quickstart) · [Certificates](https://teller.io/docs/api/authentication) · [Teller Connect](https://teller.io/docs/guides/connect) · [How WalletWeather uses it](bank-sync/teller-plaid.md#through-teller-or-plaid) |
| **Plaid** | [Plaid dashboard](https://dashboard.plaid.com/) · [Keys page](https://dashboard.plaid.com/developers/keys) | [Quickstart](https://plaid.com/docs/quickstart/) · [Plaid Link](https://plaid.com/docs/link/) · [How WalletWeather uses it](bank-sync/teller-plaid.md#through-teller-or-plaid) |

{: .note }
SimpleFIN Bridge's pages are on `beta-bridge.simplefin.org`: the older
`bridge.simplefin.org` now sends every address to its home page. Plaid's
menus move around now and then; if Developers → Keys isn't where you expect,
use the Keys page link above.
