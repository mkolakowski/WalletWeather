# Usability pass: the choices behind the plan

Decisions made while planning [`Plans/usability.md`](../../../Plans/usability.md) (tracking issue #56), after the interface audit of 2026-11-14. The audit read `apps/web/index.html`; nothing was checked by eye, so each choice is confirmed when its phase is tried on a real instance.

## 2026-11-14: scope, order and how phases are checked

**Decided:** 2026-11-14, by Matthew. **Status:** accepted.

- **The plan covers every group of findings**, one phase each: the Subscriptions page, Forecast editing and lost features, messages and dialogs, navigation and Settings layout, and polish.
- **Order:** the Subscriptions rework first, then Forecast and lost features (search, bulk tagging and transfer editing are unreachable today). Messages first, or navigation first, were the other options.
- **A phase is done when the tests pass and Matthew has tried it** on desktop and phone. Tests alone with one look at the end was turned down: layout mistakes would pile up unseen.
- **Each phase gets its own release.** One release at the end, or deciding each time, were the other options.

## 2026-11-14: the Subscriptions page becomes "Bills & income", one combined list

**Decided:** 2026-11-14, by Matthew. **Status:** accepted.

**The question:** the page showed the same recurring items twice: an editable table for one account and a read-only table for all accounts, with the same three totals under the same labels. How should it be reworked, and what is it called?

**Options considered:**
- Keep both panels and fix them (an add button, edit from either, clearer labels): still two places for one job.
- Make the page a read-only overview and move editing back to the Forecast page: editing a bill on another account would still mean leaving the page.
- One combined, editable list for all accounts with an account filter: chosen.
- Name, "Recurring": accurate, but Matthew preferred plainer words.
- Name, keep "Subscriptions": the page also holds rent, loans and paychecks.
- Name, "Bills & income": chosen.

**The decision:**
- One table for every account, with an Account column, an account filter, edit in place and an "+ Add recurring" button.
- The page and its top-bar button read "Bills & income". The `#subscriptions` address keeps working.
- **Totals show bills, income and net:** monthly bills, monthly income and what's left per month, with yearly figures underneath, following the account filter. Bills only, as before, was the other option.
- **"Start date for all monthly"** is done through bulk edit: a "Select all monthly" shortcut, then Start date in the bulk bar. The always-visible bar goes. Keeping the bar, shown or folded away, were the other options.

**What it changes:** phase 1 (#51): the page, a server endpoint that lists recurring items across accounts with income in its totals, and its tests.

## 2026-11-14: a Transactions page, and an edit button on forecast rows

**Decided:** 2026-11-14, by Matthew. **Status:** accepted.

**The question:** cross-account search, bulk tagging and the transfers list have had no way in since 1.32.0, and forecast rows can only be edited by a double-click nothing mentions. How is each reached?

**Options considered:**
- Search as a toggle on the Forecast page, as before 1.32.0: hidden one level down.
- Search behind a button in Account actions: a sub-page with no address of its own.
- Search as its own "Transactions" page in the top bar, with the address `#transactions`: chosen. It adds a ninth button, which phase 4 deals with.
- Row editing, a hint line only: no new column, but easy to miss.
- Row editing, both a button and a hint: more on screen than needed.
- Row editing, an ✎ button at the end of each row: chosen. Double-click keeps working, and Delete stays inside the open row.

**What it changes:** phase 2 (#52).

## 2026-11-14: deletes are confirmed in an in-page dialog

**Decided:** 2026-11-14, by Matthew. **Status:** accepted.

**The question:** with browser pop-ups being replaced, how is a delete confirmed?

**Options considered:**
- Delete at once with an "Undo" message for small things: faster, but the server would need an undo path, with more to build and test.
- An in-page dialog that names what will be lost, with the Delete button last and never the default: chosen.

**What it changes:** phase 3 (#53).

## 2026-11-14: a bottom bar on phones, and tabs inside Settings

**Decided:** 2026-11-14, by Matthew. **Status:** accepted.

**The question:** nine page buttons plus Log out wrap onto several rows on a phone, and Settings is one page of eight panels. What does each become?

**Options considered:**
- Phone, a menu button: every page two taps away, none one tap.
- Phone, one sideways-scrolling row: least to build, but pages off-screen are easy to forget.
- Phone, a bar fixed at the bottom with Dashboard, Forecast, Bills & income and Calendar, and a "More" button for the rest: chosen. Desktop keeps the row of buttons.
- Settings, jump links on the one long page: still a lot of scrolling on a phone.
- Settings, tabs with Budgets moved out to its own page: one more page in the navigation.
- Settings, tabs inside the page, one section showing at a time, each with its own address: chosen. Budgets is one of the tabs.

**What it changes:** phase 4 (#54).

## 2026-11-14: "Expense" and "Income" everywhere

**Decided:** 2026-11-14, by Matthew. **Status:** accepted.

**The question:** the app shows Withdraw/Deposit, Spending/Income and Outgoing/Incoming for the same idea. Which one pair is used?

**Options considered:**
- Spending / Income: fewest labels to change, but "Spending" reads oddly as the type of one transaction.
- Money out / Money in: plainest, but long in tight columns.
- Expense / Income: chosen.

**What it changes:** phase 5 (#55): the words shown only. Stored values and API fields such as `withdraw` and `deposit` stay as they are.
