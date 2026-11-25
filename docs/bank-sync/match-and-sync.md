---
title: "Match and sync"
parent: Set up bank sync
nav_order: 5
---

# Match and sync
{: .no_toc }

Once a bank is connected: match its accounts to yours, sync, and read what each sync did.
{: .fs-6 .fw-300 }

<details open markdown="block">
  <summary>On this page</summary>
  {: .text-delta }
1. TOC
{:toc}
</details>
## Match your accounts

For each bank account:

- **Your account:** pick the WalletWeather account its transactions go into,
  or **Leave out**. Only accounts you own can be picked, not ones someone
  shares with you, and each of your accounts can be matched to one bank
  account only, across all your connections: if SimpleFIN and Teller both
  reach your checking account, match it on one of them. A second match is
  refused, naming the connection that has it, so no line comes in twice.
- **New account…** (from 1.76.0): for a bank account you haven't set up in
  WalletWeather yet. Pick it, check the name (it starts as the bank's own),
  and press **Save matches**: WalletWeather makes the account, matches it
  from the "Bring in from" date and syncs straight away. Its starting
  balance is worked out from the bank's balance and the lines that come in,
  so its balance today is the bank's. If the sync can't run, nothing is made
  and you can try again. If the bank sends no balance, the account starts at
  0: set it in Settings → Accounts. It uses one of the day's 20 syncs.
- **Bring in from:** the first date to bring in. It starts at today, which
  means only new transactions come in. Set it back up to 90 days to bring in
  recent history. Anything older is best brought in with a CSV import.

Press **Save matches**.

## Sync

Press **Sync now** for the first sync. The message says how many lines came
in and how many were already there.

After that, WalletWeather syncs by itself **about once a day** (from 1.70.0);
the tab says when the next one is due. **Sync now** still works whenever you
want one sooner.

## Read the sync log

Each matched bank account has a **Sync log** button: every sync of that
account, newest first, whether it ran by itself (Daily) or by **Sync now**,
how many lines came in, how many were already there, how many joined an
email alert's line (see [The Unmatched list](bills-and-balances.md#the-unmatched-list)), and any
error; the last 200 syncs are listed. **Show lines** lists the lines a sync brought in. The account's owners and the
people it's shared with to edit see it (from 1.91.0; before, only the person
who connected the bank did); people it's shared with read-only don't. Entries
are kept as long as the server keeps its audit log (180 days unless its admin
changed it).

## If sync keeps failing

The Dashboard shows a warning when bank sync has been failing for more than a
day, or when a service (SimpleFIN, Teller or Plaid) no longer accepts the
connection. The daily sync retries a failed sync about 6 hours later, and
stops altogether once the service has stopped accepting the connection, until
you connect again.

## What a sync does

- **Posted transactions only.** A transaction your bank still shows as
  pending comes in on a later sync, once the bank has posted it. A line never
  changes after it arrives.
- **Each one pays a planned bill, or lands as a paid line** on the matched
  account, dated the day the bank posted it ([Bills paid by a
  sync](bills-and-balances.md#bills-paid-by-a-sync)). A line's name is the bank's description,
  shortened to the company when the bank sends a whole ACH record (from
  1.71.0), with the full text in its notes.
- **Teller's and Plaid's category is mapped onto yours** (from 1.87.0): see
  [Categories from your banks](bills-and-balances.md#categories-from-your-banks).
- **The bank's balance is kept** for each matched account (from 1.88.0): see
  [Your bank's balance next to yours](bills-and-balances.md#your-banks-balance-next-to-yours).
- **Your auto-tag rules run** on each new line, as they do for a CSV import,
  after its category is set, so a rule limited to a category sees it.
- **Nothing comes in twice.** A line already brought in is recognised by the
  bank's own id. A paid line you added by CSV or by hand, with the same date,
  amount and description, is recognised too and isn't doubled. A line that is
  the posted version of an [email alert](../email-alerts.md)'s line joins the
  alert's line instead of becoming a second one.
- **Late postings are caught.** Each sync looks back 14 days before the
  last one, for lines a bank posts late.
- **At most 20 syncs in 24 hours, per connection** (SimpleFIN, Teller or
  Plaid). SimpleFIN disables a connection that asks much more often than
  about 24 times a day, so Sync now stops at 20 and says when it can run
  again. The tab shows how many are left. SimpleFIN
  itself refreshes from banks about once a day, so syncing more often rarely
  brings anything new.
