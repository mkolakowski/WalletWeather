# Tags on recurring items

Tracking issue: #121

## Status

| Phase | Issue | State |
| --- | --- | --- |
| 1. Server: recurring items carry tags | #118 | Released in v1.40.0, closed 2026-11-15 |
| 2. Forecast: tags on repeating lines | #119 | Released in v1.41.0, closed 2026-11-15 |
| 3. Bills & income: tag pickers | #120 | Released in v1.42.0, closed 2026-11-15 |

- **Phase 1** — app 1.40.0, schema 15, released 2026-11-15 (#123). Verified: 10 new API tests in `tests/test_recurring_tags.py` (53 pass in all); the migration run on a v14 database filled by the v14 test suite (24 recurring items): `recurring_tags` created with both foreign keys, nothing lost, the full suite passes on it.

- **Phase 2** — web 1.62.1 (no server change), built 2026-11-15, released the same day in v1.41.0 (the API tokens release, cut by another session after this phase's commit). Verified: headless Chromium with the API stubbed (picker enabled with Repeats and `tag_ids` reach `POST …/recurring`; a projected line opens with its item's tags and saves them, or `[]` when cleared; a saved line PATCHes; add row one line with columns fixed at four widths).

- **Phase 3** — web 1.64.0 (no server change), built 2026-11-15, released the same day in v1.42.0 (the installable-web-app release, cut by another session). Verified: headless Chromium with the API stubbed at 1440 and 390px wide (chips under the description of a tagged item and none on an untagged one; the edit row's picker opens with the item's tags and saves `tag_ids` incl. `[]`; the table's columns don't move when a row opens; spreadsheet mode saves only rows whose tags changed and updates them locally; Enter inside the picker doesn't save; the add form sends `tag_ids`, keeps its picks if reopened and starts empty after a save). An open edit row is about 15px taller than a read row because the picker stacks under the description.

All three phases are released and closed; the plan is closed (2026-11-15).

Sessions: may span — each phase ends with a release and your look on your own instance before the next starts.

## Agents and tools

| Phase | Main session | Subagents | Why |
| --- | --- | --- | --- |
| 1. Server | Opus | Sonnet: write the API tests once the response shape is set | A schema change and a migration, plus copying tags when a line is created. |
| 2. Forecast | Sonnet | none | Wires an existing picker to a field the API now accepts; follows the line editor's pattern. |
| 3. Bills & income | Sonnet | none | Adds the same picker to a form and an edit row; tag chips under the description. |

## Open questions

- ~~**Should auto-tag rules tag recurring items themselves?**~~ Decided 2026-11-24 ([decision](../docs/dev/decisions/recurring-tags.md#2026-11-24-auto-tag-rules-tag-lines-not-bills), #339): no, as built. Today rules run when a transaction is created or edited, so lines made from a recurring item already get rule tags then. Tagging the item too would show rule tags on projected lines before they're saved. Blocks nothing: the plan assumes **no** (rules keep running on transactions only).

## The plan

**Goal:** a bill or income item can carry tags. Its projected lines on Forecast show them, and each line saved from it starts with them.

**Decided 2026-11-14 (this plan's scoping round):**
- Tags are copied when a line is created from the item. Changing the item's tags later doesn't touch lines already saved.
- Three phases: server first, then Forecast, then Bills & income, each released on its own.
- On the Bills & income table, tags show as small chips under the description; the edit row puts the picker in the Description cell. No new column.
- Each phase is checked by tests (phase 1) or a headless browser run with the API stubbed (phases 2 and 3), then your look after release.

**Out of scope:**
- Updating tags on lines already saved when the item's tags change.
- Auto-tag rules on recurring items (see Open questions).
- Backups: they carry no tags at all today; that's its own issue, #117.

### Phase 1: Server: recurring items carry tags

What changes:
- A `recurring_tags` join table (recurring id, tag id; cascade delete from either side), `SCHEMA_VERSION` 14 → 15 with its migration.
- `tag_ids` on `RecurringIn`: `POST /api/accounts/{id}/recurring` and `PATCH /api/recurring/{id}` set them (owner's tags only, as for transactions); `null` leaves them alone on PATCH, `[]` clears them.
- `tags` (`[{id, name, color}]`) on recurring items in `GET /api/accounts/{id}/recurring` and `GET /api/recurring`, and on projected rows in the forecast (today always `[]`).
- `POST /api/accounts/{id}/transactions` with a `recurring_id` and no `tag_ids` starts the line with the item's tags (auto-tag rules still add on top). Explicit `tag_ids` win.
- Deleting a tag removes it from recurring items too.

What you do: nothing until the release; then add a tag to an item through the API or wait for phase 3's picker.

Done when:
- API tests cover: create and patch with tags (happy path and someone else's tag refused), tags in both list responses and in forecast projections, a line created from a projection inheriting the tags, explicit `tag_ids` overriding, and a deleted tag disappearing from items.
- The full test suite passes; the migration runs on a copy of a v14 database.

### Phase 2: Forecast: tags on repeating lines

What changes:
- The add row's Tags picker stays usable when Repeats is set; its tags are sent as the recurring item's `tag_ids`.
- Projected lines show the item's tag chips, like saved lines.
- Opening a projected line in the line editor shows a Tags picker filled with the item's tags; saving it creates the transaction with those tags (or what you changed them to).

What you do: after the release, add a repeating line with tags and check its projected lines show them.

Done when:
- In a headless browser with the API stubbed: the picker stays enabled for every Repeats choice and its ids reach `POST …/recurring`; a projected row with tags shows chips; saving a projected line sends its tags.
- Columns don't move and the add row stays one line at 1600, 1440, 1280 and 1100px.

### Phase 3: Bills & income: tag pickers

What changes:
- The add form gets a Tags picker; its tags are saved with the item.
- Each edit row puts a Tags picker in the Description cell, filled with the item's tags; saving sends `tag_ids`. Spreadsheet mode saves them the same way.
- The read view shows small tag chips under the description.

What you do: after the release, tag an item from Bills & income and check it on Forecast.

Done when:
- In a headless browser with the API stubbed: the add form and an edit row send the chosen `tag_ids`; a row with tags shows chips under its description; the table's columns don't move when a row opens.
- Phone layout shows the picker in the stacked form.
