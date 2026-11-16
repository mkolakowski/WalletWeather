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

**What it changes:** roadmap item 12 becomes phase 1 of this plan, and item 29 is built on SimpleFIN only. Plaid is out of scope. What's still open (what unlocks an encrypted backup, who may connect, how close a match is) is in the plan's open questions.
