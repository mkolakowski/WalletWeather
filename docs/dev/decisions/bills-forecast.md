# Bills & income, closer to Forecast

Decisions made while planning and building [`Plans/bills-forecast.md`](../../../Plans/bills-forecast.md) (tracking issue #131).

## 2026-11-15: the scoping round

**Decided:** 2026-11-15, by Matthew. **Status:** accepted.

**The question:** "more closely align the Bills & income table to the Forecast table" could mean several things.

**The decision:** all four parts: Forecast's column layout (Description | Start date | Ends | Category | Amount | Account | Repeats | Monthly | Yearly | Tags | Notes), compact one-line rows, an inline add line instead of the add panel, and + Add in the table's controls row. The add line and edit rows take a signed amount (negative = expense) and drop the Type dropdown. Phases ship columns first, then the add line, then the controls row.

## 2026-11-15: tags move into a column

**Decided:** 2026-11-15, by Matthew (the chosen column layout includes a Tags column). **Status:** accepted, built in phase 1 (v1.45.0).

**The question:** #120 showed an item's tags as chips under its description, with no new column. The chosen layout has a Tags column.

**The decision:** tags show in the Tags column (chips that clip at its edge; the picker in an open row), no longer under the description. **What it changes:** rows stay one line when there's room.

## 2026-11-15: Day of month in edit rows

**Decided:** 2026-11-15, by Matthew. **Status:** accepted, for phase 2 (#129).

**The question:** #110 took Day of month out of the add form (the day comes from the start date) but kept it in edit rows, because some saved monthly items have a day and no start date.

**Options considered:**
- Keep Day of month in edit rows: saved items untouched.
- Take the day from the start date in edit rows too.
- Keep Day of month only for items with no start date.

**The decision:** take it from the start date. Edit rows drop the Day of month box. A monthly item with no start date opens with one filled in on its next day-of-month date (today or later); saving writes that start date and its day.

**What it changes:** saving such an item sets a start date, which hides any projected dates before it (none of them are earlier than today). Items you don't edit are untouched.
