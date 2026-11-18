# Matching bank lines by hand

Decisions made while planning and building [`Plans/match-by-hand.md`](../../../Plans/match-by-hand.md) (tracking issue #225).

## 2026-11-17: the scoping round

**Decided:** 2026-11-17, by Matthew. **Status:** accepted, built in 1.77.0 to 1.79.0.

**The question:** the Unmatched panel felt far apart and showed things twice: the bank line and the planned bill as two Forecast rows, the date and amount in two tables with different headings, and one bill listed at every date in the 60 days. Matching should also be possible from Forecast, and teach the bill.

**The decision:** one pop-in with the bank line on top and a card per planned line in words, one card per bill (#222); matching from Forecast both ways, Match… on an unmatched bank row and "Paid by a bank line…" on a planned row (#223); a ticked "Match lines like this … from now on" that teaches the bill the line's name and catches up lines already unmatched (#224). Three phases, each its own version.

## 2026-11-17: a taught name pays at any amount

**Decided:** 2026-11-17, by Matthew. **Status:** accepted, built in 1.79.0 before release. Replaces the scoping round's "text + days + amount %".

**The question:** with the first rule, a taught line still had to be within the bill's amount %. Matching by amount and days already did that, so the taught name only broke ties between two bills, and a bill that varies (power, phone) still waited on the Unmatched list.

**The decision:** a line with the name a bill learned pays it at any amount going the bill's way (money out for a bill, in for income), within the bill's ± days, and wins over bills that fit by amount. A refund under the same name doesn't pay a bill. Catching up lines already on the Unmatched list follows the same rule.

**What it changes:** `_bill_for_bank_line` skips the % check for a taught bill; tests in `apps/server/tests/test_bank_match_learn.py`.

## 2026-11-18: "lines like this" ignores codes

**Decided:** 2026-11-18, by Matthew. **Status:** accepted, to build in #230. Replaces the plan's assumption (the short name, exactly, ignoring case and spaces), which 1.79.0 shipped.

**The question:** when is a new bank line "like" the one a bill learned? Card purchases often carry a changing code, e.g. "AMAZON MKTPL*2K4AB1" one month and "AMAZON MKTPL*9XZ3" the next, which an exact name never matches.

**The decision:** names are compared with digits and codes after `*` or `#` stripped: lowercase, split on spaces, `*` and `#`, drop each piece with a digit in it. A name with nothing left is compared as itself. The bill still stores and shows the name it learned.

**Other options:** the short name exactly (safe, misses changing codes); "starts with the learned name" (wider, catches codes only at the end).

## 2026-11-18: the lists show the bill's days first

**Decided:** 2026-11-18, by Matthew. **Status:** accepted, to build in #231. Replaces the plan's assumption (everything within 60 days), which 1.79.0 shipped.

**The question:** how far should Match… (planned lines) and "Paid by a bank line…" (bank lines) look either side?

**The decision:** both show what's within the bill's own bank-match ± days first (5 days for a planned line that isn't a bill's), with a "Show N more, up to 60 days away" link for the rest. When nothing is within the days, everything shows, with a line saying so.

**Other options:** keep 60 days (long lists on a busy account); 30 days (shorter, but a payment over a month off needs the Unmatched list).
