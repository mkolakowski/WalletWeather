---
title: "SimpleFIN"
parent: Set up bank sync
nav_order: 3
---

# SimpleFIN
{: .no_toc }

Connect a bank through your own SimpleFIN Bridge subscription, with a setup token.
{: .fs-6 .fw-300 }

## Get a setup token from SimpleFIN

1. Go to [SimpleFIN Bridge](https://beta-bridge.simplefin.org/simplefin/create)
   and subscribe ([sign in](https://beta-bridge.simplefin.org/auth/login) if
   you already have an account).
2. Link your bank there. You sign in to your bank on SimpleFIN's pages, not
   in WalletWeather; WalletWeather never sees your bank password.
3. Make a **setup token** for a new app and copy it. It's a long line of
   letters and numbers.

{: .note }
A setup token works **once**. If connecting fails after the token was
accepted, or you connect again later, make a new one.

## Connect it in WalletWeather

1. Open **Paste a SimpleFIN token** under **Connect a bank**.
2. Paste the setup token and press **Connect**. If you have two-factor
   sign-in on, type the code from your authenticator app too.
3. Your bank accounts are listed, as SimpleFIN names them.

With a server, connecting works in a browser only: an API token or the
iPhone app talking to a server can't connect a bank.
