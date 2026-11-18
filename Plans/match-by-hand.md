# Matching bank lines by hand: a pop-in, Forecast, and bills that learn

Tracking issue: #225

## Status

| Phase | Apps | Issue | State |
| --- | --- | --- | --- |
| 1. The match pop-in | Server, Web | #222 | Built in 1.77.0 (web 1.93.0), 2026-11-17; waits for the release and your try |
| 2. Match from Forecast | Server, Web | #223 | Built in 1.78.0 (web 1.94.0), 2026-11-17; waits for the release and your try |
| 3. Bills learn bank text | Server, Web | #224 | Built in 1.79.0 (web 1.95.0, schema 31), 2026-11-17; waits for the release and your try |

Phase 3 built 2026-11-17 in 1.79.0 (web 1.95.0, schema 31), with open question 1 decided the same day (a taught name pays its bill at any amount within its days; first built as days and %, changed before release) and on question 2's assumption: "lines like this" is the line's short name (worked out again from the bank's text in its notes when renamed), ignoring case and spaces. The name is kept encrypted (`recurring_transactions.match_text_enc`) and goes into backups. Matching at sync and alert time prefers a taught bill among those that fit; `remember: true` on the match teaches the bill and catches up the Unmatched list (`also_matched`). Forget is `DELETE /api/recurring/{id}/match-text` (immediate, so the editor's unsaved fields aren't needed); a bill's PATCH can also set or clear `match_text`. Verified by API tests in `apps/server/tests/test_bank_match_learn.py` (6: a taught bill takes the next tie and another name still ties, no remember no change, catch-up of a fitting line and not of one outside the %, Forget with its permission checks, PATCH keeps/sets/clears, a one-off teaches nothing) with the full suite, and headless Chromium with the API stubbed (the box ticked, `remember` sent, the "and 2 more" note; caught and fixed the checkbox stretching across the row). Not seen in a browser: Forget in the bill editor.

Phase 2 built 2026-11-17 in 1.78.0 (web 1.94.0, no schema change): Forecast rows carry `bank_unmatched`, the forecast carries `bank_unmatched_count` (the owner's only, 0 for people it's shared with), and `GET /api/accounts/{id}/bank-unmatched/near` lists the lines that could pay a planned line. Verified by API tests in `apps/server/tests/test_bank_match_forecast.py` (5) with the full suite, and headless Chromium with the API stubbed: the buttons appear only on the right rows and only while lines wait, the turned-round pop-in sends the right match, reloads the forecast and says what was paid, no page errors. Not seen in a real browser: the buttons inside Forecast's open line (the stubbed check renders them on their own). Set in building, not asked: the pill isn't a button (a tap opens the line, as for every row); the turned-round cards say "money in, not out" for a line going the other way; the button reads "This paid it".

Phase 1 built 2026-11-17 in 1.77.0 (web 1.93.0, no schema change): the candidates response keeps `candidates` and adds `choices` (one per bill, its dates in `dates`, with `amount_diff`, `days_after` and `same_direction`) and the line's `source` and `bank_text`. Verified by API tests in `apps/server/tests/test_bank_match_popin.py` (4) with the full suite, and headless Chromium at 1280 and 390px with the API stubbed (cards, picking another date updates the card and is what Pay this sends, the box closes and the list refreshes, no page errors). Set in building, not asked: a planned line going the other way says "planned as money in/out" and sorts last; "earlier/later" and "more/less" are the bank's line against the planned one, with a hint line saying so; a tap on the backdrop closes the box.

Planned 2026-11-17 (9:30 PM ET), from your look at the Unmatched panel after web 1.91.0 (#220).

Sessions: may span — each phase ships its own version and you check it on your own instance before the next starts.

## Agents and tools

| Phase | Apps | Main session | Subagents | Why |
| --- | --- | --- | --- | --- |
| 1. The match pop-in | Server, Web | Opus | Sonnet: the API tests for the grouped candidates; Sonnet: runs the suite and the headless-browser check | A new screen whose layout you chose, and a change to the candidates response the web client reads. |
| 2. Match from Forecast | Server, Web | Opus | Sonnet: the API tests for the new fields and endpoint | Changes the Forecast response and the Forecast table, the busiest screen; the pop-in from phase 1 is reused both ways. |
| 3. Bills learn bank text | Server, Web | Opus | Sonnet: the matching tests (taught, untaught, tie, catch-up, Forget) | A schema change, and a change to what pays a bill automatically: a wrong match moves real numbers. |

## Open questions

1. ~~**What a taught bill adds.**~~ Decided 2026-11-17 ([decision](../docs/dev/decisions/match-by-hand.md)): a line with the name a bill learned pays it **at any amount** going its way, within the bill's ± days, and wins over bills that fit by amount. (Changed from the first answer, text + days + %, after phase 3 showed that the taught text would then only break ties.)
2. **What "lines like this" means.** Blocks phase 3. Assumed: the line's short name (what Description shows after #213's shortening, e.g. "Example Internet"), compared ignoring case and extra spaces, exactly. Lines you renamed by hand are compared by the bank's text in their notes.
3. **How far the planned row's list reaches** ("Paid by a bank line…", phase 2). Blocks nothing. Assumed: unmatched lines within 60 days of the planned date, the same reach as Match….

## The plan

**Goal:** matching an unmatched bank line to a planned line is quick to read and quick to do, can be started from the Forecast page, and teaches the bill so lines like it match on their own from then on.

**What you saw** (2026-11-17): the information feels far apart, and things show twice:

- Forecast shows both the bank's line and the planned bill, two rows for one payment, until they're matched.
- The date and amount are in the bank line's table and again in the planned-lines table under it, with different headings.
- One bill shows up more than once in the planned lines to pay: Match… reaches 60 days either side, so a monthly bill appears at up to four dates.

**Decided 2026-11-17** (asked in the session):

- **One pop-in, used everywhere:** the bank line on top (name, date, amount, the bank's full text), and below it one card per planned line in plain words, e.g. "Amazon · Nov 15 · −$40.00 · $2.17 more · 1 day later", with Pay this. The closest card is highlighted. Leave as its own line and Close sit at the bottom.
- **Both ways from Forecast:** an unmatched bank row gets an "Unmatched" pill and Match…, which opens the pop-in listing planned lines; a planned row gets "Paid by a bank line…", which lists the unmatched bank lines near it.
- **Bills learn:** the pop-in offers "Match lines like this to ‹bill› from now on", ticked by default. A later line with the same text pays that bill when it's inside the bill's ± days, at any amount going its way (first chosen as days and %, changed 2026-11-17, open question 1). Teaching also matches lines already on the Unmatched list that fit, and says how many ("Paid, and 2 more lines like it matched"). The bill editor shows what it learned, with Forget.
- **A plan in three phases**, each its own version.

### Phase 1: The match pop-in

- **Server:** `GET /api/accounts/{id}/bank-unmatched/{txn_id}/candidates` lists **one entry per bill** (its nearest open date), with the bill's other open dates in the 60 days on the entry, so the pop-in can offer them without repeating the bill. Saved planned lines that aren't a bill's date stay one entry each. Each entry also carries the amount difference and which side of the bank's date it falls, so the card's words come from one place. The line carries the bank's full text (`_bank_text_of`). The old fields stay, so an older web client keeps working.
- **Web:** Match… on the Unmatched list opens the pop-in (the app's dialog style, full width on a phone) instead of the table under the row. A card's date can be changed to another of the bill's open dates. Pay this and Leave as its own line work from the pop-in, then the list and counts refresh as now.
- **Done when:** a monthly bill shows once with its other dates on offer; each card reads in words; Pay this and Leave work from the pop-in, from Bank sync and from Email alerts; the API tests pass; the pop-in is checked in a headless browser at desktop and phone widths.

### Phase 2: Match from Forecast

- **Server:** a Forecast row for an unmatched bank or alert line says so (a new field, e.g. `bank_unmatched: true`). A new endpoint lists the unmatched lines near a planned line (a saved line by id, or a bill's date), nearest first. Both come with tests.
- **Web:** an unmatched bank row shows an "Unmatched" pill, and its open line has Match… (the phase 1 pop-in). A planned row's open line has "Paid by a bank line…" when the account has unmatched lines near it: the same pop-in turned round, the planned line on top and the bank lines as cards. After a match, the Forecast reloads and shows one row where there were two.
- **Done when:** both directions match from Forecast; the pill goes once a line is matched or left; the tests pass; checked in a headless browser.

### Phase 3: Bills learn bank text

- **Server:** a bill can carry learned bank text (a new column, schema version bumped, a migration). Automatic matching at sync and alert time prefers a bill whose learned text matches the line, within its ± days and amount %; a tie between taught bills is still left unmatched. The match endpoint takes `remember: true`, saves the text on the bill and matches the lines already on the Unmatched list that fit the bill's other open dates, returning how many. The bill's PATCH can clear it (Forget).
- **Web:** the checkbox in the pop-in, ticked by default; the "and N more" message; the bill editor shows the learned text with Forget.
- **Done when:** a taught bill takes next month's line on the next sync, including where two bills tied before; untaught bills match as today; catch-up says how many it matched; Forget stops it; the tests pass.
