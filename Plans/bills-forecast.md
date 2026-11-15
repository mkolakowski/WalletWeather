# Bills & income, closer to Forecast

Tracking issue: #131

## Status

| Phase | Issue | State |
| --- | --- | --- |
| 1. Forecast's columns, compact rows | #128 | Released in v1.45.0, closed 2026-11-15 |
| 2. Inline add line and edit rows | #129 | Released in v1.46.1, closed 2026-11-15 |
| 3. Controls row | #130 | Not started, waits for 2 |

- **Phase 1** — web 1.67.0 (no server change), built and released 2026-11-15 in v1.45.0 (#138). Verified: headless Chromium with sample data at 1600, 1440, 1280, 1100 and 390px (still a table down to 1100; header, read and open-row lines match; no column moves and no height change when a row opens; every heading sorts; spreadsheet mode and Archived render; phone cards label every field). Tags moved into their column per the open question's assumption. Known limit: Description is about 86px wide at 1440–1600, as on Forecast for editable accounts.

- **Phase 2** — web 1.68.0 and 1.68.1 (no server change), built and released 2026-11-15 in v1.46.1 (#140). Verified: headless Chromium with the API stubbed (POST/PATCH bodies for each Repeats choice, signed amounts and the start date's day; errors beside the field; spreadsheet mode skips a row whose only change is a filled-in start date; no column moves and 34px rows when the add line or a row opens at 1440 and 1100; phone add line stacks with labels). Width hints rebalanced so dates get more room; then (1.68.1, your choice) the date columns got a 130px floor, so a whole date always shows while editing and windows under about 1250px get the phone cards. Headings don't change with the add line (Bills' already name each field).

Sessions: may span — each phase ends with a release and your look on your own instance before the next starts.

## Agents and tools

| Phase | Main session | Subagents | Why |
| --- | --- | --- | --- |
| 1. Columns, compact rows | Opus | none | Reorders a table's columns and every rule that counts them (widths, lines, phone card, sort keys, spreadsheet mode). |
| 2. Add line, edit rows | Opus | none | A new kind of row, signed amounts, and the save paths for add, edit and spreadsheet mode. |
| 3. Controls row | Sonnet | none | Moves existing buttons into an existing pattern. |

## Open questions

- ~~**Day of month in edit rows (blocks Phase 2).**~~ Decided 2026-11-15: edit rows take the day from the start date; a monthly item without one opens with its next day-of-month date filled in. See [the decision page](../docs/dev/decisions/bills-forecast.md).
- ~~**Tags move into a column (blocks Phase 1).**~~ Decided 2026-11-15 with the column layout: tags show in the Tags column. Built in Phase 1.

## The plan

**Goal:** the Bills & income table looks and behaves like Forecast's: the same column grid, short one-line rows, an inline add line at the top of the table instead of a separate panel, and the buttons in the table's controls row.

**Decided 2026-11-15 (this plan's scoping round):**
- All four parts are in: columns, compact rows, inline add line, controls row.
- Columns, dates and amounts first: Description | Start date | Ends | Category | Amount | Account | Repeats | Monthly | Yearly | Tags | Notes | buttons (with the select checkbox column first, as now). Start date and Ends get their own columns, so Frequency no longer wraps and rows can be one line.
- The inline add line and edit rows take a **signed** Amount (negative = expense), like Forecast; the Type dropdown goes there. Everything else about how items are stored is unchanged.
- **+ Add** moves into the table's controls row, left, like Forecast; the separate "Bills & income" actions panel goes. Totals stay above the table.
- Phases ship in this order: columns and rows, then the add line, then the controls row.
- Each phase is checked in headless Chromium with the API stubbed (columns, row heights, lines, saves) at desktop and phone widths, then your look after release. No API change is expected, so no server tests are added.

**Out of scope:**
- Transfer, Import and the ⋯ menu from Forecast's controls row (they don't apply to recurring items).
- Changing how items are stored or the recurring API.
- The Reports, Calendar and other tables.

### Phase 1: Forecast's columns, compact rows

What changes:
- `#recurringTable` gets the column order above, with Forecast's widths (dates 142px, category 150px, amounts 120px, Notes 240px) and the same column lines and heading style. Account moves after Amount; Repeats shows Weekly / Bi-weekly / Monthly; Start date and Ends are plain date columns.
- Tags show as chips in their own column (see Open questions), no longer under the description.
- Read rows are one line (about 34px, like Forecast), instead of 48px or more.
- Sorting works on every heading, including the new Start date column. Selecting rows, the bulk bar, spreadsheet mode, the Archived view and the phone card layout keep working.

What you do: after the release, look at Bills & income on desktop and phone.

Done when:
- In headless Chromium with the API stubbed at 1600, 1440, 1280, 1100 and 390px wide: columns in the new order at Forecast's widths, untagged read rows one line tall, each heading sorts, row selection and the bulk bar work, spreadsheet mode and Archived render, and the phone card shows every field.
- No server change; web version bumped, changelog entry.

### Phase 2: Inline add line and edit rows

What changes:
- **+ Add** opens a new line at the top of the table, built like Forecast's: a field under each column (Description, Start date, Ends, Category, signed Amount, Account), Repeats and the Tags picker sharing the computed columns as in Forecast's add row, Notes with Save / + Another / Cancel. The account is a dropdown only on the All accounts tab. The #recAddPanel panel and its code go.
- Edit rows (and spreadsheet mode) use the same columns and a signed Amount; the Type dropdown goes; Repeats is the dropdown; Day of month goes too: the day comes from the start date, and a monthly item without one opens with its next day-of-month date filled in (decided 2026-11-15).
- While the add line is open its headings follow Repeats as on Forecast; no column moves when it opens or changes.

What you do: after the release, add and edit a monthly and a weekly item.

Done when:
- In headless Chromium with the API stubbed: each Repeats choice posts the right frequency, day of month, start date and signed amount; a missing start date or description shows an error beside the field; editing and spreadsheet-mode saves send the signed amount and tags; the add line is one row tall and no column moves at four desktop widths; the phone layout stacks the fields.
- Web version bumped, changelog entry (marked **Breaking** where the Type dropdown goes).

### Phase 3: Controls row

What changes:
- + Add moves to the left of the table's controls row, in Forecast's button style, and the "Bills & income" actions panel is removed. Active/Archived, Spreadsheet mode and paging stay, arranged and spaced like Forecast's row.

What you do: after the release, check the page on desktop and phone.

Done when:
- In headless Chromium at desktop and phone widths: + Add opens the inline add line, the controls sit in Forecast's arrangement, and nothing else on the page moved.
- Web version bumped, changelog entry.
