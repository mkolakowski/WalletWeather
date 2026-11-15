# Usability pass: the web client

Tracking issue: #56

## Status

| Phase | Issue | State |
| --- | --- | --- |
| 1. Bills & income page | #51 | Released in v1.25.0, waiting on your check |
| 2. Forecast editing and lost features | #52 | Released in v1.26.0, waiting on your check |
| 3. Messages and dialogs | #53 | Released in v1.27.0, waiting on your check |
| 4. Navigation and Settings layout | #54 | Open |
| 5. Polish: wording, keyboard, filters | #55 | Open |

- **Phase 1** — app 1.25.0, web 1.49.0, released 2026-11-14 (#59). Verified: 7 new API tests for `GET /api/recurring` (43 pass); the page driven in jsdom against a demo copy (filter, totals, add, edit on another account, Select all monthly → bulk bar, Archived, a read-only shared account). Not yet seen in a real browser: screenshots were blocked in that session, so your look on desktop and phone is the check.
- **Phase 2** — app 1.26.0 (no server change), web 1.50.0, released 2026-11-14 (#60). Verified: 43 API tests pass; the page driven in jsdom against a demo copy (✎ opens a line with Delete inside; Save and add another keeps date and category; Transactions page search, bulk tag bar, transfer Edit / Save / Back returning to Transactions, and to Forecast when opened there; a read-only viewer gets no ✎). Not yet seen in a real browser.
- **Phase 3** — app 1.27.0 (no server change), web 1.51.0, released 2026-11-14 (#61). Verified: no `alert(`, `confirm(` or `prompt(` call left (grep); 43 API tests pass; jsdom against a demo copy: delete dialog (Cancel focused, red Delete last; Cancel, Escape and Delete each behave), rename account through the input dialog, short password refused inside the dialog, form mistakes next to the fields, a duplicate category shown as the server's sentence. Row editors on Forecast and Transactions still report mistakes as a message rather than beside the field. Not yet seen in a real browser.

Sessions: may span — each phase ends with a release and your look on your own instance (desktop and phone) before the next starts.

## Agents and tools

| Phase | Main session | Subagents | Why |
| --- | --- | --- | --- |
| 1. Bills & income page | Opus | Sonnet: write the endpoint tests once the response shape is set | Replaces two tables and their state with one, and adds an endpoint. |
| 2. Forecast editing and lost features | Sonnet | none | Re-links markup and code that already exist; small additions to the forecast table. |
| 3. Messages and dialogs | Sonnet | Haiku: list every `alert`/`confirm`/`prompt` call with its line and message | Wide but mechanical once the two shared pieces exist. |
| 4. Navigation and Settings layout | Opus | none | Changes the layout every page sits in, on phone and desktop. |
| 5. Polish | Sonnet | none | Small, separate fixes following patterns the earlier phases set. |

## Open questions

None open. Resolved 2026-11-14, all recorded in [`docs/dev/decisions/usability.md`](../docs/dev/decisions/usability.md):

1. ~~**Where does "Start date for all monthly" go on the combined list?**~~ Into bulk edit, with a "Select all monthly" shortcut. The always-visible bar goes.
2. ~~**How do you get back into transaction search?**~~ Its own "Transactions" page in the top bar, at `#transactions`.
3. ~~**How does a forecast row show it can be edited?**~~ An ✎ button at the end of each row. Double-click keeps working.
4. ~~**How are destructive actions confirmed?**~~ An in-page dialog that names what will be lost.
5. ~~**What does the top bar become on a phone?**~~ A bar fixed at the bottom with four main pages and a "More" button.
6. ~~**How is Settings split up?**~~ Tabs inside Settings, each with its own address. Budgets is one of them.
7. ~~**Which words for money in and out?**~~ Expense and Income.
8. ~~**What do the Bills & income totals show?**~~ Bills, income and net.

## The plan

**Goal:** every feature of the web client is reachable, each job is done in one place, and the app says what happened in plain words, with nothing it does today taken away.

**Where it came from:** an audit of `apps/web/index.html` on 2026-11-14, read from the code. Screenshots were blocked in that session, so layout findings (the phone ones above all) are unconfirmed until you look.

**Decided 2026-11-14:**
- The Subscriptions page becomes one combined, editable list for all accounts.
- The design choices in each phase below, recorded in [`docs/dev/decisions/usability.md`](../docs/dev/decisions/usability.md).
- The page and its top-bar button are called "Bills & income". The `#subscriptions` address keeps working.
- All four other groups of findings are in, one phase each, with Forecast and lost features second.
- A phase is done when the tests pass and you have tried it. Each phase gets its own release.

**Out of scope:** new features, a visual redesign or new themes, splitting `index.html` into several files, the native apps.

**Other plans touching the same file:** `phone-path` phase 1 (#41) and `legal-risk` phase 2 (#46) also edit `apps/web/index.html`. Phase 3's message pieces are there for #46's first-login notice to use if it lands later.

### Phase 1: Bills & income page

What's wrong today: the page shows the same recurring items twice (an editable table for one account on top, a read-only table for all accounts below), with the same three totals under the same labels but different numbers. Editing from the lower table means clicking the account, being scrolled up, and finding the row again. A recurring item can't be added on the page at all.

- One table for every account you can see: Description, Account, Category, Amount, Monthly, Yearly, Frequency, Ends, Notes, and ✎ to edit in place (the edit form that exists today).
- An account filter above it, "All accounts" by default. The totals follow the filter and say which accounts they cover: monthly bills, monthly income and what's left per month, with yearly figures underneath.
- An "+ Add recurring" button that opens the add form on this page, with an Account field. Forecast's "Make this recurring" checkbox stays.
- Active / Archived, sorting, paging (default raised from 5 to 20 rows) and bulk edit stay. Rows on read-only accounts can't be selected or edited.
- "Start date for all monthly" moves into bulk edit: a "Select all monthly" shortcut next to "Select all", then Start date in the bulk bar. The always-visible bar goes.
- The top-bar button and page title read "Bills & income". `#subscriptions` still opens it.
- Server: one endpoint that lists recurring items across accounts, active or archived, income included and counted in the totals, with tests. `/api/subscriptions` stays for anything else that calls it.

**You:** on your instance, add a recurring bill from the page, edit one on each of two accounts without leaving it, filter to one account and check the totals, bulk-edit two rows, and look at Archived.

**Done when:** tests pass; everything the two old tables could do is done from the one table; you've run the steps above on desktop and phone.

### Phase 2: Forecast editing and lost features

- A "Transactions" page in the top bar, at `#transactions`, holds cross-account transaction search, bulk tagging and the recent transfers list (with its Edit and Delete for a transfer). Their markup and code are still in the page; since 1.32.0 nothing opens them.
- Each forecast row ends with an ✎ button that opens it for editing, with Delete inside the open row as now. Double-click keeps working.
- "Add transaction" gets a "Save and add another" button that keeps the form open with the account, date and category kept.

**You:** search for a transaction across accounts and tag two results at once; edit a transfer; edit and delete a forecast row; add three transactions in a row.

**Done when:** tests still pass; each of those is reachable from a visible control; you've run the steps on desktop and phone.

### Phase 3: Messages and dialogs

- One in-page message strip (saved, failed, why) and one in-page confirm dialog (it names what will be lost; the Delete button is last and never the default) replace the browser pop-ups: about 50 `alert`, 21 `confirm` and 4 `prompt` calls.
- Errors read as sentences. Today a failed save shows the server's raw reply, such as `{"detail":"…"}`.
- Rename account, rename tag, "Save report as" and the admin's password reset get a small in-page form in place of `prompt`.
- Form mistakes (a missing amount, a missing date) are shown next to the field.

**You:** trigger a save, a failed save (an empty amount), a delete and a rename, on desktop and phone.

**Done when:** no `alert(`, `confirm(` or `prompt(` call is left in `apps/web/index.html`; every destructive action still asks first; you've run the steps.

### Phase 4: Navigation and Settings layout

- On a phone, a bar fixed at the bottom holds Dashboard, Forecast, Bills & income and Calendar, plus a "More" button for the other pages and Log out. Desktop keeps the row of buttons in the top bar.
- Settings becomes tabs (Appearance, Accounts, Categories & tags, Budgets, Sharing, Backup), one showing at a time, each with its own address. Every panel that exists today sits under one of them.
- Import and Transfer get their own addresses, so a refresh or the back button keeps you there.

**You:** walk every page on your phone and on desktop; refresh on Import and on Transfer; open Budgets from a cold start.

**Done when:** every page is one or two taps from anywhere on a phone; refresh keeps the page; old addresses still work; you've walked it.

### Phase 5: Polish: wording, keyboard, filters

- "Expense" and "Income" are the words shown for money out and in, everywhere. Stored values and API fields don't change.
- Account tabs reachable and usable from the keyboard; every form label tied to its field; a visible focus outline.
- Report filters (Accounts, Categories, Tags) become checklists in place of list boxes that need Cmd/Ctrl-click.
- The admin backup hour is shown and set in your local time, stored as UTC as today.
- Anything small you report while checking phases 1 to 4.

**You:** tab through the Forecast page without a mouse; build a report with two categories on your phone; check the backup hour.

**Done when:** each item above is in; tests pass; you've run the steps.
