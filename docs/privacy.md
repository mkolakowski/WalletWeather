---
title: Privacy policy
nav_order: 4
---

# WalletWeather privacy policy

Last updated: November 23, 2026

This policy covers the WalletWeather apps for iOS and Android and the
WalletWeather web app. WalletWeather is self-hosted: the apps connect to a
WalletWeather server that you, or someone you know, run, or the iOS app
keeps your numbers on your iPhone with no server at all. The people who
write WalletWeather do not run a service and do not receive your data.

## What we collect

Nothing. The apps have no analytics, no advertising, no tracking and no
crash reporting, and they send nothing to WalletWeather's authors or to any
third party.

## What the apps send, and where

The apps talk only to the WalletWeather server whose address you enter.
Everything you see and enter in them (your email address, your accounts,
balances, transactions and notes) is sent to that server and stored there,
and nowhere else. When the iOS app signs in, it names its sign-in after the
phone's model (for example "iPhone 17"), which you can change first, so you
can tell it apart in the web app's settings.

**On this iPhone** in the iOS app uses no server: your accounts, bills and
transactions are kept on the iPhone (see below) and the app sends them
nowhere. If you connect SimpleFIN Bridge in its Settings → Bank sync, the
iPhone itself asks SimpleFIN for your bank accounts and posted transactions
(see bank sync below); nothing of yours is sent to SimpleFIN beyond the
request.

**Try the demo** in the iOS app shows sample numbers built into the app. It
connects to nothing and saves nothing you change.

If the person who runs your server has switched on Google sign-in and you
choose to use it, you sign in with Google, and Google tells the server your
email address and name. Google's privacy policy covers its part in that.

If they have switched on bank sync and you connect your bank in the web app,
the server (not your phone) asks the service you connected through
(SimpleFIN Bridge, Teller or Plaid) for your bank accounts and posted
transactions whenever it syncs. You sign in to your bank on that service's
own page, never on WalletWeather's. The service and your bank see that, and
the service's privacy policy covers its part. For Teller or Plaid you add keys
from a developer account of your own in the web app's Settings → Bank sync;
the server keeps them encrypted, never shows the secret part again, and
checks them with the service when you save them. Signed in to a server, the iOS
app itself never talks to SimpleFIN, Teller or Plaid.

If you use the iOS app **On this iPhone** and connect SimpleFIN Bridge in its
Settings → Bank sync, the iPhone does what a server would: it swaps the setup
token you paste for a connection, and asks SimpleFIN for your bank accounts
and posted transactions when it syncs (at most once a day by itself, when you
open the app or in the background, and when you press Sync now). The
connection's secret address is kept in the iPhone's Keychain only, on that
device: never in iCloud, a backup or an exported file. The transactions land
with your other numbers on the iPhone, kept as described below. Disconnect
in the same place forgets the connection; disable the token at SimpleFIN
Bridge to stop it there too. Teller and Plaid can't be used without a server.

If they have switched on email alerts and you connect your Microsoft mailbox
in the web app, the server (not your phone) reads your bank's alert emails
from the one folder you picked, read-only, whenever it checks. Microsoft sees
that, and its privacy policy covers its part. The iOS app itself never talks
to Microsoft.

## What is kept on your device

What the app needs to reconnect: a sign-in per server, each kept in its own
item in the device's Keychain, on that device only (never in iCloud): the
server's address, the sign-in it was given, what the phone keeps for it and
the name of the theme saved on it (for "Match the web app"). And the app's
own settings: the look you picked, whether the app lock is on, which pages
are in the tab bar and which Getting started steps you've done.

Themes you make yourself in the iOS app (Settings → Appearance → My themes)
are kept in your iPhone's iCloud key-value storage, in your own iCloud
account, so they reach your other iPhones signed in to the same Apple ID, and
also on the iPhone itself, so with iCloud off they stay on that iPhone. Only
each theme's name and colours go there: never a number or anything else.
WalletWeather's authors can't see them. Deleting a theme deletes it on your
other iPhones too.

What the phone keeps is your choice for each server, asked when you sign in
and changeable in the app's settings:

- **Nothing** (the default): no balances or transactions are stored on the
  device, and the app needs a connection to your server.
- **Last-known numbers:** the pages you last loaded (balances, forecast
  lines, bills, the calendar, net worth, budgets and reports) are kept on the
  device, so the app can still show them, marked with when they were loaded,
  when your server can't be reached. They can't be read while the device is
  locked, are left out of iCloud and computer backups, and never leave the
  device. Each server's are kept apart, and deleted when you sign out of
  that server or switch it back to Nothing.

If you use the iOS app **On this iPhone**, with no server, your accounts,
bills, income, transactions, notes and categories are kept on the iPhone,
in the app's own storage, and in your iPhone's iCloud or computer backup (an
iCloud backup is encrypted by Apple, and end to end with Advanced Data
Protection on). Two iCloud features, both in your own iCloud account, which
WalletWeather's authors can't see:

