---
title: "Bills, categories and balances"
parent: Set up bank sync
nav_order: 6
---

# Bills, categories and balances
{: .no_toc }

What happens to the lines a sync brings in: paying your planned bills, the Unmatched list, your banks' categories and the bank's balance.
{: .fs-6 .fw-300 }

<details open markdown="block">
  <summary>On this page</summary>
  {: .text-delta }
1. TOC
{:toc}
</details>
## Bills paid by a sync

From 1.73.0, a synced line that looks like one of your planned bills or
paychecks pays it instead of landing as a second line. The bill's line in
Forecast is marked paid, at the bank's date and amount, with a **Bank sync**
mark. A line looks like a bill when it's on the same account, goes the same
way (money out for a bill, in for income), and is close to one of the bill's
dates that isn't paid yet:

- **within 5 days** either side, and
- **within 10%** of the planned amount.

Each bill has its own two settings in its editor in Bills & income: change
them for a bill that's often late or varies a lot, or set them to 0 for one
that must match exactly. When two dates are equally close, nothing is
matched, so you choose.

**Un-match** a line that was matched wrongly, from its row in Forecast: the
bill goes back to planned and the bank's line stays as its own paid line. It
isn't matched again.

## The Unmatched list

Synced lines that didn't pay a bill are kept on an **Unmatched** list, with a
count beside the account on the Bank sync tab. For each one:

- **Match…** shows the account's planned lines that aren't paid yet, nearest
  in date first (whatever the bill's settings say). Pick one: it's marked paid
  with the bank's date and amount, and the separate line goes away.
- **Leave as its own line** takes it off the list.
- **Join…** (when the account also takes lines from
  [email alerts](../email-alerts.md)) pairs an alert's line with this bank line.
  An alert no bank line has met in 10 days shows **Never posted**, with
  **Delete** or **Keep**.

Lines synced before 1.73.0 are on the list too, so you can match any that
duplicate a bill you hadn't marked paid.

## Categories from your banks

Teller and Plaid give each line a category of their own, such as `groceries`
or `FOOD_AND_DRINK`. SimpleFIN gives none, so this is only for lines that
come through Teller or Plaid. From 1.87.0 they're turned into your own
categories as lines land, by a table at the bottom of the Bank sync tab:

- **One row for each category seen so far.** A row appears the first time a
  sync brings in a line with that category, so the table is empty until
  then. Teller's and Plaid's categories are separate rows.
- **Each row says which of your categories it lands in.** It's filled in by
  itself where one of your categories has the same name, ignoring case and
  punctuation (Plaid's `FOOD_AND_DRINK` matches your "Food & Drink"; your
  default Groceries and Income match Teller's). Otherwise it's blank, and the
  line lands **Uncategorized**. Pick another category, or Uncategorized, and
  press **Save categories**.
- **Only lines that come in afterwards use a change.** Lines already here
  keep the category they landed with; change those by hand as usual. A
  category you add later isn't matched to a row that's already there: pick it
  in the table.
- **A line that pays a planned bill keeps the bill's category**, whatever its
  row says ([Bills paid by a sync](#bills-paid-by-a-sync)).
- **Your auto-tag rules run after the category is set,** so a rule limited
  to a category applies to lines that land in it.

## Your bank's balance next to yours

From 1.88.0, under **Current balance** on an account's Forecast tab, a linked
account shows the balance your bank reported at the last sync:

> Bank: $1,234.56 as of Nov 21, 2026, 9:05 AM

It's compared with **Current balance**, which counts only lines dated up to
today. When the two agree it says **Matches your bank**. When they don't, it
says **Bank differs by** the amount, in amber (positive when the bank has
more than you), with an **Adjust to bank** button:

- **Adjust to bank** adds one paid line named "Adjust to bank", dated today,
  for exactly the difference, so the two balances agree. It checks that the
  difference is still the one you were shown, and says so instead of adding
  a line if a sync or an edit has changed it.
- **Undo** appears in its place afterwards and deletes that line. It's an
  ordinary line, so you can also delete or edit it from the Forecast table
  like any other.
- **A gap usually means something is missing or doubled,** such as a line the
  bank hasn't posted yet, a pending line you entered by hand, or the account's
  starting balance. Adjust to bank is the quick fix when you'd rather not hunt
  for it; the correction line stays visible in the table as what it is.
- **Planned lines that aren't paid yet are named.** Your balance counts a
  planned bill dated today or earlier at its planned amount, which the bank
  can't have posted yet. When there are any, the tile says how many and how
  much, and Adjust to bank asks you to confirm, since a correction made now
  would be wrong once the bank posts them.
- **Two taps count once:** a second Adjust to bank for the same gap is refused,
  and **Undo** only shows while the bank balance is the one you adjusted
  against.

Where it comes from: SimpleFIN and Plaid send each account's balance with
every sync, and a bank account with no balance shows none. A credit card's
or loan's balance counts against you, as it does in your own account.
**Teller bills for each balance it's asked for in production,** so WalletWeather
asks only when the balance has likely moved: at the first sync of a linked
account, when the sync brings in a line it hasn't seen, or when the balance it
has is a week old. Pressing Sync now twice, or a quiet day, makes no billed
call, and the balance shown keeps the time it was read. If Teller can't give
the balance, the last good one stays unless new lines came in (it wouldn't
include them), and it's tried again at most once a day, not at every sync.
A balance that can't be read never stops the lines from coming in.

The account's owners and the people it's shared with to edit see it and can
adjust (from 1.91.0; before, only the person who connected the bank could);
people it's shared with read-only don't see the bank's balance. It isn't shown while an
admin has bank sync switched off, and it goes when you disconnect or move the
match to another bank account. It isn't in backups; the next sync brings it
again.
