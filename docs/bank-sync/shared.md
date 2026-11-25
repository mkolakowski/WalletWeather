---
title: "Shared accounts"
parent: Set up bank sync
nav_order: 7
---

# Shared accounts
{: .no_toc }

How sync works for an account someone shares with you, and what happens when the person who connected the bank leaves.
{: .fs-6 .fw-300 }

## Accounts shared with you

From 1.91.0 an account's sync belongs to the account, not only to the person
whose bank login feeds it. If someone shares an account with you to edit (or
as an owner) and it takes lines from their bank connection, your Settings →
**Bank sync** tab lists it under **Shared accounts that sync**: "Synced from
Sam's Teller connection · Total Checking", how its last sync went, and when
it syncs by itself next. You can press **Sync now** for it, read its **Sync
log**, and work through its **Unmatched** list, and its Forecast tab shows the
bank's balance with **Adjust to bank**, as it does for the person who
connected it. You never see their bank login or their other accounts on it.

Some things stay with the person who connected the bank: reconnecting or
disconnecting it, and where its bank's categories land. Only an account's
owners can match it to a bank account or take the match away. If an admin
pauses that person's connection, the card says so and Sync now waits until
it's back. If the person who connected has been turned off by an admin, it
doesn't sync until an admin turns them back on or an owner matches it to
their own bank account. People the account is shared with read-only see the lines that
come in and nothing about the sync.

If you're an owner of such an account, its card also has **Stop syncing**:
the account stops taking lines from that connection (lines already in stay,
and the connection stays the other person's). Either of you can match it
again later.

## When the person who connected leaves

From 1.92.0, deleting someone (they delete themselves, or an admin does) no
longer stops the accounts their bank connection feeds. Each connection that
still feeds an account staying with another owner passes to that owner: the
other owner of the account it was matched to first. It keeps syncing, with
its matches and sync logs, and the new holder is let use its service in
Admin → Users if they weren't already. Matches to accounts the new holder
doesn't own stay too; Bank sync shows them as text they can't change, and
those accounts' owners can use **Stop syncing**. The delete screens say which
connections pass to whom before anything is deleted.
