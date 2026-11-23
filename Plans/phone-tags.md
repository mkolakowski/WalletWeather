# Phone tags: tags on the iPhone

Tracking issue: #247

## Status

| Phase | Apps | Issue | State |
| --- | --- | --- | --- |
| 1. Tags in the household | iOS | #250 | Built in iOS 0.26.0, 2026-11-20; shipped alongside v1.85.0 (iOS 0.28.0), closed 2026-11-21 at your say; on TestFlight in build 400 (iOS 0.33.0) |
| 2. Tag screens | iOS | #251 | Built in iOS 0.27.0, 2026-11-20; shipped alongside v1.85.0 (iOS 0.28.0), closed 2026-11-21 at your say; your try left on TestFlight build 400 |
| 3. Auto-tag rules on the phone | iOS | #252 | Built in iOS 0.28.0, 2026-11-20; shipped alongside v1.85.0, closed 2026-11-21 at your say; your try left on TestFlight build 400 |

Phase 3 built 2026-11-20 in iOS 0.28.0, not released. `LocalServer` answers `/api/tag-rules` (list newest first, make, change, delete, and `/backfill`) with the server's checks, and applies the active rules as the server's `_apply_tag_rules` does (description contains the pattern without case, the category gate, a tag already there skipped) when a line is added, changed or imported. Settings → Tags lists the rules below the tags, with a rule editor and **Apply to existing lines**, with or without a server. Verified: `LocalTagTests` (rules on add, change, import and replay; switched-off and category-gated rules; the server's checks), the package's tests, and the page on the simulator.

Phase 2 built 2026-11-20 in iOS 0.27.0, not released. Tag chips on rows (Forecast's list and table, Bills & income, a tag's lines in Search), a tag picker with **New tag…** in the line editor, Add transaction and the bill editor, and Settings → **Tags** (add, rename, recolour, delete), with or without a server. Tags are sent with a line or bill only when changed, so a bill's date marked paid still takes the bill's tags (a test caught the first version sending an empty list). Set in building: the search box's own transaction results carry no tags (the server's answer, from the core), so chips show in a tag's list of lines rather than there. Verified: `LocalTagTests` through the app's own calls, 172 package tests, the screens on the simulator (Bills & income's chip, Search finding a tag with its line).

Phase 1 built 2026-11-20 in iOS 0.26.0 (no server code change), not released. The household holds tags, their links to lines and bills (one table), and tag rules; `LocalServer` answers `/api/tags` (list in name order, make, rename, recolour, delete with its links and rules) with the server's checks, `tag_ids` on lines and bills (a line saved from a bill starts with its tags), tags on every row, tag search and the search box's tags. Backups and moves carry tags and rules both ways, sync joins tags made apart by name, Delete everywhere empties them. Verified: `LocalTagTests` (3), `BackupTests` with the fixtures rewritten on both sides (the round trip compares each row's tags by name, and the server's `test_backup_moves.py` checks the tags and rule arrive), `SyncTests` (tags made apart), 172 package tests, the server's move and tag-backup tests.

Planned 2026-11-20 (about 2:00 AM ET), from #247 (split from #246).

Sessions: may span — three iOS versions, each with your try on TestFlight.

## Agents and tools

| Phase | Main session | Subagents | Why |
| --- | --- | --- | --- |
| 1. Tags in the household | Opus | none | The store, the routes, the backup format both ways and sync. |
| 2. Tag screens | Opus | none | Screens across many files. |
| 3. Auto-tag rules | Opus | none | Rules that match the server's exactly. |

## Open questions

None. Settled 2026-11-20 ([decision](../docs/dev/decisions/standalone.md)): tags are managed on a Tags page in Settings and inline from a picker; chips show on rows and Search filters by tag; a phone signed in to a server gets the same screens; auto-tag rules come to the phone too.

## The plan

Today the iPhone app has no tag screens, even with a server, and a household on the phone has no tags: its backups carry empty `tags`, and a server's tags and rules are dropped on the way in.

### Phase 1: Tags in the household

The household's store gains tags (name, colour), links from lines and bills to tags, and tag rules (kept for phase 3). `LocalServer` answers the server's routes with its checks: `GET/POST /api/tags`, `PATCH/DELETE /api/tags/{id}`, `tag_ids` on lines and bills, `tags` in every row and in search, and a line made from a bill starting with the bill's tags. Backups and moves keep tags and rules both ways. Sync joins tags made apart by name, as it does categories. Checked by `LocalTests`, `BackupTests` with the server's `test_backup_moves.py`, and `SyncTests`.

### Phase 2: Tag screens

With or without a server: a tag picker on a line and on a bill, with **New tag…**; a **Tags** page in Settings (add, rename, colour, delete); chips in the tag's colour under lines in Forecast and Search and on bills in Bills & income; Search finds tags and tapping one lists its lines. Checked on the simulator and by you on TestFlight.

### Phase 3: Auto-tag rules on the phone

A **Rules** list under Settings → Tags, as the web app's: "description contains … (in category …) → tag". On the phone they're applied as the server applies them (a line added, changed or imported); with a server the list edits the server's rules. Checked against the server's own behaviour, and by you on TestFlight.
