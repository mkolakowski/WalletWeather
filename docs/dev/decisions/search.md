# Search across everything: the choices behind it

Decisions for one search across the app: the server's `GET /api/search` and the web app's search box (#111), which the iOS app's search (ios-app phase 10, #112) builds on. What search should find was answered while settling the iOS mockups (#93): everything, in the web app too.

## 2026-11-15: the box on a phone, what a result shows, and tags

**Decided:** 2026-11-15, by Matthew, while starting #111. **Status:** accepted.

- **On a narrow screen the web app shows a magnifier in the top bar** that opens a full-width search box with the results under it; on wider screens the box sits in the bar itself. The other options were a box in the bar at every width (squeezing the bar's other items on a phone) and a full-width search row under the bar on every page.
- **Each result shows its name and one detail:** a transaction its description, date, amount and account; a bill or income its name, amount and next date; an account its name and balance; a category or tag its name and how many transactions carry it; a report its name. The other options were names only, and the name with the matching part of the note highlighted.
- **Tags are searched too, as their own group**, opening as their transactions like a category. Leaving tags out, to the five kinds first listed in #111, was the other option.

**Also settled in building it:** the box sits in the bar whenever there's room for it (at least 200 px) beside the title and the page buttons, whose width depends on the email shown and the Admin button; otherwise it's the magnifier, as on a phone. An empty search finds nothing. Up to 20 results show per group, with the group's full count; "Show all" opens the rest of the transactions in Forecast's Search transactions. Bills that have ended come after running ones. Categories, tags and reports are only ever the caller's own, so someone an account is shared with sees its transactions and bills but not the owner's categories or reports.

**What it changes:** #111 (server and web app) and ios-app phase 10 (#112).
