# Bank sync

Decisions made while planning and building [`Plans/bank-sync.md`](../../../Plans/bank-sync.md) (tracking issue #198).

## 2026-11-16: the provider, backups first, the first slice, matching and the iOS part

**Decided:** 2026-11-16, by Matthew. **Status:** accepted.

**The questions:** which service brings the transactions in, what a backup does with the bank token while backups aren't encrypted, how big the first release is, how a bank row meets the forecast, and what the iOS app does.

**Options considered:**
- Provider: SimpleFIN Bridge; Plaid with each instance's own keys (both looked at in #163).
- Backups: leave the connection out of backups; encrypted backups first (roadmap item 12); put the token in today's plain backups.
- First slice: connect and Sync now; connect plus a daily sync; everything in one release.
- Forecast: match planned bills automatically; a review list first; land as paid with no matching; decide later.
- iOS: status and Sync now; connecting from the phone too; nothing for now.

**The decision:** SimpleFIN Bridge. Encrypted backups are built first, as the plan's phase 1, and the bank connection only ever goes into the encrypted kind. The first bank release is connect and Sync now; the daily schedule follows. A bank row close in date and amount to a planned bill marks it paid at the real amount, anything else lands as a new paid line, and a wrong match can be undone. The iOS app shows the sync's status and has a Sync now button; connecting stays in the web app.

**Why:** SimpleFIN needs no provider approval, no script from another site and no public address, which Plaid does. The token reads bank transactions, so it shouldn't sit in a file anyone can read. A small first release tries the real bank early.

**What it changes:** roadmap item 12 becomes phase 1 of this plan, and item 29 is built on SimpleFIN only. Plaid is out of scope. The plan's open questions were settled the same day, below.

## 2026-11-16: the plan's eight open questions

**Decided:** 2026-11-16, by Matthew. **Status:** accepted.

**The questions and what was chosen** (the first option listed is the one chosen):

1. **What unlocks an encrypted backup:** a passphrase typed at export and import; not the server's `ENCRYPTION_KEY`; not a choice of either at each export. Scheduled backups take theirs from `BACKUP_PASSPHRASE` in `.env`.
2. **Whether plain backups stay:** no, backups are encrypted only; not both kinds side by side.
3. **Who may connect a bank:** nobody until an admin switches it on in Admin, off by default; not a `.env` setting; not every user always.
4. **How far back the first sync reaches:** a start date picked per account, defaulting to today; not all 90 days with a preview; not today only.
5. **Pending bank transactions:** wait until posted; not shown as unpaid lines.
6. **How close a match is:** settable per bill, starting at 5 days and 10%; not one fixed rule of 5 days and 10%; not 3 days and the exact amount.
7. **Shared accounts:** only the owner links an account to a bank; not anyone with edit access.
8. **A fresh code:** with two-factor on, connecting and disconnecting each ask for one; not connecting only; not none.

**Why:** a passphrase restores on any server, where the server's key would lose the backups with the `.env`. The admin switch keeps `PRIVACY.md`'s "nothing leaves the server unless the operator chooses". A start date keeps a balance from moving by surprise. Posted-only means a line never changes after it arrives.

**What it changes:** phase 1 drops the plain backup as a choice, which raised the plan's question 9 (the readable "Download my data" copy, old plain files still importing, and the schedule needing `BACKUP_PASSPHRASE`), built on stated assumptions. Phase 4 gains two settings on every bill and a schema version, and phase 5 adds them to the iOS bill editor.

## 2026-11-16: a sync log and matching by hand

**Decided:** 2026-11-16, by Matthew (asked for while the plan was being written). **Status:** accepted.

**The decision:** the account's owner can read a log of each sync (phase 3), and synced lines that matched no bill are kept on an Unmatched list, from which one can be matched by hand to a planned line that isn't paid yet (phase 4).

**What it changes:** phases 3 and 4 are bigger. Both are web only; the iOS app doesn't get them in this plan. How long the log is kept is the plan's open question 10.
