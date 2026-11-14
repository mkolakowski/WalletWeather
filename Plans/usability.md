# Usability pass: the web client

Tracking issue: #56

## Status

| Phase | Issue | State |
| --- | --- | --- |
| 1. Bills & income page | #51 | Open |
| 2. Forecast editing and lost features | #52 | Open (waits on open questions 2 and 3) |
| 3. Messages and dialogs | #53 | Open |
| 4. Navigation and Settings layout | #54 | Open (waits on open questions 5 and 6) |
| 5. Polish: wording, keyboard, filters | #55 | Open (waits on open question 7) |

Nothing shipped yet.

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

1. **Where does "Start date for all monthly" go on the combined list?** (phase 1, not blocking) Working assumption: the always-visible bar goes; the same job is done by selecting rows and using the bulk bar's Start date, with a "Select all monthly" shortcut next to "Select all".
2. **How do you get back into transaction search?** (blocks phase 2) A "Transactions" button in the top bar, or a "This account / Search all accounts" toggle on the Forecast page as before 1.32.0.
3. **How does a forecast row show it can be edited?** (blocks phase 2) An ✎ button at the end of each row, or a one-line hint above the table with double-click kept as the only way.
4. **How are destructive actions confirmed?** (phase 3, not blocking) Working assumption: an in-page dialog that names what will be lost, with the destructive button last and never the default.
5. **What does the top bar become on a phone?** (blocks phase 4) A menu button, a bottom bar with the main pages, or one sideways-scrolling row.
6. **How is Settings split up?** (blocks phase 4) Jump links at the top of the one page, tabs inside Settings, or Budgets moved out to its own page.
7. **Which words for money in and out?** (blocks phase 5) Today the app uses Withdraw/Deposit, Spending/Income and Outgoing/Incoming for the same idea.

## The plan

**Goal:** every feature of the web client is reachable, each job is done in one place, and the app says what happened in plain words, with nothing it does today taken away.

**Where it came from:** an audit of `apps/web/index.html` on 2026-11-14, read from the code. Screenshots were blocked in that session, so layout findings (the phone ones above all) are unconfirmed until you look.

**Decided 2026-11-14:**
- The Subscriptions page becomes one combined, editable list for all accounts.
- The page and its top-bar button are called "Bills & income". The `#subscriptions` address keeps working.
- All four other groups of findings are in, one phase each, with Forecast and lost features second.
- A phase is done when the tests pass and you have tried it. Each phase gets its own release.

**Out of scope:** new features, a visual redesign or new themes, splitting `index.html` into several files, the native apps.

**Other plans touching the same file:** `phone-path` phase 1 (#41) and `legal-risk` phase 2 (#46) also edit `apps/web/index.html`. Phase 3's message pieces are there for #46's first-login notice to use if it lands later.

### Phase 1: Bills & income page

What's wrong today: the page shows the same recurring items twice (an editable table for one account on top, a read-only table for all accounts below), with the same three totals under the same labels but different numbers. Editing from the lower table means clicking the account, being scrolled up, and finding the row again. A recurring item can't be added on the page at all.

- One table for every account you can see: Description, Account, Category, Amount, Monthly, Yearly, Frequency, Ends, Notes, and ✎ to edit in place (the edit form that exists today).
- An account filter above it, "All accounts" by default. The totals (count, monthly cost, yearly cost) follow the filter and say which accounts they cover. They count bills only, as today; income rows show "—".
- An "+ Add recurring" button that opens the add form on this page, with an Account field. Forecast's "Make this recurring" checkbox stays.
- Active / Archived, sorting, paging (default raised from 5 to 20 rows) and bulk edit stay. Rows on read-only accounts can't be selected or edited.
- "Start date for all monthly" as in open question 1.
- The top-bar button and page title read "Bills & income". `#subscriptions` still opens it.
- Server: one endpoint that lists recurring items across accounts, active or archived, income included, with tests. `/api/subscriptions` stays for anything else that calls it.

**You:** on your instance, add a recurring bill from the page, edit one on each of two accounts without leaving it, filter to one account and check the totals, bulk-edit two rows, and look at Archived.

**Done when:** tests pass; everything the two old tables could do is done from the one table; you've run the steps above on desktop and phone.

### Phase 2: Forecast editing and lost features

Depends on open questions 2 and 3.

- Cross-account transaction search, bulk tagging and the recent transfers list (with its Edit and Delete for a transfer) are reachable again. Their markup and code are still in the page; since 1.32.0 nothing opens them.
- Forecast rows show they can be edited, and delete is reachable without knowing about Spreadsheet mode.
- "Add transaction" gets a "Save and add another" button that keeps the form open with the account, date and category kept.

**You:** search for a transaction across accounts and tag two results at once; edit a transfer; edit and delete a forecast row; add three transactions in a row.

**Done when:** tests still pass; each of those is reachable from a visible control; you've run the steps on desktop and phone.

### Phase 3: Messages and dialogs

- One in-page message strip (saved, failed, why) and one in-page confirm dialog replace the browser pop-ups: about 50 `alert`, 21 `confirm` and 4 `prompt` calls.
- Errors read as sentences. Today a failed save shows the server's raw reply, such as `{"detail":"…"}`.
- Rename account, rename tag, "Save report as" and the admin's password reset get a small in-page form in place of `prompt`.
- Form mistakes (a missing amount, a missing date) are shown next to the field.

**You:** trigger a save, a failed save (an empty amount), a delete and a rename, on desktop and phone.

**Done when:** no `alert(`, `confirm(` or `prompt(` call is left in `apps/web/index.html`; every destructive action still asks first; you've run the steps.

### Phase 4: Navigation and Settings layout

Depends on open questions 5 and 6. Starts with a short round of questions.

- The top bar (eight pages plus Log out) fits a phone without wrapping onto several rows.
- Settings (eight panels on one page) gets a way to reach a panel directly, and Budgets is easy to get to.
- Import and Transfer get their own addresses, so a refresh or the back button keeps you there.

**You:** walk every page on your phone and on desktop; refresh on Import and on Transfer; open Budgets from a cold start.

**Done when:** every page is one or two taps from anywhere on a phone; refresh keeps the page; old addresses still work; you've walked it.

### Phase 5: Polish: wording, keyboard, filters

Depends on open question 7 for the first item.

- One pair of words for money in and out, everywhere.
- Account tabs reachable and usable from the keyboard; every form label tied to its field; a visible focus outline.
- Report filters (Accounts, Categories, Tags) become checklists in place of list boxes that need Cmd/Ctrl-click.
- The admin backup hour is shown and set in your local time, stored as UTC as today.
- Anything small you report while checking phases 1 to 4.

**You:** tab through the Forecast page without a mouse; build a report with two categories on your phone; check the backup hour.

**Done when:** each item above is in; tests pass; you've run the steps.