- **Sync with iCloud** (on unless you turn it off in the app's Settings)
  keeps them in your private iCloud database (CloudKit), so your devices
  signed in to the same Apple ID share the same numbers. While it's on, they
  can be read on the iPhone after its first unlock, so they can sync in the
  background; with it off, they can't be read while the iPhone is locked.
- **Backup to iCloud Drive** (on from your first account, unless you turn it
  off) keeps an encrypted copy in your iCloud Drive's WalletWeather folder,
  at most once a day and the last 14, locked with your backup passphrase.

**Delete everything on this iPhone** in the app's Settings deletes them from
the iPhone. With sync on it offers **Delete on this iPhone only**, which
leaves the synced copy in your iCloud and on your other devices, and **Delete
everywhere**, which deletes them in your iCloud and on every device too. The
encrypted backups stay in iCloud Drive either way: delete them in the Files
app (iCloud Drive → WalletWeather), or remove all of WalletWeather's iCloud
data in your iPhone's Settings → your name → iCloud.

**Export for a server** saves them as an encrypted backup file wherever you
choose (for example the Files app), to restore on your own server. It's
locked with a backup passphrase you choose, which is kept in your iCloud
Keychain so your other Apple devices can open your backups. Nobody else,
including WalletWeather's authors, can recover the passphrase or open the
file without it.

**Widgets** in the iOS app (Balance, Next bills and To confirm, on the Home
Screen, the Lock Screen and in StandBy) read a small summary the app keeps on
the iPhone for each connection, in storage the app shares only with its own
widgets: the connection's name, when the summary was made, each account's name,
balance and the month's lowest forecast balance, your bills and income with
their names, amounts and next dates, each account's lowest forecast balance on
each of the next 7 days, and how many lines wait to be confirmed.

- The app writes it while the iPhone is unlocked, when its pages load and when
  you open or leave the app. The widgets only read it and never contact a
  server.
- It can't be read while the iPhone is locked, is left out of iCloud and
  computer backups, and never leaves the iPhone.
- Amounts in a widget show as •••• while the iPhone is locked, and also while
  the app's own lock is on, even on an unlocked iPhone. Names, labels and
  counts still show.
- A server set to keep **Nothing** gets a summary with its name only, and its
  widgets show no numbers. Switching a server to Nothing removes the rest of
  its summary straight away.
- A server's summary is deleted when you sign out of it. The summary of **On
  this iPhone** is deleted when you leave it, delete everything on this iPhone,
  or delete everywhere.

**Reminders** in the iOS app (Settings → Reminders: a bill due tomorrow, a
balance heading under an amount you pick, and new bank lines to match) are off
until you turn them on, which is when the iPhone asks to allow notifications.

- They're worked out on the iPhone from the same summary, for the connection
  you're using, and scheduled with the iPhone's own notifications. Nothing is
  sent anywhere, and no server sends them.
- None are made for the demo or for a server set to keep **Nothing**.
- A reminder's text names the bill or account and never shows an amount ("Rent
  is due tomorrow"), so a locked iPhone shows no numbers. Pressing and holding
  one shows the amount, which reads the summary, so it shows as •••• while the
  iPhone is locked or WalletWeather's own lock is on.
- Your choices (which switches are on, the time, the account and the amount)
  are kept in the app's settings on the iPhone. Signing out of the connection
  you're using removes its reminders.

**Siri and Shortcuts** in the iOS app (also on the Action button) offer two
actions: **Open To confirm**, which opens the app on the lines waiting to
confirm, and **What's my balance**, which answers with each account's balance
on the connection you're using, naming it and saying when its numbers are from.

- What's my balance answers from the same summary and never contacts a server.
  Nothing new is kept for it.
- It answers only while the iPhone is unlocked: on a locked iPhone, Siri asks
  you to unlock first. While WalletWeather's own lock is on, it asks for Face
  ID (or your passcode) before telling any amount.
- For a server set to keep **Nothing**, it says no numbers are kept on the
  iPhone, and tells no amount. The demo has no summary, so it has nothing to
  tell.
- What Siri shows and says is handled by the iPhone like any other Siri answer.
  Open To confirm only opens the app, where its own lock still applies.

Two more actions change your numbers, on the connection you're using:
**Add a line** opens the app's Add line form filled in with the
amount, description and date you gave, for you to check and save; **Mark a bill
paid** marks a bill's next date paid, as planned, without opening the app, and
says what it did.

- Mark a bill paid offers the bills from the same summary, and sends the change
  to your server (or the household on this iPhone) the same way the app does
  when you mark a line paid. It runs only while the iPhone is unlocked, and asks
  for Face ID (or your passcode) first while WalletWeather's own lock is on.
- It isn't offered for a server set to keep **Nothing** (no bills are kept to
  pick from) or the demo.
- Nothing new is kept on the iPhone for either.

**The iPhone's search** (swipe down on the Home Screen) finds your bills,
income and accounts by name, and opens each where it lives in the app.

- Each entry holds a name, what it is and where it lives ("Bill · Checking ·
  Home"), never an amount or a date. The entries are made on the iPhone from
  the same summary, are kept in the iPhone's own search index, and are
  searchable only while the iPhone is unlocked.
- The household on this iPhone and servers that keep Last-known numbers are
  included. Servers set to keep **Nothing** and the demo aren't.
- A bill or account you delete leaves the search the next time the summary is
  written. A server's entries go when you sign out of it or switch it to
  Nothing; the household's go when you leave it, delete everything on this
  iPhone, or delete everywhere.
- To keep WalletWeather out of the search altogether, turn off its Search
  setting in the iPhone's Settings → Apps → WalletWeather.

Removing the app removes all of it.

The app asks for the camera only when you choose **Scan a QR code** to sign
in. It looks for the QR code and nothing else: no picture is kept or sent
anywhere.

## Who is responsible for your data

Whoever runs the server you connect to. If that's you, your data never
leaves equipment you control. If someone else runs it, they hold your data
and are the person to ask about it.

## Seeing and deleting your data

In the app's Settings you can download a copy of your data and delete your
account, which removes your sign-in and everything only you own from the
server. The person who runs the server may still have backups made before
then.

## Children

WalletWeather is not directed at children under 13, and collects nothing
from anyone.

## Changes

If this policy changes, the new version is published on this page with a
new date.

## Contact

Questions about this policy:
<https://github.com/mkolakowski/WalletWeather/issues>. To report a security
problem privately, see the project's
[security policy](https://github.com/mkolakowski/WalletWeather/security/policy).
