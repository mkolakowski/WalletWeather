---
title: "On the iPhone"
parent: Set up bank sync
nav_order: 4
---

# On the iPhone
{: .no_toc }

Connect Teller or Plaid from the iPhone app, or SimpleFIN on an iPhone used without a server.
{: .fs-6 .fw-300 }

## From the iPhone app

From iOS 0.30.0 with server 1.89.0, Teller and Plaid can be connected from
the phone: Settings → Bank sync → **Connect a bank**.

1. The phone's sign-in sheet opens your server's connect page. If it asks,
   sign in as you do in the web app; it shares Safari's sign-in, so usually
   you're signed in already.
2. Pick **Teller** or **Plaid** on its card (only the ones you're ticked for
   and have added your keys for, in the web app's Settings → Bank sync or on
   the keys page the app opens from Settings → Bank sync), and type your
   two-factor code if it's on: connecting a bank always takes a fresh one.
3. Sign in to your bank on Teller's or Plaid's page. When it's done the sheet
   closes by itself and the card says which bank was connected.
4. Match its accounts to yours in the web app, Settings → Bank sync, as for a
   connection made there.

The phone never holds anything that reads your bank: the page runs in the
sheet under your browser sign-in, as Settings does, and hands the app only
"connected" and the connection's number. With a server, SimpleFIN is
connected in the web app, since it means pasting a setup token (an iPhone
used on its own can paste one in the app: see [On an iPhone without a
server](#on-an-iphone-without-a-server)). A bank that would hand
off to its own app (Plaid's app-to-app sign-in) shows its web sign-in in the
sheet instead, so there's no Universal Link to set up.

## On an iPhone without a server

From iOS 0.32.0, an iPhone used on its own (**On this iPhone**, no server)
can connect SimpleFIN itself. Open **Settings → Bank sync → Connect
SimpleFIN**, paste a setup token made as on the [SimpleFIN](simplefin.md) page, and pick which of your
accounts each bank account fills and how far back to bring lines in (up to 90
days). The connection is kept in the iPhone's Keychain only, never in iCloud,
a backup or an exported file. It syncs at most once a day, when you open the
app or when iOS gives it time in the background, and **Sync now** works any
time. Only SimpleFIN can connect this way: Teller and Plaid need keys that
stay on a server.

Lines that don't pay a bill wait under **Unmatched** in the same card, where
**Match…** pays a bill or planned line with one and **Leave** keeps it as its
own line. When bank sync needs something, a slim card at the top of the
Dashboard says so.
