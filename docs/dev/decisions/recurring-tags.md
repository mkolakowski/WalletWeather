# Tags on recurring items

Decisions for [`Plans/recurring-tags.md`](../../../Plans/recurring-tags.md).

## 2026-11-24: auto-tag rules tag lines, not bills

**Decided:** 2026-11-24, by Matthew, confirming what shipped in 1.40.0 to 1.42.0 on a working assumption. **Status:** accepted. Settles the plan's open question (#339).

**The question:** should auto-tag rules tag recurring items (bills and income) themselves, as well as the transactions made from them?

**Options considered:**
- **No:** rules keep running only when a transaction is created or edited, so a line made from a bill gets the rule's tags when it's saved.
- **Yes:** rules also tag the bill, so its projected lines show rule tags before they're saved.

**The decision:** no. Rules run on transactions only; a bill carries only the tags given to it by hand.

**What it changes:** nothing in the code. It's how 1.40.0 to 1.42.0 already work; the plan's question is struck.
