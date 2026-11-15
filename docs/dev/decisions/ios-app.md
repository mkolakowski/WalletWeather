# iOS app: sign-in, Cloudflare, what the phone keeps, and the look

Decisions made while planning [`Plans/ios-app.md`](../../../Plans/ios-app.md) (tracking issue #93). The mockups they refer to are at <https://claude.ai/artifact/4P7y4vUZww5xJGAq1TPKcc> (a private page).

## 2026-11-14: how the app signs in

**Decided:** 2026-11-14, by Matthew. **Status:** accepted.

**The question:** the app holds an API token (phone-path phase 2, #42) and never the password. How does the token get onto the phone?

**Options considered:**
- An "Open in WalletWeather" link beside a new token in the web app's Settings, with paste as the fallback: the smallest build, and it covers Google accounts.
- A QR code in Settings that the app scans: handy from a computer screen, but something has to draw the code (a new dependency to licence-check, or code written for the page).
- Email and password typed into the app: waits on phone-path phase 3 and login rate limiting, and can't cover Google-only accounts.
- A web sign-in sheet inside the app that handles local, Google and Cloudflare sign-in at once: the smoothest, and the most server work.

**The decision:** all four, with the web sign-in sheet as the first choice on the Connect screen. The sheet, the link and paste are built in phase 1 (#87); the QR code and email and password in phase 7.

**What it changes:** phase 1 grows (a "sign in an app" page and a code-for-token exchange on the server, on top of #42), and the plan gains phase 7. One thing isn't proven yet and is tried first in phase 1: Google refuses to sign in inside an app's own web view, so the sheet has to be the system's sign-in sheet, and that sheet doesn't share its Cloudflare session with the app's own requests.

## 2026-11-14: getting past Cloudflare Access

**Decided:** 2026-11-14, by Matthew. **Status:** accepted.

**The question:** the server sits behind a Cloudflare Tunnel with Zero Trust rules, which turn a request away before WalletWeather sees its token. How does the app get through? (For native apps, this is open question 1 of `Plans/phone-path.md`.)

**Options considered:**
- A Cloudflare service token entered on the Connect screen and sent with every request: Cloudflare still guards everything, and the token is made once in the Zero Trust dashboard.
- An Access rule that lets `/api/*` through: nothing to build, but the API is then reachable from the internet with the WalletWeather token as the only check.
- The app signs in to Cloudflare itself and reuses that session: no service token to manage, but signing in again whenever the Cloudflare session ends, and more to build.

**The decision:** the app signs in to Cloudflare itself by default, and takes a service token as the alternative (under "Advanced" on the Connect screen). The Access rule for `/api/*` isn't used for the app.

**What it changes:** phase 1 (#87). If the Cloudflare session can't be carried from the sign-in sheet to the app's own requests, the service token is the way through until it can, and Matthew is told before the rest of the phase is built. How scripts get past Cloudflare is still open in `Plans/phone-path.md`.

## 2026-11-14: what the phone keeps

**Decided:** 2026-11-14, by Matthew. **Status:** accepted.

**The question:** phone-path decided the installed web app stores no balances or transactions. Does the native app keep anything?

**Options considered:**
- Nothing but the server's address and the token: matches the web app and the privacy policy as written, and rules out widgets and reminders.
- The last pages loaded, so the app opens offline to last-known numbers marked with their age.
- Offline editing that syncs later: large, because the server has no sync.

**The decision:** each person chooses, asked once at set-up, with **Nothing** as the default and **Last-known numbers** as the other level. The choice can be changed in the app's settings. Offline editing isn't in this plan: it's roadmap item 27.

**What it changes:** the plan gains phase 8, and `docs/privacy.md` is updated before that phase ships. Until then the app keeps nothing, as phase 1 builds it.

## 2026-11-14: plain http, the oldest iOS, the look, and the bar on the open Duo

**Decided:** 2026-11-14, by Matthew. **Status:** accepted.

- **Plain `http://` is accepted for home-network addresses only**, with a warning on the Connect screen. The other option was https everywhere, which would shut out a server that's only on the home network without a certificate.
- **iOS 26 and later.** The Duo layouts switch on under iOS 27.1. The other option was iOS 27.1 only: less code, newest phones only.
- **The system's light and dark, with WalletWeather's own colours, and the web app's ten themes later.** Carrying the themes over from the start meant ten palettes to check on every screen while the screens are still changing. The themes are phase 9.
- **On the open Duo the pages are on the system's bar down the right edge.** The other options were a sidebar on the left listing every page (about a quarter of the width, and it pushes the first pane across the fold) and a setting to switch between the two (both layouts to build and test on every page).

**What it changes:** phase 1 (#87) for all four, and the plan gains phase 9 for the themes.

## 2026-11-14: the second pane, editing, the app lock, and backups

**Decided:** 2026-11-14, by Matthew. **Status:** accepted.

- **On the open Duo, the right half shows the page's chart and totals until something is tapped, then what was tapped takes that place.** The other options were the right half holding only what's tapped, with a prompt when nothing is (an empty half most of the time), and charts always on the right with editing in a sheet (the sheet would cover the fold).
- **Day-to-day edits are in the app, and set-up stays on the web.** In the app: mark a line as paid with its real amount and date, add, change or delete a transaction, add, change or skip a bill, move money between accounts. On the web: accounts, categories, tags and rules, budgets, sharing, CSV import, building reports, backups, the Admin pages, deleting your account. The other options were a read-only app first (it couldn't confirm a payment) and bringing set-up into the app in a later phase.
- **The app lock is offered once at first sign-in** ("Lock WalletWeather with Touch ID?") and can be changed in the app's settings. The other options were off unless switched on, and on from the start. The numbers are hidden in the app switcher either way.
- **Kept numbers are left out of iCloud and computer backups.** A restored or new phone starts empty and loads them again. Including them would have put copies of the numbers in iCloud or on a computer.

**What it changes:** phases 2 and 3 (#88, #89) for the second pane and editing, phase 5 (#91) for the app lock, and phase 8 (#101) for backups.

## 2026-11-14: Apple's reviewer, and iPad and Mac

**Decided:** 2026-11-14, by Matthew. **Status:** accepted.

- **Apple's reviewer gets in through sample data built into the app**, behind "Try the demo" on the Connect screen. No server is needed, and anyone can try the app before setting one up. The other options were a demo server put on the internet for each review (a public instance each time, which the README warns against) and staying on TestFlight with no public listing.
- **iPhone only for now.** The open-Duo layouts follow the screen's width and would mostly carry over to an iPad, and iPad was picked first, then changed to iPhone only in the same conversation. iPad and Mac can be a later plan.

**What it changes:** phase 6 (#92). With these, none of the plan's thirteen questions is open.

## 2026-11-14: AMOLED black and Sepia

**Decided:** 2026-11-14, by Matthew. **Status:** accepted.

**The question:** Matthew asked for an AMOLED black look and a sepia look in the mockups. Neither is among the web app's ten themes, and the decision so far was the system's light and dark, with the themes in phase 9. Where do the two new looks go?

**Options considered:**
- From the first version: every screen built in phases 1 to 3 would be checked in four palettes while it's still changing.
- With the app's settings, in phase 5: that phase builds the Appearance choice, and the pages are stable by then.
- With the ten themes, in phase 9: light and dark only until then.
- Mockups only, decided later.

**The decision:** phase 5's Appearance choice offers Match the phone, Light, Dark, AMOLED black and Sepia. In the mockups the light and sepia cards carry an outline and a soft shadow on a darker page background, after the first drawing left them hard to tell from the background.

**What it changes:** phase 5 (#91). Phases 1 to 3 still build light and dark only. The web app doesn't gain the two looks.

## 2026-11-14: search, and where its button goes

**Decided:** 2026-11-14, by Matthew. **Status:** accepted.

**The question:** Matthew asked for a search button in the app. What does search find, and where does the button sit? Today the server searches transactions only, and the web app has that as a panel under Forecast.

**Options considered:**
- Transactions only: exactly what the web app does today; bills and lines that haven't happened aren't found.
- Transactions and bills: the server's existing search plus bills and paychecks matched by name in the app. No server change.
- Everything, in the web app too: one search across transactions, bills, accounts, categories and reports. It needs a new search endpoint, and the web app gains a search box to match.
- The button beside the pages bar with + moved to the top corner of each page; two round buttons beside the bar; or a magnifier at the top of each page.

**The decision:** everything, in the web app too. The app's search button is the round one beside the pages bar, the spot iOS gives search, and + moves to the top corner of each page.

**What it changes:** a new piece of server and web work (#111, roadmap item 28); phase 2 (#88) puts the button in place with transaction search; a new phase 10 widens it to everything once #111 has shipped.

## 2026-11-15: Liquid Glass

**Decided:** 2026-11-15, by Matthew. **Status:** accepted.

**The question:** the plan got Liquid Glass only by using the system's bars and sheets. It never stated glass, said which of the app's own surfaces use it, or checked it against the phone's Liquid Glass setting (a slider from clear to tinted in iOS 27, overridden by Reduce Transparency).

**Options considered:**
- System glass with solid cards: the bar, sheets and round buttons are glass and the cards stay solid, so the numbers are always on a plain surface.
- Glass on the cards too: more striking, but the numbers sit over whatever is behind the card, and every look has to be checked at each glass setting.
- System glass with solid cards, plus a switch in the app to turn its glass off.
- Leaving the plan as it was.

**The decision:** glass on the cards too. The bar, the sheets, the round buttons and the app's own cards and panels are all Liquid Glass, following the phone's setting, and they turn solid under Reduce Transparency or Increase Contrast.

**What it changes:** phase 1 (#87) builds it and checks it with the setting at each end and with both accessibility switches on; phase 5 (#91) checks each look the same way. Behind the cards, each page carries a soft tint of the look's accent colour fading down from the top, so the glass has something to show. That was chosen the same day over the plain page colour, which would have left the glass reading as a slightly lighter panel.

## 2026-11-15: how the Cloudflare sign-in reaches the app

**Built:** 2026-11-15, in phase 1 (#87). **Status:** built; to be confirmed on Matthew's phone through his real Cloudflare Access.

**The question:** the sign-in sheet (`ASWebAuthenticationSession`) shares Safari's sign-ins, so Cloudflare Access and Google work in it, but the app can't read its cookies. How do the app's own requests get past Cloudflare after signing in there? (The part of the 2026-11-14 decisions that was tried first.)

**Options considered:**
- **The server hands it back.** Cloudflare puts the signed-in person's Access token on every request it lets through (`Cf-Access-Jwt-Assertion`). The "sign in an app" page's answer to the app (`walletweather://signed-in?code=…&cf=…`) carries that token, and the app sends it as `cf-access-token`, the header `cloudflared` uses. One sheet signs in to Cloudflare and WalletWeather at once, with nothing undocumented.
- **Cloudflare's token transfer**, as `cloudflared access login` does it: the sheet opens the site's `/cdn-cgi/access/cli` page, which leaves the token, sealed to a key the app made, at Cloudflare's transfer service for the app to collect. Matthew's mkplus app does this (`CloudflareSafariSignIn.swift`) and it worked on his iPhone, but the hand-off isn't documented by Cloudflare, needs a NaCl box implementation, and means a second sheet before the WalletWeather one.
- **A service token only:** no sign-in to carry, but one to make and paste per phone.

**What was built:** the server hands it back, with the service token under Advanced as the alternative. `GET /app-sign-in/cloudflare` hands back only the Cloudflare token, for when it runs out (24 hours unless the Access application says otherwise). Telling Access's sign-in page from the server's own answer, and the `cf-access-token` header, follow mkplus's `CloudflareAccess` gateway. If the token handed back turns out not to be accepted, the transfer is the fallback, copied from mkplus. Cloudflare's "binding cookie" option, if switched on for the application, would refuse the handed-back token; it's off unless chosen.

## 2026-11-15: marking paid, adding a transaction, and search results

**Decided:** 2026-11-15, by Matthew, while starting phase 2 (#88). **Status:** accepted.

**The questions:** the plan said what Forecast edits (mark paid with the real amount and date, undo, notes and category, add, delete) but not how they're done on a phone.

- **Marking paid from the list:** swipe a line right to mark it paid as planned, and right again to undo; the editor is for a different amount or day. The other option was the editor only (one way to do it, one more tap per bill). A swiped line is dated its planned day, or today when that's still to come, so an early payment gets today and an old bill marked late keeps the day it was due.
- **Income or spending when adding:** a Spending / Income switch over a plain amount, starting on Spending. The other option was a signed amount, as the web app's add row has, which means typing a minus on the number pad.
- **A new transaction starts paid, dated today,** for recording something just spent; turning Paid off plans one ahead. The other option was planned, not yet paid.
- **Tapping a search result opens its editor right there** (a sheet closed, the right half open). The other option was jumping to the line in Forecast, on its account and month.

**What it changes:** phase 2 (#88). Found on the way: a line on an account shared for editing carries the owner's category, which the server refused when the line was saved with it, so server 1.52.0 lets a save keep the category a line already has.

## 2026-11-15: the Calendar's accounts, moving money, skipping and ending

**Decided:** 2026-11-15, by Matthew, while starting phase 3 (#89). **Status:** accepted.

- **The Calendar shows all accounts, or one you pick,** as the web app's does; picking one adds each day's closing balance (the server has a balance only for one account). The other option was one account at a time, like Forecast.
- **+ becomes a menu** on Forecast, Bills & income and Calendar: the page's own Add (a transaction, or a bill or income) and Move money. The other option was a separate button beside +.
- **Skip once picks from the next six dates,** the next one first. The other option was the next date only. The server sends the dates (`next_dates` on `/api/recurring`, from 1.53.0), so the app still does no forecasting of its own.
- **End asks for the last date,** today by default; the item stops after it and moves to Ended. The other option was ending today in one tap.

**What it changes:** phase 3 (#89). `/api/subscriptions`, listed in the phase for a shape test, isn't called by the app: the web app's Bills & income page reads `/api/recurring` too, so it was left out.

## 2026-11-15: when the app lock asks again

**Decided:** 2026-11-15, by Matthew, while starting phase 5 (#91). **Status:** accepted.

**The decision:** with the lock on, the app asks when it starts and when it comes back after **a minute or more** away. Quick trips to another app (the bank, a message) don't ask. The other options were every time it comes back, after five minutes, and only when it starts. The numbers are hidden in the app switcher whatever the setting.

**Also settled in building it:** AMOLED black and Sepia use the mockups' colours (AMOLED: a black page, outlined cards, the dark theme's accent; Sepia: a tan page, cream cards with an outline and a soft shadow, brown text, a rust accent). The look and the lock setting are kept in the app's preferences, and `docs/privacy.md` now says so.

**What it changes:** phase 5 (#91).

## 2026-11-15: kept numbers after signing out, and when they show

**Decided:** 2026-11-15, by Matthew, while starting phase 8 (#101). **Status:** accepted.

- **Signing out sets the choice back to Nothing**, and the next sign-in asks again. Someone else signing in on the same phone keeps nothing until they choose to. The other option was a choice that stays across sign-outs, asked once per install like the lock.
- **Kept numbers show only when the server can't be reached** (no connection, nothing answering, or too slow to answer), under a bar saying when they were loaded. Online, pages load from the server as before. The other option was opening every page on its kept copy at once and swapping in fresh numbers: faster, but it shows old numbers briefly even when online.

**Also settled in building it:** what's kept is the server's answer to each page's read requests (Dashboard, its charts and pinned reports, Forecast, Bills & income, Calendar, Net worth, Budgets, Reports, and the accounts and categories lists), keyed by the request without the phone's date, so yesterday's copy still answers today. Search, sign-in and edits are never kept. Each answer is a file in the app's own Application Support folder, written with complete file protection and left out of backups; at most 300 are kept, oldest out first. A new sign-in starts empty. Someone already signed in when this arrived stays on Nothing and isn't asked.

**What it changes:** phase 8 (#101).
