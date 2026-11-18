"""FastAPI application: local + Google auth, accounts, transactions, forecasting."""
import base64
import hashlib
import math
import os
import re
import secrets
from datetime import date, datetime, timedelta
from decimal import Decimal
from pathlib import Path
from urllib.parse import urlencode, urlsplit

# =============================================================================
# APP VERSION (web / backend application version)
# =============================================================================
# Semver-style version string for the WalletWeather web app as a whole
# (backend + bundled frontend SPA). Shipped to the frontend via
# /api/auth/config so the UI can display it in the footer / About dialog.
#
# *** AI ASSISTANT INSTRUCTIONS — READ BEFORE EDITING ***
# If you make a user-visible change to the app — a new feature, a bug fix,
# a behavioral change, a UI overhaul, a security fix — YOU MUST:
#   1. Bump APP_VERSION below (PATCH for fixes, MINOR for features,
#      MAJOR for breaking changes).
#   2. Add an entry to the APP CHANGELOG block below (see format there).
#   3. If your change also changes the database shape, also bump
#      SCHEMA_VERSION in apps/server/app/db.py per the instructions there.
#   4. If your change touches the SPA (apps/web/index.html), also
#      bump the WEB_VERSION constant in that file per the instructions
#      at the top of it.
# -----------------------------------------------------------------------------
APP_VERSION = "1.79.0"

# --- APP CHANGELOG ------------------------------------------------------------
# Format for every new line (keep newest at TOP):
#   # <version> (YYYY-MM-DD, <your name or handle>): <one-line summary>
# Example:
#   # 1.4.1 (2026-05-03, mkolakowski): fix forecast overflow on leap years
#
# When you bump APP_VERSION, add the matching line here. Do not rewrite
# history — only append new entries. If multiple changes ship in one
# version, use a short multi-line entry under a single version header.
#
# 1.75.0 (2026-11-17, claude+mkolakowski): email alerts matched to bills
#     (bank-alert-emails phase 4, #209). An alert that lands pays a planned
#     bill or income line the way a bank line does (_bill_for_bank_line, the
#     bill's own match_days and match_percent; the paid line has bank_match
#     'auto' and mail_ref, so match_source is 'alert' on forecast rows).
#     The Unmatched list, match by hand, leave and un-match endpoints
#     (/api/accounts/{id}/bank-unmatched..., /api/transactions/{id}/bank-unmatch)
#     now cover alert lines too (lines have source 'bank' or 'alert');
#     GET /api/mail gains unmatched [{account_id, count}]; check results and
#     the check log gain matched. Schema 30.
# 1.74.0 (2026-11-17, claude+mkolakowski): email alerts checked by
#     themselves (bank-alert-emails phase 2, #207). _mail_scheduler_loop runs
#     run_due_mail_checks every minute; each mailbox is due check_minutes (5,
#     15 or 60, PUT /api/mail/settings, starts at 5) after its last check, a
#     failed one is tried again at the same interval, never while
#     needs_reconnect; a per-user lock keeps it apart from Check now.
#     GET /api/mail/status (any token), POST /api/mail/check now takes write
#     tokens; GET /api/mail/checks[/{run_id}] is the mailbox's log (session
#     only; checks that brought something in or failed; pruned with the audit
#     log). Schema 29.
# 1.72.0 (2026-11-16, claude+mkolakowski): email alerts, first part
#     (bank-alert-emails phase 1, #206). GET /api/mail; POST
#     /api/mail/microsoft/device {code?, utc_offset_minutes} and .../poll
#     (sign in with a code); POST /api/mail/microsoft/web and GET .../callback
#     (the Connect button, PKCE + MS_CLIENT_SECRET); GET /api/mail/folders,
#     PUT /api/mail/settings {folder_id, start_date, utc_offset_minutes};
#     GET /api/mail/messages, POST /api/mail/preview {message_id|unread_id};
#     POST /api/mail/senders (teach), PUT/DELETE /api/mail/senders/{id},
#     DELETE .../kinds/{kind_id}; POST /api/mail/check; GET/DELETE
#     /api/mail/unread[/{id}]; POST /api/mail/disconnect {code?}; GET/PUT
#     /api/admin/mail-alerts; /api/admin/users gains mail_connected. All
#     browser-session only. Calls out live in mailbox.py (Microsoft only),
#     reading in alerts.py. Encrypted backups carry the mailbox and each
#     line's mail_ref. Schema 27.
# 1.70.0 (2026-11-16, claude+mkolakowski): the daily bank sync and its log
#     (bank-sync phase 3, #195). _bank_scheduler_loop runs run_due_bank_syncs
#     every 30 minutes (due 23h30 after the last try, 6h after a failure, never
#     while needs_reconnect); a per-user lock keeps it apart from Sync now.
#     GET /api/bank/status (any token), POST /api/bank/sync now takes write
#     tokens, GET /api/accounts/{id}/bank-syncs[/{run_id}] (owner only).
#     Runs are pruned with the audit log. Schema 26.
# 1.69.0 (2026-11-16, claude+mkolakowski): bank sync with SimpleFIN
#     (bank-sync phase 2, #194). GET /api/bank, POST /api/bank/connect
#     {token, code?}, PUT /api/bank/links {links: [{ref, account_id,
#     start_date}]}, POST /api/bank/sync, POST /api/bank/disconnect {code?},
#     all browser-session only; GET/PUT /api/admin/bank-sync {enabled};
#     /api/admin/users gains bank_connected. Calls out live in simplefin.py;
#     SIMPLEFIN_HOSTS limits where a token may point. Encrypted backups carry
#     the connection and each line's bank_ref. Schema 25.
# 1.68.1 (2026-11-16, claude+mkolakowski): docker-compose.yml passes
#     BACKUP_PASSPHRASE to the app (#200); 1.68.0 left it out, so a value in
#     .env never arrived. test_settings_wiring.py now checks every setting.
# 1.68.0 (2026-11-16, claude+mkolakowski): encrypted backups (bank-sync
#     phase 1, #193). POST /api/backup/export {passphrase, account_ids?}
#     returns the backup sealed with AES-256-GCM under a scrypt key
#     (backup.seal); POST /api/backup/preview opens one to list its accounts;
#     POST /api/backup/import takes `passphrase` and answers `encrypted`.
#     GET /api/backup/export stays as "Download my data" (event
#     data_downloaded). System backups are sealed with BACKUP_PASSPHRASE and
#     don't run without it; /api/admin/backup-config says passphrase_set and
#     /api/admin/backups marks each file encrypted. Plain files still import.
# 1.67.1 (2026-11-16, claude+mkolakowski): two fixes. Saving a line with a
#     tag that one of the user's own tag rules also adds was a 500 (#182):
#     the rules now see the tags just set. Importing a backup dropped every
#     note (#191): notes on recurring items and transactions are restored.
# 1.67.0 (2026-11-16, claude+mkolakowski): sharing and sign-in limits
#     (security-fixes phase 6, #189). Sharing is by invitation: POST
#     /api/invitations {account_id, email, level}, GET /api/invitations
#     {received, sent}, POST /api/invitations/{id}/accept, DELETE
#     /api/invitations/{id} (schema v24, account_invitations). GET
#     /api/permissions lists only the accounts the caller owns and the
#     people on them; POST /api/permissions changes or removes someone who
#     already has access, owners only, and lets anyone remove themselves.
#     Google sign-in linking to a user with a password removes the password,
#     two-factor, sessions and tokens. Sign-in is also limited per email
#     across addresses and per address across emails, and registration per
#     address per hour.
# 1.66.0 (2026-11-16, claude+mkolakowski): sessions that can be ended
#     (security-fixes phase 3, #186). users.session_epoch (schema v23) is
#     kept in the session cookie and checked on every request. Changing the
#     password, an admin's reset, and switching two-factor on or off raise
#     it, signing out the user's other browsers; an admin's reset also
#     revokes the user's API tokens. New POST /api/me/sessions/end-others.
# 1.65.0 (2026-11-16, claude+mkolakowski): dependencies (security-fixes
#     phase 5, #188): fastapi 0.163.1 with starlette 1.10.0, authlib 1.9.8,
#     cryptography 50.0.2; python-multipart and APScheduler, which nothing
#     called, are gone. No change to what the API does.
# 1.64.0 (2026-11-16, claude+mkolakowski): the browser's side
#     (security-fixes phase 4, #187). A POST, PUT, PATCH or DELETE that a
#     browser says comes from another site is answered 403 (Origin compared
#     with the Host, X-Forwarded-Host, APP_BASE_URL and TRUSTED_ORIGINS;
#     requests with an API token or no Origin are untouched). Every answer
#     carries X-Content-Type-Options, X-Frame-Options, Referrer-Policy and a
#     small Content-Security-Policy; /api and /auth answers are no-store.
#     /docs, /redoc and /openapi.json are gone.
# 1.63.0 (2026-11-16, claude+mkolakowski): limits on what's accepted
#     (security-fixes phase 2, #185). Names, descriptions and passwords have
#     maximum lengths (422 past them); a request body over MAX_BODY_MB
#     (default 25) is a 413; the forecast and report windows stop at ten
#     years; amounts must be finite and within a trillion; a recurring item
#     needs a known frequency with its day of the month or start date; the
#     server won't start with SESSION_SECRET empty, under 16 characters or
#     left as the template's.
# 1.62.0 (2026-11-16, claude+mkolakowski): security fixes from the review
#     (#183). A colour is a hex colour or nothing (categories, tags, backup
#     import; schema v22 blanks the rest). POST /api/auth/register takes
#     "registration_code" when REGISTRATION_CODE is set
#     (/api/auth/config: registration_code_required), and refuses the demo's
#     domain and, once the instance has a user, an ADMIN_EMAILS address:
#     new POST /api/admin/users adds a user instead. Google sign-in needs a
#     verified address. A line's recurring_id must be on its own account,
#     "mark paid" checks category_id, and the two-factor hold goes by the
#     routed path.
# 1.61.1 (2026-11-16, claude+mkolakowski): no server change; the release
#     that holds the iPhone app 0.15.0 (#177), which landed just after v1.61.0
#     was tagged (#181).
# 1.61.0 (2026-11-15, claude+mkolakowski): a code for sensitive actions
#     (#169): for a user with two-factor on, POST /api/me/password,
#     DELETE /api/me, POST /api/tokens and POST /api/app-sign-in take a
#     "code" (from the authenticator app, or a recovery code) and answer 403
#     without a right one; wrong codes count toward the per-user code limit
#     (429), as do wrong codes when switching two-factor off or remaking
#     recovery codes. Tests in tests/test_two_factor_actions.py.
# 1.60.0 (2026-11-15, claude+mkolakowski): an admin can require two-factor
#     sign-in (#168): GET/PUT /api/admin/two-factor. While it's on, a user
#     with a password who hasn't set it up is held back from every endpoint
#     but /api/me, the notice, set-up and signing an app out, by session or
#     token alike (403); /api/me says two_factor_setup_required, and
#     POST /api/auth/token refuses them. Tests in
#     tests/test_two_factor_required.py.
# 1.59.0 (2026-11-15, claude+mkolakowski): POST /api/auth/token takes an
#     optional "code" (#166): for a user with two-factor sign-in on, no code
#     or a wrong one answers 403 with "two_factor_required": true, and a
#     right code or a recovery code makes the token. Tests in
#     tests/test_two_factor.py.
# 1.58.0 (2026-11-15, claude+mkolakowski): remember this browser (#167,
#     schema 21): POST /api/auth/login/two-factor takes "remember": true and
#     sets a 30-day cookie; POST /api/auth/login skips the code for a
#     remembered browser; GET/DELETE /api/me/remembered-browsers lists and
#     forgets them. Switching two-factor off (yourself or an admin), changing
#     the password or an admin's password reset forgets them all. Two new
#     audit events. Tests in tests/test_remembered_browsers.py.
# 1.57.0 (2026-11-15, claude+mkolakowski): two-factor sign-in (#165, schema
#     20): set-up, switch-off and new recovery codes under
#     /api/me/two-factor/*; POST /api/auth/login answers
#     {"two_factor_required": true} for a user who has it on and
#     POST /api/auth/login/two-factor takes the code (or a recovery code);
#     POST /api/auth/token refuses such a user; an admin can switch a user's
#     off (PATCH /api/admin/users/{id} {"two_factor": false}); five new audit
#     events. The codes are app/twofactor.py. Tests in
#     tests/test_two_factor.py.
# 1.56.0 (2026-11-15, claude+mkolakowski): GET /api/search (#111): one search
#     across transactions, bills and income, accounts, categories, tags and
#     saved reports, grouped by kind with each group's count; only what the
#     caller may see. Tests in tests/test_search.py.
# 1.55.0 (2026-11-15, claude+mkolakowski): no server change; the release
#     that ships web 1.73.0 (Show QR code) and the iOS app 0.9.0, email and
#     password and QR sign-in (#100, #164).
# 1.54.3 (2026-11-15, claude+mkolakowski): no server change; the release
#     that ships the iOS app 0.8.1 (#155-#161, #162).
# 1.54.2 (2026-11-15, claude+mkolakowski): no server change; the release
#     that ships the iOS app 0.6.0 and 0.7.0 (#102, #90, #153).
# 1.54.1 (2026-11-15, claude+mkolakowski): no server change; the release
#     that ships the iOS app 0.5.0, Last-known numbers (#101, #151).
# 1.54.0 (2026-11-15, claude+mkolakowski): for the iOS app's More pages (#91):
#     /api/networth, /api/budgets/progress and POST
#     /api/saved-reports/{id}/run take today= (the viewer's date), so "this
#     month" is the phone's month, not the server's.
# 1.53.0 (2026-11-15, claude+mkolakowski): for the iOS app's Bills & income
#     and Calendar (#89): GET /api/recurring items gain next_dates (the next
#     six dates from today, leaving out skipped and already-paid ones) and
#     next_date (the first of them, or null); saving an item that keeps its
#     category no longer needs the category to be the saver's own.
# 1.52.0 (2026-11-15, claude+mkolakowski): for the iOS app's Forecast (#88):
#     /api/me gains token_access (read, full or admin for a token, null for
#     a browser session); forecast rows gain category_id; saving a line that
#     keeps its category no longer needs the category to be the saver's own
#     (a shared account's line kept the owner's category only by being
#     cleared before).
# 1.51.0 (2026-11-15, claude+mkolakowski): DELETE /api/tokens/current (#145):
#     a token, read-only too, may revoke itself (the iOS app's Sign out).
# 1.50.0 (2026-11-15, claude+mkolakowski): signing in the iOS app (#87):
#     the /app-sign-in page, POST /api/app-sign-in (one-time code, PKCE) and
#     POST /api/app-sign-in/token (code → 90-day token), GET
#     /app-sign-in/cloudflare (hands the Cloudflare Access token back);
#     Google sign-in can return to /app-sign-in; /api/dashboard cards gain
#     current_balance, and it and /api/dashboard/charts take today=;
#     schema 19 (app_sign_in_codes); web 1.72.0.
# 1.49.0 (2026-11-15, claude+mkolakowski): audit log viewer and pruning
#     (#134): GET /api/admin/audit (newest first, event/email filters,
#     `before` cursor); events older than AUDIT_RETENTION_DAYS (180) are
#     deleted once a day by the backup thread; web 1.71.0.
# 1.48.0 (2026-11-15, claude+mkolakowski): more audit events (#133):
#     password changes and resets, admin user/permission/title/backup
#     settings changes, backups made/downloaded/restored, personal
#     export/import, own-user deletion, tokens made/revoked; POST
#     /api/me/password; /api/me gains has_password; web 1.70.0.
# 1.47.1 (2026-11-15, claude+mkolakowski): backups carry tags, tag rules and the tags on recurring items and transactions (BACKUP_VERSION 4, #117); no web change.
# 1.47.0 (2026-11-15, claude+mkolakowski): no server change; web 1.69.0 (Bills & income's + Add in the controls row like Forecast's, #130).
# 1.46.1 (2026-11-15, claude+mkolakowski): deleting a user blanks their email
#     on their sign-in log entries (#139).
# 1.46.0 (2026-11-15, claude+mkolakowski): POST /api/auth/token (#43): email
#     + password returns a read-only or full token (90 days unless asked),
#     sharing the login rate limit and sign-in log with /api/auth/login.
# 1.45.0 (2026-11-15, claude+mkolakowski): no server change; web 1.67.0 (Bills & income on Forecast's column grid, compact rows, #128).
# 1.44.0 (2026-11-15, claude+mkolakowski): login rate limiting (#132): failed
#     password sign-ins per email + address are limited (429 + Retry-After);
#     sign-ins, failures and blocks go to audit_events (schema 18);
#     TRUST_PROXY_HEADERS, LOGIN_MAX_FAILURES, LOGIN_WINDOW_MINUTES settings.
# 1.43.0 (2026-11-15, claude+mkolakowski): token extras (#43): expiry chosen
#     at creation (30/90/365 days or never), last-used time, GET
#     /api/admin/tokens and DELETE /api/admin/tokens/{id} (browser only);
#     schema 17; web 1.66.0.
# 1.42.0 (2026-11-15, claude+mkolakowski): installable web app (#41):
#     /manifest.webmanifest (named after the app title) and /sw.js routes;
#     web 1.65.0 (icons, service worker, offline notice).
# 1.41.0 (2026-11-15, claude+mkolakowski): API tokens (#42): `Authorization:
#     Bearer <token>` works wherever the session cookie does; read/full/admin
#     access; GET/POST/DELETE /api/tokens from a browser session only;
#     schema 16 (api_tokens); web 1.63.0 (Settings → API tokens).
# 1.40.0 (2026-11-15, claude+mkolakowski): recurring items carry tags (recurring_tags, schema 15): tag_ids on create/PATCH, tags in both recurring lists and on projected forecast rows; a line created from an item starts with its tags (#118).
# 1.39.1 (2026-11-15, claude+mkolakowski): no server change; web 1.61.9 (Repeats dropdown only as wide as Bi-weekly, #116).
# 1.39.0 (2026-11-14, claude+mkolakowski): no server change; web 1.61.8 (tag picker and Repeats/Tags headings in Forecast's add row, #114).
# 1.38.0 (2026-11-14, claude+mkolakowski): no server change; web 1.61.7 (one Repeats dropdown in Forecast's add row and the Bills & income add form, #109 #110).
# 1.37.5 (2026-11-14, claude+mkolakowski): no server change; web 1.61.5 (add row headings follow Repeats and Every, #107).
# 1.37.4 (2026-11-14, claude+mkolakowski): no server change; web 1.61.4 (Actual date heading reads Ends while Repeats is on, #105).
# 1.37.3 (2026-11-14, claude+mkolakowski): no server change; web 1.61.3 (Ends in the add row's Actual date cell, #103).
# 1.37.2 (2026-11-14, claude+mkolakowski): no server change; web 1.61.2 (add row keeps its columns when Repeats changes, #98).
# 1.37.1 (2026-11-14, claude+mkolakowski): no server change; web 1.61.1 (no '/' marks in the add line, #94).
# 1.37.0 (2026-11-14, claude+mkolakowski): no server change; web 1.61.0 (Add transaction as an aligned new line; Add recurring button removed, #94 #85).
# 1.36.0 (2026-11-14, claude+mkolakowski): no server change; web 1.60.0 (Forecast account actions in the controls row, #85).
# 1.35.0 (2026-11-14, claude+mkolakowski): no server change; web 1.59.0 (tables wrap instead of scrolling sideways, #82).
# 1.34.0 (2026-11-14, claude+mkolakowski): no server change; web 1.58.0 (Bills & income like Forecast, #81).
# 1.33.0 (2026-11-14, claude+mkolakowski): no server change; web 1.57.0 (Transactions folded into Forecast's All accounts tab, #80).
# 1.32.6 (2026-11-14, claude+mkolakowski): no server change; web 1.56.6 (every page full width, #79).
# 1.32.5 (2026-11-14, claude+mkolakowski): no server change. Bumped with
#     web 1.56.5 (number arrows on the left, Notes up to Save, #69).
# 1.32.4 (2026-11-14, claude+mkolakowski): no server change. Bumped with
#     web 1.56.4 (right-aligned amounts, Notes runs up to the ✎, #69).
# 1.32.3 (2026-11-14, claude+mkolakowski): no server change. Bumped with
#     web 1.56.3 (open line same height as the others, buttons right, #69).
# 1.32.2 (2026-11-14, claude+mkolakowski): no server change. Bumped with
#     web 1.56.2 (column widths fix, wider Notes, ✎ at the row's end, #69).
# 1.32.1 (2026-11-14, claude+mkolakowski): no server change. Bumped with
#     web 1.56.1 (columns don't shift when a line opens, #69).
# 1.32.0 (2026-11-14, claude+mkolakowski): no server change. Bumped with
#     web 1.56.0 (line editor aligned to the table's columns, #69).
# 1.31.2 (2026-11-14, claude+mkolakowski): no server change. Bumped with
#     web 1.55.2 (shorter line editor, smaller tags field, #68 #69).
# 1.31.1 (2026-11-14, claude+mkolakowski): no server change. Bumped with
#     web 1.55.1 (line editor button order, #66) for its release.
# 1.31.0 (2026-11-14, claude+mkolakowski): no server change. Bumped with
#     web 1.55.0 (tag dropdown, compact line editor, #68 #69) for its release.
# 1.30.0 (2026-11-14, claude+mkolakowski): no server change. Bumped with
#     web 1.54.0 (one labelled line editor on three pages, #66) for its release.
# 1.29.1 (2026-11-14, claude+mkolakowski): no server change. Bumped with
#     web 1.53.1 (local "today" defaults, #62) for its release.
# 1.29.0 (2026-11-14, claude+mkolakowski): no server change. Bumped with
#     web 1.53.0 (wording, keyboard and labels, report checklists, local
#     backup hour, #55) for its release.
# 1.28.0 (2026-11-14, claude+mkolakowski): no server change. Bumped with
#     web 1.52.0 (phone bottom bar, Settings tabs, addresses for Import and
#     Transfer, #54) for its release.
# 1.27.0 (2026-11-14, claude+mkolakowski): no server change. Bumped with
#     web 1.51.0 (in-page messages and dialogs, #53) for its release.
# 1.26.0 (2026-11-14, claude+mkolakowski): no server change. Bumped with
#     web 1.50.0 (a Transactions page, ✎ on forecast lines, Save and add
#     another, #52) so the release has its own version.
# 1.25.0 (2026-11-14, claude+mkolakowski): GET /api/recurring lists every
#     recurring template (bills and income) across the accounts the user can
#     see, with each row's account and access level and totals for bills,
#     income and net per month and year; ?archived, ?account_id and ?today.
#     For the Bills & income page (#51). The per-account list gains signed
#     monthly/yearly fields; both share _recurring_row().
# 1.24.1 (2026-11-14, claude+mkolakowski): DELETE /api/admin/users/{uid}
#     follows the self-deletion rules: an account with another owner stays
#     (it used to be deleted with its creator), and the call is refused with
#     409, naming the accounts, while the user is the only owner of an
#     account other people can see (#57).
# 1.24.0 (2026-11-14, claude+mkolakowski): a user can delete themselves.
#     New GET /api/me/deletion-check (what would go, what stays, what's in
#     the way) and DELETE /api/me (password, or the typed email for a
#     Google-only user). Refused with 409 while the user is the only owner
#     of an account other people can see; an account with another owner
#     stays and its row moves to that owner. The demo user is refused (#48).
# 1.23.1 (2026-11-14, claude+mkolakowski): demo data (demo.py) and the
#     import sample CSV use generic merchant names ("Streaming service",
#     "Grocery store") instead of real brands. A running demo reseeds once,
#     because its fingerprint changes (#47).
# 1.23.0 (2026-11-14, claude+mkolakowski): the "Important notice" (the
#     disclaimer) is acknowledged once per user. GET /api/me adds
#     notice_required and notice_acknowledged_at; new POST
#     /api/me/acknowledge-notice records it (the first time sticks). Demo
#     users are never asked. Schema 14 (users.notice_ack_at) (#46).
# 1.22.2 (2026-11-14, claude+mkolakowski): current_balance on GET
#     /api/accounts and GET /api/accounts/{id}/forecast goes by the viewer's
#     date (new optional ?today=YYYY-MM-DD, within a day of the server's,
#     else 400) instead of the server's UTC date, which in the evening in the
#     Americas is already tomorrow and counted tomorrow's lines (#39).
# 1.22.1 (2026-10-18, claude+mkolakowski): Forecast rows' actual_balance
#     (and diff_balance) now accumulate in actual-date order instead of
#     planned-date order (forecast.build_forecast), so a line that cleared
#     later than planned shows the balance as of the day it really cleared.
#     current_balance (forecast.actual_balance_as_of) now counts the month's
#     lines by actual date too, so it still equals Actual bal at today's
#     position (a line planned before today but due to clear later no longer
#     counts yet). forecast_balance and the ending balances are unchanged.
#     Cleared transactions now land in the window of their actual date rather
#     than their planned date (matching the opening-balance rule), so a line
#     that cleared in another month than planned shows in, and counts toward,
#     the month it cleared: no longer missing from both months (late) or
#     counted twice in the next month (early).
#
# 1.22.0 (2026-10-15, claude+mkolakowski): current_balance (GET
#     /api/accounts and GET /api/accounts/{id}/forecast) is now the actual
#     balance as of today computed by forecast.actual_balance_as_of — the
#     same calculation as the forecast table's "Actual bal" column — instead
#     of a cleared-only sum. Past-dated rows not yet marked cleared now count
#     at their forecast amount, so the figure matches the table at today's row.
#     build_forecast gains with_tags=False to skip tag lookups for this.
#
# 1.21.0 (2026-10-15, claude+mkolakowski): New per-user Forecast page
#     layout preference. users.recurring_position (schema v13) is
#     'above' | 'below' (NULL = above) and is returned by GET /api/me and
#     accepted/returned by PATCH /api/me/preferences (400 on other values).
#
# 1.20.0 (2026-10-14, claude+mkolakowski): GET
#     /api/accounts/{id}/forecast now also returns current_balance (the
#     same today-dated cleared balance as GET /api/accounts, via
#     _current_balance) so the Forecast page can show it fresh on every
#     load.
#
# 1.19.0 (2026-10-08, claude+mkolakowski): Deleting recurring
#     occurrences. New POST /api/recurring/{id}/skip records a
#     RecurringSkip (schema v12) so build_forecast stops projecting that
#     date; DELETE /api/recurring/{id}/skips restores them all;
#     list_recurring rows gain skipped_count. DELETE /api/transactions/{id}
#     on a recurring-backed row now also records a skip for its
#     forecast_date so the projection doesn't immediately reappear.
#     forecast._occurrences: weekly/biweekly no longer project before
#     anchor_date (it is now the first occurrence, not just the phase).
#     Backups carry each template's skipped_dates (optional key, so
#     BACKUP_VERSION stays 3).
#
# 1.18.1 (2026-10-08, claude+mkolakowski): GET / serves index.html with
#     Cache-Control: no-cache so a new deploy's SPA is picked up on the
#     next load (revalidated via ETag) rather than a stale cached copy.
#
# 1.18.0 (2026-10-08, claude+mkolakowski): Bulk recurring edits. New
#     POST /api/recurring/bulk-update applies only the keys present in
#     the body (category_id, amount_abs, day_of_month, anchor_date,
#     end_date; explicit null clears category/end date, and the start
#     date on monthly templates only) across up to 1000 templates.
#     amount_abs keeps each template's sign; day_of_month only touches
#     monthly templates. New POST /api/recurring/bulk-delete. Both skip
#     (and count) rows that are missing or on accounts the user can't
#     edit, same as /api/transactions/bulk-tag (see WEB_VERSION 1.22.0).
#
# 1.17.0 (2026-10-08, claude+mkolakowski): Monthly recurring templates
#     now honor anchor_date as an optional start date — forecast.
#     _occurrences() emits no monthly_day occurrence before it (NULL keeps
#     the old "always ran" behavior). No schema change: the column already
#     existed and was only used by weekly/biweekly.
#
# 1.16.1 (2026-09-07, claude+mkolakowski): GET /api/accounts/{id}/recurring
#     rows gain monthly_cost/yearly_cost (same normalization
#     _MONTHLY_FACTOR already used by /api/subscriptions, now defined
#     once and shared) — null for income rows or unrecognized cadences.
#     Backs the Recurring Transactions panel's new Subscriptions-style
#     summary tiles and Monthly/Yearly columns (see WEB_VERSION 1.18.0).
#
# 1.16.0 (2026-09-07, claude+mkolakowski): Three forward-looking views
#     plus a spreadsheet-style bulk editor. (1) GET
#     /api/accounts/{id}/forecast already supported explicit start/end,
#     so the new "Rest of this month" Forecast-page range just calls it
#     with today->month-end, no backend change. (2) GET /api/dashboard
#     cards gain `upcoming_count`/`upcoming_net` (not-yet-cleared rows
#     from today through month end) backing a new dashboard summary
#     widget. (3) Calendar's "Future view" toggle is purely client-side
#     (dims past day cells) — no backend change. (4) Forecast table
#     "Spreadsheet mode": every row becomes always-editable, saved via
#     the existing PATCH/POST /api/transactions endpoints — no new
#     backend surface, just more frequent, per-row calls to what
#     saveForecastRowEdit already used.
#
# 1.15.0 (2026-09-07, claude+mkolakowski): Calendar shows a running
#     account balance and inline transaction editing lands on the
#     Transactions tab. GET /api/calendar gains `daily_balances`
#     ({date: balance}), computed only in single-account mode (the same
#     carry-forward walk as dashboard_charts/net_worth) — "All accounts"
#     has no one balance to show, so it's null there. GET
#     /api/transactions/search rows gain `forecast_amount` and
#     `recurring_id` so the search table can offer the same
#     forecast/actual dual-amount inline edit as the Forecast table,
#     PATCHing the existing /api/transactions/{id} endpoint (no backend
#     write-path changes needed — search rows always have a real id, so
#     there's no "materialize a projection" case to handle).
#
# 1.14.0 (2026-09-07, claude+mkolakowski): CSV import supports *past*
#     recurring transactions, not just future ones. BEHAVIOR CHANGE: a row
#     with a recognized `Frequency` value now always creates a real actual
#     Transaction (like a one-time row) in addition to being linked via
#     recurring_id to a RecurringTransaction template — previously it
#     created ONLY the template and no transaction. Rows sharing the same
#     Frequency + Description (or the same optional new `Recurring Group`
#     column, for series whose description text drifts) are clustered into
#     one series per import; the template is seeded from the group's
#     most-recent row (anchor/day-of-month, baseline amount/category/notes)
#     while each row keeps its own actual amount, so forecast-vs-actual
#     still reflects price drift across the series. Importing more months
#     of the same bill in a later CSV reuses the existing template
#     (matched by frequency + the template's stored description) instead
#     of creating a duplicate. New helpers `_recurring_group_key`,
#     `_recurring_template_identity`, `_resolve_recurring_groups` (shared
#     by preview and commit so they can't disagree on grouping); removed
#     the now-obsolete `_recurring_row_key`/`_existing_recurring_keys`
#     (recurring rows dedupe through the same actual-transaction key as
#     everything else now). Commit response gains `recurring_linked`
#     (rows attached to a template) alongside `recurring_created` (new
#     templates only, now a subset metric rather than a row count).
#
# 1.13.2 (2026-09-05, claude+mkolakowski): Fix GET
#     /api/transactions/search (the Transactions tab) building its scope
#     of visible accounts with include_archived=True — archived accounts'
#     transactions kept appearing in the unfiltered "all accounts" search
#     view even though the account picker itself already hides archived
#     accounts. Now defaults to non-archived only, matching the Dashboard
#     and Accounts page. `/api/transfers`' Recent-transfers list still
#     includes archived-account legs intentionally (a transfer already
#     happened and still explains the other leg's balance history).
#
# 1.13.1 (2026-09-05, claude+mkolakowski): Account rename. PATCH
#     /api/accounts/{id} accepts an optional `name`, restricted to the
#     `owner` permission level (shared `edit` users can still
#     archive/unarchive but not rename or delete — delete already
#     required owner). 403 (not 404) on insufficient level since the
#     caller already has edit access and knows the account exists.
#
# 1.13.0 (2026-09-04, claude+mkolakowski): CSV import gains Tags support
#     and recurring-transaction import. `_detect_columns`/`_parse_csv_rows`
#     now also read optional Tags (comma/semicolon-separated, matched
#     case-insensitively against the user's existing tags — unmatched
#     names are skipped rather than auto-created, same policy as
#     Category) and Frequency/End Date columns; a row with a recognized
#     Frequency (Monthly/Weekly/Biweekly) is imported as a
#     RecurringTransaction template (row date -> anchor date or
#     day-of-month) instead of a one-time Transaction, with its own
#     duplicate check against existing recurring templates. New GET
#     /api/accounts/{id}/import/template returns a starter CSV
#     demonstrating every importable column.
#
# 1.12.1 (2026-09-04, claude+mkolakowski): CSV import fixes. A mapped
#     "Category" column is now actually applied per-row (matched
#     case-insensitively against the user's existing categories, falling
#     back to the chosen default category when absent/unmatched) — it was
#     previously auto-detected but silently discarded. Imported notes are
#     now truncated to NOTES_MAX_LEN (256, shared with the manual
#     transaction/recurring forms) instead of bypassing that cap entirely.
#
# 1.12.0 (2026-04-24, claude+mkolakowski): saved reports + dashboard
#     pinning. Schema v11 adds `saved_reports` (per-user, JSON params,
#     pinned flag, sort_order). New /api/report/run takes inline
#     params for the live editor; /api/saved-reports CRUD persists
#     them; /api/saved-reports/{id}/run resolves and executes;
#     /api/report-templates returns built-in starting points. The
#     existing /api/report endpoint is retained for back-compat.
#     `_compute_report` is a unified helper supporting group_by =
#     'category' | 'tag' | 'account', range_mode covering month /
#     last_30d / last_90d / ytd / year / custom, multi-select account /
#     category / tag filters, kind = any|income|spending, and
#     include_transfers. Demo seed adds four sample reports with one
#     pinned to the demo dashboard, and the demo fingerprint hashes
#     saved_reports too so user edits trigger the hourly reset.
# 1.11.0 (2026-04-24, claude+mkolakowski): tag deepening pass.
#     Reports: /api/report now returns a `tags` array (forecast/actual
#       totals per tag, double-counted across multi-tag rows by design).
#     Bulk ops: new POST /api/transactions/bulk-tag accepting
#       transaction_ids + add_tag_ids/remove_tag_ids; idempotent and
#       enforces tag ownership + per-row edit permission.
#     Auto-tag rules: schema v10 adds `tag_rules` (per-user
#       description-substring match → optional category gate → target
#       tag). New /api/tag-rules CRUD plus /api/tag-rules/backfill that
#       replays every active rule across existing transactions. Rules
#       fire automatically on transaction create, PATCH, and CSV import
#       commit, and are additive (never remove existing tags).
# 1.10.1 (2026-04-24, claude+mkolakowski): frontend-only polish — new
#     pencil "Edit" button on the Dashboard that jumps to Settings and
#     flashes the chart placement picker, and the default
#     chart-placement value flipped from "above" to "inside" so new /
#     unset users get the inside-each-card layout by default. No
#     backend API change — `chart_position` is still per-user and
#     server-persisted; this is just a client-side default fallback
#     tweak. (APP_VERSION bumped alongside WEB_VERSION so the two keep
#     moving together even when a release is frontend-only.)
# 1.10.0 (2026-04-24, claude+mkolakowski): /api/accounts now returns a
#     `current_balance` field (today-dated sum of starting balance +
#     every cleared transaction). Backed by a new `_current_balance`
#     helper that issues a single SQL scan instead of running the
#     forecast walk, so the transfer page can refresh balances live as
#     the user types an amount. No schema change.
# 1.9.0 (2026-04-24, claude+mkolakowski): new Calendar page. Added
#     /api/calendar endpoint aggregating forecasted + recorded events
#     across every visible account for an arbitrary date window
#     (capped at 366 days). Each event carries account, category +
#     color, tags, amount sign, recurring/transfer linkage, and
#     cleared/pending flag so the frontend can filter by Account,
#     Category, Tag, Source (scheduled vs one-time), Kind (income /
#     spending / transfer), and Status. Forecast rows now include tag
#     metadata for both recorded transactions and projected
#     occurrences (empty list for projections).
# 1.8.0 (2026-04-24, claude+mkolakowski): Tier-2 roadmap — subscription audit
#     page surfacing every active recurring outflow with normalized monthly
#     and annual totals (/api/subscriptions), and cross-category transaction
#     tags (schema v9 adds tags + transaction_tags). Tags are per-user
#     labels with optional color, many-to-many with transactions, exposed on
#     list/search/forecast rows and editable via an inline pill picker.
#     Tag filter added to /api/transactions/search.
# 1.7.1 (2026-04-23, claude+mkolakowski): demo mode — show "WalletWeather Demo"
#     as the app title whenever DEMO_MODE is on (overrides any admin-set
#     title), and add an hourly background job that wipes+reseeds the demo
#     data only if it's actually drifted from the post-seed fingerprint.
#     Untouched demo instances skip the reset. DEMO_MODE default flipped
#     from true to false so production installs boot empty.
# 1.7.0 (2026-04-23, claude+mkolakowski): Tier-1 roadmap features —
#     account transfers (paired Transaction legs linked via transfer_id,
#     excluded from spend/income aggregations), per-category monthly
#     budgets with progress endpoint, transaction search/filter endpoint,
#     CSV import (preview + commit with dedupe), and net worth endpoint
#     summing daily balance trends across all visible accounts.
# 1.6.0 (2026-04-23, claude+mkolakowski): dashboard charts — per-account
#     spending-by-category donut, income/spending/net totals tile, and
#     daily balance sparkline. New /api/dashboard/charts endpoint with
#     selectable window (month / 30d / 90d). New users.chart_position
#     preference for placement (above / below / inside cards).
# 1.5.0 (2026-04-23, claude+mkolakowski): admin-customizable app title
#     (AdminSetting-backed, shown in tab + header), default theme set to
#     "system", theme localStorage removed to fix cross-user theme leak,
#     theme picker grouped into Dark / Light rows.
# 1.4.0 (2026-04-22, claude+mkolakowski): add 10 UI themes (light + 8 fun
#     themes + system), server-side theme persistence per user, demo mode
#     with pre-seeded admin + sample data, DEMO_MODE env var.
# 1.3.x and earlier: pre-versioning — see git history.
# -----------------------------------------------------------------------------


import bcrypt
from fastapi import FastAPI, Depends, HTTPException, Request, status, Response
from fastapi.responses import RedirectResponse, JSONResponse, FileResponse
from fastapi.encoders import jsonable_encoder
from fastapi.exceptions import RequestValidationError
from fastapi.staticfiles import StaticFiles
from starlette.middleware.sessions import SessionMiddleware
from sqlalchemy import func, or_
from sqlalchemy.orm import Session
from typing import Annotated, Literal

from pydantic import BaseModel, EmailStr, Field, model_validator

from .db import (
    init_db, get_db, User, Account, RecurringTransaction, Transaction, Category,
    AccountPermission, AccountInvitation, BackupSchedule, AdminSetting, Transfer, CategoryBudget,
    Tag, TransactionTag, RecurringTag, TagRule, SavedReport, RecurringSkip,
    ApiToken, AuditEvent, AppSignInCode, RecoveryCode, RememberedBrowser, SessionLocal,
    BankConnection, BankAccountLink, BankSyncRun, MailConnection, MailSender, MailAlertKind,
    MailUnread, MailCheckRun, encrypt_str, decrypt_str, SCHEMA_VERSION,
)
from . import twofactor
from . import simplefin
from . import mailbox, alerts
from .forecast import build_forecast, actual_balance_as_of, upcoming_dates, _occurrences
from .backup import (export_user, import_user, seal, unwrap, passphrase_problem,
                     BackupLocked, SEALED_MARKER)

SECRET_KEY = os.environ["SESSION_SECRET"]
# The session cookie is only as good as this secret: anyone who can guess it
# can sign a cookie for any user. Refuse to start on one that's empty, short
# or still the template's (security-fixes phase 2, #185).
if len(SECRET_KEY) < 16 or SECRET_KEY == "replace_with_random_string":
    raise RuntimeError(
        "SESSION_SECRET is empty, shorter than 16 characters, or still the "
        "placeholder from .env.example. Set it to a long random string: "
        'python -c "import secrets; print(secrets.token_urlsafe(48))"')
# The largest request body accepted, in megabytes (#185). The default leaves
# room for a backup import; nothing else comes close.
MAX_BODY_BYTES = max(1, int(os.environ.get("MAX_BODY_MB", "25"))) * 1024 * 1024
APP_BASE_URL = os.environ.get("APP_BASE_URL", "http://localhost:8300")
ALLOWED_EMAILS = {e.strip().lower() for e in os.environ.get("ALLOWED_EMAILS", "").split(",") if e.strip()}
ALLOW_REGISTRATION = os.environ.get("ALLOW_REGISTRATION", "true").lower() == "true"
ADMIN_EMAILS = {e.strip().lower() for e in os.environ.get("ADMIN_EMAILS", "").split(",") if e.strip()}
# Registering with a password proves nothing about who owns the address, so
# (decided 2026-11-16, #183) an instance can ask for a code only the people
# it's meant for were given. Empty means no code is asked for.
REGISTRATION_CODE = os.environ.get("REGISTRATION_CODE", "").strip()
BACKUP_DIR = Path(os.environ.get("BACKUP_DIR", "/data/backups"))
# Seals the scheduled and full-system backups (bank-sync phase 1, #193).
# Without it (or with one too short) they don't run, and Admin says why.
BACKUP_PASSPHRASE = os.environ.get("BACKUP_PASSPHRASE", "")


def _backup_passphrase_problem() -> str | None:
    """Why system backups can't run, or None when BACKUP_PASSPHRASE is usable."""
    if not BACKUP_PASSPHRASE:
        return "BACKUP_PASSPHRASE isn't set in .env, so system backups don't run."
    problem = passphrase_problem(BACKUP_PASSPHRASE)
    return f"BACKUP_PASSPHRASE in .env is too short: {problem}" if problem else None

# Login rate limiting (login-limits phase 1, #132). TRUST_PROXY_HEADERS makes
# the visitor's address come from Cloudflare's CF-Connecting-IP header; only
# turn it on when the server can be reached only through Cloudflare, since
# anyone who reaches it directly could forge the header.
TRUST_PROXY_HEADERS = os.environ.get("TRUST_PROXY_HEADERS", "false").lower() == "true"
LOGIN_MAX_FAILURES = max(1, int(os.environ.get("LOGIN_MAX_FAILURES", "5")))
LOGIN_WINDOW_MINUTES = max(1, int(os.environ.get("LOGIN_WINDOW_MINUTES", "15")))
# How long audit events are kept (login-limits phase 3, #134; 180 days decided
# 2026-11-15). Never less than a day, so the rate limit's window is always there.
AUDIT_RETENTION_DAYS = max(1, int(os.environ.get("AUDIT_RETENTION_DAYS", "180")))
# Wider sign-in limits (security-fixes phase 6, #189), in the same window as
# LOGIN_MAX_FAILURES. That one is per email from one address, so someone
# with many addresses got five tries from each, and someone trying one
# password on many emails was never slowed at all.
#   per email, from all addresses together (default: 4 x LOGIN_MAX_FAILURES)
#   per address, across all emails           (default: 10 x LOGIN_MAX_FAILURES)
LOGIN_MAX_FAILURES_PER_EMAIL = max(1, int(os.environ.get(
    "LOGIN_MAX_FAILURES_PER_EMAIL", str(4 * LOGIN_MAX_FAILURES))))
LOGIN_MAX_FAILURES_PER_ADDRESS = max(1, int(os.environ.get(
    "LOGIN_MAX_FAILURES_PER_ADDRESS", str(10 * LOGIN_MAX_FAILURES))))
# New users, and wrong registration codes, from one address in an hour.
REGISTRATIONS_PER_HOUR = max(1, int(os.environ.get("REGISTRATIONS_PER_HOUR", "10")))

# Demo mode: when on, the app boots with a pre-seeded admin user and sample
# data, the UI is branded "WalletWeather Demo", and a background daemon
# wipes+reseeds the sample data hourly (only if it's been edited). Default
# OFF so a fresh production install doesn't accidentally expose the demo
# admin login. Set DEMO_MODE=true in .env to turn it on.
DEMO_MODE = os.environ.get("DEMO_MODE", "false").lower() == "true"
from .demo import (
    DEMO_ADMIN_EMAIL, DEMO_ADMIN_PASSWORD, DEMO_APP_TITLE, is_demo_email,
    seed_demo_data, wipe_demo_data, reseed_demo_if_changed,
)

# How often the demo-reset daemon checks whether the demo data has drifted.
# The user requested "once an hour". Kept as a module constant so tests or
# future operators can tune it without editing the loop body.
DEMO_RESET_INTERVAL_SECONDS = 3600
if DEMO_MODE:
    # Make the demo admin an actual admin without requiring the operator to
    # add them to ADMIN_EMAILS in .env.
    ADMIN_EMAILS.add(DEMO_ADMIN_EMAIL.lower())

# Google OAuth is optional - only enabled if both client id and secret are set
GOOGLE_CLIENT_ID = os.environ.get("GOOGLE_CLIENT_ID", "").strip()
GOOGLE_CLIENT_SECRET = os.environ.get("GOOGLE_CLIENT_SECRET", "").strip()
GOOGLE_ENABLED = bool(GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET)

# Other addresses the web app is opened at, besides APP_BASE_URL and
# whatever Host the request names: comma-separated origins, like
# "https://wallet.example.com" (security-fixes phase 4, #187).
TRUSTED_ORIGINS = {o.strip().lower().rstrip("/")
                   for o in os.environ.get("TRUSTED_ORIGINS", "").split(",") if o.strip()}
TRUSTED_ORIGINS.add(APP_BASE_URL.strip().lower().rstrip("/"))

# The API's own documentation pages are off: they described every route to
# anyone who asked (#187). README.md documents the API.
app = FastAPI(title="WalletWeather", docs_url=None, redoc_url=None, openapi_url=None)
app.add_middleware(SessionMiddleware, secret_key=SECRET_KEY, same_site="lax", https_only=False)


class BodyLimitMiddleware:
    """Refuse a request body over MAX_BODY_BYTES with 413 (#185): by its
    Content-Length before any of it is read, and by counting for a body
    sent without one. Past the limit the app is told the body has ended
    and whatever it answers is replaced by the 413."""

    def __init__(self, app, max_bytes: int):
        self.app, self.max_bytes = app, max_bytes

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            return await self.app(scope, receive, send)

        async def refuse():
            body = json.dumps({"detail": "That request is too large "
                               f"(over {self.max_bytes // (1024 * 1024)} MB)."}).encode()
            await send({"type": "http.response.start", "status": 413,
                        "headers": [(b"content-type", b"application/json"),
                                    (b"content-length", str(len(body)).encode()),
                                    (b"connection", b"close")]})
            await send({"type": "http.response.body", "body": body})

        declared = dict(scope.get("headers") or []).get(b"content-length", b"")
        if declared.isdigit() and int(declared) > self.max_bytes:
            return await refuse()
        seen, too_large, started = 0, False, False

        async def counted_receive():
            nonlocal seen, too_large
            if too_large:
                return {"type": "http.disconnect"}
            message = await receive()
            if message["type"] == "http.request":
                seen += len(message.get("body") or b"")
                if seen > self.max_bytes:
                    too_large = True
                    return {"type": "http.request", "body": b"", "more_body": False}
            return message

        async def guarded_send(message):
            nonlocal started
            if too_large and not started:
                return          # dropped: the 413 below is the answer
            if message["type"] == "http.response.start":
                started = True
            await send(message)

        await self.app(scope, counted_receive, guarded_send)
        if too_large and not started:
            await refuse()


app.add_middleware(BodyLimitMiddleware, max_bytes=MAX_BODY_BYTES)


_WRITE_METHODS = {"POST", "PUT", "PATCH", "DELETE"}
SECURITY_HEADERS = [
    (b"x-content-type-options", b"nosniff"),
    # Never inside another site's frame: the "Allow" button on the app
    # sign-in page mustn't be clickable through one.
    (b"x-frame-options", b"DENY"),
    (b"content-security-policy", b"frame-ancestors 'none'; base-uri 'self'; object-src 'none'"),
    (b"referrer-policy", b"same-origin"),
]
OTHER_SITE_MESSAGE = (
    "This request came from a page on another site, so it was refused. If "
    "that's WalletWeather's own address, set APP_BASE_URL (or TRUSTED_ORIGINS) "
    "in .env to the address you open it at.")


def _from_another_site(headers: dict[bytes, bytes]) -> bool:
    """True when a browser says this write was started by a page that isn't
    the app's own. The session cookie's SameSite=Lax already stops other
    sites; this also stops other apps on the same domain, which Lax doesn't.

    Not judged: a request signed by an API token (a page on another site
    can't attach one), and one with no Origin or Sec-Fetch-Site at all (the
    native app, scripts)."""
    if headers.get(b"authorization", b"")[:7].lower() == b"bearer ":
        return False
    origin = headers.get(b"origin", b"").decode("latin-1").strip().lower().rstrip("/")
    if origin:
        if origin in TRUSTED_ORIGINS:
            return False
        origin_host = urlsplit(origin).netloc
        own_hosts = {headers.get(name, b"").decode("latin-1").strip().lower()
                     for name in (b"host", b"x-forwarded-host")}
        return not origin_host or origin_host not in own_hosts
    return headers.get(b"sec-fetch-site", b"").decode("latin-1").strip().lower() in (
        "cross-site", "same-site")


class BrowserGuardMiddleware:
    """Refuses writes started by another site's page, and puts the security
    headers on every answer (security-fixes phase 4, #187)."""

    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            return await self.app(scope, receive, send)
        private = scope["path"].startswith(("/api/", "/auth/"))

        async def send_with_headers(message):
            if message["type"] == "http.response.start":
                headers = list(message.get("headers") or [])
                present = {name.lower() for name, _ in headers}
                headers += [h for h in SECURITY_HEADERS if h[0] not in present]
                # Answers about a user aren't for any cache to keep.
                if private and b"cache-control" not in present:
                    headers.append((b"cache-control", b"no-store"))
                message = {**message, "headers": headers}
            await send(message)

        if scope["method"] in _WRITE_METHODS and _from_another_site(dict(scope["headers"])):
            body = json.dumps({"detail": OTHER_SITE_MESSAGE}).encode()
            await send_with_headers({"type": "http.response.start", "status": 403,
                                     "headers": [(b"content-type", b"application/json"),
                                                 (b"content-length", str(len(body)).encode())]})
            return await send({"type": "http.response.body", "body": body})
        await self.app(scope, receive, send_with_headers)


app.add_middleware(BrowserGuardMiddleware)

oauth = None
if GOOGLE_ENABLED:
    from authlib.integrations.starlette_client import OAuth
    oauth = OAuth()
    oauth.register(
        name="google",
        client_id=GOOGLE_CLIENT_ID,
        client_secret=GOOGLE_CLIENT_SECRET,
        server_metadata_url="https://accounts.google.com/.well-known/openid-configuration",
        client_kwargs={"scope": "openid email profile"},
    )


import json
import threading
import time


@app.on_event("startup")
def _startup():
    init_db()
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    # Backfill: seed default categories for any existing user who has none.
    from .db import SessionLocal
    db = SessionLocal()
    try:
        for user in db.query(User).all():
            seed_default_categories(db, user)
        # Lines synced before names were shortened (#213).
        shorten_synced_names(db)
        # Demo-mode reconciliation. This must run after init_db so the
        # admin_settings table exists.
        if DEMO_MODE:
            seed_demo_data(db, seed_default_categories)
        else:
            # If the demo was seeded previously and the operator has now
            # turned it off, wipe the demo user(s) and their data. Real
            # users are safe — we only delete the reserved demo email suffix.
            wipe_demo_data(db)
    finally:
        db.close()
    # Start the backup scheduler daemon thread
    t = threading.Thread(target=_backup_scheduler_loop, daemon=True)
    t.start()
    # The daily bank sync (#195).
    threading.Thread(target=_bank_scheduler_loop, daemon=True).start()
    # Checking the mailboxes for email alerts (#207).
    threading.Thread(target=_mail_scheduler_loop, daemon=True).start()
    # Demo-reset daemon: on an instance running in DEMO_MODE, check hourly
    # whether the demo data has drifted from its post-seed fingerprint, and
    # wipe + reseed only if something has been edited.
    if DEMO_MODE:
        dt = threading.Thread(target=_demo_reset_scheduler_loop, daemon=True)
        dt.start()


class BackupPassphraseMissing(RuntimeError):
    pass


def _run_system_backup() -> str:
    """Execute a full-system backup to BACKUP_DIR, sealed with
    BACKUP_PASSPHRASE (#193). Returns the filename. Raises
    BackupPassphraseMissing, writing nothing, when the passphrase isn't usable."""
    problem = _backup_passphrase_problem()
    if problem:
        raise BackupPassphraseMissing(problem)
    from .db import SessionLocal
    from .backup import export_full_system
    db = SessionLocal()
    try:
        payload = seal(export_full_system(db), BACKUP_PASSPHRASE, kind="system")
        stamp = datetime.utcnow().strftime("%Y%m%d_%H%M%S")
        filename = f"system-backup-{stamp}.json"
        filepath = BACKUP_DIR / filename
        filepath.write_text(json.dumps(payload))
        return filename
    finally:
        db.close()


def _enforce_retention(retention_days: int):
    """Delete backup files older than retention_days."""
    if retention_days <= 0:
        return
    cutoff = datetime.utcnow() - timedelta(days=retention_days)
    for f in sorted(BACKUP_DIR.glob("system-backup-*.json")):
        try:
            # Parse timestamp from filename: system-backup-YYYYMMDD_HHMMSS.json
            parts = f.stem.replace("system-backup-", "")
            file_dt = datetime.strptime(parts, "%Y%m%d_%H%M%S")
            if file_dt < cutoff:
                f.unlink()
        except (ValueError, OSError):
            pass


def prune_audit_events(db: Session, now: datetime | None = None) -> int:
    """Delete audit events older than AUDIT_RETENTION_DAYS (never less than
    a day). Returns how many went."""
    cutoff = (now or datetime.utcnow()) - timedelta(days=max(1, AUDIT_RETENTION_DAYS))
    gone = (db.query(AuditEvent).filter(AuditEvent.created_at < cutoff)
            .delete(synchronize_session=False))
    # The bank sync log is kept as long (#195; the plan's question 10).
    db.query(BankSyncRun).filter(BankSyncRun.run_at < cutoff).delete(synchronize_session=False)
    # And alerts that didn't become lines (#206; question 3).
    db.query(MailUnread).filter(MailUnread.created_at < cutoff).delete(synchronize_session=False)
    # And the mailbox's log of checks (#207).
    db.query(MailCheckRun).filter(MailCheckRun.run_at < cutoff).delete(synchronize_session=False)
    db.commit()
    return gone


def _backup_scheduler_loop():
    """Background daemon that checks every 30 minutes whether a scheduled
    backup should run. Reads config from the BackupSchedule table. Also
    prunes old audit events once a day (#134)."""
    from .db import SessionLocal
    last_prune = None
    while True:
        time.sleep(1800)  # 30 minutes
        if last_prune is None or datetime.utcnow() - last_prune >= timedelta(days=1):
            db = SessionLocal()
            try:
                prune_audit_events(db)
                last_prune = datetime.utcnow()
            except Exception:
                pass  # tried again in 30 minutes
            finally:
                db.close()
        db = SessionLocal()
        try:
            sched = db.query(BackupSchedule).first()
            if not sched or not sched.enabled:
                continue
            now = datetime.utcnow()
            # Decide if it's time to run based on frequency + hour
            should_run = False
            if sched.last_run_at is None:
                should_run = True
            elif sched.frequency == "daily":
                # Run if we haven't run today and current hour >= scheduled hour
                last_date = sched.last_run_at.date()
                if now.date() > last_date and now.hour >= sched.hour:
                    should_run = True
            elif sched.frequency == "weekly":
                days_since = (now - sched.last_run_at).days
                if days_since >= 7 and now.hour >= sched.hour:
                    should_run = True
            elif sched.frequency == "monthly":
                # Run if we're in a new month
                if (now.year, now.month) > (sched.last_run_at.year, sched.last_run_at.month) \
                   and now.hour >= sched.hour:
                    should_run = True
            if not should_run:
                continue
            problem = _backup_passphrase_problem()
            if problem:
                # Nothing is written, and last_run_at stays put so the
                # backup runs as soon as the passphrase is added (#193).
                status = f"NOT RUN: {problem}"
                if sched.last_run_status != status:
                    sched.last_run_status = status
                    db.commit()
                continue
            try:
                filename = _run_system_backup()
                _enforce_retention(sched.retention_days)
                sched.last_run_at = now
                sched.last_run_status = f"OK: {filename}"
                record_event(db, "backup_made", detail=f"scheduled: {filename}")
            except Exception as e:
                sched.last_run_at = now
                sched.last_run_status = f"ERROR: {str(e)[:200]}"
            db.commit()
        except Exception:
            pass  # never crash the daemon
        finally:
            db.close()


def _demo_reset_scheduler_loop():
    """Background daemon that resets demo data once an hour, but only if the
    data has actually changed since the last seed.

    Compares the current content fingerprint against the baseline stored when
    the demo was last seeded. Match → skip (nobody touched anything, so
    there's nothing to roll back). Mismatch → wipe + reseed.
    """
    from .db import SessionLocal
    while True:
        time.sleep(DEMO_RESET_INTERVAL_SECONDS)
        db = SessionLocal()
        try:
            reseed_demo_if_changed(db, seed_default_categories)
        except Exception:
            pass  # never crash the daemon
        finally:
            db.close()


# ---------- Password helpers ----------
def hash_password(pw: str) -> str:
    return bcrypt.hashpw(pw.encode("utf-8"), bcrypt.gensalt(rounds=12)).decode("utf-8")


def verify_password(pw: str, hashed: str) -> bool:
    try:
        return bcrypt.checkpw(pw.encode("utf-8"), hashed.encode("utf-8"))
    except (ValueError, TypeError):
        return False


def _email_ok(email: str) -> bool:
    return bool(re.match(r"^[^@\s]+@[^@\s]+\.[^@\s]+$", email))


# ---------- Auth ----------
# A request is signed in by the session cookie (a browser) or by an API token
# sent as `Authorization: Bearer <token>` (#42). With a token, the access it
# was made with limits what it reaches:
#   read   GET only (plus the report "run" POSTs, which change nothing)
#   full   everything a signed-in user can do, except the Admin endpoints
#   admin  full, plus the Admin endpoints while its owner is an admin
# No token can list, create or revoke tokens: that needs a browser session.
# The one exception: a token may revoke itself (DELETE /api/tokens/current),
# so an app can end its own token when it signs out (#145).
TOKEN_ACCESS_LEVELS = ("read", "full", "admin")
TOKEN_PREFIX = "ww_"
_READ_METHODS = {"GET", "HEAD", "OPTIONS"}
# Expiry choices when a token is made (#43); leaving it out means never.
TOKEN_EXPIRY_DAYS = (30, 90, 365)
# last_used_at is written at most this often, so a busy script doesn't turn
# every request into a database write.
TOKEN_LAST_USED_EVERY = timedelta(minutes=1)


def _hash_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def _bearer_token(request: Request) -> str | None:
    """The token from an `Authorization: Bearer` header, "" for a Bearer
    header with nothing after it, None when there's no Bearer header."""
    scheme, _, value = request.headers.get("authorization", "").partition(" ")
    if scheme.lower() != "bearer":
        return None
    return value.strip()


def _authenticate(request: Request, db: Session) -> User:
    """The signed-in user, by API token or session. Sets
    request.state.api_token to the token's row, or None for a session."""
    request.state.api_token = None
    token = _bearer_token(request)
    if token is not None:
        row = (db.query(ApiToken).filter_by(token_hash=_hash_token(token)).first()
               if token else None)
        if not row or row.revoked_at is not None:
            raise HTTPException(status_code=401, detail="Invalid or revoked API token")
        now = datetime.utcnow()
        if row.expires_at is not None and row.expires_at <= now:
            raise HTTPException(status_code=401, detail="API token expired")
        user = db.get(User, row.owner_id)
        if not user or user.disabled:
            raise HTTPException(status_code=401, detail="Invalid or revoked API token")
        if row.last_used_at is None or now - row.last_used_at >= TOKEN_LAST_USED_EVERY:
            row.last_used_at = now
            db.commit()
        request.state.api_token = row
        _hold_for_two_factor(request, db, user)
        return user
    uid = request.session.get("uid")
    if not uid:
        raise HTTPException(status_code=401, detail="Not authenticated")
    user = db.get(User, uid)
    if not user:
        raise HTTPException(status_code=401, detail="User not found")
    if request.session.get("v", 0) != (user.session_epoch or 0):
        # Signed out from elsewhere: the password changed, or "sign out my
        # other browsers" (#186).
        request.session.clear()
        raise HTTPException(status_code=401, detail="Not authenticated")
    if user.disabled:
        # Disabled users get logged out cleanly
        request.session.clear()
        raise HTTPException(status_code=403, detail="Account disabled")
    _hold_for_two_factor(request, db, user)
    return user


# ---------- Sessions that can be ended (security-fixes phase 3, #186) ----------
# The session cookie is signed, not stored, so there's nothing on the server
# to delete when a session should end. Instead each user has a number,
# session_epoch; a session carries the number it was started under, and a
# session with an old number is no session. Raising the number signs out
# every browser at once. Decided 2026-11-16 (docs/dev/decisions/
# security-fixes.md): a password change ends the user's other browser
# sessions and leaves their API tokens; an admin's reset ends both.
def _start_session(request: Request, user: User) -> None:
    request.session["uid"] = user.id
    request.session["v"] = user.session_epoch or 0


def _end_other_sessions(request: Request | None, user: User) -> None:
    """Sign `user` out everywhere; the caller commits. With `request` (the
    user's own), that one browser stays signed in."""
    user.session_epoch = (user.session_epoch or 0) + 1
    if request is not None:
        request.session["v"] = user.session_epoch


# ---------- Two-factor sign-in required by an admin (#168) ----------
# Decided 2026-11-15 (Plans/two-factor.md, open question 4, and #168): when
# an admin requires it, it covers every user with a password (Google-only
# users aren't asked: Google sign-in skips the code). Until such a user has
# set it up, every request of theirs is held back, by session or API token
# alike, except what setting it up needs.
REQUIRE_TWO_FACTOR_KEY = "require_two_factor"
TWO_FACTOR_SETUP_MESSAGE = ("This instance requires two-factor sign-in. "
                            "Set it up in Settings in a browser first.")
# (method, path) still open to a user who must set it up: who they are, the
# first-login notice, the two set-up steps, and an app signing itself out.
TWO_FACTOR_SETUP_OPEN = {
    ("GET", "/api/me"),
    ("POST", "/api/me/acknowledge-notice"),
    ("POST", "/api/me/two-factor/setup"),
    ("POST", "/api/me/two-factor/enable"),
    ("DELETE", "/api/tokens/current"),
}


def two_factor_required(db: Session) -> bool:
    row = db.get(AdminSetting, REQUIRE_TWO_FACTOR_KEY)
    return bool(row and row.value == "true")


def must_set_up_two_factor(db: Session, user: User) -> bool:
    """True for a user the requirement covers who hasn't set it up yet."""
    if user.password_hash is None or user.totp_enabled_at is not None:
        return False
    if is_demo_email(user.email):
        return False
    return two_factor_required(db)


def _hold_for_two_factor(request: Request, db: Session, user: User) -> None:
    # The path the request was routed by. request.url is rebuilt from the
    # Host header, which the caller writes (#183).
    if (request.method, request.scope.get("path")) in TWO_FACTOR_SETUP_OPEN:
        return
    if must_set_up_two_factor(db, user):
        raise HTTPException(status_code=403, detail=TWO_FACTOR_SETUP_MESSAGE)


def current_user(request: Request, db: Session = Depends(get_db)) -> User:
    user = _authenticate(request, db)
    token = request.state.api_token
    if token and token.access == "read" and request.method not in _READ_METHODS:
        raise HTTPException(status_code=403, detail="This API token is read-only")
    return user


def current_reader(request: Request, db: Session = Depends(get_db)) -> User:
    """Like current_user, but a read-only token passes on any method. Only
    for POST endpoints that change nothing (running a report)."""
    return _authenticate(request, db)


def current_session_user(request: Request, db: Session = Depends(get_db)) -> User:
    """Like current_user, but refuses API tokens: for managing tokens."""
    if _bearer_token(request) is not None:
        raise HTTPException(status_code=403,
                            detail="API tokens can't manage tokens. Sign in in a browser.")
    return current_user(request, db)


def is_admin(user: User) -> bool:
    return bool(ADMIN_EMAILS) and user.email.lower() in ADMIN_EMAILS


def current_session_admin(request: Request, db: Session = Depends(get_db)) -> User:
    """An admin signed in through a browser session. Refuses every API token,
    admin ones too: managing tokens needs a browser (#42, #43)."""
    user = current_session_user(request, db)
    if not is_admin(user):
        raise HTTPException(status_code=403, detail="Admin access required")
    return user


def current_admin(request: Request, user: User = Depends(current_user)) -> User:
    if not is_admin(user):
        raise HTTPException(status_code=403, detail="Admin access required")
    token = getattr(request.state, "api_token", None)
    if token and token.access != "admin":
        raise HTTPException(status_code=403,
                            detail="Only an admin API token reaches the Admin endpoints")
    return user


# ---------- Audit log and login rate limiting (#132) ----------
def client_ip(request: Request) -> str | None:
    """The visitor's address: Cloudflare's CF-Connecting-IP when
    TRUST_PROXY_HEADERS is on and the header is there, otherwise the
    connection's own address."""
    if TRUST_PROXY_HEADERS:
        forwarded = request.headers.get("cf-connecting-ip", "").strip()
        if forwarded:
            return forwarded[:45]
    return request.client.host[:45] if request.client and request.client.host else None


def record_event(db: Session, event: str, request: Request | None = None,
                 user: User | None = None, email: str | None = None,
                 detail: str | None = None) -> None:
    """Write one audit event and commit it. Never pass a password.

    `user` is who did it. Who it was done to goes in `detail` by number
    ("user #7", see audit_target), never by email, so deleting that user
    leaves nothing naming them (decided 2026-11-15, #139, #133). No amounts,
    account names or other financial data in `detail`.
    """
    db.add(AuditEvent(
        event=event,
        user_id=user.id if user else None,
        email=(email if email is not None else (user.email if user else None) or None),
        ip=client_ip(request) if request is not None else None,
        detail=detail[:200] if detail else None,
    ))
    db.commit()


def audit_target(actor: User, target_id: int) -> str:
    """How an event's detail names the user an action was done to."""
    return "own user" if target_id == actor.id else f"user #{target_id}"


def _login_retry_after(db: Session, email: str, ip: str | None) -> int:
    """Seconds until this email may try a password again from this address,
    or 0 when it isn't blocked.

    Blocked when the last LOGIN_MAX_FAILURES failed sign-ins for the pair
    since its last successful one all fall within LOGIN_WINDOW_MINUTES of
    each other, until that window has passed since the newest of them.
    Blocked attempts aren't failures, so trying during a block doesn't make
    it longer.
    """
    same_pair = (AuditEvent.email == email,
                 AuditEvent.ip.is_(None) if ip is None else AuditEvent.ip == ip)
    return _failures_retry_after(db, same_pair, same_pair)


def _wide_login_retry_after(db: Session, email: str, ip: str | None) -> int:
    """Seconds to wait under the two wider limits (#189), or 0: too many
    failed sign-ins for this email from all addresses together, or from
    this address across all emails, within LOGIN_WINDOW_MINUTES. Plain
    counts, unlike the per-pair limit: a correct password doesn't clear
    them, since the person failing and the person succeeding may differ."""
    window = timedelta(minutes=LOGIN_WINDOW_MINUTES)
    now = datetime.utcnow()
    recent = (AuditEvent.event == "login_failed", AuditEvent.created_at > now - window)

    def oldest_counted(limit: int, *who):
        times = [t for (t,) in db.query(AuditEvent.created_at).filter(*recent, *who)
                 .order_by(AuditEvent.created_at.desc()).limit(limit).all()]
        return times[-1] if len(times) >= limit else None

    blocked_since = [t for t in (
        oldest_counted(LOGIN_MAX_FAILURES_PER_EMAIL, AuditEvent.email == email),
        oldest_counted(LOGIN_MAX_FAILURES_PER_ADDRESS, AuditEvent.ip == ip) if ip else None,
    ) if t is not None]
    if not blocked_since:
        return 0
    return max(1, math.ceil((max(blocked_since) + window - now).total_seconds()))


def _registration_retry_after(db: Session, ip: str | None) -> int:
    """Seconds until this address may register again, or 0 (#189): each new
    user costs a password hash, and each wrong registration code is a guess."""
    if ip is None:
        return 0
    hour = timedelta(hours=1)
    now = datetime.utcnow()
    times = [t for (t,) in db.query(AuditEvent.created_at)
             .filter(AuditEvent.event.in_(("user_registered", "registration_refused")),
                     AuditEvent.ip == ip, AuditEvent.created_at > now - hour)
             .order_by(AuditEvent.created_at.desc()).limit(REGISTRATIONS_PER_HOUR).all()]
    if len(times) < REGISTRATIONS_PER_HOUR:
        return 0
    return max(1, math.ceil((times[-1] + hour - now).total_seconds()))


def _code_retry_after(db: Session, user: User) -> int:
    """Seconds until this user may try a two-factor code again, or 0.

    Counted per user, from any address (#165): a code has only a million
    values, so someone who has the password mustn't get a fresh set of tries
    from every address they can reach. Same numbers as the password limit.
    """
    own = (AuditEvent.user_id == user.id,)
    return _failures_retry_after(
        db, own, own + (AuditEvent.detail.like("%" + WRONG_CODE),))


def _failures_retry_after(db: Session, ok_filters: tuple, failed_filters: tuple) -> int:
    """The counting behind both limits: the last LOGIN_MAX_FAILURES
    `login_failed` rows matching `failed_filters`, since the last `login`
    matching `ok_filters`."""
    window = timedelta(minutes=LOGIN_WINDOW_MINUTES)
    now = datetime.utcnow()
    last_ok = (db.query(func.max(AuditEvent.created_at))
               .filter(AuditEvent.event == "login", *ok_filters).scalar())
    q = (db.query(AuditEvent.created_at)
         .filter(AuditEvent.event == "login_failed", *failed_filters,
                 AuditEvent.created_at > now - 2 * window))
    if last_ok is not None:
        q = q.filter(AuditEvent.created_at > last_ok)
    times = [t for (t,) in q.order_by(AuditEvent.created_at.desc())
             .limit(LOGIN_MAX_FAILURES).all()]
    if len(times) < LOGIN_MAX_FAILURES or times[0] - times[-1] > window:
        return 0
    remaining = (times[0] + window - now).total_seconds()
    return math.ceil(remaining) if remaining > 0 else 0


def _refuse_blocked(db: Session, request: Request, wait: int, email: str,
                    user: User | None = None) -> None:
    """Log a sign-in try made during a block and answer 429."""
    record_event(db, "login_blocked", request, user=user, email=email)
    minutes = math.ceil(wait / 60)
    raise HTTPException(
        429,
        f"Too many failed sign-ins. Try again in {minutes} minute{'s' if minutes != 1 else ''}.",
        headers={"Retry-After": str(wait)})


# ---------- Limits on what's accepted (security-fixes phase 2, #185) ----------
# A password that's typed back for checking: far longer than any real one
# (new ones stop at 128), short enough to cost nothing.
PASSWORD_CHECK_MAX = 1024
EMAIL_MAX = 320              # users.email's column
USER_NAME_MAX = 255          # users.name's column
ACCOUNT_NAME_MAX = 120
DESCRIPTION_MAX = 500
CATEGORY_NAME_MAX = 80       # categories.name's column
# A day's forecast is cheap, a few million of them isn't.
FORECAST_MAX_DAYS = 3660
# An amount is a real number of a size money comes in: never NaN or
# Infinity, which every page showing the account would then choke on.
Money = Annotated[float, Field(ge=-1e12, le=1e12, allow_inf_nan=False)]
RECURRING_FREQUENCIES = ("monthly_day", "weekly", "biweekly")


def _check_window(start: date, end: date) -> None:
    if end < start:
        raise HTTPException(400, "end must be on or after start")
    if (end - start).days > FORECAST_MAX_DAYS:
        raise HTTPException(400, f"The window can't be longer than {FORECAST_MAX_DAYS} days")


@app.exception_handler(RequestValidationError)
async def _validation_error(request: Request, exc: RequestValidationError):
    """FastAPI's own 422, except that a value JSON can't carry (NaN,
    Infinity) is given as text: the stock handler answers 500 on those,
    while trying to quote the bad input back (#185)."""
    def clean(value):
        if isinstance(value, float) and not math.isfinite(value):
            return str(value)
        if isinstance(value, dict):
            return {k: clean(v) for k, v in value.items()}
        if isinstance(value, (list, tuple)):
            return [clean(v) for v in value]
        return value
    return JSONResponse({"detail": clean(jsonable_encoder(exc.errors()))}, status_code=422)


# ---------- Local auth schemas ----------
class RegisterIn(BaseModel):
    email: str = Field(max_length=EMAIL_MAX)
    password: str = Field(min_length=8, max_length=128)
    name: str | None = Field(default=None, max_length=USER_NAME_MAX)
    # Needed when the instance sets REGISTRATION_CODE (#183).
    registration_code: str | None = Field(default=None, max_length=200)


class LoginIn(BaseModel):
    email: str = Field(max_length=EMAIL_MAX)
    password: str = Field(max_length=PASSWORD_CHECK_MAX)


# --- App title (admin-customizable) -----------------------------------------
# The display name shown in the browser tab and in the UI header / login card.
# Stored as an AdminSetting row so admins can rename the instance without
# redeploying. Default is "WalletWeather".
APP_TITLE_KEY = "app_title"
APP_TITLE_DEFAULT = "WalletWeather"
APP_TITLE_MAX_LEN = 80


def get_app_title(db: Session) -> str:
    # Demo mode forces a distinctive title so it's obvious the instance is
    # ephemeral. This wins over any admin-customized value.
    if DEMO_MODE:
        return DEMO_APP_TITLE
    row = db.get(AdminSetting, APP_TITLE_KEY)
    if row and row.value:
        return row.value
    return APP_TITLE_DEFAULT


@app.get("/api/auth/config")
def auth_config(db: Session = Depends(get_db)):
    """Public endpoint so the frontend knows which login methods to show."""
    return {
        "google_enabled": GOOGLE_ENABLED,
        "registration_enabled": ALLOW_REGISTRATION,
        # The sign-up form shows a code field when this is true (#183).
        "registration_code_required": bool(REGISTRATION_CODE),
        "demo_mode": DEMO_MODE,
        "demo_email": DEMO_ADMIN_EMAIL if DEMO_MODE else None,
        "demo_password": DEMO_ADMIN_PASSWORD if DEMO_MODE else None,
        "app_version": APP_VERSION,
        "schema_version": SCHEMA_VERSION,
        "app_title": get_app_title(db),
    }


@app.get("/api/version")
def version_info():
    """Version info for the About dialog / footer. Public, no auth required."""
    return {
        "app_version": APP_VERSION,
        "schema_version": SCHEMA_VERSION,
    }


@app.post("/api/auth/register")
def register(payload: RegisterIn, request: Request, db: Session = Depends(get_db)):
    if not ALLOW_REGISTRATION:
        raise HTTPException(403, "Registration is disabled")
    email = payload.email.strip().lower()
    if not _email_ok(email):
        raise HTTPException(400, "Invalid email")
    if ALLOWED_EMAILS and email not in ALLOWED_EMAILS:
        raise HTTPException(403, "This email is not authorized for this app")
    wait = _registration_retry_after(db, client_ip(request))
    if wait:
        minutes = math.ceil(wait / 60)
        raise HTTPException(
            429, "Too many new users from this address. "
                 f"Try again in {minutes} minute{'s' if minutes != 1 else ''}.",
            headers={"Retry-After": str(wait)})
    try:
        _check_registration_code(payload.registration_code)
    except HTTPException:
        record_event(db, "registration_refused", request, detail="wrong code")
        raise
    _refuse_reserved_address(db, email)
    if db.query(User).filter_by(email=email).first():
        raise HTTPException(409, "An account with that email already exists")
    user = _create_password_user(db, email, payload.name, payload.password)
    # By number, like every event about someone (#139), and it's the
    # address that the limit above counts.
    record_event(db, "user_registered", request, detail=f"user #{user.id}")
    _start_session(request, user)
    return {"id": user.id, "email": user.email}


# Registering proves nothing about who owns an address (#183, decided
# 2026-11-16): the code keeps strangers out, and the addresses that carry
# power here can't be claimed by whoever types them first.
RESERVED_ADDRESS_MESSAGE = ("This address can't be registered here. "
                            "Ask an administrator to add it.")


def _check_registration_code(code: str | None) -> None:
    if not REGISTRATION_CODE:
        return
    given = (code or "").strip().encode("utf-8")
    if not secrets.compare_digest(given, REGISTRATION_CODE.encode("utf-8")):
        raise HTTPException(403, "That registration code isn't right. "
                                 "Ask whoever runs this instance for it.")


def _refuse_reserved_address(db: Session, email: str) -> None:
    """Addresses nobody may register for themselves: the demo's own domain
    (its users skip the notice and required two-factor, and are deleted at
    the next start), and an administrator's address once the instance has a
    user. The first user of a new instance may be its administrator; after
    that an administrator adds the others (POST /api/admin/users)."""
    if is_demo_email(email):
        raise HTTPException(403, RESERVED_ADDRESS_MESSAGE)
    if email in ADMIN_EMAILS and db.query(User.id).first() is not None:
        raise HTTPException(403, RESERVED_ADDRESS_MESSAGE)


def _create_password_user(db: Session, email: str, name: str | None, password: str) -> User:
    user = User(email=email, name=(name or "").strip() or email.split("@")[0],
                password_hash=hash_password(password))
    db.add(user)
    db.commit()
    db.refresh(user)
    seed_default_categories(db, user)
    return user


def _password_sign_in(db: Session, request: Request, email_in: str, password: str,
                      via: str) -> User:
    """Check an email and password for /api/auth/login and /api/auth/token,
    under one rate limit and one sign-in log, and return the user or raise
    429, 401 or 403. `via` goes in the events' detail ("password", "token")."""
    email = email_in.strip().lower()[:320]
    ip = client_ip(request)
    # Too many recent failures for this email from this address: refuse
    # without checking the password (a right one too), whether or not the
    # account exists, so the answer never says which emails have one.
    wait = _login_retry_after(db, email, ip) or _wide_login_retry_after(db, email, ip)
    if wait:
        _refuse_blocked(db, request, wait, email)
    user = db.query(User).filter_by(email=email).first()
    # Constant-ish failure path: still verify against a dummy hash to reduce timing leaks
    if not user or not user.password_hash:
        bcrypt.checkpw(b"x", b"$2b$12$" + b"." * 53)
        record_event(db, "login_failed", request, user=user, email=email,
                     detail=via if user is None else via + "; no password set")
        raise HTTPException(401, "Invalid email or password")
    if not verify_password(password, user.password_hash):
        record_event(db, "login_failed", request, user=user, email=email, detail=via)
        raise HTTPException(401, "Invalid email or password")
    if user.disabled:
        record_event(db, "login_failed", request, user=user, email=email,
                     detail=via + "; account disabled")
        raise HTTPException(403, "Account disabled")
    # With two-factor on, the password is only half of it: no "login" is
    # logged yet (the caller asks for the code), so a right password doesn't
    # clear the count of wrong codes either (#165).
    if user.totp_enabled_at is None:
        record_event(db, "login", request, user=user, email=email, detail=via)
    return user


@app.post("/api/auth/login")
def local_login(payload: LoginIn, request: Request, db: Session = Depends(get_db)):
    user = _password_sign_in(db, request, payload.email, payload.password, "password")
    if user.totp_enabled_at is not None and _remembered_browser(db, request, user):
        # A browser the user asked not to be asked on (#167): the password
        # is enough here until the remembering runs out or is forgotten.
        request.session.clear()
        _start_session(request, user)
        record_event(db, "login", request, user=user, detail="password; remembered browser")
        return {"id": user.id, "email": user.email}
    if user.totp_enabled_at is not None:
        # Not signed in yet: the browser has TWO_FACTOR_STEP_MINUTES to send
        # the code to /api/auth/login/two-factor.
        request.session.clear()
        request.session["2fa_uid"] = user.id
        request.session["2fa_at"] = int(time.time())
        record_event(db, "two_factor_asked", request, user=user, detail="password")
        return {"two_factor_required": True}
    _start_session(request, user)
    return {"id": user.id, "email": user.email}


# ---------- Two-factor sign-in: the code step (#165) ----------
# Decided 2026-11-15 (Plans/two-factor.md): the code is asked after a
# password only (Google runs its own two-step check), and ten one-time
# recovery codes or an admin get someone back in without their phone.
TWO_FACTOR_STEP_MINUTES = 5
# How a wrong code's login_failed row ends; _code_retry_after counts these.
WRONG_CODE = "wrong code"


class TwoFactorCodeIn(BaseModel):
    code: str = Field(max_length=40)


class TwoFactorSignInIn(TwoFactorCodeIn):
    # "Don't ask on this browser for 30 days" (#167).
    remember: bool = False


# ---------- Two-factor sign-in: remembered browsers (#167) ----------
# Decided 2026-11-15 (Plans/two-factor.md, open question 3): a browser is
# remembered for 30 days, and switching two-factor off, changing the
# password or an admin's switch-off forgets every remembered browser. The
# browser holds a random cookie of its own; the server keeps its SHA-256, so
# a copy of the database can't be turned into a cookie.
REMEMBER_BROWSER_DAYS = 30
REMEMBER_COOKIE = "ww_remember"


def _browser_label(user_agent: str | None) -> str:
    """A short name for a browser, like "Safari on iPhone", so the user can
    tell their remembered browsers apart. Only this is kept, never the
    user-agent string itself."""
    ua = user_agent or ""
    if "Edg" in ua:
        browser = "Edge"
    elif "Firefox/" in ua or "FxiOS" in ua:
        browser = "Firefox"
    elif "Chrome/" in ua or "CriOS" in ua:
        browser = "Chrome"
    elif "Safari/" in ua:
        browser = "Safari"
    else:
        browser = "A browser"
    for marker, system in (("iPhone", "iPhone"), ("iPad", "iPad"), ("Android", "Android"),
                           ("CrOS", "ChromeOS"), ("Windows", "Windows"),
                           ("Mac OS X", "macOS"), ("Macintosh", "macOS"), ("Linux", "Linux")):
        if marker in ua:
            return f"{browser} on {system}"
    return browser


def _cookie_is_secure(request: Request) -> bool:
    """Mark the cookie Secure when the browser reached us over HTTPS, either
    directly or through a proxy that says so (Cloudflare does)."""
    if request.url.scheme == "https":
        return True
    return TRUST_PROXY_HEADERS and request.headers.get("x-forwarded-proto", "").lower() == "https"


def _remember_hash(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def _remembered_browser(db: Session, request: Request, user: User) -> RememberedBrowser | None:
    """This browser's remembering for `user`, if it has one that's current,
    marked as used just now."""
    token = request.cookies.get(REMEMBER_COOKIE)
    if not token or len(token) > 100:
        return None
    row = (db.query(RememberedBrowser)
           .filter(RememberedBrowser.token_hash == _remember_hash(token),
                   RememberedBrowser.user_id == user.id,
                   RememberedBrowser.expires_at > datetime.utcnow())
           .first())
    if row:
        row.last_used_at = datetime.utcnow()
        db.commit()
    return row


def _remember_browser(db: Session, request: Request, response: Response, user: User) -> None:
    """Remember this browser for `user` for REMEMBER_BROWSER_DAYS: a new
    cookie, and its hash on the server. The user's lapsed rows go too."""
    now = datetime.utcnow()
    db.query(RememberedBrowser).filter(
        RememberedBrowser.user_id == user.id,
        RememberedBrowser.expires_at <= now).delete(synchronize_session=False)
    token = secrets.token_urlsafe(32)
    db.add(RememberedBrowser(
        user_id=user.id, token_hash=_remember_hash(token),
        label=_browser_label(request.headers.get("user-agent")),
        created_at=now, last_used_at=now,
        expires_at=now + timedelta(days=REMEMBER_BROWSER_DAYS)))
    db.commit()
    response.set_cookie(REMEMBER_COOKIE, token, max_age=REMEMBER_BROWSER_DAYS * 86400,
                        httponly=True, samesite="lax", secure=_cookie_is_secure(request),
                        path="/")


def _forget_browsers(db: Session, user: User) -> int:
    """Forget every browser remembered for `user`; the caller commits.
    Returns how many there were."""
    return (db.query(RememberedBrowser).filter_by(user_id=user.id)
            .delete(synchronize_session=False))


def _use_two_factor_code(db: Session, user: User, code: str) -> str | None:
    """Check a 6-digit code or a recovery code for a user who has two-factor
    on, and spend it. Returns "code", "recovery code", or None when it's
    wrong or was already used. Each is spent by one UPDATE, so two requests
    with the same code can't both win."""
    text = "".join(code.split())
    if twofactor.looks_like_code(text):
        step = twofactor.matching_step(user.totp_secret, text, after_step=user.totp_last_step)
        if step is None:
            return None
        won = (db.query(User)
               .filter(User.id == user.id,
                       (User.totp_last_step.is_(None)) | (User.totp_last_step < step))
               .update({User.totp_last_step: step}, synchronize_session=False))
        db.commit()
        db.refresh(user)
        return "code" if won else None
    won = (db.query(RecoveryCode)
           .filter(RecoveryCode.user_id == user.id, RecoveryCode.used_at.is_(None),
                   RecoveryCode.code_hash == twofactor.hash_recovery_code(text))
           .update({RecoveryCode.used_at: datetime.utcnow()}, synchronize_session=False))
    db.commit()
    return "recovery code" if won else None


def _recovery_codes_left(db: Session, user: User) -> int:
    return db.query(RecoveryCode).filter_by(user_id=user.id, used_at=None).count()


@app.post("/api/auth/login/two-factor")
def local_login_two_factor(payload: TwoFactorSignInIn, request: Request, response: Response,
                           db: Session = Depends(get_db)):
    """The second step of a password sign-in: a code from the authenticator
    app, or a recovery code. Only after /api/auth/login accepted the
    password in this browser, within TWO_FACTOR_STEP_MINUTES."""
    uid, started = request.session.get("2fa_uid"), request.session.get("2fa_at")
    user = db.get(User, uid) if uid else None
    if (not user or user.totp_enabled_at is None or not isinstance(started, int)
            or time.time() - started > TWO_FACTOR_STEP_MINUTES * 60):
        request.session.clear()
        raise HTTPException(401, "That sign-in has expired. Enter your email and password again.")
    if user.disabled:
        request.session.clear()
        raise HTTPException(403, "Account disabled")
    wait = max(_login_retry_after(db, user.email, client_ip(request)),
               _code_retry_after(db, user))
    if wait:
        _refuse_blocked(db, request, wait, user.email, user=user)
    how = _use_two_factor_code(db, user, payload.code)
    if not how:
        record_event(db, "login_failed", request, user=user, detail="password; " + WRONG_CODE)
        raise HTTPException(401, "That code isn't right. Check your authenticator app and try again.")
    request.session.clear()
    _start_session(request, user)
    left = _recovery_codes_left(db, user)
    if how == "recovery code":
        record_event(db, "recovery_code_used", request, user=user, detail=f"{left} left")
    record_event(db, "login", request, user=user, detail="password; " + how)
    if payload.remember:
        _remember_browser(db, request, response, user)
        record_event(db, "browser_remembered", request, user=user,
                     detail=f"{REMEMBER_BROWSER_DAYS} days")
    return {"id": user.id, "email": user.email, "recovery_codes_left": left,
            "remembered": payload.remember}


# Password sign-in for apps (#43): the native apps swap an email and password
# for an API token rather than keeping a session cookie. Decided 2026-11-15:
# only read or full access (never admin), and 90 days unless the app asks for
# 30, 365 or never (null). Same rate limit and sign-in log as the web sign-in;
# no session cookie is set. Google-only accounts have no password, so they get
# the same 401 as a wrong password and make tokens in Settings instead.
APP_TOKEN_ACCESS_LEVELS = ("read", "full")
APP_TOKEN_DEFAULT_DAYS = 90


class AppTokenIn(BaseModel):
    email: str = Field(max_length=EMAIL_MAX)
    password: str = Field(max_length=PASSWORD_CHECK_MAX)
    name: str = Field(max_length=80)
    access: str
    expires_in_days: int | None = APP_TOKEN_DEFAULT_DAYS
    # For a user with two-factor sign-in on (#166): the code from their
    # authenticator app, or a recovery code. Sent with the email and password
    # again once the first try was answered with two_factor_required.
    code: str | None = Field(default=None, max_length=40)


@app.post("/api/auth/token")
def app_token(payload: AppTokenIn, request: Request, db: Session = Depends(get_db)):
    """Email + password → a new API token, shown once. For native apps."""
    name = payload.name.strip()
    if not name:
        raise HTTPException(400, "Name is required")
    if payload.access == "admin":
        raise HTTPException(403, "Admin tokens can only be made in Settings")
    if payload.access not in APP_TOKEN_ACCESS_LEVELS:
        raise HTTPException(400, "Access must be read or full")
    _check_expiry(payload.expires_in_days)
    user = _password_sign_in(db, request, payload.email, payload.password, "token")
    if must_set_up_two_factor(db, user):
        # Required by an admin and not set up yet (#168): no token until it is.
        record_event(db, "two_factor_asked", request, user=user, detail="token; set-up required")
        raise HTTPException(403, TWO_FACTOR_SETUP_MESSAGE)
    if user.totp_enabled_at is not None:
        # The password was right, and that's half of it (#166). Both answers
        # below carry two_factor_required so an app can show a code field;
        # the sentence is for apps from before it existed.
        def code_needed(detail: str) -> JSONResponse:
            return JSONResponse({"detail": detail, "two_factor_required": True}, status_code=403)
        if not (payload.code or "").strip():
            record_event(db, "two_factor_asked", request, user=user, detail="token")
            return code_needed("This account has two-factor sign-in on. Type the code from your "
                               "authenticator app, or sign in through the browser.")
        wait = _code_retry_after(db, user)
        if wait:
            _refuse_blocked(db, request, wait, user.email, user=user)
        how = _use_two_factor_code(db, user, payload.code)
        if not how:
            record_event(db, "login_failed", request, user=user, detail="token; " + WRONG_CODE)
            return code_needed(WRONG_CODE_MESSAGE)
        if how == "recovery code":
            record_event(db, "recovery_code_used", request, user=user,
                         detail=f"{_recovery_codes_left(db, user)} left")
        record_event(db, "login", request, user=user, detail="token; " + how)
    token, row = _make_token(db, user, name, payload.access, payload.expires_in_days)
    record_event(db, "token_created", request, user=user,
                 detail=f"token #{row.id}, {row.access}; by sign-in")
    return {**_token_json(row), "token": token,
            "user": {"id": user.id, "email": user.email}}


def _safe_next(path: str | None) -> str | None:
    """Where Google sign-in may return to besides "/": only the "sign in an
    app" page (#87), so `next` can't send anyone off the site."""
    if path and (path == "/app-sign-in" or path.startswith("/app-sign-in?")) \
            and "\\" not in path:
        return path
    return None


@app.get("/auth/login")
async def google_login(request: Request, next: str | None = None):
    if not GOOGLE_ENABLED:
        raise HTTPException(404, "Google login is not configured")
    # Kept in the session across Google's redirect; the callback goes there.
    request.session.pop("next", None)
    if _safe_next(next):
        request.session["next"] = next
    redirect_uri = f"{APP_BASE_URL}/auth/callback"
    return await oauth.google.authorize_redirect(request, redirect_uri)


@app.get("/auth/callback")
async def auth_callback(request: Request, db: Session = Depends(get_db)):
    if not GOOGLE_ENABLED:
        raise HTTPException(404, "Google login is not configured")
    token = await oauth.google.authorize_access_token(request)
    info = token.get("userinfo") or {}
    sub = info.get("sub")
    email = (info.get("email") or "").lower()
    if not sub or not email:
        raise HTTPException(400, "Google did not return an identity")
    # Only an address Google has checked may match, link to or create a
    # user here (#183).
    if info.get("email_verified") is not True:
        raise HTTPException(403, "Google hasn't verified this email address")
    if ALLOWED_EMAILS and email not in ALLOWED_EMAILS:
        raise HTTPException(403, "This email is not authorized for this app")
    # Match by google_sub first, then by email (link existing local account)
    user = db.query(User).filter_by(google_sub=sub).one_or_none()
    is_new = False
    if not user:
        user = db.query(User).filter_by(email=email).one_or_none()
        if user:
            user.google_sub = sub  # link Google to existing local account
            if user.password_hash is not None:
                # Whoever registered this address with a password proved
                # nothing; Google has. Decided 2026-11-16 (#189, docs/dev/
                # decisions/security-fixes.md): the password goes, and with
                # it two-factor, every session and every API token, so only
                # the address's Google owner is left holding the user.
                user.password_hash = None
                _clear_two_factor(db, user)
                _end_other_sessions(None, user)
                (db.query(ApiToken)
                 .filter(ApiToken.owner_id == user.id, ApiToken.revoked_at.is_(None))
                 .update({ApiToken.revoked_at: datetime.utcnow()}, synchronize_session=False))
                db.commit()
                record_event(db, "password_removed", request, user=user,
                             detail="first Google sign-in")
        else:
            if not ALLOW_REGISTRATION:
                raise HTTPException(403, "Registration is disabled")
            # There's nowhere to type a registration code on the way back
            # from Google, so where one is asked for, Google makes new
            # users only for addresses on the allow-list (#183).
            if REGISTRATION_CODE and email not in ALLOWED_EMAILS:
                raise HTTPException(403, "Registration here needs a code. Register with "
                                         "an email and password, then sign in with Google.")
            if is_demo_email(email):
                raise HTTPException(403, RESERVED_ADDRESS_MESSAGE)
            user = User(google_sub=sub, email=email, name=info.get("name"))
            db.add(user)
            is_new = True
    db.commit()
    db.refresh(user)
    if user.disabled:
        record_event(db, "login_failed", request, user=user, email=email,
                     detail="google; account disabled")
        raise HTTPException(403, "Account disabled")
    if is_new:
        seed_default_categories(db, user)
    record_event(db, "login", request, user=user, email=email,
                 detail="google; new user" if is_new else "google")
    _start_session(request, user)
    return RedirectResponse(_safe_next(request.session.pop("next", None)) or "/")


@app.post("/auth/logout")
async def logout(request: Request):
    request.session.clear()
    return {"ok": True}


# ---------- Signing in an app (ios-app phase 1, #87) ----------
# The native app opens /app-sign-in in the phone's system sign-in sheet. The
# sheet is a real browser, so Cloudflare Access (when it's in front), Google
# and the web app's own sign-in all work there as they do in Safari. Once the
# person is signed in and taps Allow, the page asks POST /api/app-sign-in for
# a one-time code and sends the sheet to walletweather://signed-in with it.
# The app swaps the code for a token at POST /api/app-sign-in/token, proving
# with its PKCE verifier that it's the app that opened the sheet.
#
# Cloudflare: the sheet's Cloudflare sign-in stays in the sheet, so the app's
# own requests would be turned away. Cloudflare passes the signed-in
# person's Access token to this server on every request
# (Cf-Access-Jwt-Assertion), so the redirect carries it back to the app,
# which sends it with its requests as Cloudflare's own CF_Authorization
# cookie. GET /app-sign-in/cloudflare does only that part, for when the
# app's Cloudflare sign-in ends or it was connected another way.
APP_CALLBACK = "walletweather://"
APP_SIGN_IN_CODE_MINUTES = 5
_B64URL = re.compile(r"^[A-Za-z0-9_-]+$")
_JWT = re.compile(r"^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$")


def _cloudflare_token(request: Request) -> str | None:
    """The Cloudflare Access token Cloudflare stamped on this request, or
    None when no Cloudflare is in front (or it doesn't look like one)."""
    jwt = (request.headers.get("cf-access-jwt-assertion")
           or request.cookies.get("CF_Authorization") or "").strip()
    return jwt if len(jwt) <= 8192 and _JWT.match(jwt) else None


def _app_callback(path: str, request: Request, **params: str) -> str:
    """walletweather://<path>?..., with the Cloudflare token when there is one."""
    cf = _cloudflare_token(request)
    if cf:
        params["cf"] = cf
    return APP_CALLBACK + path + "?" + urlencode(params)


def _check_state(state: str) -> None:
    if not (8 <= len(state) <= 128 and _B64URL.match(state)):
        raise HTTPException(400, "state must be 8 to 128 letters, digits, - or _")


@app.get("/app-sign-in/cloudflare")
def app_sign_in_cloudflare(request: Request, state: str):
    """Send the sheet back to the app with this request's Cloudflare token.
    Reaching this at all means Cloudflare let the person in. No WalletWeather
    sign-in is needed: the token is the person's own, from their own sheet."""
    _check_state(state)
    if not _cloudflare_token(request):
        return RedirectResponse(APP_CALLBACK + "cloudflare?" + urlencode(
            {"state": state, "error": "no-cloudflare"}))
    return RedirectResponse(_app_callback("cloudflare", request, state=state))


class AppSignInIn(BaseModel):
    name: str = Field(max_length=80)
    access: str
    code_challenge: str
    state: str
    # A current code from the authenticator app, for a user with two-factor
    # on (#169). Not to be confused with the one-time code this answers with.
    two_factor_code: str | None = Field(default=None, max_length=40)


@app.post("/api/app-sign-in")
def app_sign_in(payload: AppSignInIn, request: Request,
                user: User = Depends(current_session_user),
                db: Session = Depends(get_db)):
    """Allow an app in: a one-time code, returned inside the walletweather://
    address the page sends the sheet to. From a browser session only."""
    name = payload.name.strip()
    if not name:
        raise HTTPException(400, "Name is required")
    if payload.access not in APP_TOKEN_ACCESS_LEVELS:
        raise HTTPException(400, "Access must be read or full")
    if not (len(payload.code_challenge) == 43 and _B64URL.match(payload.code_challenge)):
        raise HTTPException(400, "code_challenge must be a base64url SHA-256")
    _check_state(payload.state)
    _confirm_code_for(db, request, user, payload.two_factor_code, "app sign-in")
    code = secrets.token_urlsafe(32)
    db.add(AppSignInCode(
        code_hash=_hash_token(code), user_id=user.id, name=name,
        access=payload.access, code_challenge=payload.code_challenge,
        expires_at=datetime.utcnow() + timedelta(minutes=APP_SIGN_IN_CODE_MINUTES)))
    db.commit()
    return {"redirect_url": _app_callback("signed-in", request,
                                          code=code, state=payload.state)}


class AppSignInTokenIn(BaseModel):
    code: str = Field(max_length=200)
    code_verifier: str = Field(max_length=200)


@app.post("/api/app-sign-in/token")
def app_sign_in_token(payload: AppSignInTokenIn, request: Request,
                      db: Session = Depends(get_db)):
    """A one-time code and its PKCE verifier → a new API token, shown once.
    The token is named as the page showed it, so it's listed (and can be
    revoked) in Settings. A code works once: any swap spends it."""
    bad = HTTPException(400, "This sign-in has expired or was already used. Sign in again.")
    row = (db.query(AppSignInCode)
           .filter_by(code_hash=_hash_token(payload.code)).first())
    now = datetime.utcnow()
    if not row or row.used_at is not None or row.expires_at <= now:
        raise bad
    row.used_at = now
    db.commit()
    digest = hashlib.sha256(payload.code_verifier.encode("ascii", "replace")).digest()
    challenge = base64.urlsafe_b64encode(digest).rstrip(b"=").decode("ascii")
    if not secrets.compare_digest(challenge, row.code_challenge):
        raise bad
    user = db.get(User, row.user_id)
    if not user or user.disabled:
        raise bad
    token, tok = _make_token(db, user, row.name, row.access, APP_TOKEN_DEFAULT_DAYS)
    record_event(db, "token_created", request, user=user,
                 detail=f"token #{tok.id}, {tok.access}; by app sign-in")
    return {**_token_json(tok), "token": token,
            "user": {"id": user.id, "email": user.email}}


def _notice_required(user: User) -> bool:
    """True until the user has acknowledged the "Important notice".

    Demo users are never asked: the demo is reset hourly, and its login is
    shared by everyone who tries it.
    """
    return user.notice_ack_at is None and not is_demo_email(user.email)


def _iso(dt: datetime | None) -> str | None:
    return dt.isoformat() + "Z" if dt else None


@app.get("/api/me")
def me(request: Request, user: User = Depends(current_user),
       db: Session = Depends(get_db)):
    token = request.state.api_token
    two_factor = user.totp_enabled_at is not None
    return {"id": user.id, "email": user.email, "name": user.name,
            # What this token may do (read, full or admin), or null when
            # signed in through a browser: the iOS app hides editing under a
            # read-only token (#88).
            "token_access": token.access if token else None,
            "is_admin": is_admin(user),
            "theme_preference": user.theme_preference,
            "chart_position": user.chart_position,
            "recurring_position": user.recurring_position,
            "notice_required": _notice_required(user),
            "notice_acknowledged_at": _iso(user.notice_ack_at),
            "has_password": user.password_hash is not None,
            # Two-factor sign-in (#165): whether it's on, and how many
            # one-time recovery codes are unused.
            "two_factor_enabled": two_factor,
            # An admin requires two-factor and this user hasn't set it up
            # (#168): the web app shows only the set-up screen.
            "two_factor_setup_required": must_set_up_two_factor(db, user),
            "recovery_codes_left": _recovery_codes_left(db, user) if two_factor else 0}


@app.post("/api/me/acknowledge-notice")
def acknowledge_notice(user: User = Depends(current_user),
                       db: Session = Depends(get_db)):
    """Record that the user has read and agreed to the "Important notice".

    Safe to call again: the first acknowledgement's time is kept.
    """
    if user.notice_ack_at is None:
        user.notice_ack_at = datetime.utcnow()
        db.commit()
    return {"ok": True,
            "notice_required": False,
            "notice_acknowledged_at": _iso(user.notice_ack_at)}


# ---------- API tokens (#42) ----------
# Listed, made and revoked from a signed-in browser only (current_session_user).
# The token is returned once, by POST, and only its SHA-256 is stored.
class ApiTokenIn(BaseModel):
    name: str = Field(max_length=80)
    access: str
    # 30, 90 or 365; left out (or null) means the token never expires.
    expires_in_days: int | None = None
    # A current code, for a user with two-factor on (#169).
    code: str | None = Field(default=None, max_length=40)


def _token_json(t: ApiToken) -> dict:
    return {"id": t.id, "name": t.name, "access": t.access,
            "created_at": _iso(t.created_at), "revoked_at": _iso(t.revoked_at),
            "expires_at": _iso(t.expires_at), "last_used_at": _iso(t.last_used_at),
            "expired": t.expires_at is not None and t.expires_at <= datetime.utcnow()}


@app.get("/api/tokens")
def list_tokens(user: User = Depends(current_session_user),
                db: Session = Depends(get_db)):
    """The caller's tokens, newest first, revoked ones included."""
    rows = (db.query(ApiToken).filter_by(owner_id=user.id)
            .order_by(ApiToken.created_at.desc(), ApiToken.id.desc()).all())
    return [_token_json(t) for t in rows]


@app.post("/api/tokens")
def create_token(payload: ApiTokenIn, request: Request,
                 user: User = Depends(current_session_user),
                 db: Session = Depends(get_db)):
    """Make a token. The response is the only time `token` is shown."""
    name = payload.name.strip()
    if not name:
        raise HTTPException(400, "Name is required")
    if payload.access not in TOKEN_ACCESS_LEVELS:
        raise HTTPException(400, "Access must be read, full or admin")
    if payload.access == "admin" and not is_admin(user):
        raise HTTPException(403, "Only an admin can make an admin token")
    _check_expiry(payload.expires_in_days)
    _confirm_code_for(db, request, user, payload.code, "token")
    token, row = _make_token(db, user, name, payload.access, payload.expires_in_days)
    record_event(db, "token_created", request, user=user,
                 detail=f"token #{row.id}, {row.access}")
    return {**_token_json(row), "token": token}


def _check_expiry(days: int | None) -> None:
    if days is not None and days not in TOKEN_EXPIRY_DAYS:
        raise HTTPException(400, "Expiry must be 30, 90 or 365 days, or null for never")


def _make_token(db: Session, user: User, name: str, access: str,
                days: int | None) -> tuple[str, ApiToken]:
    """Store a new token for `user` and return (the token, its row). The
    token itself is never stored, only its SHA-256."""
    token = TOKEN_PREFIX + secrets.token_urlsafe(32)
    expires_at = datetime.utcnow() + timedelta(days=days) if days else None
    row = ApiToken(owner_id=user.id, name=name, access=access,
                   token_hash=_hash_token(token), expires_at=expires_at)
    db.add(row)
    db.commit()
    db.refresh(row)
    return token, row


# Declared before /api/tokens/{token_id}, which would otherwise take "current".
@app.delete("/api/tokens/current")
def revoke_current_token(request: Request, user: User = Depends(current_reader),
                         db: Session = Depends(get_db)):
    """End the API token this request is signed with, and nothing else (#145).

    The one thing a token may do to tokens: an app ends its own when it signs
    out. Any access level, read-only too, since ending itself gives nothing
    away. A browser session has no token to end: 400.
    """
    row = request.state.api_token
    if row is None:
        raise HTTPException(400, "Only an API token can end itself. Sign out instead.")
    row.revoked_at = datetime.utcnow()
    db.commit()
    record_event(db, "token_revoked", request, user=user, detail=f"token #{row.id}; by itself")
    return _token_json(row)


@app.delete("/api/tokens/{token_id}")
def revoke_token(token_id: int, request: Request,
                 user: User = Depends(current_session_user),
                 db: Session = Depends(get_db)):
    """Revoke one of the caller's tokens. It stops working at once. Safe to
    call again: the first revocation's time is kept."""
    row = db.get(ApiToken, token_id)
    if not row or row.owner_id != user.id:
        raise HTTPException(404, "Token not found")
    if row.revoked_at is None:
        row.revoked_at = datetime.utcnow()
        db.commit()
        record_event(db, "token_revoked", request, user=user, detail=f"token #{row.id}")
    return _token_json(row)


# Admin panel (#43): every user's tokens, and revoking any of them. Browser
# session only, like the caller's own token endpoints (current_session_admin).
@app.get("/api/admin/tokens")
def admin_list_tokens(user: User = Depends(current_session_admin),
                      db: Session = Depends(get_db)):
    """All tokens, newest first, with their owner's email."""
    rows = (db.query(ApiToken, User)
            .join(User, User.id == ApiToken.owner_id)
            .order_by(ApiToken.created_at.desc(), ApiToken.id.desc()).all())
    return [{**_token_json(t), "owner_id": u.id, "owner_email": u.email}
            for (t, u) in rows]


@app.delete("/api/admin/tokens/{token_id}")
def admin_revoke_token(token_id: int, request: Request,
                       user: User = Depends(current_session_admin),
                       db: Session = Depends(get_db)):
    """Revoke anyone's token. It stops working at once; safe to repeat."""
    row = db.get(ApiToken, token_id)
    if not row:
        raise HTTPException(404, "Token not found")
    if row.revoked_at is None:
        row.revoked_at = datetime.utcnow()
        db.commit()
        record_event(db, "token_revoked", request, user=user,
                     detail=f"token #{row.id} of {audit_target(user, row.owner_id)}")
    owner = db.get(User, row.owner_id)
    return {**_token_json(row), "owner_id": row.owner_id,
            "owner_email": owner.email if owner else None}


# ---------- Changing your own password (#133) ----------
class PasswordChangeIn(BaseModel):
    current_password: str = Field(max_length=PASSWORD_CHECK_MAX)
    new_password: str = Field(..., min_length=8, max_length=128)
    # A current code, for a user with two-factor on (#169).
    code: str | None = Field(default=None, max_length=40)


@app.post("/api/me/password")
def change_password(payload: PasswordChangeIn, request: Request,
                    user: User = Depends(current_session_user),
                    db: Session = Depends(get_db)):
    """Change the caller's own password, confirmed with the current one.
    Browser session only: a token can't change the password it can't see.
    A Google-only user has no password here; an admin can set one."""
    if is_demo_email(user.email):
        raise HTTPException(403, "The demo user's password can't be changed.")
    if not user.password_hash:
        raise HTTPException(400, "You sign in with Google, so there's no password to change.")
    if not verify_password(payload.current_password, user.password_hash):
        # 403, not 401: the session is fine, the confirmation isn't.
        raise HTTPException(403, "That password is incorrect.")
    _confirm_code_for(db, request, user, payload.code, "password change")
    user.password_hash = hash_password(payload.new_password)
    # A new password forgets every remembered browser (#167) and signs out
    # every other one (#186).
    _forget_browsers(db, user)
    _end_other_sessions(request, user)
    db.commit()
    record_event(db, "password_changed", request, user=user)
    return {"ok": True}


@app.post("/api/me/sessions/end-others")
def end_other_sessions(request: Request, user: User = Depends(current_session_user),
                       db: Session = Depends(get_db)):
    """Sign the caller out of every browser but this one (#186). API tokens
    are separate: they're listed, and revoked, in Settings."""
    _end_other_sessions(request, user)
    db.commit()
    record_event(db, "sessions_ended", request, user=user, detail="own other browsers")
    return {"ok": True}


# ---------- Two-factor sign-in: your own set-up (#165) ----------
# Browser session only, like changing the password. Every step that turns it
# on or off, or shows new recovery codes, asks for the password again, so a
# browser left signed in can't be used to lock its owner out.
class TwoFactorSetupIn(BaseModel):
    password: str = Field(max_length=PASSWORD_CHECK_MAX)


class TwoFactorConfirmIn(BaseModel):
    password: str = Field(max_length=PASSWORD_CHECK_MAX)
    code: str = Field(max_length=40)


WRONG_CODE_MESSAGE = "That code isn't right. Check your authenticator app and try again."
CODE_USED_MESSAGE = ("That code has already been used. "
                     "Wait for the next one in your authenticator app.")
CODE_NEEDED_MESSAGE = ("Two-factor sign-in is on: type the code from your authenticator app, "
                       "or a recovery code, to confirm.")


def _confirm_code_for(db: Session, request: Request, user: User, code: str | None,
                      action: str) -> None:
    """For a user with two-factor on, a current code (or a recovery code)
    before a sensitive action (#169), every time: decided 2026-11-15, a code
    typed earlier doesn't count. Wrong codes count toward the same per-user
    limit as the sign-in's code step. Does nothing for a user without it."""
    if user.totp_enabled_at is None:
        return
    if not (code or "").strip():
        raise HTTPException(403, CODE_NEEDED_MESSAGE)
    wait = _code_retry_after(db, user)
    if wait:
        record_event(db, "login_blocked", request, user=user, detail=action)
        minutes = math.ceil(wait / 60)
        raise HTTPException(
            429, f"Too many wrong codes. Try again in {minutes} minute{'s' if minutes != 1 else ''}.",
            headers={"Retry-After": str(wait)})
    how = _use_two_factor_code(db, user, code)
    if not how:
        # Always asking means a code typed seconds ago (at sign-in, say) is
        # often still on the phone's screen; it works once, so say so rather
        # than call it wrong. It isn't a guess, so it isn't counted.
        text = "".join(code.split())
        if twofactor.looks_like_code(text) and twofactor.matching_step(user.totp_secret, text) is not None:
            raise HTTPException(403, CODE_USED_MESSAGE)
        record_event(db, "login_failed", request, user=user, detail=f"{action}; {WRONG_CODE}")
        raise HTTPException(403, WRONG_CODE_MESSAGE)
    if how == "recovery code":
        record_event(db, "recovery_code_used", request, user=user,
                     detail=f"{action}; {_recovery_codes_left(db, user)} left")


def _check_two_factor_password(user: User, password: str) -> None:
    if is_demo_email(user.email):
        raise HTTPException(403, "The demo user can't use two-factor sign-in.")
    if not user.password_hash:
        raise HTTPException(400, "You sign in with Google, which has its own two-step check.")
    if not verify_password(password, user.password_hash):
        # 403, not 401: the session is fine, the confirmation isn't.
        raise HTTPException(403, "That password is incorrect.")


def _new_recovery_codes(db: Session, user: User) -> list[str]:
    """Replace the user's recovery codes; the caller commits."""
    db.query(RecoveryCode).filter_by(user_id=user.id).delete(synchronize_session=False)
    codes = twofactor.new_recovery_codes()
    for code in codes:
        db.add(RecoveryCode(user_id=user.id, code_hash=twofactor.hash_recovery_code(code)))
    return codes


def _clear_two_factor(db: Session, user: User) -> None:
    """Switch two-factor off: the key, the recovery codes and the
    remembered browsers go."""
    user.totp_secret = None
    user.totp_enabled_at = None
    user.totp_last_step = None
    db.query(RecoveryCode).filter_by(user_id=user.id).delete(synchronize_session=False)
    _forget_browsers(db, user)
    db.commit()


@app.post("/api/me/two-factor/setup")
def two_factor_setup(payload: TwoFactorSetupIn,
                     user: User = Depends(current_session_user),
                     db: Session = Depends(get_db)):
    """Start set-up: make a key and return it, with the otpauth:// address
    the page draws as a QR code. Nothing is on until /enable gets a code.
    Starting again replaces the key."""
    _check_two_factor_password(user, payload.password)
    if user.totp_enabled_at is not None:
        raise HTTPException(409, "Two-factor sign-in is already on.")
    secret = twofactor.new_secret()
    user.totp_secret = secret
    user.totp_last_step = None
    db.commit()
    return {"secret": secret,
            "otpauth_url": twofactor.otpauth_url(secret, user.email, get_app_title(db))}


@app.post("/api/me/two-factor/enable")
def two_factor_enable(payload: TwoFactorCodeIn, request: Request,
                      user: User = Depends(current_session_user),
                      db: Session = Depends(get_db)):
    """Finish set-up with a code from the app, proving it has the key.
    Returns the recovery codes, this once."""
    if user.totp_enabled_at is not None:
        raise HTTPException(409, "Two-factor sign-in is already on.")
    if not user.totp_secret_enc:
        raise HTTPException(400, "Start the set-up again.")
    step = twofactor.matching_step(user.totp_secret, "".join(payload.code.split()))
    if step is None:
        raise HTTPException(403, WRONG_CODE_MESSAGE)
    user.totp_enabled_at = datetime.utcnow()
    user.totp_last_step = step
    codes = _new_recovery_codes(db, user)
    # Browsers signed in before it was on didn't give a code (#186).
    _end_other_sessions(request, user)
    db.commit()
    record_event(db, "two_factor_enabled", request, user=user)
    return {"two_factor_enabled": True, "recovery_codes": codes}


def _confirm_two_factor(db: Session, request: Request, user: User,
                        payload: TwoFactorConfirmIn, action: str) -> None:
    """The password and a current code (or a recovery code), for a user who
    has two-factor on. Wrong codes are counted and limited (#169)."""
    _check_two_factor_password(user, payload.password)
    if user.totp_enabled_at is None:
        raise HTTPException(400, "Two-factor sign-in isn't on.")
    _confirm_code_for(db, request, user, payload.code, action)


@app.post("/api/me/two-factor/disable")
def two_factor_disable(payload: TwoFactorConfirmIn, request: Request,
                       user: User = Depends(current_session_user),
                       db: Session = Depends(get_db)):
    """Switch two-factor off, confirmed with the password and a code."""
    _confirm_two_factor(db, request, user, payload, "two-factor off")
    _end_other_sessions(request, user)
    _clear_two_factor(db, user)
    record_event(db, "two_factor_disabled", request, user=user,
                 detail=audit_target(user, user.id))
    return {"two_factor_enabled": False}


@app.post("/api/me/two-factor/recovery-codes")
def two_factor_new_recovery_codes(payload: TwoFactorConfirmIn, request: Request,
                                  user: User = Depends(current_session_user),
                                  db: Session = Depends(get_db)):
    """Replace the recovery codes with ten new ones, shown this once. The old
    ones stop working."""
    _confirm_two_factor(db, request, user, payload, "recovery codes")
    codes = _new_recovery_codes(db, user)
    db.commit()
    record_event(db, "recovery_codes_remade", request, user=user)
    return {"recovery_codes": codes}


def _browser_out(row: RememberedBrowser, this_hash: str | None) -> dict:
    return {"id": row.id, "label": row.label,
            "created_at": _iso(row.created_at), "last_used_at": _iso(row.last_used_at),
            "expires_at": _iso(row.expires_at),
            # The browser asking: Settings marks it "This browser".
            "current": this_hash is not None and row.token_hash == this_hash}


def _this_browser_hash(request: Request) -> str | None:
    token = request.cookies.get(REMEMBER_COOKIE)
    return _remember_hash(token) if token and len(token) <= 100 else None


@app.get("/api/me/remembered-browsers")
def list_remembered_browsers(request: Request,
                             user: User = Depends(current_session_user),
                             db: Session = Depends(get_db)):
    """The browsers that skip the two-factor code for this user, newest
    first. Lapsed ones aren't listed."""
    rows = (db.query(RememberedBrowser)
            .filter(RememberedBrowser.user_id == user.id,
                    RememberedBrowser.expires_at > datetime.utcnow())
            .order_by(RememberedBrowser.created_at.desc(), RememberedBrowser.id.desc())
            .all())
    this_hash = _this_browser_hash(request)
    return [_browser_out(r, this_hash) for r in rows]


@app.delete("/api/me/remembered-browsers/{browser_id}")
def forget_remembered_browser(browser_id: int, request: Request, response: Response,
                              user: User = Depends(current_session_user),
                              db: Session = Depends(get_db)):
    """Forget one browser: it's asked for the code at its next sign-in."""
    row = db.query(RememberedBrowser).filter_by(id=browser_id, user_id=user.id).first()
    if not row:
        raise HTTPException(404, "That browser isn't remembered.")
    if row.token_hash == _this_browser_hash(request):
        response.delete_cookie(REMEMBER_COOKIE, path="/")
    db.delete(row)
    db.commit()
    record_event(db, "browser_forgotten", request, user=user, detail="one browser")
    return {"ok": True}


@app.delete("/api/me/remembered-browsers")
def forget_all_remembered_browsers(request: Request, response: Response,
                                   user: User = Depends(current_session_user),
                                   db: Session = Depends(get_db)):
    """Forget every remembered browser, this one included."""
    count = _forget_browsers(db, user)
    db.commit()
    response.delete_cookie(REMEMBER_COOKIE, path="/")
    if count:
        record_event(db, "browser_forgotten", request, user=user,
                     detail=f"all, {count} browser{'s' if count != 1 else ''}")
    return {"forgotten": count}


# ---------- Deleting your own user ----------
# A user can delete themselves, with everything only they own. What must not
# happen is someone else losing an account by surprise, so (decided
# 2026-11-14, docs/dev/decisions/legal-risk.md) deletion is refused while the
# user is the only owner of an account other people can still see. They
# promote someone else to owner, or remove the others' access, on the
# Permissions panel first.
#
# "Owner" here is the permission level, which is what the app enforces.
# accounts.owner_id only records who the row belongs to in the database, and
# deleting that user would delete the account with them (ON DELETE CASCADE),
# so an account that stays is first re-pointed at one of its other owners.
def _deletion_plan(db: Session, user: User) -> dict:
    """Sort the accounts tied to `user` into: deleted with them, kept (with
    the owner the row moves to), and blocking (shared, with no other owner).
    """
    account_ids = {a.id for a in db.query(Account).filter_by(owner_id=user.id)}
    account_ids |= {p.account_id for p in db.query(AccountPermission)
                    .filter_by(user_id=user.id, level="owner")}
    deleted, kept, blocking = [], [], []
    for acc in db.query(Account).filter(Account.id.in_(account_ids)).order_by(Account.id):
        others = (db.query(AccountPermission, User)
                  .join(User, User.id == AccountPermission.user_id)
                  .filter(AccountPermission.account_id == acc.id,
                          AccountPermission.user_id != user.id,
                          AccountPermission.level.in_(["owner", "edit", "read"]))
                  .order_by(AccountPermission.created_at, AccountPermission.user_id)
                  .all())
        other_owners = [u for (p, u) in others if p.level == "owner"]
        if other_owners:
            kept.append((acc, other_owners[0]))
        elif others:
            blocking.append((acc, others))
        else:
            deleted.append(acc)
    return {"deleted": deleted, "kept": kept, "blocking": blocking}


def _deletion_plan_json(plan: dict) -> dict:
    return {
        "can_delete": not plan["blocking"],
        "accounts_deleted": [{"id": a.id, "name": a.name} for a in plan["deleted"]],
        "accounts_kept": [{"id": a.id, "name": a.name, "new_owner_email": u.email}
                          for (a, u) in plan["kept"]],
        "blocking_accounts": [
            {"id": a.id, "name": a.name,
             "shared_with": [{"email": u.email, "level": p.level} for (p, u) in others]}
            for (a, others) in plan["blocking"]
        ],
    }


@app.get("/api/me/deletion-check")
def deletion_check(user: User = Depends(current_user), db: Session = Depends(get_db)):
    """What deleting the caller's own user would do, without doing it."""
    out = _deletion_plan_json(_deletion_plan(db, user))
    out["has_password"] = bool(user.password_hash)
    out["is_demo"] = is_demo_email(user.email)
    return out


class DeleteMeIn(BaseModel):
    # A user with a password confirms with it. A Google-only user has none,
    # and confirms by typing their email address.
    password: str | None = Field(default=None, max_length=PASSWORD_CHECK_MAX)
    confirm_email: str | None = Field(default=None, max_length=EMAIL_MAX)
    # A current code, for a user with two-factor on (#169).
    code: str | None = Field(default=None, max_length=40)


@app.delete("/api/me")
def delete_me(payload: DeleteMeIn, request: Request,
              user: User = Depends(current_user), db: Session = Depends(get_db)):
    """Delete the caller's own user and everything only they own."""
    if is_demo_email(user.email):
        raise HTTPException(403, "The demo user can't be deleted.")
    if user.password_hash:
        if not payload.password or not verify_password(payload.password, user.password_hash):
            # 403, not 401: the session is fine, the confirmation isn't.
            raise HTTPException(403, "That password is incorrect.")
    elif (payload.confirm_email or "").strip().lower() != user.email.lower():
        raise HTTPException(400, "Type your email address to confirm.")
    _confirm_code_for(db, request, user, payload.code, "account deletion")

    plan = _deletion_plan(db, user)
    if plan["blocking"]:
        raise HTTPException(409, {
            "message": "You are the only owner of accounts other people can "
                       "see. Make someone else an owner, or remove their "
                       "access, then delete your user.",
            **_deletion_plan_json(plan),
        })
    # Written before the deletion, which then blanks its email and user like
    # the rest of theirs (#139): what's left says a user deleted themselves,
    # when, and from where.
    record_event(db, "user_deleted", request, user=user, detail="own user")
    _delete_user(db, user, plan)
    request.session.clear()
    return {"ok": True}


def _delete_user(db: Session, user: User, plan: dict) -> None:
    """Delete `user` following a `_deletion_plan` with nothing blocking.

    Shared by self-deletion and the Admin panel, so both keep an account
    that has another owner.
    """
    # Accounts that stay: move the row to their other owner, so deleting this
    # user doesn't take the account with it.
    for acc, new_owner in plan["kept"]:
        acc.owner = new_owner
    db.flush()  # so owner_id below is already the new owner's
    # Accounts that go. Most would go with the user anyway; one whose row
    # belongs to someone who has since left it would otherwise be orphaned.
    doomed_ids = {a.id for a in plan["deleted"]}
    # Transfers this user made between accounts that both stay would be
    # deleted with them, legs included. Hand each to its from-account's owner.
    for t in db.query(Transfer).filter_by(owner_id=user.id):
        if t.from_account_id in doomed_ids or t.to_account_id in doomed_ids:
            continue
        from_acc = db.get(Account, t.from_account_id)
        if from_acc and from_acc.owner_id != user.id:
            t.owner_id = from_acc.owner_id
        else:
            to_acc = db.get(Account, t.to_account_id)
            if to_acc and to_acc.owner_id != user.id:
                t.owner_id = to_acc.owner_id
    db.flush()
    for acc in plan["deleted"]:
        db.delete(acc)
    db.flush()
    # The sign-in log keeps what happened but not who (decided 2026-11-15,
    # #139): blank the email on rows that are theirs by id or by address,
    # failed attempts on their email included. user_id goes to NULL by the
    # foreign key when the user row goes.
    (db.query(AuditEvent)
     .filter((AuditEvent.user_id == user.id) | (AuditEvent.email == user.email.lower()))
     .update({AuditEvent.email: None}, synchronize_session=False))
    db.expire(user)
    db.delete(user)
    db.commit()


ALLOWED_THEMES = {
    "dark", "light", "system",
    "dracula", "solarized", "nord", "synthwave",
    "forest", "mint", "monokai", "sunset",
}
ALLOWED_CHART_POSITIONS = {"above", "below", "inside"}
ALLOWED_RECURRING_POSITIONS = {"above", "below"}


class PreferencesIn(BaseModel):
    # Only the fields we want users to be able to change live here.
    # None means "don't touch this field"; use explicit values to set.
    theme_preference: str | None = None
    chart_position: str | None = None
    recurring_position: str | None = None


@app.patch("/api/me/preferences")
def update_preferences(payload: PreferencesIn,
                       user: User = Depends(current_user),
                       db: Session = Depends(get_db)):
    """Update the current user's UI preferences."""
    if payload.theme_preference is not None:
        if payload.theme_preference not in ALLOWED_THEMES:
            raise HTTPException(400, f"theme_preference must be one of {sorted(ALLOWED_THEMES)}")
        user.theme_preference = payload.theme_preference
    if payload.chart_position is not None:
        if payload.chart_position not in ALLOWED_CHART_POSITIONS:
            raise HTTPException(400, f"chart_position must be one of {sorted(ALLOWED_CHART_POSITIONS)}")
        user.chart_position = payload.chart_position
    if payload.recurring_position is not None:
        if payload.recurring_position not in ALLOWED_RECURRING_POSITIONS:
            raise HTTPException(400, f"recurring_position must be one of {sorted(ALLOWED_RECURRING_POSITIONS)}")
        user.recurring_position = payload.recurring_position
    db.commit()
    return {
        "ok": True,
        "theme_preference": user.theme_preference,
        "chart_position": user.chart_position,
        "recurring_position": user.recurring_position,
    }


# ---------- Schemas ----------
NOTES_MAX_LEN = 256  # shared cap for transaction/recurring notes, incl. CSV import


class AccountIn(BaseModel):
    name: str = Field(max_length=ACCOUNT_NAME_MAX)
    starting_balance: Money
    starting_date: date


MATCH_DAYS_MAX, MATCH_PERCENT_MAX = 31, 100   # a bill's bank-match settings (#196)


MATCH_TEXT_MAX = 120   # a taught bill's bank-line name (#224)


class RecurringIn(BaseModel):
    description: str = Field(max_length=DESCRIPTION_MAX)
    amount: Money  # signed: negative = withdraw
    frequency: str  # 'monthly_day' | 'weekly' | 'biweekly'
    day_of_month: int | None = Field(default=None, ge=1, le=31)
    anchor_date: date | None = None
    end_date: date | None = None
    category_id: int | None = None
    notes: str | None = Field(default=None, max_length=NOTES_MAX_LEN)
    active: bool = True
    # Tags (#118): None leaves them as they are, [] clears them. Lines created
    # from the item start with these tags.
    tag_ids: list[int] | None = Field(default=None, max_length=200)
    # How close a bank line must be to pay one of its dates (#196): None
    # leaves them as they are (a new item starts at 5 days and 10%).
    match_days: int | None = Field(default=None, ge=0, le=MATCH_DAYS_MAX)
    match_percent: int | None = Field(default=None, ge=0, le=MATCH_PERCENT_MAX)
    # The bank lines' name the bill was taught (#224): left out leaves it as
    # it is, null or "" forgets it.
    match_text: str | None = Field(default=None, max_length=MATCH_TEXT_MAX)

    @model_validator(mode="after")
    def _one_the_forecast_can_run(self):
        """A known frequency, with what it needs to produce dates (#185)."""
        if self.frequency not in RECURRING_FREQUENCIES:
            raise ValueError("frequency must be monthly_day, weekly or biweekly")
        if self.frequency == "monthly_day" and self.day_of_month is None:
            raise ValueError("a monthly item needs day_of_month")
        if self.frequency != "monthly_day" and self.anchor_date is None:
            raise ValueError("a weekly or biweekly item needs anchor_date, its first date")
        return self


class TransactionIn(BaseModel):
    description: str = Field(max_length=DESCRIPTION_MAX)
    amount: Money
    forecast_date: date | None = None
    actual_date: date | None = None
    forecast_amount: Money | None = None
    is_actual: bool = False
    recurring_id: int | None = None
    category_id: int | None = None
    notes: str | None = Field(default=None, max_length=NOTES_MAX_LEN)
    # Optional tag ids to attach to the transaction. None means "don't
    # touch tags" on update; an empty list means "clear all tags". On
    # create, None is treated as empty.
    tag_ids: list[int] | None = Field(default=None, max_length=200)


class CategoryIn(BaseModel):
    name: str = Field(max_length=CATEGORY_NAME_MAX)
    color: str | None = Field(default=None, max_length=20)


class TagIn(BaseModel):
    name: str = Field(max_length=200)   # the routes answer 400 past TAG_NAME_MAX
    color: str | None = Field(default=None, max_length=20)


# A colour is written into the page's markup, so it's a hex colour or
# nothing (#183). Checked wherever one comes in, a backup included.
_HEX_COLOR = re.compile(r"#[0-9a-fA-F]{3}(?:[0-9a-fA-F]{3})?")


def clean_color(value: str | None) -> str | None:
    """`value` as a hex colour, None for none; 400 for anything else."""
    value = (value or "").strip()
    if not value:
        return None
    if not _HEX_COLOR.fullmatch(value):
        raise HTTPException(400, "A colour must be a hex colour, like #58a6ff")
    return value


# ---------- Categories ----------
DEFAULT_CATEGORIES = [
    ("Groceries",      "#3fb950"),
    ("Dining",         "#f0883e"),
    ("Transportation", "#58a6ff"),
    ("Utilities",      "#56d4dd"),
    ("Rent/Mortgage",  "#a371f7"),
    ("Insurance",      "#2ea043"),
    ("Healthcare",     "#ff7b72"),
    ("Entertainment",  "#e3b341"),
    ("Shopping",       "#db61a2"),
    ("Subscriptions",  "#7c6be6"),
    ("Income",         "#3fb950"),
    ("Savings",        "#d29922"),
    ("Other",          "#8b949e"),
]


def seed_default_categories(db: Session, user: User) -> int:
    """Insert default categories for a user who has none. Idempotent: if the
    user already has any categories, this is a no-op. Returns the number of
    rows inserted."""
    existing = db.query(Category).filter_by(owner_id=user.id).count()
    if existing > 0:
        return 0
    for name, color in DEFAULT_CATEGORIES:
        db.add(Category(owner_id=user.id, name=name, color=color))
    db.commit()
    return len(DEFAULT_CATEGORIES)


def _own_category(db: Session, user: User, cat_id: int) -> Category:
    cat = db.get(Category, cat_id)
    if not cat or cat.owner_id != user.id:
        raise HTTPException(404, "Category not found")
    return cat


@app.get("/api/categories")
def list_categories(user: User = Depends(current_user), db: Session = Depends(get_db)):
    cats = db.query(Category).filter_by(owner_id=user.id).order_by(Category.name).all()
    return [{"id": c.id, "name": c.name, "color": c.color} for c in cats]


@app.post("/api/categories")
def create_category(payload: CategoryIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    name = payload.name.strip()
    if not name:
        raise HTTPException(400, "Name is required")
    existing = db.query(Category).filter_by(owner_id=user.id, name=name).first()
    if existing:
        raise HTTPException(409, "A category with that name already exists")
    cat = Category(owner_id=user.id, name=name, color=clean_color(payload.color))
    db.add(cat)
    db.commit()
    db.refresh(cat)
    return {"id": cat.id, "name": cat.name, "color": cat.color}


@app.patch("/api/categories/{cat_id}")
def update_category(cat_id: int, payload: CategoryIn,
                    user: User = Depends(current_user), db: Session = Depends(get_db)):
    cat = _own_category(db, user, cat_id)
    cat.name = payload.name.strip()
    cat.color = clean_color(payload.color)
    db.commit()
    return {"ok": True}


@app.delete("/api/categories/{cat_id}")
def delete_category(cat_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    cat = _own_category(db, user, cat_id)
    db.delete(cat)
    db.commit()
    return {"ok": True}


# ---------- Tags (Tier-2 cross-cutting labels) ----------
# A tag is a lightweight label a user attaches to any number of transactions.
# Unlike Category, each transaction can carry many tags — useful for
# cross-cutting reports like "vacation" or "reimbursable" that don't belong
# in the primary category hierarchy.
TAG_NAME_MAX = 60


def _own_tag(db: Session, user: User, tag_id: int) -> Tag:
    tag = db.get(Tag, tag_id)
    if not tag or tag.owner_id != user.id:
        raise HTTPException(404, "Tag not found")
    return tag


def _transaction_tag_ids(db: Session, transaction_id: int) -> list[int]:
    """Return the sorted tag ids attached to a transaction."""
    rows = db.query(TransactionTag.tag_id).filter_by(
        transaction_id=transaction_id
    ).all()
    return sorted(r[0] for r in rows)


def _apply_tags(db: Session, user: User, t: Transaction,
                tag_ids: list[int] | None) -> None:
    """Replace the tag set on a transaction.

    None means "don't touch". An empty list means "clear all tags". Any
    listed id must be owned by the current user (guards against users
    attaching other users' tags). Callers should `db.commit()` after.
    """
    if tag_ids is None:
        return
    # Validate every id belongs to this user before we touch the join table.
    validated: list[int] = []
    for tid in tag_ids:
        _own_tag(db, user, tid)
        validated.append(tid)
    db.query(TransactionTag).filter_by(transaction_id=t.id).delete(
        synchronize_session=False
    )
    for tid in validated:
        db.add(TransactionTag(transaction_id=t.id, tag_id=tid))


def _tags_for_transactions(db: Session, txn_ids: list[int]) -> dict[int, list[dict]]:
    """Bulk-load tag rows for a batch of transactions.

    Returns `{transaction_id: [{id, name, color}, ...]}`. Used by the
    list / search endpoints so we don't N+1 the tag lookup per row.
    """
    if not txn_ids:
        return {}
    rows = (db.query(TransactionTag.transaction_id, Tag.id, Tag.name, Tag.color)
              .join(Tag, Tag.id == TransactionTag.tag_id)
              .filter(TransactionTag.transaction_id.in_(txn_ids))
              .order_by(Tag.name).all())
    out: dict[int, list[dict]] = {}
    for txn_id, tid, name, color in rows:
        out.setdefault(txn_id, []).append({"id": tid, "name": name, "color": color})
    return out


def _apply_recurring_tags(db: Session, user: User, rec: RecurringTransaction,
                          tag_ids: list[int] | None) -> None:
    """Replace the tag set on a recurring item (#118); same rules as
    _apply_tags: None leaves it, [] clears it, every id must be the user's."""
    if tag_ids is None:
        return
    validated = []
    for tid in dict.fromkeys(tag_ids):
        _own_tag(db, user, tid)
        validated.append(tid)
    db.query(RecurringTag).filter_by(recurring_id=rec.id).delete(
        synchronize_session=False
    )
    for tid in validated:
        db.add(RecurringTag(recurring_id=rec.id, tag_id=tid))


def _tags_for_recurring(db: Session, rec_ids: list[int]) -> dict[int, list[dict]]:
    """`{recurring_id: [{id, name, color}, ...]}` for a batch of items."""
    if not rec_ids:
        return {}
    rows = (db.query(RecurringTag.recurring_id, Tag.id, Tag.name, Tag.color)
              .join(Tag, Tag.id == RecurringTag.tag_id)
              .filter(RecurringTag.recurring_id.in_(rec_ids))
              .order_by(Tag.name).all())
    out: dict[int, list[dict]] = {}
    for rid, tid, name, color in rows:
        out.setdefault(rid, []).append({"id": tid, "name": name, "color": color})
    return out


def _copy_recurring_tags(db: Session, rec_id: int, t: Transaction) -> None:
    """Start a line created from a recurring item with the item's tags
    (#118). They're the item's own tags, so no per-user check here."""
    for (tid,) in db.query(RecurringTag.tag_id).filter_by(recurring_id=rec_id).all():
        db.add(TransactionTag(transaction_id=t.id, tag_id=tid))


@app.get("/api/tags")
def list_tags(user: User = Depends(current_user), db: Session = Depends(get_db)):
    tags = (db.query(Tag).filter_by(owner_id=user.id)
              .order_by(Tag.name).all())
    return [{"id": t.id, "name": t.name, "color": t.color} for t in tags]


@app.post("/api/tags")
def create_tag(payload: TagIn, user: User = Depends(current_user),
               db: Session = Depends(get_db)):
    name = (payload.name or "").strip()
    if not name:
        raise HTTPException(400, "Name is required")
    if len(name) > TAG_NAME_MAX:
        raise HTTPException(400, f"Name must be <= {TAG_NAME_MAX} characters")
    existing = db.query(Tag).filter_by(owner_id=user.id, name=name).first()
    if existing:
        raise HTTPException(409, "A tag with that name already exists")
    tag = Tag(owner_id=user.id, name=name, color=clean_color(payload.color))
    db.add(tag)
    db.commit()
    db.refresh(tag)
    return {"id": tag.id, "name": tag.name, "color": tag.color}


@app.patch("/api/tags/{tag_id}")
def update_tag(tag_id: int, payload: TagIn,
               user: User = Depends(current_user), db: Session = Depends(get_db)):
    tag = _own_tag(db, user, tag_id)
    name = (payload.name or "").strip()
    if not name:
        raise HTTPException(400, "Name is required")
    if len(name) > TAG_NAME_MAX:
        raise HTTPException(400, f"Name must be <= {TAG_NAME_MAX} characters")
    clash = (db.query(Tag)
               .filter(Tag.owner_id == user.id, Tag.name == name, Tag.id != tag_id)
               .first())
    if clash:
        raise HTTPException(409, "A tag with that name already exists")
    tag.name = name
    tag.color = clean_color(payload.color)
    db.commit()
    return {"ok": True, "id": tag.id, "name": tag.name, "color": tag.color}


@app.delete("/api/tags/{tag_id}")
def delete_tag(tag_id: int, user: User = Depends(current_user),
               db: Session = Depends(get_db)):
    tag = _own_tag(db, user, tag_id)
    db.delete(tag)  # cascade drops rows in transaction_tags
    db.commit()
    return {"ok": True}


# ---------- Tag rules (auto-apply tags on transaction save / import) ----------
TAG_RULE_PATTERN_MIN = 2
TAG_RULE_PATTERN_MAX = 120
TAG_RULE_NAME_MAX = 80


class TagRuleIn(BaseModel):
    """Inbound shape for create/update of an auto-tagging rule.

    `description_pattern` is matched as a case-insensitive substring
    against `transactions.description`. We require at least 2 characters
    so a degenerate single-letter rule doesn't tag the world.
    """
    name: str | None = Field(default=None, max_length=TAG_RULE_NAME_MAX)
    description_pattern: str = Field(..., min_length=TAG_RULE_PATTERN_MIN,
                                     max_length=TAG_RULE_PATTERN_MAX)
    category_id: int | None = None
    tag_id: int
    active: bool = True


def _own_rule(db: Session, user: User, rule_id: int) -> TagRule:
    r = db.get(TagRule, rule_id)
    if not r or r.owner_id != user.id:
        raise HTTPException(404, "Rule not found")
    return r


def _apply_tag_rules(db: Session, user: User, t: Transaction) -> int:
    """Run every active rule against a transaction, attach matching tag.

    Returns the number of tags newly attached. Idempotent — if the tag
    is already on the transaction the rule is a no-op for that pairing.
    Caller is responsible for `db.commit()`.

    Why we re-fetch rules each call instead of caching: rules change
    rarely but transaction writes happen often, and the rules table is
    small (typical user has <30 rules). A SQL scan beats stale cache
    invalidation logic for a single-instance app.
    """
    if not t.description:
        return 0
    # Tags set a moment ago (the line's own, a CSV row's) are still unsaved,
    # and the session doesn't flush by itself: without this the lookup below
    # misses them and the same tag is added twice, which is a 500 (#182).
    db.flush()
    desc = t.description.lower()
    rules = (db.query(TagRule)
               .filter(TagRule.owner_id == user.id, TagRule.active == True)
               .all())
    if not rules:
        return 0
    # Pull existing tag links once so we can short-circuit duplicates.
    existing = {
        row[0] for row in db.query(TransactionTag.tag_id)
                            .filter_by(transaction_id=t.id).all()
    }
    added = 0
    for r in rules:
        # Category gate (optional).
        if r.category_id is not None and t.category_id != r.category_id:
            continue
        if r.description_pattern not in desc:
            continue
        if r.tag_id in existing:
            continue
        db.add(TransactionTag(transaction_id=t.id, tag_id=r.tag_id))
        existing.add(r.tag_id)
        added += 1
    return added


@app.get("/api/tag-rules")
def list_tag_rules(user: User = Depends(current_user),
                   db: Session = Depends(get_db)):
    rules = (db.query(TagRule).filter_by(owner_id=user.id)
               .order_by(TagRule.id.desc()).all())
    # Resolve names for the picker UI in one extra query each. Tag and
    # Category lookup is cheap (small tables, indexed by id).
    out = []
    for r in rules:
        tag = db.get(Tag, r.tag_id)
        cat = db.get(Category, r.category_id) if r.category_id else None
        out.append({
            "id": r.id,
            "name": r.name,
            "description_pattern": r.description_pattern,
            "category_id": r.category_id,
            "category_name": cat.name if cat else None,
            "tag_id": r.tag_id,
            "tag_name": tag.name if tag else None,
            "tag_color": tag.color if tag else None,
            "active": r.active,
        })
    return out


@app.post("/api/tag-rules")
def create_tag_rule(payload: TagRuleIn, user: User = Depends(current_user),
                    db: Session = Depends(get_db)):
    pattern = payload.description_pattern.strip().lower()
    if len(pattern) < TAG_RULE_PATTERN_MIN:
        raise HTTPException(400, "Pattern too short")
    # Validate ownership of referenced tag and (optional) category.
    _own_tag(db, user, payload.tag_id)
    if payload.category_id is not None:
        cat = db.get(Category, payload.category_id)
        if not cat or cat.owner_id != user.id:
            raise HTTPException(404, "Category not found")
    rule = TagRule(
        owner_id=user.id,
        name=(payload.name or "").strip() or None,
        description_pattern=pattern,
        category_id=payload.category_id,
        tag_id=payload.tag_id,
        active=payload.active,
    )
    db.add(rule)
    db.commit()
    db.refresh(rule)
    return {"id": rule.id}


@app.patch("/api/tag-rules/{rule_id}")
def update_tag_rule(rule_id: int, payload: TagRuleIn,
                    user: User = Depends(current_user),
                    db: Session = Depends(get_db)):
    rule = _own_rule(db, user, rule_id)
    pattern = payload.description_pattern.strip().lower()
    if len(pattern) < TAG_RULE_PATTERN_MIN:
        raise HTTPException(400, "Pattern too short")
    _own_tag(db, user, payload.tag_id)
    if payload.category_id is not None:
        cat = db.get(Category, payload.category_id)
        if not cat or cat.owner_id != user.id:
            raise HTTPException(404, "Category not found")
    rule.name = (payload.name or "").strip() or None
    rule.description_pattern = pattern
    rule.category_id = payload.category_id
    rule.tag_id = payload.tag_id
    rule.active = payload.active
    db.commit()
    return {"ok": True}


@app.delete("/api/tag-rules/{rule_id}")
def delete_tag_rule(rule_id: int, user: User = Depends(current_user),
                    db: Session = Depends(get_db)):
    rule = _own_rule(db, user, rule_id)
    db.delete(rule)
    db.commit()
    return {"ok": True}


@app.post("/api/tag-rules/backfill")
def backfill_tag_rules(user: User = Depends(current_user),
                       db: Session = Depends(get_db)):
    """Replay every active rule across every transaction the user owns.

    Useful when adding a new rule retroactively. Walks each visible
    account's transactions; rules are idempotent so running this twice
    in a row is harmless (the second pass will report `tags_added=0`).
    """
    visible = _user_visible_accounts(db, user, include_archived=True)
    visible_ids = [a.id for a in visible]
    if not visible_ids:
        return {"transactions_scanned": 0, "tags_added": 0}
    txns = (db.query(Transaction)
              .filter(Transaction.account_id.in_(visible_ids))
              .all())
    total_added = 0
    for t in txns:
        total_added += _apply_tag_rules(db, user, t)
    db.commit()
    return {"transactions_scanned": len(txns), "tags_added": total_added}


# ---------- Accounts & Permissions ----------
LEVEL_RANK = {"deny": 0, "read": 1, "edit": 2, "owner": 3}


def _user_level(db: Session, user: User, account_id: int) -> str:
    """Return the user's effective level on an account: 'owner' | 'edit' | 'read' | 'deny'."""
    p = db.query(AccountPermission).filter_by(
        account_id=account_id, user_id=user.id
    ).first()
    return p.level if p else "deny"


def _account_with_perm(db: Session, user: User, account_id: int,
                       required: str) -> Account:
    """Fetch an account if the user has at least `required` access, else 404.

    We return 404 (not 403) to avoid leaking which account ids exist.
    """
    acc = db.get(Account, account_id)
    if not acc:
        raise HTTPException(404, "Account not found")
    level = _user_level(db, user, account_id)
    if LEVEL_RANK[level] < LEVEL_RANK[required]:
        raise HTTPException(404, "Account not found")
    return acc


def _own_account(db: Session, user: User, account_id: int) -> Account:
    """Backwards-compatible alias used by older endpoints. Requires edit."""
    return _account_with_perm(db, user, account_id, "edit")


def _user_visible_accounts(db: Session, user: User, include_archived: bool = False) -> list[Account]:
    """All accounts the user has at least 'read' access to.

    By default archived accounts are excluded so they don't appear on the
    Accounts page or Dashboard. Pass include_archived=True for Settings
    management views that need to see everything.
    """
    q = (
        db.query(Account, AccountPermission.level)
        .join(AccountPermission, AccountPermission.account_id == Account.id)
        .filter(AccountPermission.user_id == user.id)
        .filter(AccountPermission.level.in_(["owner", "edit", "read"]))
    )
    if not include_archived:
        q = q.filter(Account.archived == False)
    return [acc for (acc, _level) in q.all()]


def _user_editable_accounts(db: Session, user: User, include_archived: bool = False) -> list[Account]:
    """All accounts the user has at least 'edit' access to."""
    q = (
        db.query(Account)
        .join(AccountPermission, AccountPermission.account_id == Account.id)
        .filter(AccountPermission.user_id == user.id)
        .filter(AccountPermission.level.in_(["owner", "edit"]))
    )
    if not include_archived:
        q = q.filter(Account.archived == False)
    return list(q.all())


def _viewer_today(today: date | None) -> date:
    """The viewer's own date, sent by the browser as `?today=YYYY-MM-DD`.

    The server's clock is usually UTC, so from the evening in the Americas
    its date is already tomorrow; going by it would count tomorrow's lines in
    "today's" balance. Without the parameter (scripts, older clients) the
    server's date is used. Any real time zone is within a day of UTC, so a
    date further off than that is refused rather than trusted.
    """
    server_today = date.today()
    if today is None:
        return server_today
    if abs((today - server_today).days) > 1:
        raise HTTPException(400, "today must be within a day of the server's date")
    return today


def _current_balance(db: Session, account: Account, today: date | None = None) -> float:
    """Today's actual balance — the same number the Forecast table's "Actual
    bal" column shows at today's row (see forecast.actual_balance_as_of).

    Rows dated on or before today that haven't been marked cleared still count
    (at their forecast amount), exactly as the table treats them, so this
    figure and the table never disagree. `today` is the viewer's date (see
    _viewer_today); it defaults to the server's.
    """
    return actual_balance_as_of(db, account, today or date.today())


@app.get("/api/accounts")
def list_accounts(include_archived: bool = False, today: date | None = None,
                  user: User = Depends(current_user), db: Session = Depends(get_db)):
    today = _viewer_today(today)
    out = []
    for a in _user_visible_accounts(db, user, include_archived=include_archived):
        out.append({
            "id": a.id, "name": a.name,
            "starting_balance": float(a.starting_balance),
            "starting_date": a.starting_date.isoformat(),
            # Today-dated cleared balance. Surfaced so selectors (transfer
            # page, account pickers) can show the user's actual available
            # money without a second round-trip.
            "current_balance": round(_current_balance(db, a, today), 2),
            "archived": a.archived,
            "level": _user_level(db, user, a.id),
        })
    return out


@app.post("/api/accounts")
def create_account(payload: AccountIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    acc = Account(owner_id=user.id, starting_date=payload.starting_date)
    acc.name = payload.name
    acc.starting_balance = Decimal(str(payload.starting_balance))
    db.add(acc)
    db.flush()  # populate acc.id without committing
    db.add(AccountPermission(account_id=acc.id, user_id=user.id, level="owner"))
    db.commit()
    db.refresh(acc)
    return {"id": acc.id}


class AccountPatchIn(BaseModel):
    archived: bool | None = None
    name: str | None = Field(default=None, max_length=ACCOUNT_NAME_MAX)


@app.patch("/api/accounts/{account_id}")
def update_account(account_id: int, payload: AccountPatchIn,
                   user: User = Depends(current_user), db: Session = Depends(get_db)):
    # Must have edit on the account to toggle archive state. We bypass the
    # visible-accounts filter (which excludes archived) by going straight
    # through _account_with_perm, which uses db.get() directly.
    acc = _account_with_perm(db, user, account_id, "edit")
    if payload.name is not None:
        # Renaming is restricted to the owner permission level — shared
        # editors can log transactions but shouldn't be able to rename (or,
        # via delete below) an account they don't own.
        if LEVEL_RANK[_user_level(db, user, account_id)] < LEVEL_RANK["owner"]:
            raise HTTPException(403, "Only the account owner can rename this account")
        name = payload.name.strip()
        if not name:
            raise HTTPException(400, "Name is required")
        acc.name = name
    if payload.archived is not None:
        acc.archived = payload.archived
    db.commit()
    return {"ok": True, "archived": acc.archived, "name": acc.name}


@app.delete("/api/accounts/{account_id}")
def delete_account(account_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    # Owner-only: deleting cascades to every transaction, recurring template,
    # and permission grant on the account (see Account relationships in db.py).
    acc = _account_with_perm(db, user, account_id, "owner")
    db.delete(acc)
    db.commit()
    return {"ok": True}


# ---------- Recurring ----------
# Shared with /api/subscriptions below — normalizes a recurring row's
# per-charge amount to a monthly magnitude so cadences (weekly/biweekly/
# monthly) can be compared apples-to-apples.
_MONTHLY_FACTOR = {
    "monthly_day": 1.0,
    "biweekly":    26.0 / 12.0,
    "weekly":      52.0 / 12.0,
}


def _recurring_skip_counts(db: Session, rec_ids: list[int]) -> dict[int, int]:
    """How many occurrences have been deleted from each template."""
    return dict(
        db.query(RecurringSkip.recurring_id, func.count(RecurringSkip.id))
        .filter(RecurringSkip.recurring_id.in_(rec_ids or [0]))
        .group_by(RecurringSkip.recurring_id)
        .all()
    )


def _recurring_row(r: RecurringTransaction, today: date,
                   skip_counts: dict[int, int],
                   tags_by_rec: dict[int, list[dict]] | None = None) -> dict:
    """One recurring template as the Recurring / Bills & income tables show it."""
    is_expired = r.end_date is not None and r.end_date < today
    amt = float(r.amount)
    # monthly/yearly: the signed amount normalized to a month (income
    # positive, bills negative). monthly_cost/yearly_cost: the same for bills
    # only, as a positive cost; null for income. Both null on an
    # unrecognized cadence.
    factor = _MONTHLY_FACTOR.get(r.frequency)
    monthly = amt * factor if factor is not None else None
    monthly_cost = -monthly if (monthly is not None and amt < 0) else None
    return {
        "id": r.id,
        "description": r.description,
        "amount": amt,
        "frequency": r.frequency,
        "day_of_month": r.day_of_month,
        "anchor_date": r.anchor_date.isoformat() if r.anchor_date else None,
        "end_date": r.end_date.isoformat() if r.end_date else None,
        "category_id": r.category_id,
        "category_name": r.category.name if r.category else None,
        "notes": r.notes,
        "active": r.active,
        "expired": is_expired,
        "monthly": round(monthly, 2) if monthly is not None else None,
        "yearly": round(monthly * 12, 2) if monthly is not None else None,
        "monthly_cost": round(monthly_cost, 2) if monthly_cost is not None else None,
        "yearly_cost": round(monthly_cost * 12, 2) if monthly_cost is not None else None,
        "skipped_count": skip_counts.get(r.id, 0),
        "tags": (tags_by_rec or {}).get(r.id, []),
        "match_days": r.match_days,
        "match_percent": r.match_percent,
        "match_text": r.match_text,
    }


@app.get("/api/accounts/{account_id}/recurring")
def list_recurring(account_id: int, archived: bool = False,
                   user: User = Depends(current_user), db: Session = Depends(get_db)):
    acc = _account_with_perm(db, user, account_id, "read")
    today = date.today()
    skip_counts = _recurring_skip_counts(db, [r.id for r in acc.recurring])
    tags_by_rec = _tags_for_recurring(db, [r.id for r in acc.recurring])
    out = []
    for r in acc.recurring:
        row = _recurring_row(r, today, skip_counts, tags_by_rec)
        if archived == row["expired"]:
            out.append(row)
    return out


def _recurring_upcoming(db: Session, recs: list, today: date) -> dict[int, list[date]]:
    """Each item's next dates (forecast.upcoming_dates), with the skipped
    and already-paid dates from today on looked up in two queries."""
    ids = [r.id for r in recs] or [0]
    skipped: dict[int, set] = {}
    for rid, d in (db.query(RecurringSkip.recurring_id, RecurringSkip.skip_date)
                   .filter(RecurringSkip.recurring_id.in_(ids), RecurringSkip.skip_date >= today)):
        skipped.setdefault(rid, set()).add(d)
    paid: dict[int, set] = {}
    for rid, d in (db.query(Transaction.recurring_id, Transaction.forecast_date)
                   .filter(Transaction.recurring_id.in_(ids), Transaction.is_actual.is_(True),
                           Transaction.forecast_date >= today)):
        paid.setdefault(rid, set()).add(d)
    return {r.id: upcoming_dates(r, today, skipped.get(r.id, set()), paid.get(r.id, set()))
            for r in recs}


@app.get("/api/recurring")
def list_all_recurring(archived: bool = False, account_id: int | None = None,
                       today: date | None = None,
                       user: User = Depends(current_user),
                       db: Session = Depends(get_db)):
    """Every recurring template (bills and income) across the accounts the
    user can see, for the Bills & income page. `archived=true` lists the ones
    whose end date has passed. `account_id` narrows it to one account (404 if
    the user can't see it). `today` is the viewer's date (see _viewer_today).

    Each item carries its account and the user's access level on it, so the
    page knows which rows it may edit. `totals` covers the listed items that
    are active and on a known cadence: monthly and yearly bills, income, and
    net (income minus bills).
    """
    today = _viewer_today(today)
    if account_id is not None:
        accounts = [_account_with_perm(db, user, account_id, "read")]
    else:
        accounts = _user_visible_accounts(db, user)
    levels = dict(
        db.query(AccountPermission.account_id, AccountPermission.level)
        .filter(AccountPermission.user_id == user.id,
                AccountPermission.account_id.in_([a.id for a in accounts] or [0]))
        .all()
    )
    recs = [(a, r) for a in accounts for r in a.recurring]
    skip_counts = _recurring_skip_counts(db, [r.id for _, r in recs])
    tags_by_rec = _tags_for_recurring(db, [r.id for _, r in recs])
    upcoming = _recurring_upcoming(db, [r for _, r in recs], today)
    items = []
    bills_n = income_n = 0
    bills_m = income_m = 0.0
    for a, r in recs:
        row = _recurring_row(r, today, skip_counts, tags_by_rec)
        if archived != row["expired"]:
            continue
        nexts = upcoming.get(r.id, [])
        row.update({
            "account_id": a.id,
            "account_name": a.name,
            "account_level": levels.get(a.id, "read"),
            "category_color": r.category.color if r.category else None,
            # The iOS app's next date and "skip once" choices (#89).
            "next_date": nexts[0].isoformat() if nexts else None,
            "next_dates": [d.isoformat() for d in nexts],
        })
        items.append(row)
        factor = _MONTHLY_FACTOR.get(r.frequency)
        if not r.active or factor is None:
            continue
        # Sum unrounded figures so the yearly totals don't drift by cents.
        monthly = float(r.amount) * factor
        if monthly < 0:
            bills_n += 1
            bills_m += -monthly
        else:
            income_n += 1
            income_m += monthly
    items.sort(key=lambda x: (x["description"].lower(), x["account_name"].lower(), x["id"]))
    return {
        "items": items,
        "totals": {
            "bills_count": bills_n,
            "bills_monthly": round(bills_m, 2),
            "bills_yearly": round(bills_m * 12, 2),
            "income_count": income_n,
            "income_monthly": round(income_m, 2),
            "income_yearly": round(income_m * 12, 2),
            "net_monthly": round(income_m - bills_m, 2),
            "net_yearly": round((income_m - bills_m) * 12, 2),
        },
    }


@app.post("/api/accounts/{account_id}/recurring")
def create_recurring(account_id: int, payload: RecurringIn,
                     user: User = Depends(current_user), db: Session = Depends(get_db)):
    acc = _own_account(db, user, account_id)
    if payload.category_id is not None:
        _own_category(db, user, payload.category_id)
    rec = RecurringTransaction(
        account_id=acc.id,
        frequency=payload.frequency,
        day_of_month=payload.day_of_month,
        anchor_date=payload.anchor_date,
        end_date=payload.end_date,
        category_id=payload.category_id,
        active=payload.active,
        match_days=5 if payload.match_days is None else payload.match_days,
        match_percent=10 if payload.match_percent is None else payload.match_percent,
    )
    rec.description = payload.description
    rec.amount = Decimal(str(payload.amount))
    rec.notes = payload.notes
    rec.match_text = (payload.match_text or "").strip() or None
    db.add(rec)
    db.flush()  # need rec.id before attaching tags
    _apply_recurring_tags(db, user, rec, payload.tag_ids)
    db.commit()
    db.refresh(rec)
    return {"id": rec.id}


@app.patch("/api/recurring/{rec_id}")
def update_recurring(rec_id: int, payload: RecurringIn,
                     user: User = Depends(current_user), db: Session = Depends(get_db)):
    rec = db.get(RecurringTransaction, rec_id)
    if not rec:
        raise HTTPException(404)
    _account_with_perm(db, user, rec.account_id, "edit")
    # A category the item already has may be kept: on a shared account it's
    # the owner's, not the saver's own (#89, as for lines in #88).
    if payload.category_id is not None and payload.category_id != rec.category_id:
        _own_category(db, user, payload.category_id)
    rec.description = payload.description
    rec.amount = Decimal(str(payload.amount))
    rec.frequency = payload.frequency
    rec.day_of_month = payload.day_of_month
    rec.anchor_date = payload.anchor_date
    rec.end_date = payload.end_date
    rec.category_id = payload.category_id
    rec.notes = payload.notes
    rec.active = payload.active
    if payload.match_days is not None:
        rec.match_days = payload.match_days
    if payload.match_percent is not None:
        rec.match_percent = payload.match_percent
    if "match_text" in payload.model_fields_set:
        rec.match_text = (payload.match_text or "").strip() or None
    _apply_recurring_tags(db, user, rec, payload.tag_ids)
    db.commit()
    return {"ok": True}


@app.delete("/api/recurring/{rec_id}/match-text")
def forget_match_text(rec_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    """Forget: the bill stops preferring the bank lines it was taught (#224)."""
    rec = db.get(RecurringTransaction, rec_id)
    if not rec:
        raise HTTPException(404)
    _account_with_perm(db, user, rec.account_id, "edit")
    rec.match_text = None
    db.commit()
    return {"ok": True}


@app.delete("/api/recurring/{rec_id}")
def delete_recurring(rec_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    rec = db.get(RecurringTransaction, rec_id)
    if not rec:
        raise HTTPException(404)
    _account_with_perm(db, user, rec.account_id, "edit")
    db.delete(rec)
    db.commit()
    return {"ok": True}


# ---------- Recurring: skipped (deleted) occurrences ----------
class RecurringSkipIn(BaseModel):
    skip_date: date


def _add_skip(db: Session, recurring_id: int, skip_date: date) -> None:
    """Record that one occurrence was deleted. Idempotent."""
    exists = (db.query(RecurringSkip.id)
                .filter_by(recurring_id=recurring_id, skip_date=skip_date)
                .first())
    if not exists:
        db.add(RecurringSkip(recurring_id=recurring_id, skip_date=skip_date))


@app.post("/api/recurring/{rec_id}/skip")
def skip_recurring_occurrence(rec_id: int, payload: RecurringSkipIn,
                              user: User = Depends(current_user),
                              db: Session = Depends(get_db)):
    """Delete a single projected occurrence without touching the template."""
    rec = db.get(RecurringTransaction, rec_id)
    if not rec:
        raise HTTPException(404)
    _account_with_perm(db, user, rec.account_id, "edit")
    _add_skip(db, rec.id, payload.skip_date)
    db.commit()
    return {"ok": True}


@app.delete("/api/recurring/{rec_id}/skips")
def restore_recurring_occurrences(rec_id: int,
                                  user: User = Depends(current_user),
                                  db: Session = Depends(get_db)):
    """Bring back every occurrence previously deleted from this template."""
    rec = db.get(RecurringTransaction, rec_id)
    if not rec:
        raise HTTPException(404)
    _account_with_perm(db, user, rec.account_id, "edit")
    restored = (db.query(RecurringSkip)
                  .filter(RecurringSkip.recurring_id == rec.id)
                  .delete(synchronize_session=False))
    db.commit()
    return {"restored": restored}


# ---------- Recurring: bulk operations ----------
class RecurringBulkUpdateIn(BaseModel):
    """Change the same fields across many recurring templates at once.

    Only keys actually present in the request body are applied (checked
    via `model_fields_set`), so an omitted key means "leave unchanged"
    while an explicit null clears the field where that makes sense:

    `category_id`  — set, or null to clear.
    `amount_abs`   — new magnitude; each template keeps its own sign so
                     expenses stay expenses and income stays income.
    `day_of_month` — monthly templates only; other cadences are untouched.
    `anchor_date`  — start date for monthly, cadence anchor for weekly/
                     biweekly. Null clears it on monthly templates only
                     (weekly/biweekly can't run without one).
    `end_date`     — set, or null to clear (runs forever).
    """
    recurring_ids: list[int] = Field(..., min_length=1, max_length=1000)
    category_id:  int | None = None
    amount_abs:   float | None = Field(default=None, ge=0, le=1e12, allow_inf_nan=False)
    day_of_month: int | None = Field(default=None, ge=1, le=31)
    anchor_date:  date | None = None
    end_date:     date | None = None


class RecurringBulkDeleteIn(BaseModel):
    recurring_ids: list[int] = Field(..., min_length=1, max_length=1000)


def _editable_recurring(db: Session, user: User, ids: list[int]):
    """Yield templates the user may edit; count the rest as skipped.

    Mirrors bulk-tag: rows that are missing or on an account the user can
    only read are skipped rather than failing the whole batch.
    """
    found, skipped = [], 0
    for rid in ids:
        rec = db.get(RecurringTransaction, rid)
        if not rec:
            skipped += 1
            continue
        try:
            _account_with_perm(db, user, rec.account_id, "edit")
        except HTTPException:
            skipped += 1
            continue
        found.append(rec)
    return found, skipped


@app.post("/api/recurring/bulk-update")
def bulk_update_recurring(payload: RecurringBulkUpdateIn,
                          user: User = Depends(current_user),
                          db: Session = Depends(get_db)):
    fields = payload.model_fields_set - {"recurring_ids"}
    # amount_abs/day_of_month have no meaningful "clear", so an explicit
    # null for them is the same as leaving them out.
    if payload.amount_abs is None:
        fields.discard("amount_abs")
    if payload.day_of_month is None:
        fields.discard("day_of_month")
    if not fields:
        raise HTTPException(400, "No fields to update")
    # Validate category ownership once so a bad id fails the batch atomically.
    if "category_id" in fields and payload.category_id is not None:
        _own_category(db, user, payload.category_id)
    recs, skipped = _editable_recurring(db, user, payload.recurring_ids)
    for rec in recs:
        if "category_id" in fields:
            rec.category_id = payload.category_id
        if "amount_abs" in fields:
            mag = Decimal(str(payload.amount_abs))
            rec.amount = -mag if rec.amount < 0 else mag
        if "day_of_month" in fields and rec.frequency == "monthly_day":
            rec.day_of_month = payload.day_of_month
        if "anchor_date" in fields:
            if payload.anchor_date is not None or rec.frequency == "monthly_day":
                rec.anchor_date = payload.anchor_date
        if "end_date" in fields:
            rec.end_date = payload.end_date
    db.commit()
    return {"updated": len(recs), "skipped": skipped}


@app.post("/api/recurring/bulk-delete")
def bulk_delete_recurring(payload: RecurringBulkDeleteIn,
                          user: User = Depends(current_user),
                          db: Session = Depends(get_db)):
    recs, skipped = _editable_recurring(db, user, payload.recurring_ids)
    for rec in recs:
        db.delete(rec)
    db.commit()
    return {"deleted": len(recs), "skipped": skipped}


# ---------- Transactions ----------
@app.get("/api/accounts/{account_id}/transactions")
def list_transactions(account_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    acc = _account_with_perm(db, user, account_id, "read")
    txn_ids = [t.id for t in acc.transactions]
    tags_by_txn = _tags_for_transactions(db, txn_ids)
    return [
        {"id": t.id, "description": t.description, "amount": float(t.amount),
         "forecast_date": t.forecast_date.isoformat() if t.forecast_date else None,
         "actual_date": t.actual_date.isoformat() if t.actual_date else None,
         "forecast_amount": float(t.forecast_amount) if t.forecast_amount is not None else None,
         "is_actual": t.is_actual, "recurring_id": t.recurring_id,
         "category_id": t.category_id,
         "category_name": t.category.name if t.category else None,
         "notes": t.notes,
         "tags": tags_by_txn.get(t.id, [])}
        for t in acc.transactions
    ]


def _keeps_recurring_category(db: Session, acc: Account, payload: "TransactionIn") -> bool:
    """A line saved from a recurring item with the item's own category. On
    an account shared with the saver, that category is the owner's, so it
    can't be one of the saver's own; keeping it is still allowed (#88)."""
    if payload.recurring_id is None:
        return False
    rec = db.get(RecurringTransaction, payload.recurring_id)
    return bool(rec and rec.account_id == acc.id and rec.category_id == payload.category_id)


@app.post("/api/accounts/{account_id}/transactions")
def create_transaction(account_id: int, payload: TransactionIn,
                       user: User = Depends(current_user), db: Session = Depends(get_db)):
    acc = _own_account(db, user, account_id)
    # A line belongs to a recurring item on its own account, or to none (#183).
    if payload.recurring_id is not None:
        rec = db.get(RecurringTransaction, payload.recurring_id)
        if not rec or rec.account_id != acc.id:
            raise HTTPException(404, "Recurring item not found")
    if payload.category_id is not None and not _keeps_recurring_category(db, acc, payload):
        _own_category(db, user, payload.category_id)
    t = Transaction(
        account_id=acc.id,
        recurring_id=payload.recurring_id,
        category_id=payload.category_id,
        forecast_date=payload.forecast_date,
        actual_date=payload.actual_date,
        is_actual=payload.is_actual,
    )
    t.description = payload.description
    t.amount = Decimal(str(payload.amount))
    t.notes = payload.notes
    if payload.forecast_amount is not None:
        t.forecast_amount = Decimal(str(payload.forecast_amount))
    db.add(t)
    db.flush()  # need t.id before attaching tags
    if payload.tag_ids is None and payload.recurring_id is not None:
        # A line saved from a recurring item starts with its tags (#118).
        rec = db.get(RecurringTransaction, payload.recurring_id)
        if rec and rec.account_id == acc.id:
            _copy_recurring_tags(db, rec.id, t)
    _apply_tags(db, user, t, payload.tag_ids)
    # Auto-tagging rules fire AFTER explicit tag_ids so that the user's
    # explicit list is the floor, and rules can only add (never remove).
    # If a rule and the explicit list both target the same tag, the
    # idempotency check inside _apply_tag_rules avoids a duplicate row.
    _apply_tag_rules(db, user, t)
    db.commit()
    db.refresh(t)
    return {"id": t.id}


@app.patch("/api/transactions/{tid}")
def update_transaction(tid: int, payload: TransactionIn,
                       user: User = Depends(current_user), db: Session = Depends(get_db)):
    t = db.get(Transaction, tid)
    if not t:
        raise HTTPException(404)
    _account_with_perm(db, user, t.account_id, "edit")
    # A category the line already has may be kept: on a shared account it's
    # the owner's, not the saver's own (#88).
    if payload.category_id is not None and payload.category_id != t.category_id:
        _own_category(db, user, payload.category_id)
    t.description = payload.description
    t.amount = Decimal(str(payload.amount))
    t.forecast_date = payload.forecast_date
    t.actual_date = payload.actual_date
    t.is_actual = payload.is_actual
    t.category_id = payload.category_id
    t.notes = payload.notes
    if payload.forecast_amount is not None:
        t.forecast_amount = Decimal(str(payload.forecast_amount))
    _apply_tags(db, user, t, payload.tag_ids)
    # Re-run auto-tagging on PATCH too: a description or category change
    # can flip which rules match. Existing tag links are preserved
    # (rules are additive).
    _apply_tag_rules(db, user, t)
    db.commit()
    return {"ok": True}


@app.delete("/api/transactions/{tid}")
def delete_transaction(tid: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    t = db.get(Transaction, tid)
    if not t:
        raise HTTPException(404)
    _account_with_perm(db, user, t.account_id, "edit")
    # A transaction backing a recurring occurrence would otherwise be
    # replaced by the template's projection for that same date on the next
    # forecast, so the delete would look like it didn't happen. Skip it.
    if t.recurring_id and t.forecast_date:
        _add_skip(db, t.recurring_id, t.forecast_date)
    db.delete(t)
    db.commit()
    return {"ok": True}


# ---------- Forecast ----------
class ForecastActualIn(BaseModel):
    """Body for upserting an actual against a forecast row.

    If transaction_id is provided we update that transaction.
    Otherwise recurring_id + forecast_date + forecast_amount + description are
    required so we can create a brand-new Transaction backing this occurrence.
    Pass actual_amount=None and actual_date=None to clear the actual back to
    a pure forecast (deletes the transaction if it had no other purpose).
    """
    transaction_id: int | None = None
    recurring_id: int | None = None
    forecast_date: date | None = None
    forecast_amount: Money | None = None
    description: str | None = Field(default=None, max_length=DESCRIPTION_MAX)
    category_id: int | None = None
    actual_amount: Money | None = None
    actual_date: date | None = None
    notes: str | None = Field(default=None, max_length=256)


@app.post("/api/accounts/{account_id}/forecast/actual")
def upsert_forecast_actual(account_id: int, payload: ForecastActualIn,
                           user: User = Depends(current_user), db: Session = Depends(get_db)):
    acc = _own_account(db, user, account_id)

    # Update existing transaction
    if payload.transaction_id is not None:
        t = db.get(Transaction, payload.transaction_id)
        if not t or t.account_id != acc.id:
            raise HTTPException(404, "Transaction not found")
        if payload.actual_amount is None and payload.actual_date is None:
            # Clear the actual. If this transaction was a pure recurring-backed
            # actual (no manual content beyond the override), delete it so the
            # forecast view shows the template projection again.
            if t.recurring_id is not None:
                db.delete(t)
            else:
                t.is_actual = False
                t.actual_date = None
            db.commit()
            return {"ok": True}
        if payload.actual_amount is not None:
            t.amount = Decimal(str(payload.actual_amount))
        if payload.actual_date is not None:
            t.actual_date = payload.actual_date
        if payload.notes is not None:
            t.notes = payload.notes
        t.is_actual = True
        db.commit()
        return {"ok": True, "transaction_id": t.id}

    # Create a new transaction backing this forecast occurrence
    if payload.recurring_id is None or payload.forecast_date is None:
        raise HTTPException(400, "transaction_id or (recurring_id + forecast_date) is required")
    rec = db.get(RecurringTransaction, payload.recurring_id)
    if not rec or rec.account_id != acc.id:
        raise HTTPException(404, "Recurring template not found")
    # The item's own category may be kept (on a shared account it's the
    # owner's); any other must be the caller's (#183).
    if payload.category_id is not None and payload.category_id != rec.category_id:
        _own_category(db, user, payload.category_id)
    fc_amt = payload.forecast_amount if payload.forecast_amount is not None else float(rec.amount)
    actual_amt = payload.actual_amount if payload.actual_amount is not None else fc_amt
    t = Transaction(
        account_id=acc.id,
        recurring_id=rec.id,
        category_id=payload.category_id if payload.category_id is not None else rec.category_id,
        forecast_date=payload.forecast_date,
        actual_date=payload.actual_date or payload.forecast_date,
        is_actual=True,
    )
    t.description = payload.description or rec.description
    t.amount = Decimal(str(actual_amt))
    t.forecast_amount = Decimal(str(fc_amt))
    t.notes = payload.notes if payload.notes is not None else rec.notes
    db.add(t)
    db.flush()
    _copy_recurring_tags(db, rec.id, t)  # #118
    db.commit()
    db.refresh(t)
    return {"ok": True, "transaction_id": t.id}


@app.get("/api/accounts/{account_id}/forecast")
def forecast(account_id: int, days: int = 90,
             start: date | None = None, end: date | None = None,
             today: date | None = None,
             user: User = Depends(current_user), db: Session = Depends(get_db)):
    # The window is checked before anything is looked up (#185).
    if not 0 <= days <= FORECAST_MAX_DAYS:
        raise HTTPException(400, f"days must be 0 to {FORECAST_MAX_DAYS}")
    if start is not None and end is not None:
        _check_window(start, end)
    acc = _account_with_perm(db, user, account_id, "read")
    today = _viewer_today(today)
    if start is None or end is None:
        start = today
        end = today + timedelta(days=days)
    data = build_forecast(db, acc, start, end)
    # Today-dated cleared balance, independent of the requested window, so
    # the UI can show "where the account is right now" next to the forecast.
    data["current_balance"] = round(_current_balance(db, acc, today), 2)
    # How many lines wait on the Unmatched list, for the owner only (only
    # the owner can match them, #223); 0 for the people it's shared with.
    data["bank_unmatched_count"] = (_unmatched_query(db, acc.id).count()
                                    if _user_level(db, user, acc.id) == "owner" else 0)
    return data


# ---------- Backup: export / import ----------
def _export_accounts(db: Session, user: User, wanted: set[int] | None) -> list:
    """The accounts a user may put in a backup: the ones they can edit,
    narrowed to `wanted` when given."""
    editable = _user_editable_accounts(db, user, include_archived=True)
    if wanted is None:
        return editable
    accounts = [a for a in editable if a.id in wanted]
    if not accounts:
        raise HTTPException(404, "No matching accounts found")
    return accounts


def _accounts_detail(accounts) -> str:
    return f"{len(accounts)} account{'' if len(accounts) == 1 else 's'}"


# "Download my data": the readable JSON copy PRIVACY.md promises, a copy to
# read and not a backup (decided 2026-11-16, #193). The path is kept from when
# this was the backup, so scripts reading it keep working.
@app.get("/api/backup/export")
def backup_export(request: Request, account_ids: str | None = None,
                  user: User = Depends(current_user), db: Session = Depends(get_db)):
    wanted = None
    if account_ids:
        try:
            wanted = {int(x) for x in account_ids.split(",") if x.strip()}
        except ValueError:
            raise HTTPException(400, "Invalid account_ids (must be comma-separated integers)")
    accounts = _export_accounts(db, user, wanted)
    payload = export_user(db, user, accounts=accounts)
    record_event(db, "data_downloaded", request, user=user, detail=_accounts_detail(accounts))
    filename = f"walletweather-my-data-{date.today().isoformat()}.json"
    return JSONResponse(
        content=payload,
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


class BackupExportIn(BaseModel):
    passphrase: str = Field(max_length=1024)
    account_ids: list[int] | None = None


# An encrypted backup (#193). A POST so the passphrase never sits in a URL
# or an access log.
@app.post("/api/backup/export")
def backup_export_encrypted(body: BackupExportIn, request: Request,
                            user: User = Depends(current_user), db: Session = Depends(get_db)):
    problem = passphrase_problem(body.passphrase)
    if problem:
        raise HTTPException(400, problem)
    accounts = _export_accounts(db, user, set(body.account_ids) if body.account_ids else None)
    # A sealed backup carries the bank connection; Download my data never does.
    payload = seal(export_user(db, user, accounts=accounts, include_bank=True), body.passphrase)
    record_event(db, "backup_exported", request, user=user, detail=_accounts_detail(accounts))
    filename = f"walletweather-backup-{date.today().isoformat()}.json"
    return JSONResponse(
        content=payload,
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


def _unwrap_upload(payload, passphrase) -> tuple[dict, bool]:
    try:
        return unwrap(payload, passphrase)
    except BackupLocked as e:
        raise HTTPException(400, str(e))
    except ValueError as e:
        raise HTTPException(400, str(e))


class BackupPreviewIn(BaseModel):
    payload: dict
    passphrase: str | None = Field(default=None, max_length=1024)


@app.post("/api/backup/preview")
def backup_preview(body: BackupPreviewIn, user: User = Depends(current_user)):
    """What a backup file holds, so the restore screen can list its accounts
    before anything changes (#193). Opens an encrypted one with the
    passphrase; changes nothing."""
    data, encrypted = _unwrap_upload(body.payload, body.passphrase)
    if not isinstance(data.get("accounts"), list):
        raise HTTPException(400, "Not a valid backup file (missing 'accounts').")
    names = [str(a.get("name") or "") for a in data["accounts"] if isinstance(a, dict)]
    return {"encrypted": encrypted, "accounts": names}


class ImportIn(BaseModel):
    mode: str = "merge"  # 'merge' or 'replace'
    payload: dict
    account_names: list[str] | None = None  # if set, only import these by name
    passphrase: str | None = Field(default=None, max_length=1024)  # for an encrypted file (#193)


@app.post("/api/backup/import")
def backup_import(body: ImportIn, request: Request,
                  user: User = Depends(current_user), db: Session = Depends(get_db)):
    # Opened before anything is touched: a wrong passphrase changes nothing.
    data, encrypted = _unwrap_upload(body.payload, body.passphrase)
    try:
        counts = import_user(db, user, data, mode=body.mode,
                             account_names=body.account_names)
    except ValueError as e:
        db.rollback()
        raise HTTPException(400, str(e))
    n = counts.get("accounts", 0)
    record_event(db, "backup_imported", request, user=user,
                 detail=f"{body.mode}, {n} account{'' if n == 1 else 's'}"
                        + ("" if encrypted else ", unencrypted file"))
    return {"ok": True, "imported": counts, "encrypted": encrypted}


# ---------- Bank sync with SimpleFIN (bank-sync phase 2, #194) ----------
# Off until an admin switches it on (decided 2026-11-16, question 3). Each user
# connects their own SimpleFIN Bridge, matches its bank accounts to accounts
# they own (question 7) from a start date (question 4, at most 90 days back,
# decided 2026-11-16 in phase 2), and Sync now lands new posted lines as paid.
# With two-factor on, connecting and disconnecting ask for a fresh code
# (question 8). Browser sessions only for now; phase 3 opens status and Sync
# now to API tokens.
BANK_SYNC_KEY = "bank_sync_enabled"
BANK_START_MAX_DAYS = simplefin.MAX_DAYS_PER_REQUEST
# Bridge disables a token that asks much more than 24 times a day: Sync now
# stops at 20 calls in 24 hours (decided 2026-11-16, phase 2).
BANK_CALLS_PER_DAY = 20
# How far back each sync looks again before the last one, for lines a bank
# posts late. Lines already here are recognised by their bank_ref.
BANK_OVERLAP_DAYS = 14


def bank_sync_enabled(db: Session) -> bool:
    row = db.get(AdminSetting, BANK_SYNC_KEY)
    return bool(row and row.value == "true")


def _bank_allowed(db: Session, user: User) -> None:
    if not bank_sync_enabled(db):
        raise HTTPException(403, "Bank sync is switched off on this instance. An admin can "
                                 "switch it on in Admin.")
    if is_demo_email(user.email):
        raise HTTPException(403, "The demo user can't connect a bank.")


def _bank_connection(db: Session, user: User) -> BankConnection | None:
    return db.query(BankConnection).filter_by(user_id=user.id).first()


def bank_account_ref(bank_account_id: str) -> str:
    return hashlib.sha256(f"simplefin-account:{bank_account_id}".encode()).hexdigest()


def bank_txn_ref(bank_account_id: str, txn_id: str) -> str:
    return hashlib.sha256(f"simplefin:{bank_account_id}:{txn_id}".encode()).hexdigest()


def _bank_listing(conn: BankConnection) -> list[dict]:
    try:
        rows = json.loads(decrypt_str(conn.accounts_enc)) if conn.accounts_enc else []
    except Exception:
        rows = []
    return rows if isinstance(rows, list) else []


def _set_bank_listing(conn: BankConnection, accounts: list[dict]) -> None:
    conn.accounts_enc = encrypt_str(json.dumps(
        [{"id": a["id"], "name": a["name"], "org": a["org"]} for a in accounts]))


def _bank_calls(conn: BankConnection, now: datetime) -> list[datetime]:
    try:
        times = [datetime.fromisoformat(x) for x in json.loads(conn.calls_json or "[]")]
    except (ValueError, TypeError):
        times = []
    return sorted(t for t in times if now - t < timedelta(days=1))


def _bank_call_wait(conn: BankConnection, now: datetime) -> int:
    """Seconds until another call to SimpleFIN is allowed; 0 when it is."""
    calls = _bank_calls(conn, now)
    if len(calls) < BANK_CALLS_PER_DAY:
        return 0
    return max(1, math.ceil((calls[len(calls) - BANK_CALLS_PER_DAY] + timedelta(days=1) - now)
                            .total_seconds()))


def _note_bank_call(conn: BankConnection, now: datetime) -> None:
    conn.calls_json = json.dumps([t.isoformat() for t in _bank_calls(conn, now) + [now]])


def _bank_status(db: Session, user: User) -> dict:
    conn = _bank_connection(db, user)
    out = {"enabled": bank_sync_enabled(db), "connected": conn is not None,
           "start_max_days": BANK_START_MAX_DAYS}
    if not conn:
        return out
    now = datetime.utcnow()
    links = {l.bank_account_ref: l for l in db.query(BankAccountLink).filter_by(connection_id=conn.id)}
    accounts = []
    for a in _bank_listing(conn):
        ref = bank_account_ref(a["id"])
        link = links.get(ref)
        accounts.append({
            "ref": ref, "name": a.get("name") or "", "org": a.get("org") or "",
            "account_id": link.account_id if link else None,
            "start_date": link.start_date.isoformat() if link else None,
            "synced_through": link.synced_through.isoformat() if link and link.synced_through else None,
            # Synced lines that paid no planned line, still to look at (#196).
            "unmatched_count": _unmatched_query(db, link.account_id).count() if link else 0,
        })
    wait = _bank_call_wait(conn, now)
    out.update(_bank_short_status(db, user))
    out.update({
        "connected_at": conn.created_at.isoformat() + "Z",
        "accounts": accounts,
        "last_sync_at": conn.last_sync_at.isoformat() + "Z" if conn.last_sync_at else None,
        "last_sync_ok": conn.last_sync_ok,
        "last_sync_status": conn.last_sync_status,
        "syncs_left_today": max(0, BANK_CALLS_PER_DAY - len(_bank_calls(conn, now))),
        "sync_wait_seconds": wait,
    })
    return out


@app.get("/api/bank")
def bank_status(user: User = Depends(current_session_user), db: Session = Depends(get_db)):
    """Whether bank sync is on, and this user's connection: its bank accounts,
    what each is matched to, and how the last sync went. Never the access
    address."""
    return _bank_status(db, user)


class BankConnectIn(BaseModel):
    token: str = Field(min_length=1, max_length=2000)
    code: str | None = Field(default=None, max_length=40)


@app.post("/api/bank/connect")
def bank_connect(body: BankConnectIn, request: Request,
                 user: User = Depends(current_session_user), db: Session = Depends(get_db)):
    """Claim a SimpleFIN setup token and list the bank accounts it reaches."""
    _bank_allowed(db, user)
    if _bank_connection(db, user):
        raise HTTPException(409, "You already have a bank connected. Disconnect it first.")
    _confirm_code_for(db, request, user, body.code, "bank connection")
    try:
        access = simplefin.claim(body.token)
    except simplefin.SimpleFINError as e:
        raise HTTPException(e.status, str(e))
    # The token is used up now, so the address is kept even if the listing
    # below fails: the next Sync now lists the accounts again.
    now = datetime.utcnow()
    conn = BankConnection(user_id=user.id, access_url_enc=encrypt_str(access), calls_json="[]")
    db.add(conn)
    try:
        _note_bank_call(conn, now)
        listing = simplefin.fetch_accounts(access, balances_only=True)
        _set_bank_listing(conn, listing["accounts"])
    except simplefin.SimpleFINError as e:
        conn.last_sync_at, conn.last_sync_ok, conn.last_sync_status = now, False, str(e)[:300]
    db.commit()
    record_event(db, "bank_connected", request, user=user,
                 detail=f"{len(_bank_listing(conn))} bank accounts")
    return _bank_status(db, user)


class BankLinkIn(BaseModel):
    ref: str = Field(min_length=64, max_length=64)
    account_id: int | None = None
    start_date: date | None = None


class BankLinksIn(BaseModel):
    links: list[BankLinkIn] = Field(max_length=100)


@app.put("/api/bank/links")
def bank_set_links(body: BankLinksIn, request: Request,
                   user: User = Depends(current_session_user), db: Session = Depends(get_db)):
    """Match bank accounts to the user's own accounts, each from a start date
    (today unless given, at most 90 days back). account_id null leaves a bank
    account out. Bank accounts not listed keep what they had."""
    _bank_allowed(db, user)
    conn = _bank_connection(db, user)
    if not conn:
        raise HTTPException(404, "No bank is connected.")
    known = {bank_account_ref(a["id"]) for a in _bank_listing(conn)}
    today = date.today()
    wanted: dict[str, BankLinkIn] = {}
    for l in body.links:
        if l.ref not in known:
            raise HTTPException(404, "That bank account isn't on this connection.")
        if l.ref in wanted:
            raise HTTPException(400, "A bank account is listed twice.")
        wanted[l.ref] = l
        if l.account_id is not None:
            # Only an account's owner links it to a bank (question 7). 404,
            # like every account check, so ids don't leak.
            _account_with_perm(db, user, l.account_id, "owner")
            start = l.start_date or today
            if start > today or start < today - timedelta(days=BANK_START_MAX_DAYS):
                raise HTTPException(400, f"The start date must be today or up to "
                                         f"{BANK_START_MAX_DAYS} days back.")
    existing = {l.bank_account_ref: l for l in db.query(BankAccountLink).filter_by(connection_id=conn.id)}
    after = {ref: link.account_id for ref, link in existing.items()}
    for ref, l in wanted.items():
        if l.account_id is None:
            after.pop(ref, None)
        else:
            after[ref] = l.account_id
    if len(set(after.values())) != len(after):
        raise HTTPException(400, "Each of your accounts can be matched to one bank account only.")
    # Matches that go or move are deleted first, so moving an account from
    # one bank account to another never trips the one-match-per-account rule.
    for ref, l in wanted.items():
        link = existing.get(ref)
        if link and link.account_id != l.account_id:
            db.delete(link)
            existing.pop(ref)
    db.flush()
    for ref, l in wanted.items():
        if l.account_id is None:
            continue
        start, link = l.start_date or today, existing.get(ref)
        if link is None:
            db.add(BankAccountLink(connection_id=conn.id, bank_account_ref=ref,
                                   account_id=l.account_id, start_date=start))
        elif link.start_date != start:
            # A new start date is fetched again from that date.
            link.start_date, link.synced_through = start, None
    db.commit()
    return _bank_status(db, user)


class BankNewAccountIn(BaseModel):
    ref: str = Field(min_length=64, max_length=64)
    name: str = Field(min_length=1, max_length=ACCOUNT_NAME_MAX)
    start_date: date | None = None


@app.post("/api/bank/accounts")
def bank_create_account(body: BankNewAccountIn, request: Request,
                        user: User = Depends(current_session_user), db: Session = Depends(get_db)):
    """Makes a new account of the user's own from a bank account that has no
    match, matches it from the start date and syncs straight away (#215). Its
    starting balance is worked out from the bank's balance and the lines that
    come in, so the account's balance today is the bank's. If the sync can't
    run, nothing is made."""
    _bank_allowed(db, user)
    conn = _bank_connection(db, user)
    if not conn:
        raise HTTPException(404, "No bank is connected.")
    if body.ref not in {bank_account_ref(a["id"]) for a in _bank_listing(conn)}:
        raise HTTPException(404, "That bank account isn't on this connection.")
    if db.query(BankAccountLink).filter_by(connection_id=conn.id, bank_account_ref=body.ref).first():
        raise HTTPException(400, "That bank account is already matched to one of your accounts.")
    name = body.name.strip()
    if not name:
        raise HTTPException(400, "Give the account a name.")
    today = date.today()
    start = body.start_date or today
    if start > today or start < today - timedelta(days=BANK_START_MAX_DAYS):
        raise HTTPException(400, f"The start date must be today or up to {BANK_START_MAX_DAYS} days back.")
    acc = Account(owner_id=user.id, starting_date=start)
    acc.name = name
    acc.starting_balance = Decimal("0")
    db.add(acc)
    db.flush()
    db.add(AccountPermission(account_id=acc.id, user_id=user.id, level="owner"))
    db.add(BankAccountLink(connection_id=conn.id, bank_account_ref=body.ref, account_id=acc.id,
                           start_date=start))
    db.commit()
    try:
        result = _bank_sync(db, user, conn, request, trigger="manual", calibrate={acc.id})
    except HTTPException:
        # The sync didn't run (the limit, SimpleFIN down, another sync going):
        # take away only what this request made, so the account isn't left at
        # a balance of 0 and can be made again.
        db.rollback()
        made = db.get(Account, acc.id)
        if made is not None:
            db.delete(made)
            db.commit()
        raise
    db.refresh(acc)
    record_event(db, "bank_account_created", request, user=user, detail=f"account #{acc.id}")
    return {"account_id": acc.id, "name": acc.name, "starting_balance": float(acc.starting_balance),
            "balance_known": acc.id in result["calibrated"],
            "added": result["added"], "matched": result["matched"], "skipped": result["skipped"],
            "messages": result["messages"], "status": _bank_status(db, user)}


# One sync per user at a time (#195): the daily sync and a Sync now never run
# together. The server is one process (the Dockerfile's uvicorn), so a lock
# in memory is enough.
_bank_sync_locks: dict[int, threading.Lock] = {}
_bank_sync_locks_guard = threading.Lock()


def _bank_lock(user_id: int) -> threading.Lock:
    with _bank_sync_locks_guard:
        return _bank_sync_locks.setdefault(user_id, threading.Lock())


def _bank_sync(db: Session, user: User, conn: BankConnection, request: Request | None,
               trigger: str = "manual", calibrate: set[int] | None = None) -> dict:
    lock = _bank_lock(user.id)
    if not lock.acquire(blocking=False):
        raise HTTPException(409, "A sync is already running. Try again in a minute.")
    try:
        return _bank_sync_locked(db, user, conn, request, trigger, calibrate or set())
    finally:
        lock.release()


def _bank_sync_locked(db: Session, user: User, conn: BankConnection, request: Request | None,
                      trigger: str, calibrate: set[int] = frozenset()) -> dict:
    links = db.query(BankAccountLink).filter_by(connection_id=conn.id).all()
    if not links:
        raise HTTPException(400, "Match at least one bank account to one of your accounts first.")
    now = datetime.utcnow()
    wait = _bank_call_wait(conn, now)
    if wait:
        minutes = math.ceil(wait / 60)
        raise HTTPException(
            429, f"Bank sync has asked SimpleFIN {BANK_CALLS_PER_DAY} times in the last 24 hours, "
                 f"the most it allows without risking your connection. It can run again in "
                 f"{minutes} minute{'s' if minutes != 1 else ''}.",
            headers={"Retry-After": str(wait)})
    today = date.today()
    floor = today - timedelta(days=BANK_START_MAX_DAYS)

    def link_start(l: BankAccountLink) -> date:
        since = l.synced_through - timedelta(days=BANK_OVERLAP_DAYS) if l.synced_through else l.start_date
        return max(l.start_date, since, floor)

    start = min(link_start(l) for l in links)
    _note_bank_call(conn, now)
    db.commit()   # the call counts even if it fails
    try:
        data = simplefin.fetch_accounts(decrypt_str(conn.access_url_enc), start=start)
    except simplefin.SimpleFINError as e:
        conn.last_sync_at, conn.last_sync_ok, conn.last_sync_status = now, False, str(e)[:300]
        if e.revoked:
            conn.needs_reconnect = True
        for l in links:   # the failure shows in each account's sync log
            db.add(BankSyncRun(user_id=user.id, account_id=l.account_id, run_at=now,
                               trigger=trigger, error=str(e)[:300]))
        db.commit()
        record_event(db, "bank_sync_failed", request, user=user,
                     detail=("revoked" if e.revoked else f"HTTP {e.status}") + f", {trigger}")
        raise HTTPException(e.status, str(e))
    if data["accounts"]:
        _set_bank_listing(conn, data["accounts"])
    by_account = {bank_account_ref(a["id"]): a for a in data["accounts"]}
    added = skipped = matched = 0
    calibrated: set[int] = set()
    for link in links:
        acc = db.get(Account, link.account_id)
        if acc is None:
            continue
        run = BankSyncRun(user_id=user.id, account_id=acc.id, run_at=now, trigger=trigger)
        db.add(run)
        db.flush()
        bank_acc = by_account.get(link.bank_account_ref)
        if bank_acc is None:
            run.error = "SimpleFIN didn't list this bank account this time."
            continue
        refs = {r for (r,) in db.query(Transaction.bank_ref)
                .filter(Transaction.account_id == acc.id, Transaction.bank_ref.isnot(None))}
        bills = _bills_to_match(db, acc.id)
        # Paid lines that came by CSV or by hand, by date, amount and
        # description (the CSV import's own test for a duplicate). A bank
        # line that finds one claims it instead of landing a second.
        unclaimed: dict[tuple, list[Transaction]] = {}
        for t in db.query(Transaction).filter(Transaction.account_id == acc.id,
                                              Transaction.bank_ref.is_(None),
                                              Transaction.is_actual.is_(True)):
            d = t.actual_date or t.forecast_date
            if d:
                unclaimed.setdefault((d, round(float(t.amount), 2),
                                      (t.description or "").strip().lower()), []).append(t)
        for tx in bank_acc["transactions"]:
            if tx["date"] < link.start_date:
                continue
            ref = bank_txn_ref(bank_acc["id"], tx["id"])
            if ref in refs:
                run.skipped += 1
                continue
            refs.add(ref)
            raw = tx["description"]
            short = simplefin.short_name(raw)
            # A CSV row may carry the bank's full text or a short name.
            keys = [(tx["date"], round(float(tx["amount"]), 2), name.strip().lower())
                    for name in ([raw, short] if short else [raw])]
            claim = next((k for k in keys if unclaimed.get(k)), None)
            if claim:
                unclaimed[claim].pop().bank_ref = ref
                run.skipped += 1
                continue
            # A planned bill or income line close in date and amount is
            # paid by this line instead of a second line landing (#196).
            hit = _bill_for_bank_line(bills, tx["date"], tx["amount"], short or raw)
            if hit:
                rec, occ = hit
                _pay_bill_from_bank(db, rec, occ, tx["date"], tx["amount"], ref, raw, "auto", run.id)
                bills["covered"].add((rec.id, occ))
                run.matched += 1
                continue
            _bank_own_line(db, user, acc.id, tx["date"], tx["amount"], raw, ref, run.id)
            run.added += 1
        added, skipped = added + run.added, skipped + run.skipped
        matched += run.matched
        link.synced_through = today
        if acc.id in calibrate and bank_acc.get("balance") is not None:
            # A new account made from this bank account (#215): its starting
            # balance is what makes today's balance the bank's, given the
            # lines just brought in (it has no others).
            db.flush()
            landed = sum((t.amount for t in db.query(Transaction)
                          .filter(Transaction.account_id == acc.id, Transaction.is_actual.is_(True))),
                         Decimal("0"))
            acc.starting_balance = bank_acc["balance"] - landed
            calibrated.add(acc.id)
    status = (f"{added} new line{'' if added == 1 else 's'}, "
              + (f"{matched} matched a bill, " if matched else "")
              + f"{skipped} already here")
    if data["messages"]:
        status += ". SimpleFIN said: " + "; ".join(data["messages"])
    conn.last_sync_at, conn.last_sync_ok, conn.last_sync_status = now, True, status[:300]
    conn.last_ok_at, conn.needs_reconnect = now, False
    db.commit()
    record_event(db, "bank_sync_run", request, user=user,
                 detail=f"{added} added, {matched} matched, {skipped} skipped, {trigger}")
    return {"added": added, "matched": matched, "skipped": skipped, "messages": data["messages"],
            "calibrated": sorted(calibrated)}


# ---------- Bills matched by bank sync (#196) ----------
# A bank line pays a planned bill or income line on the same account when it
# goes the same way (money out or in), its amount is within the bill's
# match_percent and its date within match_days of one of the bill's dates
# that isn't paid or deleted yet. The nearest date wins; a tie is left
# unmatched, to be matched by hand. A bank line is only ever matched as it
# arrives, so one un-matched by hand isn't matched again.

def _bills_to_match(db: Session, account_id: int) -> dict:
    recs = (db.query(RecurringTransaction)
            .filter(RecurringTransaction.account_id == account_id, RecurringTransaction.active == True)
            .all())
    covered = {(rid, d) for rid, d in
               db.query(Transaction.recurring_id, Transaction.forecast_date)
               .filter(Transaction.account_id == account_id, Transaction.recurring_id.isnot(None),
                       Transaction.forecast_date.isnot(None))}
    skipped = set()
    if recs:
        skipped = set(db.query(RecurringSkip.recurring_id, RecurringSkip.skip_date)
                      .filter(RecurringSkip.recurring_id.in_([r.id for r in recs])))
    taught = {r.id: _match_key(r.match_text) for r in recs if r.match_text_enc}
    return {"recs": recs, "covered": covered, "skipped": skipped, "taught": taught}


def _match_key(text: str | None) -> str:
    """How a taught name is compared (#224): ignoring case and extra spaces."""
    return " ".join((text or "").lower().split())


def _line_name(t: Transaction) -> str:
    """The name a bill learns from a synced or alert line (#224): its short
    name, worked out again from the bank's text in its notes when the line
    was renamed by hand."""
    short = simplefin.short_name(t.notes) if t.notes else None
    return short or t.description


def _bill_for_bank_line(bills: dict, day: date, amount: Decimal, name: str | None = None):
    """(bill, date) the bank line pays, or None (no match, or a tie). A bill
    taught the line's name (#224) takes it at any amount going its way within
    its days, and is preferred over the bills that fit by amount."""
    taught = bills.get("taught") or {}
    key = _match_key(name) if name and taught else None
    found = []
    for rec in bills["recs"]:
        planned = rec.amount
        if not planned or not amount or (planned < 0) != (amount < 0):
            continue
        named = key is not None and taught.get(rec.id) == key
        if not named and abs(amount - planned) > abs(planned) * Decimal(rec.match_percent) / 100:
            continue
        reach = timedelta(days=rec.match_days)
        for occ, _amount, _desc in _occurrences(rec, day - reach, day + reach):
            if (rec.id, occ) not in bills["covered"] and (rec.id, occ) not in bills["skipped"]:
                found.append((abs((occ - day).days), rec, occ))
    if key is not None:
        mine = [f for f in found if taught.get(f[1].id) == key]
        if mine:
            found = mine
    if not found:
        return None
    found.sort(key=lambda f: f[0])
    if len(found) > 1 and found[1][0] == found[0][0]:
        return None
    return found[0][1], found[0][2]


def _source_cols(source: str, ref: str, run_id: int | None) -> dict:
    """The columns that say where a line came from: a bank sync line
    (bank_ref, bank_sync_run_id) or an email alert's (mail_ref, mail_run_id,
    #209). The match columns (bank_match, bank_text, bank_left) are shared."""
    if source == "alert":
        return {"mail_ref": ref, "mail_run_id": run_id}
    return {"bank_ref": ref, "bank_sync_run_id": run_id}


def _pay_bill_from_bank(db: Session, rec: RecurringTransaction, occ: date, day: date,
                        amount: Decimal, ref: str, raw: str, how: str,
                        run_id: int | None, source: str = "bank") -> Transaction:
    """Marks one of a bill's dates paid with the bank's date and amount (or
    the email alert's, source "alert"), as marking it paid by hand does,
    keeping the line's own text."""
    t = Transaction(account_id=rec.account_id, recurring_id=rec.id, category_id=rec.category_id,
                    forecast_date=occ, actual_date=day, is_actual=True, bank_match=how,
                    **_source_cols(source, ref, run_id))
    t.description = rec.description
    t.amount = amount
    t.forecast_amount = rec.amount
    t.notes = rec.notes
    t.bank_text = raw
    db.add(t)
    db.flush()
    _copy_recurring_tags(db, rec.id, t)
    return t


def _bank_own_line(db: Session, user: User, account_id: int, day: date, amount: Decimal,
                   raw: str, ref: str, run_id: int | None, left: bool = False,
                   source: str = "bank") -> Transaction:
    """A bank line (or an email alert's, source "alert") landed as its own
    paid line. Tag rules see the bank's full text, as they did before names
    were shortened (#213); then the line takes the short name and keeps the
    full text in its notes."""
    t = Transaction(account_id=account_id, actual_date=day, forecast_date=day, is_actual=True,
                    bank_left=left, **_source_cols(source, ref, run_id))
    t.description = raw
    t.amount = amount
    db.add(t)
    db.flush()
    _apply_tag_rules(db, user, t)
    short = simplefin.short_name(raw)
    if short:
        t.description, t.notes = short, raw[:NOTES_MAX_LEN]
    return t


def _line_source(t: Transaction) -> str:
    """'alert' for a line an email alert brought in, else 'bank'."""
    return "alert" if t.mail_ref else "bank"


def _bank_text_of(t: Transaction) -> str:
    """A synced line's bank text: the full text in its notes when its name
    was shortened from it, else its name."""
    if t.notes and simplefin.short_name(t.notes) == t.description:
        return t.notes
    return t.description


def _unmatched_query(db: Session, account_id: int):
    """Synced lines that paid no planned line and are still to look at."""
    return (db.query(Transaction)
            .filter(Transaction.account_id == account_id,
                    or_(Transaction.bank_ref.isnot(None), Transaction.mail_ref.isnot(None)),
                    Transaction.bank_match.is_(None), Transaction.bank_left.is_(False),
                    Transaction.recurring_id.is_(None), Transaction.transfer_id.is_(None),
                    Transaction.is_actual.is_(True)))


def _unmatched_line(db: Session, acc: Account, txn_id: int) -> Transaction:
    t = db.get(Transaction, txn_id)
    if (t is None or t.account_id != acc.id or (t.bank_ref is None and t.mail_ref is None)
            or t.bank_match is not None
            or t.bank_left or t.recurring_id is not None or t.transfer_id is not None or not t.is_actual):
        raise HTTPException(404, "That line isn't on the Unmatched list.")
    return t


MATCH_BY_HAND_DAYS = 60   # how far either side the planned lines offered reach


@app.get("/api/accounts/{account_id}/bank-unmatched")
def bank_unmatched(account_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    """Synced lines and email alerts' lines that matched no planned line,
    newest first (the owner)."""
    acc = _sync_log_account(db, user, account_id)
    rows = (_unmatched_query(db, acc.id)
            .order_by(Transaction.actual_date.desc(), Transaction.id.desc()).all())
    return {"count": len(rows),
            "lines": [{"id": t.id, "date": (t.actual_date or t.forecast_date).isoformat(),
                       "description": t.description, "amount": float(t.amount), "notes": t.notes,
                       "source": _line_source(t)}
                      for t in rows]}


@app.get("/api/accounts/{account_id}/bank-unmatched/{txn_id}/candidates")
def bank_unmatched_candidates(account_id: int, txn_id: int, user: User = Depends(current_user),
                              db: Session = Depends(get_db)):
    """The account's planned lines that aren't paid yet, nearest in date
    first, whatever a bill's match settings say."""
    acc = _sync_log_account(db, user, account_id)
    line = _unmatched_line(db, acc, txn_id)
    day = line.actual_date or line.forecast_date
    lo, hi = day - timedelta(days=MATCH_BY_HAND_DAYS), day + timedelta(days=MATCH_BY_HAND_DAYS)
    out = []
    for t in (db.query(Transaction)
              .filter(Transaction.account_id == acc.id, Transaction.is_actual.is_(False),
                      Transaction.transfer_id.is_(None), Transaction.forecast_date >= lo,
                      Transaction.forecast_date <= hi)):
        out.append({"transaction_id": t.id, "recurring_id": t.recurring_id,
                    "forecast_date": t.forecast_date.isoformat(), "description": t.description,
                    "amount": float(t.amount), "days_apart": abs((t.forecast_date - day).days)})
    bills = _bills_to_match(db, acc.id)
    for rec in bills["recs"]:
        for occ, amount, desc in _occurrences(rec, lo, hi):
            if (rec.id, occ) in bills["covered"] or (rec.id, occ) in bills["skipped"]:
                continue
            out.append({"transaction_id": None, "recurring_id": rec.id,
                        "forecast_date": occ.isoformat(), "description": desc,
                        "amount": float(amount), "days_apart": abs((occ - day).days)})
    out.sort(key=lambda c: (c["days_apart"], c["forecast_date"], c["description"].lower()))
    bank_text = _bank_text_of(line)
    return {"line": {"id": line.id, "date": day.isoformat(), "description": line.description,
                     "amount": float(line.amount), "source": _line_source(line),
                     "bank_text": bank_text if bank_text != line.description else None,
                     "learn_name": _line_name(line)},
            "candidates": out[:50],
            "choices": _match_choices(out, line.amount, day)[:50]}


def _match_choices(cands: list[dict], amount: Decimal, day: date) -> list[dict]:
    """The candidates as the match pop-in shows them (#222): one entry per
    bill, at its nearest open date, with all its open dates in `dates`; a
    planned line that isn't a bill's is an entry of its own. Each date says
    how the bank's line differs from it: `amount_diff` (bank minus planned)
    and `days_after` (the bank's date minus the planned date, so negative is
    early). Entries going the bank line's way come first, then the nearest."""
    groups: dict = {}
    for c in cands:
        planned = Decimal(str(c["amount"]))
        opt = {k: c[k] for k in ("transaction_id", "recurring_id", "forecast_date", "amount",
                                 "description", "days_apart")}
        opt["days_after"] = (day - date.fromisoformat(c["forecast_date"])).days
        opt["amount_diff"] = float(amount - planned)
        opt["same_direction"] = (planned < 0) == (amount < 0) and planned != 0
        key = ("r", c["recurring_id"]) if c["recurring_id"] is not None else ("t", c["transaction_id"])
        groups.setdefault(key, []).append(opt)
    choices = []
    for opts in groups.values():
        best = min(opts, key=lambda o: (o["days_apart"], o["forecast_date"]))
        choices.append({**best, "dates": sorted(opts, key=lambda o: o["forecast_date"])})
    choices.sort(key=lambda o: (not o["same_direction"], o["days_apart"], abs(o["amount_diff"]),
                                o["description"].lower()))
    return choices


@app.get("/api/accounts/{account_id}/bank-unmatched/near")
def bank_unmatched_near(account_id: int, transaction_id: int | None = None,
                        recurring_id: int | None = None, forecast_date: date | None = None,
                        user: User = Depends(current_user), db: Session = Depends(get_db)):
    """The Unmatched list's lines that could pay one planned line (#223): a
    saved one by `transaction_id`, or a bill's date by `recurring_id` and
    `forecast_date`. Within 60 days of its date; lines going its way first,
    then the nearest. Each says how it compares, as the candidates' choices
    do (amount_diff and days_after are the bank's line minus the planned)."""
    acc = _sync_log_account(db, user, account_id)
    planned = _planned_target(db, acc, transaction_id, recurring_id, forecast_date)
    day, want = date.fromisoformat(planned["forecast_date"]), Decimal(str(planned["amount"]))
    lo, hi = day - timedelta(days=MATCH_BY_HAND_DAYS), day + timedelta(days=MATCH_BY_HAND_DAYS)
    out = []
    for t in _unmatched_query(db, acc.id):
        when = t.actual_date or t.forecast_date
        if when is None or not lo <= when <= hi:
            continue
        text = _bank_text_of(t)
        out.append({"id": t.id, "date": when.isoformat(), "description": t.description,
                    "amount": float(t.amount), "source": _line_source(t),
                    "bank_text": text if text != t.description else None,
                    "learn_name": _line_name(t),
                    "days_apart": abs((when - day).days), "days_after": (when - day).days,
                    "amount_diff": float(t.amount - want),
                    "same_direction": (t.amount < 0) == (want < 0) and want != 0})
    out.sort(key=lambda x: (not x["same_direction"], x["days_apart"], abs(x["amount_diff"]), x["id"]))
    return {"planned": planned, "lines": out[:50]}


def _planned_target(db: Session, acc: Account, transaction_id: int | None,
                    recurring_id: int | None, forecast_date: date | None) -> dict:
    """A planned line that a bank line could pay, or the error saying why
    not: the same checks as matching by hand."""
    if transaction_id is not None:
        t = db.get(Transaction, transaction_id)
        if t is None or t.account_id != acc.id:
            raise HTTPException(404, "Planned line not found")
        if t.is_actual or t.transfer_id is not None or t.forecast_date is None:
            raise HTTPException(409, "That line is already paid, or is a transfer: pick a planned line.")
        return {"transaction_id": t.id, "recurring_id": t.recurring_id,
                "forecast_date": t.forecast_date.isoformat(), "description": t.description,
                "amount": float(t.amount)}
    if recurring_id is not None and forecast_date is not None:
        rec = db.get(RecurringTransaction, recurring_id)
        if rec is None or rec.account_id != acc.id:
            raise HTTPException(404, "Bill not found")
        occ = next(((d, a, s) for d, a, s in _occurrences(rec, forecast_date, forecast_date)
                    if d == forecast_date), None)
        if occ is None:
            raise HTTPException(400, "That bill has no date on that day.")
        bills = _bills_to_match(db, acc.id)
        if (rec.id, forecast_date) in bills["covered"] or (rec.id, forecast_date) in bills["skipped"]:
            raise HTTPException(409, "That date is already paid or was deleted: pick a planned line.")
        return {"transaction_id": None, "recurring_id": rec.id, "forecast_date": forecast_date.isoformat(),
                "description": occ[2], "amount": float(occ[1])}
    raise HTTPException(400, "Give transaction_id, or recurring_id and forecast_date.")


class BankMatchIn(BaseModel):
    """A planned line: a saved one by `transaction_id`, or a bill's date by
    `recurring_id` and `forecast_date`."""
    transaction_id: int | None = None
    recurring_id: int | None = None
    forecast_date: date | None = None
    # Teach the bill this line's name (#224): later lines with it pay the
    # bill (within its days, any amount), and those already unmatched are caught up.
    remember: bool = False


@app.post("/api/accounts/{account_id}/bank-unmatched/{txn_id}/match")
def bank_match_by_hand(account_id: int, txn_id: int, body: BankMatchIn,
                       user: User = Depends(current_user), db: Session = Depends(get_db)):
    """Pays a planned line with an unmatched bank line's date and amount; the
    bank line's separate line goes away."""
    acc = _sync_log_account(db, user, account_id)
    line = _unmatched_line(db, acc, txn_id)
    day, raw = line.actual_date or line.forecast_date, _bank_text_of(line)
    if body.transaction_id is not None:
        t = db.get(Transaction, body.transaction_id)
        if t is None or t.account_id != acc.id:
            raise HTTPException(404, "Planned line not found")
        if t.is_actual or t.transfer_id is not None:
            raise HTTPException(409, "That line is already paid, or is a transfer: pick a planned line.")
        if t.forecast_amount is None:
            t.forecast_amount = t.amount
        if t.forecast_date is None:
            t.forecast_date = day
        t.amount, t.actual_date, t.is_actual = line.amount, day, True
        t.bank_match, t.bank_text = "hand", raw
        if line.mail_ref:
            t.mail_ref, t.mail_run_id = line.mail_ref, line.mail_run_id
        else:
            t.bank_ref, t.bank_sync_run_id = line.bank_ref, line.bank_sync_run_id
        paid = t
    elif body.recurring_id is not None and body.forecast_date is not None:
        rec = db.get(RecurringTransaction, body.recurring_id)
        if rec is None or rec.account_id != acc.id:
            raise HTTPException(404, "Bill not found")
        occ = body.forecast_date
        if not any(d == occ for d, _a, _s in _occurrences(rec, occ, occ)):
            raise HTTPException(400, "That bill has no date on that day.")
        bills = _bills_to_match(db, acc.id)
        if (rec.id, occ) in bills["covered"] or (rec.id, occ) in bills["skipped"]:
            raise HTTPException(409, "That date is already paid or was deleted: pick a planned line.")
        src = _line_source(line)
        paid = _pay_bill_from_bank(
            db, rec, occ, day, line.amount, line.mail_ref or line.bank_ref, raw, "hand",
            line.mail_run_id if src == "alert" else line.bank_sync_run_id, src)
    else:
        raise HTTPException(400, "Give transaction_id, or recurring_id and forecast_date.")
    name = _line_name(line)
    db.delete(line)
    db.flush()
    also, learned = 0, None
    if body.remember and paid.recurring_id is not None:
        rec = db.get(RecurringTransaction, paid.recurring_id)
        rec.match_text = name[:MATCH_TEXT_MAX]
        learned = rec.match_text
        also = _catch_up_taught(db, acc, rec)
    db.commit()
    return {"ok": True, "transaction_id": paid.id, "learned": learned, "also_matched": also}


def _catch_up_taught(db: Session, acc: Account, rec: RecurringTransaction) -> int:
    """After a bill is taught a name (#224): lines already on the Unmatched
    list with that name pay its open dates, oldest first, each within the
    bill's days (at any amount going its way). How many did."""
    key = _match_key(rec.match_text)
    bills = _bills_to_match(db, acc.id)
    only = {"recs": [rec], "covered": bills["covered"], "skipped": bills["skipped"], "taught": {rec.id: key}}
    n = 0
    for t in (_unmatched_query(db, acc.id)
              .order_by(Transaction.actual_date, Transaction.id).all()):
        name = _line_name(t)
        if _match_key(name) != key:
            continue
        day = t.actual_date or t.forecast_date
        hit = _bill_for_bank_line(only, day, t.amount, name)
        if not hit:
            continue
        occ = hit[1]
        src = _line_source(t)
        _pay_bill_from_bank(db, rec, occ, day, t.amount, t.mail_ref or t.bank_ref, _bank_text_of(t), "auto",
                            t.mail_run_id if src == "alert" else t.bank_sync_run_id, src)
        only["covered"].add((rec.id, occ))
        db.delete(t)
        db.flush()
        n += 1
    return n


@app.post("/api/accounts/{account_id}/bank-unmatched/{txn_id}/leave")
def bank_leave_unmatched(account_id: int, txn_id: int, user: User = Depends(current_user),
                         db: Session = Depends(get_db)):
    """"Leave as its own line": takes it off the Unmatched list."""
    acc = _sync_log_account(db, user, account_id)
    _unmatched_line(db, acc, txn_id).bank_left = True
    db.commit()
    return {"ok": True}


@app.post("/api/transactions/{txn_id}/bank-unmatch")
def bank_unmatch(txn_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    """Undoes a match: the planned line goes back to planned and the bank
    line becomes its own paid line (off the Unmatched list), which isn't
    matched again."""
    t = db.get(Transaction, txn_id)
    if t is None:
        raise HTTPException(404, "Transaction not found")
    acc = _sync_log_account(db, user, t.account_id)
    if not t.bank_match:
        raise HTTPException(409, "That line wasn't matched by bank sync or an email alert.")
    src = _line_source(t)
    day = t.actual_date or t.forecast_date
    raw, amount = t.bank_text or t.description, t.amount
    ref, run_id = ((t.mail_ref, t.mail_run_id) if src == "alert" else (t.bank_ref, t.bank_sync_run_id))
    if t.recurring_id is not None:
        db.delete(t)   # the bill's date shows as planned again
    else:
        if t.forecast_amount is not None:
            t.amount = t.forecast_amount
        t.is_actual, t.actual_date = False, None
        t.bank_ref = t.bank_match = t.mail_ref = None
        t.bank_text = None
        t.bank_sync_run_id = t.mail_run_id = None
    db.flush()
    own = _bank_own_line(db, user, acc.id, day, amount, raw, ref, run_id, left=True, source=src)
    db.commit()
    return {"ok": True, "transaction_id": own.id}


def shorten_synced_names(db: Session) -> int:
    """Gives lines synced before #213 their short name, the bank's full text
    moving to their notes (after any notes already there). Lines whose name
    has no bank text in it (renamed, or added by hand) aren't touched, so
    this is safe on every start. Returns how many lines changed."""
    changed = 0
    for t in db.query(Transaction).filter(Transaction.bank_ref.isnot(None),
                                          Transaction.bank_match.is_(None)):
        raw = t.description
        short = simplefin.short_name(raw)
        if not short:
            continue
        t.description = short
        t.notes = (f"{t.notes}\n\n{raw}" if t.notes else raw)[:NOTES_MAX_LEN]
        changed += 1
    if changed:
        db.commit()
    return changed


@app.post("/api/bank/sync")
def bank_sync_now(request: Request, user: User = Depends(current_user),
                  db: Session = Depends(get_db)):
    """Bring in new posted lines from every matched bank account. A token
    with write access may (#195, for the iOS app); a read-only one may not."""
    _bank_allowed(db, user)
    conn = _bank_connection(db, user)
    if not conn:
        raise HTTPException(404, "No bank is connected.")
    result = _bank_sync(db, user, conn, request, trigger="manual")
    return {**result, "status": _bank_short_status(db, user)}


# ---------- The daily sync (#195) ----------
# Each connected user is synced about once a day: due 23½ hours after the
# last try (the check runs every 30 minutes), 6 hours after a failure, and
# not at all once SimpleFIN has stopped accepting the connection, until the
# user connects again. A user over the daily call limit waits.
BANK_SYNC_EVERY = timedelta(hours=23, minutes=30)
BANK_RETRY_AFTER_FAILURE = timedelta(hours=6)
BANK_FAILING_WARN_AFTER = timedelta(days=1)


def bank_sync_due(db: Session, conn: BankConnection, now: datetime) -> bool:
    if conn.needs_reconnect or _bank_call_wait(conn, now):
        return False
    if not db.query(BankAccountLink).filter_by(connection_id=conn.id).first():
        return False
    if conn.last_sync_at is None:
        return True
    gap = BANK_RETRY_AFTER_FAILURE if conn.last_sync_ok is False else BANK_SYNC_EVERY
    return now - conn.last_sync_at >= gap


def run_due_bank_syncs(db: Session, now: datetime | None = None) -> dict:
    """Sync every connected user who is due. One user's failure is recorded
    on their connection and doesn't stop the others."""
    out = {"synced": 0, "failed": 0}
    if not bank_sync_enabled(db):
        return out
    now = now or datetime.utcnow()
    for conn in db.query(BankConnection).order_by(BankConnection.id).all():
        user = db.get(User, conn.user_id)
        if user is None or user.disabled or is_demo_email(user.email) or not bank_sync_due(db, conn, now):
            continue
        try:
            _bank_sync(db, user, conn, None, trigger="schedule")
            out["synced"] += 1
        except Exception:
            db.rollback()
            out["failed"] += 1
    return out


def _bank_scheduler_loop():
    """Background daemon: every 30 minutes, run the daily syncs that are due."""
    while True:
        time.sleep(1800)
        db = SessionLocal()
        try:
            run_due_bank_syncs(db)
        except Exception:
            pass   # tried again in 30 minutes
        finally:
            db.close()


def _bank_short_status(db: Session, user: User) -> dict:
    """What an app needs to show the sync's state (#195): no bank account
    names, nothing about the connection itself."""
    conn = _bank_connection(db, user)
    out = {"enabled": bank_sync_enabled(db), "connected": conn is not None}
    if not conn:
        return out
    now = datetime.utcnow()
    linked = [l.account_id for l in db.query(BankAccountLink).filter_by(connection_id=conn.id)]
    failing_since = None
    if conn.last_sync_ok is False:
        failing_since = conn.last_ok_at or conn.created_at
    next_at = None
    if linked and not conn.needs_reconnect and bank_sync_enabled(db):
        gap = BANK_RETRY_AFTER_FAILURE if conn.last_sync_ok is False else BANK_SYNC_EVERY
        next_at = max(now, (conn.last_sync_at + gap) if conn.last_sync_at else now)
        wait = _bank_call_wait(conn, now)
        if wait:
            next_at = max(next_at, now + timedelta(seconds=wait))
    iso = lambda d: d.isoformat() + "Z" if d else None
    out.update({
        "linked_account_ids": linked,
        "last_sync_at": iso(conn.last_sync_at),
        "last_sync_ok": conn.last_sync_ok,
        "last_sync_status": conn.last_sync_status,
        "last_ok_at": iso(conn.last_ok_at),
        "needs_reconnect": bool(conn.needs_reconnect),
        "failing_since": iso(failing_since),
        "failing_over_a_day": bool(failing_since and now - failing_since > BANK_FAILING_WARN_AFTER),
        "next_sync_at": iso(next_at),
        "syncs_left_today": max(0, BANK_CALLS_PER_DAY - len(_bank_calls(conn, now))),
        "sync_wait_seconds": _bank_call_wait(conn, now),
    })
    return out


@app.get("/api/bank/status")
def bank_short_status(user: User = Depends(current_user), db: Session = Depends(get_db)):
    """The sync's state, for the Dashboard and apps; an API token may read it."""
    return _bank_short_status(db, user)


# ---------- The sync log (#195) ----------
def _sync_log_account(db: Session, user: User, account_id: int) -> Account:
    # The owner only, not the people the account is shared with; 404 like
    # every account check.
    return _account_with_perm(db, user, account_id, "owner")


@app.get("/api/accounts/{account_id}/bank-syncs")
def bank_sync_log(account_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    """This account's syncs, newest first (the last 200)."""
    acc = _sync_log_account(db, user, account_id)
    runs = (db.query(BankSyncRun).filter_by(account_id=acc.id, user_id=user.id)
            .order_by(BankSyncRun.run_at.desc(), BankSyncRun.id.desc()).limit(200).all())
    return [{"id": r.id, "run_at": r.run_at.isoformat() + "Z", "trigger": r.trigger,
             "added": r.added, "matched": r.matched, "skipped": r.skipped, "error": r.error}
            for r in runs]


@app.get("/api/accounts/{account_id}/bank-syncs/{run_id}")
def bank_sync_log_lines(account_id: int, run_id: int, user: User = Depends(current_user),
                        db: Session = Depends(get_db)):
    """The lines one sync brought in that are still there."""
    acc = _sync_log_account(db, user, account_id)
    run = db.get(BankSyncRun, run_id)
    if run is None or run.account_id != acc.id or run.user_id != user.id:
        raise HTTPException(404, "Sync not found")
    rows = (db.query(Transaction).filter_by(account_id=acc.id, bank_sync_run_id=run.id)
            .order_by(Transaction.actual_date, Transaction.id).all())
    return {"id": run.id, "run_at": run.run_at.isoformat() + "Z", "trigger": run.trigger,
            "added": run.added, "matched": run.matched, "skipped": run.skipped, "error": run.error,
            "lines": [{"id": t.id, "date": (t.actual_date or t.forecast_date).isoformat(),
                       "description": t.description, "amount": float(t.amount),
                       # Paid a planned line (#196): auto or hand; else None.
                       "matched": t.bank_match} for t in rows]}


class BankDisconnectIn(BaseModel):
    code: str | None = Field(default=None, max_length=40)


@app.post("/api/bank/disconnect")
def bank_disconnect(body: BankDisconnectIn, request: Request,
                    user: User = Depends(current_session_user), db: Session = Depends(get_db)):
    """Forget the SimpleFIN address and the matches. Lines already brought in
    stay. Allowed with bank sync switched off, so a connection can always be
    removed."""
    conn = _bank_connection(db, user)
    if not conn:
        raise HTTPException(404, "No bank is connected.")
    _confirm_code_for(db, request, user, body.code, "bank disconnection")
    db.delete(conn)
    db.commit()
    record_event(db, "bank_disconnected", request, user=user)
    return _bank_status(db, user)


# ---------- Email alerts (bank-alert-emails phase 1, #206) ----------
# A user's bank sends an alert for every transaction; the server reads those
# mails from the user's own mailbox and lands each as a paid line marked
# "from an alert". Decided 2026-11-16 (docs/dev/decisions/bank-alert-emails.md):
# off until an admin switches it on, its own switch (question 2); either way
# of signing in to Microsoft (question 1); one folder, only taught senders,
# the mailbox never changed (question 3); a paid line (question 4); a mail
# failing the sender check never becomes a line and is shown as "may not be
# from your bank" (question 6). Browser sessions only in phase 1; phase 2
# adds the schedule and opens Check now to tokens.
MAIL_ALERTS_KEY = "mail_alerts_enabled"
MAIL_START_MAX_DAYS = 30
MAIL_LINES_PER_CHECK = 50          # never more lines from one check
MAIL_BODIES_PER_CHECK = 100        # mails opened in one check
MAIL_SCAN_LIMIT = 1000             # mails listed in one check
MAIL_OVERLAP = timedelta(minutes=10)
MAIL_CHECK_GAP = timedelta(seconds=15)
# How often a user may have their mailbox checked by itself, in minutes
# (decided 2026-11-16, open question 5); it starts at the first.
MAIL_INTERVALS = (5, 15, 60)
MAIL_SCHEDULER_TICK = 60           # seconds between looks for a mailbox that is due
MAIL_FAILING_WARN_AFTER = timedelta(days=1)
MAIL_RETURN_PATH = "/#settings/mail"
MAIL_REASONS = {
    "unreadable": "Couldn't find the values this alert was taught to have.",
    "unverified": "May not be from your bank: it failed your mailbox's sender check.",
    "card": "Its card isn't matched to an account.",
    "no_account": "No account to put it in.",
    "bank_linked": "Its account takes lines from bank sync; alerts join it in a later version.",
}
# Tried again on each check, from the kept text; an unverified or dismissed
# alert never is.
MAIL_RETRY_REASONS = ("unreadable", "card", "no_account", "bank_linked")


def mail_alerts_enabled(db: Session) -> bool:
    row = db.get(AdminSetting, MAIL_ALERTS_KEY)
    return bool(row and row.value == "true")


def _mail_allowed(db: Session, user: User) -> None:
    if not mail_alerts_enabled(db):
        raise HTTPException(403, "Email alerts are switched off on this instance. An admin can "
                                 "switch them on in Admin.")
    if is_demo_email(user.email):
        raise HTTPException(403, "The demo user can't connect a mailbox.")


def _mail_connection(db: Session, user: User) -> MailConnection | None:
    return db.query(MailConnection).filter_by(user_id=user.id).first()


def _mail_needed(db: Session, user: User) -> MailConnection:
    _mail_allowed(db, user)
    conn = _mail_connection(db, user)
    if not conn:
        raise HTTPException(404, "No mailbox is connected.")
    return conn


def mail_ref(message_id: str) -> str:
    """The same for every user, so a line restored from a backup into another
    user is still recognised; looked up only in the user's own accounts."""
    return hashlib.sha256(f"mail:{message_id}".encode()).hexdigest()


def _mail_redirect_uri() -> str:
    return APP_BASE_URL.strip().rstrip("/") + "/api/mail/microsoft/callback"


def _mail_cards(sender: MailSender) -> dict:
    try:
        cards = json.loads(sender.cards_json or "{}")
    except ValueError:
        cards = {}
    return {k: v for k, v in cards.items() if isinstance(k, str) and isinstance(v, int)} \
        if isinstance(cards, dict) else {}


def _mail_anchors(kind: MailAlertKind) -> dict:
    try:
        a = json.loads(decrypt_str(kind.anchors_enc))
    except Exception:
        a = {}
    return a if isinstance(a, dict) else {}


def _bank_linked_ids(db: Session, user: User) -> set[int]:
    conn = _bank_connection(db, user)
    if not conn:
        return set()
    return {a for (a,) in db.query(BankAccountLink.account_id).filter_by(connection_id=conn.id)}


def _mail_sender_out(db: Session, s: MailSender) -> dict:
    kinds = db.query(MailAlertKind).filter_by(sender_id=s.id).order_by(MailAlertKind.id).all()
    return {"id": s.id, "address": s.address, "label": s.label, "account_id": s.account_id,
            "cards": [{"last4": k, "account_id": v} for k, v in sorted(_mail_cards(s).items())],
            "kinds": [{"id": k.id, "subject_key": k.subject_key, "direction": k.direction,
                       "fields": [f for f in alerts.FIELDS if f in _mail_anchors(k)]} for k in kinds]}


# Sign-ins with a code that are waiting for the user (one per user). The
# server is one process, so memory is enough; a restart only means asking
# for a new code.
_mail_pending: dict[int, dict] = {}
_mail_pending_guard = threading.Lock()


def _mail_status(db: Session, user: User, request: Request | None = None) -> dict:
    conn = _mail_connection(db, user)
    iso = lambda d: d.isoformat() + "Z" if d else None
    out = {"enabled": mail_alerts_enabled(db), "available": mailbox.available(),
           "web_available": mailbox.web_available(_mail_redirect_uri()),
           "connected": conn is not None, "start_max_days": MAIL_START_MAX_DAYS}
    if request is not None and "mail_oauth_result" in request.session:
        out["connect_error"] = request.session.pop("mail_oauth_result")
    with _mail_pending_guard:
        p = _mail_pending.get(user.id)
        if p and p["expires"] > time.time() and not conn:
            out["pending"] = {"user_code": p["user_code"], "verification_uri": p["verification_uri"],
                              "expires_in": int(p["expires"] - time.time()), "interval": p["interval"]}
    if not conn:
        return out
    senders = db.query(MailSender).filter_by(connection_id=conn.id).order_by(MailSender.id).all()
    out.update({
        "provider": conn.provider, "auth_mode": conn.auth_mode,
        "address": decrypt_str(conn.address_enc) if conn.address_enc else None,
        "folder": {"id": conn.folder_id, "name": conn.folder_name} if conn.folder_id else None,
        "start_date": conn.start_date.isoformat(),
        "connected_at": iso(conn.created_at),
        "last_check_at": iso(conn.last_check_at), "last_check_ok": conn.last_check_ok,
        "last_check_status": conn.last_check_status, "last_ok_at": iso(conn.last_ok_at),
        "needs_reconnect": bool(conn.needs_reconnect),
        "senders": [_mail_sender_out(db, s) for s in senders],
        "unread_count": db.query(MailUnread).filter(MailUnread.connection_id == conn.id,
                                                     MailUnread.reason != "dismissed").count(),
        "bank_linked_account_ids": sorted(_bank_linked_ids(db, user)),
        "unmatched": _mail_unmatched_counts(db, user),
    })
    out.update(_mail_short_status(db, user))
    return out


def _mail_unmatched_counts(db: Session, user: User) -> list[dict]:
    """The user's accounts with alert lines that paid no bill and are still
    to look at (#209): [{account_id, count}]."""
    rows = (db.query(Transaction.account_id, func.count(Transaction.id))
            .join(Account, Account.id == Transaction.account_id)
            .filter(Account.owner_id == user.id, Transaction.mail_ref.isnot(None),
                    Transaction.bank_match.is_(None), Transaction.bank_left.is_(False),
                    Transaction.recurring_id.is_(None), Transaction.transfer_id.is_(None),
                    Transaction.is_actual.is_(True))
            .group_by(Transaction.account_id).order_by(Transaction.account_id).all())
    return [{"account_id": a, "count": n} for a, n in rows]


def _mail_next_check(db: Session, conn: MailConnection, now: datetime) -> datetime | None:
    """When the mailbox is next checked by itself; None while it can't be
    (no folder, nothing taught, a sign-in to make again, or alerts off)."""
    if conn.needs_reconnect or not conn.folder_id or not mail_alerts_enabled(db):
        return None
    if not db.query(MailSender.id).filter_by(connection_id=conn.id).first():
        return None
    gap = timedelta(minutes=conn.check_minutes or MAIL_INTERVALS[0])
    return max(now, conn.last_check_at + gap) if conn.last_check_at else now


def _mail_short_status(db: Session, user: User) -> dict:
    """What an app needs to show the mailbox's state (#207): no folder or
    sender names, nothing about the sign-in."""
    conn = _mail_connection(db, user)
    out = {"enabled": mail_alerts_enabled(db), "connected": conn is not None}
    if not conn:
        return out
    now = datetime.utcnow()
    iso = lambda d: d.isoformat() + "Z" if d else None
    failing_since = (conn.last_ok_at or conn.created_at) if conn.last_check_ok is False else None
    unread = db.query(MailUnread).filter(MailUnread.connection_id == conn.id,
                                         MailUnread.reason != "dismissed").count()
    out.update({
        "check_minutes": conn.check_minutes or MAIL_INTERVALS[0],
        "last_check_at": iso(conn.last_check_at), "last_check_ok": conn.last_check_ok,
        "last_check_status": conn.last_check_status, "last_ok_at": iso(conn.last_ok_at),
        "needs_reconnect": bool(conn.needs_reconnect),
        "failing_since": iso(failing_since),
        "failing_over_a_day": bool(failing_since and now - failing_since > MAIL_FAILING_WARN_AFTER),
        "next_check_at": iso(_mail_next_check(db, conn, now)),
        "unread_count": unread,
    })
    return out


@app.get("/api/mail/status")
def mail_short_status(user: User = Depends(current_user), db: Session = Depends(get_db)):
    """The mailbox's state, for the Dashboard and apps; an API token may read it."""
    return _mail_short_status(db, user)


@app.get("/api/mail")
def mail_status(request: Request, user: User = Depends(current_session_user),
                db: Session = Depends(get_db)):
    """Whether email alerts are on, and this user's mailbox: its folder, the
    senders taught and how the last check went. Never the sign-in."""
    return _mail_status(db, user, request)


def _mail_fail(db: Session, conn: MailConnection | None, e: mailbox.MailboxError):
    if conn is not None and e.revoked:
        conn.needs_reconnect = True
        db.commit()
    raise HTTPException(e.status, str(e))


def _mail_token(db: Session, conn: MailConnection) -> str:
    """A working access token for the mailbox, renewing (and storing) the
    sign-in when it's due. Raises MailboxError."""
    try:
        tokens = json.loads(decrypt_str(conn.tokens_enc))
    except Exception:
        tokens = {}
    tokens = tokens if isinstance(tokens, dict) else {}
    new = mailbox.fresh(tokens, conn.auth_mode)
    if new is not tokens:
        conn.tokens_enc = encrypt_str(json.dumps(new))
        db.commit()
    return new["access"]


def _mail_access(db: Session, conn: MailConnection) -> str:
    """The same, with a failure answered as an HTTP error."""
    try:
        return _mail_token(db, conn)
    except mailbox.MailboxError as e:
        _mail_fail(db, conn, e)


def _mail_today(offset_minutes: int) -> date:
    """The user's own date: the server's clock is usually UTC."""
    return (datetime.utcnow() + timedelta(minutes=offset_minutes)).date()


def _mail_finish_connect(db: Session, user: User, tokens: dict, mode: str,
                         request: Request | None, offset: int = 0) -> MailConnection:
    try:
        address = mailbox.mailbox_address(tokens["access"])
    except mailbox.MailboxError:
        address = None   # shown as unknown; reading mail is what matters
    conn = MailConnection(user_id=user.id, provider="microsoft", auth_mode=mode,
                          tokens_enc=encrypt_str(json.dumps(tokens)),
                          address_enc=encrypt_str(address) if address else None,
                          start_date=_mail_today(offset), utc_offset_minutes=offset)
    db.add(conn)
    db.commit()
    record_event(db, "mail_connected", request, user=user, detail=f"microsoft, {mode}")
    return conn


class MailCodeIn(BaseModel):
    code: str | None = Field(default=None, max_length=40)
    # The browser's clock, minutes east of UTC, so "today" is the user's.
    utc_offset_minutes: int = Field(default=0, ge=-840, le=840)


def _mail_connect_checks(db: Session, request: Request, user: User, code: str | None) -> None:
    _mail_allowed(db, user)
    if not mailbox.available():
        raise HTTPException(400, "This server has no Microsoft app set up yet: MS_CLIENT_ID is "
                                 "empty in its .env. See the email alerts setup guide.")
    if _mail_connection(db, user):
        raise HTTPException(409, "You already have a mailbox connected. Disconnect it first.")
    _confirm_code_for(db, request, user, code, "mailbox connection")


@app.post("/api/mail/microsoft/device")
def mail_device_start(body: MailCodeIn, request: Request,
                      user: User = Depends(current_session_user), db: Session = Depends(get_db)):
    """Start signing in with a code: the user types it at Microsoft's page,
    then the browser asks /poll until it's done."""
    _mail_connect_checks(db, request, user, body.code)
    try:
        d = mailbox.start_device()
    except mailbox.MailboxError as e:
        raise HTTPException(e.status, str(e))
    with _mail_pending_guard:
        _mail_pending[user.id] = {**d, "expires": time.time() + d["expires_in"], "next": 0.0,
                                  "offset": body.utc_offset_minutes}
    return {"user_code": d["user_code"], "verification_uri": d["verification_uri"],
            "expires_in": d["expires_in"], "interval": d["interval"]}


@app.post("/api/mail/microsoft/device/poll")
def mail_device_poll(request: Request, user: User = Depends(current_session_user),
                     db: Session = Depends(get_db)):
    """Whether the sign-in with a code has finished. {"status": "pending"}
    until it has; then the mailbox's status."""
    _mail_allowed(db, user)
    with _mail_pending_guard:
        p = _mail_pending.get(user.id)
        if not p or p["expires"] <= time.time():
            _mail_pending.pop(user.id, None)
            raise HTTPException(410, "The code ran out before the sign-in finished. Start again "
                                     "for a new one.")
        if time.time() < p["next"]:
            return {"status": "pending"}
        p["next"] = time.time() + p["interval"]
        device_code, offset = p["device_code"], p.get("offset", 0)
    if _mail_connection(db, user):
        raise HTTPException(409, "You already have a mailbox connected. Disconnect it first.")
    try:
        tokens = mailbox.poll_device(device_code)
    except mailbox.MailboxError as e:
        with _mail_pending_guard:
            _mail_pending.pop(user.id, None)
        raise HTTPException(e.status, str(e))
    if tokens is None:
        return {"status": "pending"}
    with _mail_pending_guard:
        _mail_pending.pop(user.id, None)
    _mail_finish_connect(db, user, tokens, "device", request, offset)
    return {"status": "connected", **_mail_status(db, user)}


@app.post("/api/mail/microsoft/web")
def mail_web_start(body: MailCodeIn, request: Request,
                   user: User = Depends(current_session_user), db: Session = Depends(get_db)):
    """Start signing in with the Connect button: the address to send the
    browser to. Only when this server is reached over https:// and has
    MS_CLIENT_SECRET."""
    _mail_connect_checks(db, request, user, body.code)
    redirect_uri = _mail_redirect_uri()
    if not mailbox.web_available(redirect_uri):
        raise HTTPException(400, "The Connect button needs this server on an https:// address "
                                 "(APP_BASE_URL) and MS_CLIENT_SECRET in its .env. Sign in with "
                                 "a code instead.")
    s = mailbox.start_web(redirect_uri)
    request.session["mail_oauth"] = {"state": s["state"], "verifier": s["verifier"],
                                     "uid": user.id, "at": int(time.time()),
                                     "offset": body.utc_offset_minutes}
    return {"url": s["url"]}


@app.get("/api/mail/microsoft/callback")
def mail_web_callback(request: Request, code: str | None = None, state: str | None = None,
                      error: str | None = None,
                      user: User = Depends(current_session_user), db: Session = Depends(get_db)):
    """Microsoft sends the browser back here after the Connect button."""
    pending = request.session.pop("mail_oauth", None)

    def back(problem: str | None):
        if problem:
            request.session["mail_oauth_result"] = problem
        return RedirectResponse(MAIL_RETURN_PATH, status_code=303)

    if (not isinstance(pending, dict) or pending.get("uid") != user.id or not state
            or not secrets.compare_digest(str(pending.get("state", "")), state)
            or time.time() - int(pending.get("at", 0)) > 900):
        return back("The sign-in didn't match one started here, or took too long. Start again.")
    if error or not code:
        return back("The sign-in was cancelled or declined at Microsoft.")
    try:
        _mail_allowed(db, user)
    except HTTPException as e:
        return back(e.detail)
    if _mail_connection(db, user):
        return back("You already have a mailbox connected. Disconnect it first.")
    try:
        tokens = mailbox.finish_web(code[:4000], pending["verifier"], _mail_redirect_uri())
    except mailbox.MailboxError as e:
        return back(str(e))
    offset = pending.get("offset")
    _mail_finish_connect(db, user, tokens, "web", request,
                         offset if isinstance(offset, int) and -840 <= offset <= 840 else 0)
    return back(None)


@app.get("/api/mail/folders")
def mail_folders(user: User = Depends(current_session_user), db: Session = Depends(get_db)):
    """The mailbox's folders, to pick the one alerts are read from."""
    conn = _mail_needed(db, user)
    try:
        return mailbox.folders(_mail_access(db, conn))
    except mailbox.MailboxError as e:
        _mail_fail(db, conn, e)


class MailSettingsIn(BaseModel):
    folder_id: str | None = Field(default=None, min_length=1, max_length=400)
    start_date: date | None = None
    utc_offset_minutes: int | None = Field(default=None, ge=-840, le=840)
    check_minutes: Literal[5, 15, 60] | None = None


@app.put("/api/mail/settings")
def mail_settings(body: MailSettingsIn, user: User = Depends(current_session_user),
                  db: Session = Depends(get_db)):
    """Pick the folder alerts are read from, and the day they're read from
    (today or up to 30 days back)."""
    conn = _mail_needed(db, user)
    if body.folder_id is not None and body.folder_id != conn.folder_id:
        try:
            found = [f for f in mailbox.folders(_mail_access(db, conn)) if f["id"] == body.folder_id]
        except mailbox.MailboxError as e:
            _mail_fail(db, conn, e)
        if not found:
            raise HTTPException(404, "That folder isn't in the mailbox.")
        f = found[0]
        conn.folder_id = f["id"]
        conn.folder_name = (f"{f['parent']} / {f['name']}" if f["parent"] else f["name"])[:200]
        conn.scanned_through = None
    if body.utc_offset_minutes is not None:
        conn.utc_offset_minutes = body.utc_offset_minutes
    if body.check_minutes is not None:
        conn.check_minutes = body.check_minutes
    if body.start_date is not None and body.start_date != conn.start_date:
        today = _mail_today(conn.utc_offset_minutes)
        if body.start_date > today or body.start_date < today - timedelta(days=MAIL_START_MAX_DAYS):
            raise HTTPException(400, f"The start date must be today or up to "
                                     f"{MAIL_START_MAX_DAYS} days back.")
        conn.start_date, conn.scanned_through = body.start_date, None
    db.commit()
    return _mail_status(db, user)


@app.get("/api/mail/messages")
def mail_messages(user: User = Depends(current_session_user), db: Session = Depends(get_db)):
    """The newest mail in the folder (sender, subject and when only), to pick
    a bank's alert to teach from."""
    conn = _mail_needed(db, user)
    if not conn.folder_id:
        raise HTTPException(400, "Pick the folder alerts are read from first.")
    try:
        rows = mailbox.recent(_mail_access(db, conn), conn.folder_id)
    except mailbox.MailboxError as e:
        _mail_fail(db, conn, e)
    taught = {s.address for s in db.query(MailSender).filter_by(connection_id=conn.id)}
    return [{"id": m["id"], "sender": m["sender"], "subject": m["subject"],
             "received_at": m["received"].isoformat() + "Z", "taught": m["sender"] in taught}
            for m in rows]


class MailSourceIn(BaseModel):
    message_id: str | None = Field(default=None, min_length=1, max_length=400)
    unread_id: int | None = None


def _mail_source(db: Session, user: User, conn: MailConnection, body: MailSourceIn) -> dict:
    """A sample alert as text, from the mailbox or the couldn't-read list."""
    if (body.message_id is None) == (body.unread_id is None):
        raise HTTPException(400, "Give a message or an item from the couldn't-read list.")
    if body.unread_id is not None:
        u = db.get(MailUnread, body.unread_id)
        if u is None or u.connection_id != conn.id or u.reason == "dismissed":
            raise HTTPException(404, "That alert isn't on your couldn't-read list.")
        return {"sender": u.sender, "subject": decrypt_str(u.subject_enc),
                "text": decrypt_str(u.text_enc), "received": u.received_at,
                "verified": u.reason != "unverified"}
    try:
        m = mailbox.message(_mail_access(db, conn), body.message_id)
    except mailbox.MailboxError as e:
        _mail_fail(db, conn, e)
    return {"sender": m["sender"], "subject": m["subject"], "text": alerts.to_text(m["body"], m["html"]),
            "received": m["received"], "verified": alerts.sender_verified(m["sender"], m["auth_results"])}


@app.post("/api/mail/preview")
def mail_preview(body: MailSourceIn, user: User = Depends(current_session_user),
                 db: Session = Depends(get_db)):
    """A sample alert as plain text, with where the reader thinks each value
    is (offsets into `text`), for the teaching screen."""
    conn = _mail_needed(db, user)
    src = _mail_source(db, user, conn, body)
    g = alerts.guess(src["text"], src["subject"])
    sender = db.query(MailSender).filter_by(connection_id=conn.id, address=src["sender"]).first()
    return {"sender": src["sender"], "subject": src["subject"], "text": src["text"],
            "received_at": src["received"].isoformat() + "Z", "verified": src["verified"],
            "subject_key": alerts.subject_key(src["subject"]), "guess": g,
            "known_sender": _mail_sender_out(db, sender) if sender else None}


class MailTeachIn(MailSourceIn):
    label: str = Field(min_length=1, max_length=80)
    direction: str = Field(pattern="^(out|in)$")
    subject_key: str = Field(min_length=3, max_length=200)
    account_id: int
    amount: list[int] = Field(min_length=2, max_length=2)
    merchant: list[int] | None = Field(default=None, min_length=2, max_length=2)
    date: list[int] | None = Field(default=None, min_length=2, max_length=2)
    card: list[int] | None = Field(default=None, min_length=2, max_length=2)


def _mail_account_ok(db: Session, user: User, account_id: int) -> Account:
    # Alerts land lines in the account, so its owner only, as bank sync does.
    acc = _account_with_perm(db, user, account_id, "owner")
    if acc.id in _bank_linked_ids(db, user):
        raise HTTPException(400, "That account takes lines from bank sync. Alerts and bank sync "
                                 "on one account arrive in a later version; pick another account.")
    return acc


@app.post("/api/mail/senders")
def mail_teach(body: MailTeachIn, request: Request, user: User = Depends(current_session_user),
               db: Session = Depends(get_db)):
    """Teach a kind of alert from a sample: where each value is in it (offsets
    into the preview's text), whether it's money out or in, and the account
    its lines go to (or its card's account). The same subject start taught
    again replaces what was taught."""
    conn = _mail_needed(db, user)
    src = _mail_source(db, user, conn, body)
    text, received = src["text"], src["received"]
    if not src["sender"]:
        raise HTTPException(400, "That mail has no sender address.")
    key = " ".join(body.subject_key.lower().split())
    if not alerts.subject_matches(key, src["subject"]):
        raise HTTPException(400, "The start of the subject has to match this mail's subject.")
    _mail_account_ok(db, user, body.account_id)
    day = alerts.received_day(received, conn.utc_offset_minutes)
    anchors, values = {}, {}
    for field in alerts.FIELDS:
        span = getattr(body, field)
        if span is None:
            continue
        start, end = span
        if not (0 <= start < end <= len(text)) or end - start > alerts.LIMITS[field]:
            raise HTTPException(400, f"The {field} marked isn't in this mail.")
        value = alerts.marked(field, text[start:end], day)
        if value is None:
            raise HTTPException(400, {"amount": "The text marked as the amount isn't an amount.",
                                      "date": "The text marked as the date isn't a date.",
                                      "card": "The text marked as the card has no four digits.",
                                      "merchant": "The text marked as the merchant is empty."}[field])
        anchors[field], values[field] = alerts.anchor(text, start, end), value
    if alerts.read(text, anchors, day) is None:
        raise HTTPException(400, "Marked like that, the values can't be found again in this same "
                                 "mail. Mark a little more of the text around them.")
    sender = db.query(MailSender).filter_by(connection_id=conn.id, address=src["sender"]).first()
    if sender is None:
        sender = MailSender(connection_id=conn.id, address=src["sender"], label=body.label.strip(),
                            cards_json="{}")
        db.add(sender)
        db.flush()
    sender.label = body.label.strip()[:80]
    if "card" in values:
        cards = _mail_cards(sender)
        cards[values["card"]] = body.account_id
        sender.cards_json = json.dumps(cards)
        if sender.account_id is None:
            sender.account_id = body.account_id
    else:
        sender.account_id = body.account_id
    db.query(MailAlertKind).filter_by(sender_id=sender.id, subject_key=key).delete()
    db.add(MailAlertKind(sender_id=sender.id, subject_key=key, direction=body.direction,
                         anchors_enc=encrypt_str(json.dumps(anchors)), sample_enc=encrypt_str(text)))
    conn.scanned_through = None   # mail from before is read again, now it's taught
    db.commit()
    record_event(db, "mail_sender_taught", request, user=user,
                 detail=f"{len(anchors)} values, {body.direction}")
    return _mail_status(db, user)


class MailSenderIn(BaseModel):
    label: str | None = Field(default=None, min_length=1, max_length=80)
    account_id: int | None = None
    cards: dict[str, int | None] | None = None


@app.put("/api/mail/senders/{sender_id}")
def mail_sender_update(sender_id: int, body: MailSenderIn, user: User = Depends(current_session_user),
                       db: Session = Depends(get_db)):
    """Rename a taught sender, change the account its lines go to, or match a
    card's last four digits to an account (null removes a card)."""
    conn = _mail_needed(db, user)
    s = db.get(MailSender, sender_id)
    if s is None or s.connection_id != conn.id:
        raise HTTPException(404, "Sender not found")
    if body.label is not None:
        s.label = body.label.strip()[:80]
    if body.account_id is not None:
        s.account_id = _mail_account_ok(db, user, body.account_id).id
    if body.cards is not None:
        cards = _mail_cards(s)
        for last4, acc_id in list(body.cards.items())[:50]:
            if not re.fullmatch(r"\d{4}", last4):
                raise HTTPException(400, "A card is its last four digits.")
            if acc_id is None:
                cards.pop(last4, None)
            else:
                cards[last4] = _mail_account_ok(db, user, acc_id).id
        s.cards_json = json.dumps(cards)
    db.commit()
    return _mail_status(db, user)


@app.delete("/api/mail/senders/{sender_id}")
def mail_sender_delete(sender_id: int, user: User = Depends(current_session_user),
                       db: Session = Depends(get_db)):
    """Forget a sender and everything taught from it. Lines already brought
    in stay."""
    conn = _mail_needed(db, user)
    s = db.get(MailSender, sender_id)
    if s is None or s.connection_id != conn.id:
        raise HTTPException(404, "Sender not found")
    db.delete(s)
    db.commit()
    return _mail_status(db, user)


@app.delete("/api/mail/senders/{sender_id}/kinds/{kind_id}")
def mail_kind_delete(sender_id: int, kind_id: int, user: User = Depends(current_session_user),
                     db: Session = Depends(get_db)):
    """Forget one kind of alert from a sender."""
    conn = _mail_needed(db, user)
    s = db.get(MailSender, sender_id)
    k = db.get(MailAlertKind, kind_id)
    if s is None or s.connection_id != conn.id or k is None or k.sender_id != s.id:
        raise HTTPException(404, "Kind of alert not found")
    db.delete(k)
    db.commit()
    return _mail_status(db, user)


# One check per user at a time, as bank sync does.
_mail_locks: dict[int, threading.Lock] = {}
_mail_locks_guard = threading.Lock()


def _mail_lock(user_id: int) -> threading.Lock:
    with _mail_locks_guard:
        return _mail_locks.setdefault(user_id, threading.Lock())


def _mail_land(db: Session, user: User, conn: MailConnection, sender: MailSender,
               kind: MailAlertKind, text: str, received: datetime, ref: str,
               run_id: int | None = None, bills_cache: dict | None = None):
    """Read one alert and land it as a paid line, or as the payment of a
    planned bill it matches (#209: the bank sync matcher, with the bill's own
    match settings; the returned line has bank_match set then). Returns the
    line, or (reason, detail) when it can't become one."""
    day = alerts.received_day(received, conn.utc_offset_minutes)
    values = alerts.read(text, _mail_anchors(kind), day)
    if values is None:
        return ("unreadable", None)
    account_id = sender.account_id
    if "card" in values:
        account_id = _mail_cards(sender).get(values["card"])
        if account_id is None:
            return ("card", f"Card ending {values['card']} isn't matched to an account.")
    if account_id is None:
        return ("no_account", None)
    try:
        acc = _account_with_perm(db, user, account_id, "owner")
    except HTTPException:
        return ("no_account", "The account it was matched to is gone or no longer yours.")
    if acc.id in _bank_linked_ids(db, user):
        return ("bank_linked", None)
    amount = values["amount"] if kind.direction == "in" else -values["amount"]
    when = values.get("date") or day
    merchant = values.get("merchant") or sender.label
    cache = bills_cache if bills_cache is not None else {}
    bills = cache.get(acc.id)
    if bills is None:
        bills = cache[acc.id] = _bills_to_match(db, acc.id)
    hit = _bill_for_bank_line(bills, when, amount, merchant)
    if hit:
        rec, occ = hit
        paid = _pay_bill_from_bank(db, rec, occ, when, amount, ref, merchant, "auto", run_id, "alert")
        bills["covered"].add((rec.id, occ))
        return paid
    t = Transaction(account_id=acc.id, actual_date=when, forecast_date=when, is_actual=True,
                    mail_ref=ref, mail_run_id=run_id)
    t.description = merchant
    t.amount = amount
    db.add(t)
    db.flush()
    _apply_tag_rules(db, user, t)
    return t


def _mail_keep_unread(db: Session, conn: MailConnection, ref: str, received: datetime, sender: str,
                      subject: str, text: str, reason: str, detail: str | None,
                      existing: MailUnread | None = None) -> None:
    if existing is not None:
        existing.reason, existing.detail = reason, (detail or None)
        return
    db.add(MailUnread(connection_id=conn.id, message_ref=ref, received_at=received, sender=sender[:320],
                      reason=reason, detail=(detail or None),
                      subject_enc=encrypt_str(subject or ""), text_enc=encrypt_str(text or "")))


def _mail_check(db: Session, user: User, conn: MailConnection, request: Request | None,
                trigger: str = "manual") -> dict:
    lock = _mail_lock(user.id)
    if not lock.acquire(blocking=False):
        raise HTTPException(409, "A check is already running. Try again in a minute.")
    try:
        return _mail_check_locked(db, user, conn, request, trigger)
    finally:
        lock.release()


def _mail_check_locked(db: Session, user: User, conn: MailConnection, request: Request | None,
                       trigger: str) -> dict:
    if not conn.folder_id:
        raise HTTPException(400, "Pick the folder alerts are read from first.")
    senders = {s.address: s for s in db.query(MailSender).filter_by(connection_id=conn.id)}
    if not senders:
        raise HTTPException(400, "Teach at least one bank's alert first.")
    now = datetime.utcnow()
    if trigger == "manual" and conn.last_check_at and now - conn.last_check_at < MAIL_CHECK_GAP:
        raise HTTPException(429, "The mailbox was checked a moment ago. Try again in a few seconds.",
                            headers={"Retry-After": "15"})
    kinds: dict[int, list[MailAlertKind]] = {}
    for k in (db.query(MailAlertKind).filter(MailAlertKind.sender_id.in_([s.id for s in senders.values()]))
              .order_by(MailAlertKind.id)):
        kinds.setdefault(k.sender_id, []).append(k)

    def kind_for(sender: MailSender, subject: str) -> MailAlertKind | None:
        return next((k for k in kinds.get(sender.id, []) if alerts.subject_matches(k.subject_key, subject)), None)

    added = skipped = unread = matched = 0
    bills_cache: dict = {}
    # This check's row in the log; dropped again below when it found nothing.
    run = MailCheckRun(connection_id=conn.id, run_at=now, trigger=trigger)
    db.add(run)
    db.flush()
    run_id = run.id
    # Alerts that couldn't become lines before are tried again from their
    # kept text: a sender taught since, or a card matched since.
    for u in db.query(MailUnread).filter(MailUnread.connection_id == conn.id,
                                         MailUnread.reason.in_(MAIL_RETRY_REASONS)).all():
        s = senders.get(u.sender)
        k = kind_for(s, decrypt_str(u.subject_enc)) if s else None
        if k is None or added >= MAIL_LINES_PER_CHECK:
            continue
        got = _mail_land(db, user, conn, s, k, decrypt_str(u.text_enc), u.received_at, u.message_ref,
                         run.id, bills_cache)
        if isinstance(got, Transaction):
            db.delete(u)
            added += 1
            matched += 1 if got.bank_match else 0
        else:
            u.reason, u.detail = got
    try:
        access = _mail_token(db, conn)
        if conn.scanned_through:
            after = conn.scanned_through - MAIL_OVERLAP
        else:
            start = datetime(conn.start_date.year, conn.start_date.month, conn.start_date.day)
            after = start - timedelta(minutes=conn.utc_offset_minutes)
        listed = mailbox.since(access, conn.folder_id, after, MAIL_SCAN_LIMIT)
        wanted = [m for m in listed if m["sender"] in senders]
        refs = {mail_ref(m["message_id"]): m for m in wanted}
        landed = {r for (r,) in db.query(Transaction.mail_ref).join(Account, Account.id == Transaction.account_id)
                  .filter(Account.owner_id == user.id, Transaction.mail_ref.in_(list(refs)))} if refs else set()
        kept = {u.message_ref: u for u in db.query(MailUnread).filter(
            MailUnread.connection_id == conn.id, MailUnread.message_ref.in_(list(refs)))} if refs else {}
        through, opened, stopped = None, 0, False
        for m in listed:
            ref = mail_ref(m["message_id"])
            s = senders.get(m["sender"])
            if s is None or ref in kept:
                through = m["received"]
                continue
            if ref in landed:
                skipped += 1
                through = m["received"]
                continue
            k = kind_for(s, m["subject"])
            if k is None:   # a kind of mail from the bank that wasn't taught
                through = m["received"]
                continue
            if opened >= MAIL_BODIES_PER_CHECK or added >= MAIL_LINES_PER_CHECK:
                stopped = True
                break
            opened += 1
            full = mailbox.message(access, m["id"])
            text = alerts.to_text(full["body"], full["html"])
            if not alerts.sender_verified(full["sender"], full["auth_results"]):
                _mail_keep_unread(db, conn, ref, m["received"], m["sender"], m["subject"], text,
                                  "unverified", None)
                unread += 1
            else:
                got = _mail_land(db, user, conn, s, k, text, m["received"], ref, run.id, bills_cache)
                if isinstance(got, Transaction):
                    landed.add(ref)
                    added += 1
                    matched += 1 if got.bank_match else 0
                else:
                    _mail_keep_unread(db, conn, ref, m["received"], m["sender"], m["subject"], text, *got)
                    unread += 1
            through = m["received"]
        if through is not None:
            conn.scanned_through = through
        elif not listed:
            conn.scanned_through = now - MAIL_OVERLAP
    except mailbox.MailboxError as e:
        db.rollback()
        conn = db.get(MailConnection, conn.id)
        conn.last_check_at, conn.last_check_ok, conn.last_check_status = now, False, str(e)[:300]
        if e.revoked:
            conn.needs_reconnect = True
        # A failure shows in the log (a scheduled one nobody was watching most
        # of all). The check's row is there if renewing the sign-in committed
        # it, along with lines landed from the couldn't-read list before.
        run = db.get(MailCheckRun, run_id)
        if run is None:
            run = MailCheckRun(connection_id=conn.id, run_at=now, trigger=trigger)
            db.add(run)
            db.flush()
        run.error = str(e)[:300]
        run.added = db.query(Transaction).filter_by(mail_run_id=run.id).count()
        run.matched = (db.query(Transaction).filter(Transaction.mail_run_id == run.id,
                                                    Transaction.bank_match.isnot(None)).count())
        db.commit()
        record_event(db, "mail_check_failed", request, user=user,
                     detail=("revoked" if e.revoked else f"HTTP {e.status}") + f", {trigger}")
        raise HTTPException(e.status, str(e))
    status = (f"{added} new line{'' if added == 1 else 's'}"
              + (f", {matched} of them matched a bill" if matched else "")
              + f", {skipped} already here"
              + (f", {unread} couldn't become lines" if unread else "")
              + (". More is waiting: check again." if stopped else ""))
    conn.last_check_at, conn.last_check_ok, conn.last_check_status = now, True, status[:300]
    conn.last_ok_at, conn.needs_reconnect = now, False
    if added or unread:
        run.added, run.skipped, run.unread, run.matched = added, skipped, unread, matched
    else:
        db.delete(run)   # a check that found nothing isn't kept
    db.commit()
    record_event(db, "mail_check_run", request, user=user,
                 detail=f"{added} added, {skipped} skipped, {unread} unread, {trigger}")
    return {"added": added, "matched": matched, "skipped": skipped, "unread": unread, "more": stopped}


class MailCheckIn(BaseModel):
    utc_offset_minutes: int | None = Field(default=None, ge=-840, le=840)


@app.post("/api/mail/check")
def mail_check_now(request: Request, body: MailCheckIn | None = None,
                   user: User = Depends(current_user), db: Session = Depends(get_db)):
    """Read new alerts from the folder and land them as paid lines. A token
    with write access may (#207, for the iOS app); a read-only one may not."""
    conn = _mail_needed(db, user)
    if body and body.utc_offset_minutes is not None:
        conn.utc_offset_minutes = body.utc_offset_minutes
        db.commit()
    result = _mail_check(db, user, conn, request, trigger="manual")
    return {**result, "status": _mail_status(db, user)}


# ---------- Checking by itself (#207) ----------
# Each connected mailbox is checked as often as its user chose (5, 15 or 60
# minutes; the scheduler looks every minute). A failed check is tried again
# at the same interval, except when Microsoft no longer accepts the sign-in:
# then it waits until the user connects again. Alerts being off, a mailbox
# with no folder or nothing taught, and a disabled or demo user are skipped.
def mail_check_due(db: Session, conn: MailConnection, now: datetime) -> bool:
    nxt = _mail_next_check(db, conn, now)
    return nxt is not None and nxt <= now


def run_due_mail_checks(db: Session, now: datetime | None = None) -> dict:
    """Check every mailbox that is due. One user's failure is recorded on
    their mailbox and doesn't stop the others."""
    out = {"checked": 0, "failed": 0}
    if not mail_alerts_enabled(db):
        return out
    now = now or datetime.utcnow()
    for conn in db.query(MailConnection).order_by(MailConnection.id).all():
        user = db.get(User, conn.user_id)
        if user is None or user.disabled or is_demo_email(user.email) or not mail_check_due(db, conn, now):
            continue
        try:
            _mail_check(db, user, conn, None, trigger="schedule")
            out["checked"] += 1
        except Exception:
            db.rollback()
            out["failed"] += 1
    return out


def _mail_scheduler_loop():
    """Background daemon: every minute, check the mailboxes that are due."""
    while True:
        time.sleep(MAIL_SCHEDULER_TICK)
        db = SessionLocal()
        try:
            run_due_mail_checks(db)
        except Exception:
            pass   # tried again in a minute
        finally:
            db.close()


@app.get("/api/mail/checks")
def mail_check_log(user: User = Depends(current_session_user), db: Session = Depends(get_db)):
    """This mailbox's checks that brought something in or failed, newest
    first (the last 200). The mailbox's owner only."""
    conn = _mail_connection(db, user)
    if not conn:
        raise HTTPException(404, "No mailbox is connected.")
    runs = (db.query(MailCheckRun).filter_by(connection_id=conn.id)
            .order_by(MailCheckRun.run_at.desc(), MailCheckRun.id.desc()).limit(200).all())
    return [{"id": r.id, "run_at": r.run_at.isoformat() + "Z", "trigger": r.trigger,
             "added": r.added, "matched": r.matched, "skipped": r.skipped, "unread": r.unread,
             "error": r.error}
            for r in runs]


@app.get("/api/mail/checks/{run_id}")
def mail_check_log_lines(run_id: int, user: User = Depends(current_session_user),
                         db: Session = Depends(get_db)):
    """The lines one check brought in that are still there, and the account
    each went to."""
    conn = _mail_connection(db, user)
    run = db.get(MailCheckRun, run_id)
    if conn is None or run is None or run.connection_id != conn.id:
        raise HTTPException(404, "Check not found")
    rows = (db.query(Transaction, Account).join(Account, Account.id == Transaction.account_id)
            .filter(Transaction.mail_run_id == run.id, Account.owner_id == user.id)
            .order_by(Transaction.actual_date, Transaction.id).all())
    return {"id": run.id, "run_at": run.run_at.isoformat() + "Z", "trigger": run.trigger,
            "added": run.added, "matched": run.matched, "skipped": run.skipped,
            "unread": run.unread, "error": run.error,
            "lines": [{"id": t.id, "date": (t.actual_date or t.forecast_date).isoformat(),
                       "description": t.description, "amount": float(t.amount),
                       "account_id": t.account_id, "account_name": acc.name,
                       # Paid a planned bill (#209): auto or hand; else None.
                       "matched": t.bank_match} for t, acc in rows]}


@app.get("/api/mail/unread")
def mail_unread(user: User = Depends(current_session_user), db: Session = Depends(get_db)):
    """Alerts from taught senders that didn't become lines, newest first."""
    conn = _mail_connection(db, user)
    if not conn:
        raise HTTPException(404, "No mailbox is connected.")
    rows = (db.query(MailUnread).filter(MailUnread.connection_id == conn.id,
                                        MailUnread.reason != "dismissed")
            .order_by(MailUnread.received_at.desc(), MailUnread.id.desc()).limit(200).all())
    return [{"id": u.id, "received_at": u.received_at.isoformat() + "Z", "sender": u.sender,
             "subject": decrypt_str(u.subject_enc), "reason": u.reason,
             "reason_text": u.detail or MAIL_REASONS.get(u.reason, "")} for u in rows]


@app.delete("/api/mail/unread/{unread_id}")
def mail_unread_dismiss(unread_id: int, user: User = Depends(current_session_user),
                        db: Session = Depends(get_db)):
    """Take an alert off the couldn't-read list; it isn't read again."""
    conn = _mail_connection(db, user)
    u = db.get(MailUnread, unread_id)
    if not conn or u is None or u.connection_id != conn.id:
        raise HTTPException(404, "That alert isn't on your couldn't-read list.")
    # Kept as "dismissed" with its text gone, so the next check doesn't read
    # the mail again; pruned with the rest.
    u.reason, u.detail = "dismissed", None
    u.subject_enc, u.text_enc = encrypt_str(""), encrypt_str("")
    db.commit()
    return {"ok": True}


@app.post("/api/mail/disconnect")
def mail_disconnect(body: MailCodeIn, request: Request, user: User = Depends(current_session_user),
                    db: Session = Depends(get_db)):
    """Forget the mailbox's sign-in, the senders taught and the couldn't-read
    list. Lines already brought in stay. Allowed with email alerts switched
    off, so a mailbox can always be removed."""
    conn = _mail_connection(db, user)
    if not conn:
        raise HTTPException(404, "No mailbox is connected.")
    _confirm_code_for(db, request, user, body.code, "mailbox disconnection")
    db.delete(conn)
    db.commit()
    with _mail_pending_guard:
        _mail_pending.pop(user.id, None)
    record_event(db, "mail_disconnected", request, user=user)
    return _mail_status(db, user)


# ---------- Dashboard ----------
@app.get("/api/dashboard")
def dashboard(today: date | None = None,
              user: User = Depends(current_user), db: Session = Depends(get_db)):
    """Return per-account summary cards for the current month.

    For each account the user owns, runs a forecast for the current calendar
    month and computes:
      - forecast high (max of forecast_balance) and the date it occurs
      - forecast low (min of forecast_balance) and the date it occurs
      - actual high (max of actual_balance) — no date per spec
      - actual low (min of actual_balance) — no date per spec
      - opening / forecast_end / actual_end balances
      - current_balance: today's actual balance, as the Forecast page shows it
    `today` is the viewer's date (see _viewer_today).
    """
    today = _viewer_today(today)
    # First and last day of current month
    start = date(today.year, today.month, 1)
    if today.month == 12:
        end = date(today.year, 12, 31)
    else:
        end = date(today.year, today.month + 1, 1) - timedelta(days=1)
    today_iso = today.isoformat()

    def _upcoming(rows: list[dict]) -> tuple[int, float]:
        """Count and net amount of not-yet-cleared rows from today through
        month end — the "what's still coming up" figure for the rest-of-
        month dashboard widget."""
        count = 0
        net = 0.0
        for r in rows:
            if r["is_actual_real"]:
                continue
            ref = r["forecast_date"] or r["actual_date"]
            if ref and ref >= today_iso:
                count += 1
                net += r["forecast_amount"] or 0.0
        return count, net

    cards = []
    for acc in _user_visible_accounts(db, user):
        data = build_forecast(db, acc, start, end)
        rows = data["rows"]
        upcoming_count, upcoming_net = _upcoming(rows)
        current = round(_current_balance(db, acc, today), 2)

        # Defaults: if there are no rows in this month, treat the opening
        # balance as the only "value" we know about for high/low purposes.
        if not rows:
            cards.append({
                "id": acc.id,
                "name": acc.name,
                "month_label": start.strftime("%B %Y"),
                "opening_balance": data["opening_balance"],
                "forecast_end": data["forecast_ending_balance"],
                "actual_end": data["actual_ending_balance"],
                "forecast_high": data["opening_balance"],
                "forecast_high_date": None,
                "forecast_low": data["opening_balance"],
                "forecast_low_date": None,
                "actual_high": data["opening_balance"],
                "actual_low": data["opening_balance"],
                "row_count": 0,
                "upcoming_count": upcoming_count,
                "upcoming_net": round(upcoming_net, 2),
                "current_balance": current,
            })
            continue

        # Walk rows once to find min/max of both balances and the dates of
        # the forecast extremes (we don't need actual extreme dates).
        f_high = f_low = rows[0]["forecast_balance"]
        f_high_date = f_low_date = rows[0]["forecast_date"]
        a_high = a_low = rows[0]["actual_balance"]
        for r in rows:
            if r["forecast_balance"] > f_high:
                f_high = r["forecast_balance"]
                f_high_date = r["forecast_date"]
            if r["forecast_balance"] < f_low:
                f_low = r["forecast_balance"]
                f_low_date = r["forecast_date"]
            if r["actual_balance"] > a_high:
                a_high = r["actual_balance"]
            if r["actual_balance"] < a_low:
                a_low = r["actual_balance"]

        cards.append({
            "id": acc.id,
            "name": acc.name,
            "month_label": start.strftime("%B %Y"),
            "opening_balance": data["opening_balance"],
            "forecast_end": data["forecast_ending_balance"],
            "actual_end": data["actual_ending_balance"],
            "forecast_high": f_high,
            "forecast_high_date": f_high_date,
            "forecast_low": f_low,
            "forecast_low_date": f_low_date,
            "actual_high": a_high,
            "actual_low": a_low,
            "row_count": len(rows),
            "upcoming_count": upcoming_count,
            "upcoming_net": round(upcoming_net, 2),
            "current_balance": current,
        })

    return {"cards": cards}


ALLOWED_DASHBOARD_WINDOWS = {"month", "30d", "90d"}


def _resolve_dashboard_window(window: str,
                              today: date | None = None) -> tuple[date, date, str]:
    """Convert a window string into (start, end, label). `today` is the
    viewer's date when known (see _viewer_today), else the server's."""
    today = today or date.today()
    if window == "30d":
        return today - timedelta(days=29), today, "Last 30 days"
    if window == "90d":
        return today - timedelta(days=89), today, "Last 90 days"
    # default: current calendar month
    start = date(today.year, today.month, 1)
    if today.month == 12:
        end = date(today.year, 12, 31)
    else:
        end = date(today.year, today.month + 1, 1) - timedelta(days=1)
    return start, end, start.strftime("%B %Y")


@app.get("/api/dashboard/charts")
def dashboard_charts(window: str = "month", today: date | None = None,
                     user: User = Depends(current_user),
                     db: Session = Depends(get_db)):
    """Per-account chart data: category spending breakdown, totals, balance trend.

    Response shape (per account):
      - totals:        income/spending/net, both actual & forecast
      - categories:    list of {name, color, spending_actual, spending_forecast}
                       where spending is positive (magnitude) for easier rendering
      - balance_trend: daily points [{date, balance}] across the window, using
                       actual_balance (which blends real actuals with forecast
                       projections for days that haven't happened yet)
    Pure spend is reported as a positive magnitude so the donut and bars don't
    need to flip signs; income remains signed-positive for the totals tile.
    """
    if window not in ALLOWED_DASHBOARD_WINDOWS:
        raise HTTPException(400, f"window must be one of {sorted(ALLOWED_DASHBOARD_WINDOWS)}")

    start, end, label = _resolve_dashboard_window(window, _viewer_today(today))

    # Category color lookup is per user, not per account.
    cat_colors: dict[str, str | None] = {}
    for c in db.query(Category).filter_by(owner_id=user.id).all():
        cat_colors[c.name] = c.color

    UNCAT = "(uncategorized)"
    accounts_out = []

    for acc in _user_visible_accounts(db, user):
        data = build_forecast(db, acc, start, end)
        rows = data["rows"]

        # --- Category spend buckets (magnitude, positive) ---------------------
        buckets: dict[str, dict] = {}
        f_income = 0.0
        a_income = 0.0
        f_spend = 0.0   # negative
        a_spend = 0.0   # negative
        for r in rows:
            # Skip transfer legs — they're internal money movement, not spend
            # or income, and counting them would double-book on a per-account
            # donut and make the totals tile lie.
            if r.get("transfer_id") is not None:
                continue
            cat = r.get("category") or UNCAT
            f = r.get("forecast_amount")
            a = r.get("actual_amount")
            if f is not None:
                if f > 0:
                    f_income += f
                elif f < 0:
                    f_spend += f
                    buckets.setdefault(cat, {"spending_actual": 0.0, "spending_forecast": 0.0})
                    buckets[cat]["spending_forecast"] += -f
            if a is not None:
                if a > 0:
                    a_income += a
                elif a < 0:
                    a_spend += a
                    buckets.setdefault(cat, {"spending_actual": 0.0, "spending_forecast": 0.0})
                    buckets[cat]["spending_actual"] += -a

        # Sort categories by actual spending desc (falling back to forecast) and
        # drop any that have zero in both columns.
        cats = [
            {"name": n, "color": cat_colors.get(n),
             "spending_actual": round(b["spending_actual"], 2),
             "spending_forecast": round(b["spending_forecast"], 2)}
            for n, b in buckets.items()
            if b["spending_actual"] > 0 or b["spending_forecast"] > 0
        ]
        cats.sort(key=lambda x: (x["spending_actual"], x["spending_forecast"]), reverse=True)

        # --- Daily balance trend ---------------------------------------------
        # Walk each day in the window, carrying the last-known actual_balance
        # forward. We take the LAST row on each day (events are already sorted
        # by anchor_date).
        day_to_balance: dict[str, float] = {}
        for r in rows:
            d = r.get("actual_date") or r.get("forecast_date")
            if d:
                day_to_balance[d] = r["actual_balance"]

        trend = []
        running = data["opening_balance"]
        d = start
        while d <= end:
            key = d.isoformat()
            if key in day_to_balance:
                running = day_to_balance[key]
            trend.append({"date": key, "balance": round(running, 2)})
            d += timedelta(days=1)

        accounts_out.append({
            "account_id": acc.id,
            "account_name": acc.name,
            "totals": {
                "income_actual": round(a_income, 2),
                "spending_actual": round(-a_spend, 2),     # magnitude
                "net_actual": round(a_income + a_spend, 2),
                "income_forecast": round(f_income, 2),
                "spending_forecast": round(-f_spend, 2),   # magnitude
                "net_forecast": round(f_income + f_spend, 2),
            },
            "categories": cats,
            "balance_trend": trend,
            "opening_balance": round(data["opening_balance"], 2),
            "forecast_end": round(data["forecast_ending_balance"], 2),
            "actual_end": round(data["actual_ending_balance"], 2),
        })

    return {
        "window": window,
        "label": label,
        "start": start.isoformat(),
        "end": end.isoformat(),
        "accounts": accounts_out,
    }


# ---------- Account transfers ----------
# A transfer is a single user-facing record (Transfer row) that materializes
# two paired Transaction legs sharing the same transfer_id. The legs run the
# normal forecast/balance math; the transfer_id flag is what tells the
# dashboard charts and reports endpoints to exclude them from spend/income
# aggregations so internal money movement isn't double-counted.

TRANSFER_DESC_DEFAULT = "Transfer"
TRANSFER_DESC_MAX = 120


class TransferIn(BaseModel):
    from_account_id: int
    to_account_id: int
    amount: float = Field(..., gt=0, le=1e12, allow_inf_nan=False)
    transfer_date: date
    description: str = Field(default=TRANSFER_DESC_DEFAULT, max_length=TRANSFER_DESC_MAX)
    notes: str | None = Field(default=None, max_length=256)


def _transfer_to_dict(db: Session, t: Transfer) -> dict:
    """Shape a Transfer for the API. Adds account names + the two leg ids."""
    legs = db.query(Transaction).filter(Transaction.transfer_id == t.id).all()
    leg_ids = sorted([l.id for l in legs])
    from_acc = db.get(Account, t.from_account_id)
    to_acc = db.get(Account, t.to_account_id)
    return {
        "id": t.id,
        "from_account_id": t.from_account_id,
        "from_account_name": from_acc.name if from_acc else None,
        "to_account_id": t.to_account_id,
        "to_account_name": to_acc.name if to_acc else None,
        "amount": float(t.amount),
        "transfer_date": t.transfer_date.isoformat(),
        "description": t.description,
        "notes": t.notes,
        "transaction_ids": leg_ids,
        "created_at": t.created_at.isoformat() if t.created_at else None,
    }


def _create_transfer_legs(db: Session, transfer: Transfer):
    """Insert the two Transaction rows backing a Transfer.

    Caller is responsible for db.commit(). The legs are created as cleared
    actuals on transfer_date so the user's balance reflects the move
    immediately — transfers are records of something that already happened.
    """
    desc = transfer.description
    notes = transfer.notes
    amt = float(transfer.amount)
    # Negative leg on from-account
    out_t = Transaction(
        account_id=transfer.from_account_id,
        transfer_id=transfer.id,
        actual_date=transfer.transfer_date,
        forecast_date=transfer.transfer_date,
        is_actual=True,
    )
    out_t.description = f"→ {desc}"
    out_t.amount = Decimal(str(-amt))
    out_t.notes = notes
    db.add(out_t)
    # Positive leg on to-account
    in_t = Transaction(
        account_id=transfer.to_account_id,
        transfer_id=transfer.id,
        actual_date=transfer.transfer_date,
        forecast_date=transfer.transfer_date,
        is_actual=True,
    )
    in_t.description = f"← {desc}"
    in_t.amount = Decimal(str(amt))
    in_t.notes = notes
    db.add(in_t)


def _delete_transfer_legs(db: Session, transfer_id: int):
    """Remove all Transaction rows linked to a Transfer."""
    db.query(Transaction).filter(Transaction.transfer_id == transfer_id).delete(
        synchronize_session=False
    )


@app.get("/api/transfers")
def list_transfers(limit: int = 50, offset: int = 0,
                   user: User = Depends(current_user), db: Session = Depends(get_db)):
    """List the caller's transfers, newest first.

    A transfer is visible to the user if they have at least 'read' on both
    of its legs. We query by owner_id (the user who created it) and also
    pull in transfers where the caller has access to either leg.
    """
    visible_ids = {a.id for a in _user_visible_accounts(db, user, include_archived=True)}
    q = db.query(Transfer).filter(
        (Transfer.owner_id == user.id) |
        (Transfer.from_account_id.in_(visible_ids)) |
        (Transfer.to_account_id.in_(visible_ids))
    ).order_by(Transfer.transfer_date.desc(), Transfer.id.desc())
    total = q.count()
    rows = q.offset(max(0, offset)).limit(min(max(1, limit), 500)).all()
    return {
        "total": total,
        "transfers": [_transfer_to_dict(db, t) for t in rows],
    }


@app.post("/api/transfers")
def create_transfer(payload: TransferIn,
                    user: User = Depends(current_user), db: Session = Depends(get_db)):
    if payload.from_account_id == payload.to_account_id:
        raise HTTPException(400, "from_account and to_account must differ")
    # Caller must have edit on both accounts.
    _account_with_perm(db, user, payload.from_account_id, "edit")
    _account_with_perm(db, user, payload.to_account_id, "edit")
    desc = (payload.description or TRANSFER_DESC_DEFAULT).strip() or TRANSFER_DESC_DEFAULT
    transfer = Transfer(
        owner_id=user.id,
        from_account_id=payload.from_account_id,
        to_account_id=payload.to_account_id,
        transfer_date=payload.transfer_date,
    )
    transfer.description = desc
    transfer.amount = Decimal(str(payload.amount))
    transfer.notes = payload.notes
    db.add(transfer)
    db.flush()  # populate transfer.id without committing
    _create_transfer_legs(db, transfer)
    db.commit()
    db.refresh(transfer)
    return _transfer_to_dict(db, transfer)


@app.patch("/api/transfers/{transfer_id}")
def update_transfer(transfer_id: int, payload: TransferIn,
                    user: User = Depends(current_user), db: Session = Depends(get_db)):
    transfer = db.get(Transfer, transfer_id)
    if not transfer:
        raise HTTPException(404, "Transfer not found")
    # Caller must have edit on both the OLD and NEW accounts so they can't
    # silently move money to an account they don't control.
    _account_with_perm(db, user, transfer.from_account_id, "edit")
    _account_with_perm(db, user, transfer.to_account_id, "edit")
    _account_with_perm(db, user, payload.from_account_id, "edit")
    _account_with_perm(db, user, payload.to_account_id, "edit")
    if payload.from_account_id == payload.to_account_id:
        raise HTTPException(400, "from_account and to_account must differ")
    transfer.from_account_id = payload.from_account_id
    transfer.to_account_id = payload.to_account_id
    transfer.transfer_date = payload.transfer_date
    transfer.description = (payload.description or TRANSFER_DESC_DEFAULT).strip() or TRANSFER_DESC_DEFAULT
    transfer.amount = Decimal(str(payload.amount))
    transfer.notes = payload.notes
    # Easiest correct approach: blow away + recreate the legs.
    _delete_transfer_legs(db, transfer.id)
    db.flush()
    _create_transfer_legs(db, transfer)
    db.commit()
    return _transfer_to_dict(db, transfer)


@app.delete("/api/transfers/{transfer_id}")
def delete_transfer(transfer_id: int,
                    user: User = Depends(current_user), db: Session = Depends(get_db)):
    transfer = db.get(Transfer, transfer_id)
    if not transfer:
        raise HTTPException(404, "Transfer not found")
    # Only an editor on either side can delete the transfer.
    _account_with_perm(db, user, transfer.from_account_id, "edit")
    db.delete(transfer)  # cascade removes the linked transaction legs
    db.commit()
    return {"ok": True}


# ---------- Budgets per category ----------
class BudgetIn(BaseModel):
    category_id: int
    amount: float = Field(..., ge=0, le=1e12, allow_inf_nan=False)
    period: str = Field(default="monthly", max_length=20)


ALLOWED_BUDGET_PERIODS = {"monthly"}


@app.get("/api/budgets")
def list_budgets(user: User = Depends(current_user), db: Session = Depends(get_db)):
    rows = (
        db.query(CategoryBudget)
        .filter(CategoryBudget.owner_id == user.id)
        .all()
    )
    out = []
    for b in rows:
        out.append({
            "id": b.id,
            "category_id": b.category_id,
            "category_name": b.category.name if b.category else None,
            "category_color": b.category.color if b.category else None,
            "amount": float(b.amount),
            "period": b.period,
        })
    out.sort(key=lambda x: (x["category_name"] or "").lower())
    return out


@app.post("/api/budgets")
def upsert_budget(payload: BudgetIn,
                  user: User = Depends(current_user), db: Session = Depends(get_db)):
    """Set the budget for a category. Idempotent: re-posting overwrites."""
    if payload.period not in ALLOWED_BUDGET_PERIODS:
        raise HTTPException(400, f"period must be one of {sorted(ALLOWED_BUDGET_PERIODS)}")
    _own_category(db, user, payload.category_id)
    existing = (
        db.query(CategoryBudget)
        .filter(CategoryBudget.owner_id == user.id,
                CategoryBudget.category_id == payload.category_id)
        .first()
    )
    if existing:
        existing.amount = Decimal(str(payload.amount))
        existing.period = payload.period
        b = existing
    else:
        b = CategoryBudget(
            owner_id=user.id,
            category_id=payload.category_id,
            period=payload.period,
        )
        b.amount = Decimal(str(payload.amount))
        db.add(b)
    db.commit()
    db.refresh(b)
    return {"id": b.id, "category_id": b.category_id,
            "amount": float(b.amount), "period": b.period}


@app.delete("/api/budgets/{category_id}")
def delete_budget(category_id: int,
                  user: User = Depends(current_user), db: Session = Depends(get_db)):
    existing = (
        db.query(CategoryBudget)
        .filter(CategoryBudget.owner_id == user.id,
                CategoryBudget.category_id == category_id)
        .first()
    )
    if not existing:
        raise HTTPException(404, "No budget for that category")
    db.delete(existing)
    db.commit()
    return {"ok": True}


@app.get("/api/budgets/progress")
def budgets_progress(window: str = "month", today: date | None = None,
                     user: User = Depends(current_user), db: Session = Depends(get_db)):
    """Per-category spend vs budget for the chosen window.

    Spend is computed by summing absolute values of negative actual_amount
    across every visible account's forecast rows in the window. Transfer legs
    are excluded. Returns a row per budget plus a row per category that has
    spend but no budget set (so users can see candidates to budget).
    """
    if window not in ALLOWED_DASHBOARD_WINDOWS:
        raise HTTPException(400, f"window must be one of {sorted(ALLOWED_DASHBOARD_WINDOWS)}")
    start, end, label = _resolve_dashboard_window(window, _viewer_today(today))

    spend_by_cat: dict[str, float] = {}
    UNCAT = "(uncategorized)"
    for acc in _user_visible_accounts(db, user):
        data = build_forecast(db, acc, start, end)
        for r in data["rows"]:
            if r.get("transfer_id") is not None:
                continue
            a = r.get("actual_amount")
            if a is None or a >= 0:
                continue
            cat = r.get("category") or UNCAT
            spend_by_cat[cat] = spend_by_cat.get(cat, 0.0) + (-a)

    # Budgets keyed by category name
    budgets_by_cat: dict[str, dict] = {}
    for b in db.query(CategoryBudget).filter_by(owner_id=user.id).all():
        if not b.category:
            continue
        budgets_by_cat[b.category.name] = {
            "category_id": b.category_id,
            "category_color": b.category.color,
            "amount": float(b.amount),
        }

    # Build progress rows: union of (budgeted categories) + (categories with spend)
    out = []
    seen = set()
    for name, b in budgets_by_cat.items():
        spend = round(spend_by_cat.get(name, 0.0), 2)
        budget = b["amount"]
        pct = round((spend / budget) * 100, 1) if budget > 0 else None
        out.append({
            "category_id": b["category_id"],
            "category_name": name,
            "category_color": b["category_color"],
            "budget": budget,
            "spend": spend,
            "remaining": round(budget - spend, 2),
            "pct": pct,
            "over": spend > budget,
            "has_budget": True,
        })
        seen.add(name)
    for name, spend in spend_by_cat.items():
        if name in seen:
            continue
        # Best-effort lookup so we can return a category_id when known
        cat = (
            db.query(Category)
            .filter(Category.owner_id == user.id, Category.name == name)
            .first()
        )
        out.append({
            "category_id": cat.id if cat else None,
            "category_name": name,
            "category_color": cat.color if cat else None,
            "budget": 0.0,
            "spend": round(spend, 2),
            "remaining": round(-spend, 2),
            "pct": None,
            "over": False,
            "has_budget": False,
        })
    out.sort(key=lambda r: (-(r["spend"] or 0), r["category_name"].lower()))
    total_budget = round(sum(b["amount"] for b in budgets_by_cat.values()), 2)
    total_spend = round(sum(spend_by_cat.values()), 2)
    return {
        "window": window,
        "label": label,
        "start": start.isoformat(),
        "end": end.isoformat(),
        "rows": out,
        "totals": {
            "budget": total_budget,
            "spend": total_spend,
            "remaining": round(total_budget - total_spend, 2),
        },
    }


# ---------- Transaction search ----------
@app.get("/api/transactions/search")
def search_transactions(q: str | None = None,
                        account_id: int | None = None,
                        category_id: int | None = None,
                        tag_id: int | None = None,
                        date_from: date | None = None,
                        date_to: date | None = None,
                        min_amount: float | None = None,
                        max_amount: float | None = None,
                        kind: str | None = None,    # 'income' | 'spending' | 'transfers' | None=any
                        include_transfers: bool = True,
                        limit: int = 100,
                        offset: int = 0,
                        user: User = Depends(current_user),
                        db: Session = Depends(get_db)):
    """Search the caller's transactions across all visible, non-archived
    accounts (same "browsing" scope as the Dashboard and Accounts page —
    archived accounts are hidden by default, not just from their own tab).

    Description and notes are encrypted at rest, so the text-search half of
    this filter has to decrypt-and-compare in Python. The SQL filter narrows
    on the cheap fields first (account, category, dates, transfer flag) so
    the decrypt loop only runs on a small candidate set.
    """
    visible_ids = {a.id for a in _user_visible_accounts(db, user)}
    if not visible_ids:
        return {"total": 0, "results": []}
    if account_id is not None and account_id not in visible_ids:
        raise HTTPException(404, "Account not found")

    base = db.query(Transaction).filter(Transaction.account_id.in_(visible_ids))
    if account_id is not None:
        base = base.filter(Transaction.account_id == account_id)
    if category_id is not None:
        base = base.filter(Transaction.category_id == category_id)
    if tag_id is not None:
        # Validate that the tag belongs to the caller before joining, so we
        # don't leak "tag exists" info across users.
        _own_tag(db, user, tag_id)
        base = base.join(
            TransactionTag, TransactionTag.transaction_id == Transaction.id
        ).filter(TransactionTag.tag_id == tag_id)
    if date_from is not None:
        base = base.filter(
            (Transaction.actual_date >= date_from) | (Transaction.forecast_date >= date_from)
        )
    if date_to is not None:
        base = base.filter(
            (Transaction.actual_date <= date_to) | (Transaction.forecast_date <= date_to)
        )
    if not include_transfers or kind == "income" or kind == "spending":
        # Exclude transfer legs. (Switched on either flag.)
        if kind != "transfers":
            base = base.filter(Transaction.transfer_id.is_(None))
    if kind == "transfers":
        base = base.filter(Transaction.transfer_id.isnot(None))

    candidates = base.order_by(Transaction.actual_date.desc().nullslast(),
                               Transaction.forecast_date.desc().nullslast(),
                               Transaction.id.desc()).all()

    # Decrypt + apply text/amount filter
    needle = (q or "").strip().lower() or None
    out = []
    acc_names = {a.id: a.name for a in _user_visible_accounts(db, user)}
    for t in candidates:
        amt = float(t.amount)
        if min_amount is not None and amt < min_amount:
            continue
        if max_amount is not None and amt > max_amount:
            continue
        if kind == "income" and amt <= 0:
            continue
        if kind == "spending" and amt >= 0:
            continue
        desc = t.description or ""
        notes = t.notes or ""
        if needle and needle not in desc.lower() and needle not in notes.lower():
            continue
        out.append({
            "id": t.id,
            "account_id": t.account_id,
            "account_name": acc_names.get(t.account_id),
            "description": desc,
            "amount": amt,
            "forecast_amount": float(t.forecast_amount) if t.forecast_amount is not None else None,
            "actual_date": t.actual_date.isoformat() if t.actual_date else None,
            "forecast_date": t.forecast_date.isoformat() if t.forecast_date else None,
            "is_actual": t.is_actual,
            "category_id": t.category_id,
            "category_name": t.category.name if t.category else None,
            "recurring_id": t.recurring_id,
            "transfer_id": t.transfer_id,
            "notes": notes or None,
        })

    total = len(out)
    page = out[max(0, offset): max(0, offset) + min(max(1, limit), 1000)]
    # Attach tags to the paginated results only (avoid loading tags for
    # rows the client will never see).
    page_ids = [r["id"] for r in page]
    tags_by_txn = _tags_for_transactions(db, page_ids)
    for r in page:
        r["tags"] = tags_by_txn.get(r["id"], [])
    return {"total": total, "results": page,
            "limit": limit, "offset": offset}


# ---------- Search across everything (#111) ----------
# One search for the web app's top bar and the iOS app (ios-app phase 10,
# #112): transactions, bills and income, accounts, categories, tags and saved
# reports, each group as {total, results}. Matching is a case-insensitive
# "contains" on names (and descriptions and notes for transactions and bills),
# done in Python because they're encrypted at rest. Each group holds only
# what the caller may see: the accounts they can read (archived ones left
# out, as on the Dashboard), and their own categories, tags and reports.
# Decided 2026-11-15 (docs/dev/decisions/search.md): each result carries its
# name and one detail, and tags are a group of their own.
SEARCH_GROUP_LIMIT = 20
SEARCH_GROUP_LIMIT_MAX = 100


def _search_group(rows: list[dict], limit: int) -> dict:
    return {"total": len(rows), "results": rows[:limit]}


@app.get("/api/search")
def search_everything(q: str = "", limit: int = SEARCH_GROUP_LIMIT,
                      today: date | None = None,
                      user: User = Depends(current_user),
                      db: Session = Depends(get_db)):
    """Everything matching `q`, grouped by kind, up to `limit` per group
    (1-100) with each group's full count. An empty `q` finds nothing."""
    today = _viewer_today(today)
    limit = max(1, min(limit, SEARCH_GROUP_LIMIT_MAX))
    needle = q.strip().casefold()
    groups = ("transactions", "recurring", "accounts", "categories", "tags", "reports")
    if not needle:
        return {"query": "", **{g: {"total": 0, "results": []} for g in groups}}

    def hit(*texts: str | None) -> bool:
        return any(t and needle in t.casefold() for t in texts)

    accounts = _user_visible_accounts(db, user)
    acc_by_id = {a.id: a for a in accounts}
    acc_names = {a.id: a.name for a in accounts}
    visible_ids = list(acc_by_id) or [0]

    # Transactions: newest first, as /api/transactions/search.
    txns = []
    for t in (db.query(Transaction).filter(Transaction.account_id.in_(visible_ids))
              .order_by(Transaction.actual_date.desc().nullslast(),
                        Transaction.forecast_date.desc().nullslast(),
                        Transaction.id.desc())):
        if not hit(t.description, t.notes):
            continue
        day = t.actual_date or t.forecast_date
        # The fields of /api/transactions/search's rows, so the iOS app opens
        # a result in its line editor, plus `date` (the actual or planned day).
        txns.append({
            "id": t.id, "description": t.description or "",
            "date": day.isoformat() if day else None,
            "amount": float(t.amount),
            "forecast_amount": float(t.forecast_amount) if t.forecast_amount is not None else None,
            "actual_date": t.actual_date.isoformat() if t.actual_date else None,
            "forecast_date": t.forecast_date.isoformat() if t.forecast_date else None,
            "is_actual": t.is_actual,
            "account_id": t.account_id, "account_name": acc_names.get(t.account_id),
            "category_id": t.category_id,
            "category_name": t.category.name if t.category else None,
            "recurring_id": t.recurring_id, "transfer_id": t.transfer_id,
            "notes": t.notes or None,
        })

    # Bills and income: those still running first, then ended ones; by name.
    # Each as /api/recurring's items, so the iOS app opens it in its editor.
    recs = [(a, r) for a in accounts for r in a.recurring if hit(r.description, r.notes)]
    upcoming = _recurring_upcoming(db, [r for _, r in recs], today)
    skip_counts = _recurring_skip_counts(db, [r.id for _, r in recs])
    tags_by_rec = _tags_for_recurring(db, [r.id for _, r in recs])
    levels = dict(db.query(AccountPermission.account_id, AccountPermission.level)
                  .filter(AccountPermission.user_id == user.id,
                          AccountPermission.account_id.in_(visible_ids)))
    bills = []
    for a, r in recs:
        nexts = upcoming.get(r.id, [])
        row = _recurring_row(r, today, skip_counts, tags_by_rec)
        row.update({
            "account_id": a.id, "account_name": a.name,
            "account_level": levels.get(a.id, "read"),
            "category_color": r.category.color if r.category else None,
            "next_date": nexts[0].isoformat() if nexts else None,
            "next_dates": [d.isoformat() for d in nexts],
        })
        bills.append(row)
    bills.sort(key=lambda b: (b["expired"], b["description"].casefold(), b["id"]))

    found_accounts = sorted(
        ({"id": a.id, "name": a.name,
          "current_balance": round(_current_balance(db, a, today), 2),
          "level": levels.get(a.id, "read")}
         for a in accounts if hit(a.name)),
        key=lambda x: (x["name"].casefold(), x["id"]))

    # Categories and tags: the caller's own, with how many transactions on
    # the accounts they can see carry each.
    cats = [c for c in db.query(Category).filter_by(owner_id=user.id) if hit(c.name)]
    cat_counts = dict(db.query(Transaction.category_id, func.count(Transaction.id))
                      .filter(Transaction.account_id.in_(visible_ids),
                              Transaction.category_id.in_([c.id for c in cats] or [0]))
                      .group_by(Transaction.category_id))
    found_cats = sorted(({"id": c.id, "name": c.name, "color": c.color,
                          "transaction_count": cat_counts.get(c.id, 0)} for c in cats),
                        key=lambda x: (x["name"].casefold(), x["id"]))
    tags = [t for t in db.query(Tag).filter_by(owner_id=user.id) if hit(t.name)]
    tag_counts = dict(db.query(TransactionTag.tag_id, func.count(TransactionTag.transaction_id))
                      .join(Transaction, Transaction.id == TransactionTag.transaction_id)
                      .filter(Transaction.account_id.in_(visible_ids),
                              TransactionTag.tag_id.in_([t.id for t in tags] or [0]))
                      .group_by(TransactionTag.tag_id))
    found_tags = sorted(({"id": t.id, "name": t.name, "color": t.color,
                          "transaction_count": tag_counts.get(t.id, 0)} for t in tags),
                        key=lambda x: (x["name"].casefold(), x["id"]))

    reports = [{"id": r.id, "name": r.name, "pinned": bool(r.pinned)}
               for r in (db.query(SavedReport).filter_by(owner_id=user.id)
                         .order_by(SavedReport.sort_order.asc(), SavedReport.id.asc()))
               if hit(r.name)]

    return {
        "query": q.strip(),
        "transactions": _search_group(txns, limit),
        "recurring": _search_group(bills, limit),
        "accounts": _search_group(found_accounts, limit),
        "categories": _search_group(found_cats, limit),
        "tags": _search_group(found_tags, limit),
        "reports": _search_group(reports, limit),
    }


# ---------- Bulk tag operations ----------
class BulkTagIn(BaseModel):
    """Apply or remove tags across many transactions in one shot.

    `add_tag_ids`    — tags to attach (idempotent; existing memberships left).
    `remove_tag_ids` — tags to detach (idempotent; absent memberships left).
    Both lists are optional but at least one must be non-empty. Tag
    ownership and per-transaction edit permission are checked per row.
    """
    transaction_ids: list[int] = Field(..., min_length=1, max_length=1000)
    add_tag_ids:     list[int] = Field(default_factory=list)
    remove_tag_ids:  list[int] = Field(default_factory=list)


@app.post("/api/transactions/bulk-tag")
def bulk_tag_transactions(payload: BulkTagIn,
                          user: User = Depends(current_user),
                          db: Session = Depends(get_db)):
    if not payload.add_tag_ids and not payload.remove_tag_ids:
        raise HTTPException(400, "Provide add_tag_ids and/or remove_tag_ids")
    # Validate tag ownership once up-front so a bad id fails the whole
    # batch atomically (no half-applied state).
    for tid in payload.add_tag_ids + payload.remove_tag_ids:
        _own_tag(db, user, tid)
    # Walk each transaction; require edit on its account. Skip silently
    # if the user can read but not edit a row (matches the conservative
    # behavior of single-row PATCH for shared accounts).
    applied = 0
    skipped = 0
    for tid in payload.transaction_ids:
        t = db.get(Transaction, tid)
        if not t:
            skipped += 1
            continue
        try:
            _account_with_perm(db, user, t.account_id, "edit")
        except HTTPException:
            skipped += 1
            continue
        # Add: insert join rows that don't already exist. We query the
        # existing set first so the operation is idempotent and we don't
        # rely on a unique constraint (the schema currently has none —
        # see db.py).
        if payload.add_tag_ids:
            existing = {
                row[0] for row in db.query(TransactionTag.tag_id)
                                    .filter_by(transaction_id=t.id).all()
            }
            for atag in payload.add_tag_ids:
                if atag not in existing:
                    db.add(TransactionTag(transaction_id=t.id, tag_id=atag))
                    existing.add(atag)
        if payload.remove_tag_ids:
            (db.query(TransactionTag)
               .filter(TransactionTag.transaction_id == t.id,
                       TransactionTag.tag_id.in_(payload.remove_tag_ids))
               .delete(synchronize_session=False))
        applied += 1
    db.commit()
    return {"applied": applied, "skipped": skipped}


# ---------- CSV import ----------
import csv
import io as _csvio


def _detect_columns(headers: list[str]) -> dict[str, int | None]:
    """Heuristic auto-mapping for common bank CSV column names."""
    mapping = {"date": None, "description": None, "amount": None,
               "debit": None, "credit": None, "category": None, "notes": None,
               "tags": None, "frequency": None, "end_date": None, "recurring_group": None}
    lowered = [(i, (h or "").strip().lower()) for i, h in enumerate(headers)]
    for i, h in lowered:
        if mapping["date"] is None and h in ("date", "transaction date", "posted date", "post date"):
            mapping["date"] = i
        elif mapping["description"] is None and h in ("description", "details", "memo", "merchant", "name", "payee"):
            mapping["description"] = i
        elif mapping["amount"] is None and h in ("amount", "value", "transaction amount"):
            mapping["amount"] = i
        elif mapping["debit"] is None and h in ("debit", "withdrawal", "withdrawals", "outflow"):
            mapping["debit"] = i
        elif mapping["credit"] is None and h in ("credit", "deposit", "deposits", "inflow"):
            mapping["credit"] = i
        elif mapping["category"] is None and h in ("category",):
            mapping["category"] = i
        elif mapping["tags"] is None and h in ("tags", "tag", "labels"):
            mapping["tags"] = i
        elif mapping["notes"] is None and h in ("notes", "note"):
            mapping["notes"] = i
        elif mapping["frequency"] is None and h in ("frequency", "recurring", "repeat", "recurrence"):
            mapping["frequency"] = i
        elif mapping["end_date"] is None and h in ("end date", "recurring end date", "until"):
            mapping["end_date"] = i
        elif mapping["recurring_group"] is None and h in ("recurring group", "group"):
            mapping["recurring_group"] = i
    return mapping


# Accepted values for the optional `frequency` CSV column. A row with a
# recognized frequency becomes a recurring transaction template (using the
# row's date as anchor date / day-of-month) instead of a one-time actual
# transaction. Keys are matched case-insensitively.
FREQUENCY_ALIASES = {
    "monthly": "monthly_day", "monthly_day": "monthly_day", "month": "monthly_day",
    "weekly": "weekly", "week": "weekly",
    "biweekly": "biweekly", "bi-weekly": "biweekly", "bi weekly": "biweekly",
    "fortnightly": "biweekly", "every 2 weeks": "biweekly", "every two weeks": "biweekly",
}


def _normalize_frequency(raw: str | None) -> str | None:
    if not raw:
        return None
    return FREQUENCY_ALIASES.get(str(raw).strip().lower())


def _parse_csv_amount(raw: str | None) -> float | None:
    if raw is None:
        return None
    s = str(raw).strip()
    if not s:
        return None
    # Strip currency symbols, thousands separators, parentheses-as-negative
    neg = s.startswith("(") and s.endswith(")")
    s = s.replace("(", "").replace(")", "")
    s = s.replace("$", "").replace("£", "").replace("€", "").replace(",", "").strip()
    try:
        v = float(s)
    except ValueError:
        return None
    if not math.isfinite(v) or abs(v) > 1e12:
        return None   # "nan", "inf" and absurd sizes aren't amounts (#185)
    return -v if neg else v


def _parse_csv_date(raw: str | None) -> date | None:
    if raw is None:
        return None
    s = str(raw).strip()
    if not s:
        return None
    for fmt in ("%Y-%m-%d", "%m/%d/%Y", "%m/%d/%y", "%d/%m/%Y", "%d/%m/%y",
                "%Y/%m/%d", "%m-%d-%Y", "%d-%m-%Y", "%b %d, %Y", "%d %b %Y"):
        try:
            return datetime.strptime(s, fmt).date()
        except ValueError:
            continue
    return None


def _parse_csv_rows(csv_text: str, has_header: bool, mapping: dict | None,
                    sign_convention: str = "amount"):
    """Yield dicts describing each row from a CSV blob.

    sign_convention:
      - 'amount':            single signed column (negative = withdraw)
      - 'amount_invert':     single signed column where positive = withdraw
      - 'debit_credit':      two columns: debit (positive=withdraw), credit (positive=deposit)

    A row with a recognized value in the optional `frequency` column (see
    FREQUENCY_ALIASES) is imported as an actual transaction *and* linked to a
    recurring transaction template — rows sharing the same frequency and
    description (or the same optional `recurring_group` override, for series
    whose description text drifts) are treated as past occurrences of one
    series; see _recurring_group_key / _recurring_template_identity. An
    unrecognized, non-empty frequency value skips the row rather than
    silently importing it as one-time, so a typo doesn't quietly drop a bill
    out of its series.
    """
    reader = csv.reader(_csvio.StringIO(csv_text))
    rows = list(reader)
    if not rows:
        return [], [], [], mapping or {}
    if has_header:
        headers, body = rows[0], rows[1:]
    else:
        headers = [f"col_{i+1}" for i in range(len(rows[0]))]
        body = rows
    if mapping is None:
        mapping = _detect_columns(headers)

    out = []
    skipped = []
    for idx, row in enumerate(body):
        def cell(key):
            i = mapping.get(key)
            if i is None or not 0 <= i < len(row):
                return None
            return row[i]
        d = _parse_csv_date(cell("date"))
        desc = (cell("description") or "").strip()[:DESCRIPTION_MAX] or "(no description)"
        amt: float | None = None
        if sign_convention == "debit_credit":
            deb = _parse_csv_amount(cell("debit")) or 0.0
            cred = _parse_csv_amount(cell("credit")) or 0.0
            amt = (cred - deb) if (deb or cred) else None
        else:
            amt = _parse_csv_amount(cell("amount"))
            if sign_convention == "amount_invert" and amt is not None:
                amt = -amt
        notes = cell("notes")
        if notes:
            notes = str(notes).strip()[:NOTES_MAX_LEN] or None
        category_name = (cell("category") or "").strip() or None
        tags_raw = cell("tags")
        tag_names = [p.strip() for p in re.split(r"[;,]", str(tags_raw)) if p.strip()] \
            if tags_raw else []
        freq_raw = (cell("frequency") or "").strip() or None
        frequency = _normalize_frequency(freq_raw) if freq_raw else None
        if freq_raw and frequency is None:
            skipped.append({"row_index": idx, "row": row,
                            "reason": f'unrecognized frequency "{freq_raw}"'})
            continue
        end_date = _parse_csv_date(cell("end_date"))
        recurring_group = (cell("recurring_group") or "").strip() or None
        if d is None or amt is None:
            skipped.append({"row_index": idx, "row": row,
                            "reason": "missing date or amount"})
            continue
        out.append({
            "row_index": idx,
            "date": d.isoformat(),
            "description": desc,
            "amount": amt,
            "notes": notes,
            "category_name": category_name,
            "tag_names": tag_names,
            "frequency": frequency,
            "end_date": end_date.isoformat() if end_date else None,
            "recurring_group": recurring_group,
            "raw": row,
        })
    return out, skipped, headers, mapping


def _category_lookup(db: Session, user: User) -> dict[str, int]:
    """Case-insensitive category name -> id lookup for the current user."""
    cats = db.query(Category).filter_by(owner_id=user.id).all()
    return {c.name.strip().lower(): c.id for c in cats}


def _resolve_row_category(row: dict, lookup: dict[str, int],
                          default_category_id: int | None) -> int | None:
    """CSV category column wins if it matches an existing category by name
    (case-insensitive); unmapped/unmatched names fall back to the chosen
    default category rather than silently dropping the row's category."""
    name = row.get("category_name")
    if name:
        matched = lookup.get(name.strip().lower())
        if matched is not None:
            return matched
    return default_category_id


def _tag_lookup(db: Session, user: User) -> dict[str, int]:
    """Case-insensitive tag name -> id lookup for the current user."""
    tags = db.query(Tag).filter_by(owner_id=user.id).all()
    return {t.name.strip().lower(): t.id for t in tags}


def _resolve_row_tags(row: dict, lookup: dict[str, int]) -> tuple[list[int], list[str]]:
    """Split the CSV tags cell on comma/semicolon and match each piece
    against the user's existing tags by name (case-insensitive). Unmatched
    names are returned separately rather than auto-created — same
    conservative policy as category, so a typo doesn't spawn a stray tag."""
    matched, unmatched = [], []
    for name in row.get("tag_names") or []:
        tid = lookup.get(name.strip().lower())
        if tid is not None:
            matched.append(tid)
        else:
            unmatched.append(name)
    return matched, unmatched


def _recurring_group_key(r: dict) -> str:
    """Key used to cluster rows within a single import into one recurring
    series. The optional `recurring_group` column overrides the default of
    grouping by description (case-insensitive) — useful when a bill's
    description text drifts between statements (e.g. an embedded date) but
    the user still wants every occurrence linked to one template."""
    label = r.get("recurring_group") or r["description"]
    return label.strip().lower()


def _recurring_template_identity(db: Session, account_id: int) -> dict[tuple, RecurringTransaction]:
    """(frequency, description_lower) -> existing RecurringTransaction on
    this account. Used to reuse a template across separate import runs
    (e.g. importing more months of the same bill later) instead of creating
    a duplicate template every time. Keyed on the template's own stored
    description, since that's all that's persisted — a `recurring_group`
    label used to create the template isn't itself stored anywhere."""
    out: dict[tuple, RecurringTransaction] = {}
    recs = db.query(RecurringTransaction).filter(RecurringTransaction.account_id == account_id).all()
    for r in recs:
        out.setdefault((r.frequency, (r.description or "").strip().lower()), r)
    return out


def _resolve_recurring_groups(rows: list[dict],
                              existing_templates: dict[tuple, RecurringTransaction]) -> dict[tuple, dict]:
    """For every (frequency, _recurring_group_key) among Frequency-flagged
    rows, decide whether it attaches to an existing RecurringTransaction or
    needs a new one. Identity is checked against the group's most-recent row
    (its date seeds the new template's anchor/day-of-month, and its amount/
    category/notes seed the template's baseline — recent rows best reflect
    the "current" state of a series whose amount may have drifted).

    Shared by preview and commit so the two can't disagree about grouping.
    Returns {(frequency, group_key): {"status": "existing"|"new",
                                       "template": RecurringTransaction|None,
                                       "seed_row": dict}}.
    """
    groups: dict[tuple, list[dict]] = {}
    for r in rows:
        if r["frequency"]:
            groups.setdefault((r["frequency"], _recurring_group_key(r)), []).append(r)
    resolved = {}
    for gkey, group_rows in groups.items():
        seed = max(group_rows, key=lambda x: x["date"])
        identity_key = (gkey[0], seed["description"].strip().lower())
        tmpl = existing_templates.get(identity_key)
        resolved[gkey] = {"status": "existing" if tmpl else "new",
                          "template": tmpl, "seed_row": seed}
    return resolved


class CSVPreviewIn(BaseModel):
    csv_text: str
    has_header: bool = True
    mapping: dict[str, int | None] | None = None
    sign_convention: str = "amount"


class CSVCommitIn(BaseModel):
    csv_text: str
    has_header: bool = True
    mapping: dict[str, int | None]
    sign_convention: str = "amount"
    default_category_id: int | None = None
    skip_duplicates: bool = True


def _existing_keys_for_account(db: Session, account_id: int) -> set[tuple]:
    """Build a dedupe set of (date_iso, amount, description_lower) for an account.

    Description is decrypted in-memory; for typical personal-finance volumes
    this is fine — the alternative would be a hash column we'd have to backfill.
    """
    keys = set()
    txns = db.query(Transaction).filter(Transaction.account_id == account_id).all()
    for t in txns:
        d = t.actual_date or t.forecast_date
        if not d:
            continue
        try:
            keys.add((d.isoformat(), round(float(t.amount), 2),
                      (t.description or "").strip().lower()))
        except Exception:
            continue
    return keys


@app.post("/api/accounts/{account_id}/import/preview")
def csv_import_preview(account_id: int, payload: CSVPreviewIn,
                       user: User = Depends(current_user), db: Session = Depends(get_db)):
    acc = _own_account(db, user, account_id)
    if not (payload.csv_text or "").strip():
        raise HTTPException(400, "csv_text is empty")
    if payload.sign_convention not in ("amount", "amount_invert", "debit_credit"):
        raise HTTPException(400, "Invalid sign_convention")
    rows, skipped, headers, mapping = _parse_csv_rows(
        payload.csv_text, payload.has_header, payload.mapping, payload.sign_convention)
    existing = _existing_keys_for_account(db, acc.id)
    existing_templates = _recurring_template_identity(db, acc.id)
    recurring_groups = _resolve_recurring_groups(rows, existing_templates)
    cat_lookup = _category_lookup(db, user)
    tag_lookup = _tag_lookup(db, user)
    dup_count = 0
    recurring_count = 0
    for r in rows:
        key = (r["date"], round(r["amount"], 2), r["description"].strip().lower())
        r["duplicate"] = key in existing
        if r["duplicate"]:
            dup_count += 1
        r["category_matched"] = bool(r.get("category_name")) and \
            r["category_name"].strip().lower() in cat_lookup
        _, unmatched_tags = _resolve_row_tags(r, tag_lookup)
        r["tags_unmatched"] = unmatched_tags
        if r["frequency"]:
            recurring_count += 1
            gkey = (r["frequency"], _recurring_group_key(r))
            r["recurring_template"] = recurring_groups[gkey]["status"]
        else:
            r["recurring_template"] = None
    return {
        "headers": headers,
        "mapping": mapping,
        "rows": rows[:200],   # cap preview
        "row_count": len(rows),
        "skipped": skipped[:50],
        "skipped_count": len(skipped),
        "duplicate_count": dup_count,
        "recurring_count": recurring_count,
        "sign_convention": payload.sign_convention,
        "has_header": payload.has_header,
    }


@app.post("/api/accounts/{account_id}/import/commit")
def csv_import_commit(account_id: int, payload: CSVCommitIn,
                      user: User = Depends(current_user), db: Session = Depends(get_db)):
    acc = _own_account(db, user, account_id)
    if payload.default_category_id is not None:
        _own_category(db, user, payload.default_category_id)
    if payload.sign_convention not in ("amount", "amount_invert", "debit_credit"):
        raise HTTPException(400, "Invalid sign_convention")
    rows, _skipped, _headers, _mapping = _parse_csv_rows(
        payload.csv_text, payload.has_header, payload.mapping, payload.sign_convention)
    existing = _existing_keys_for_account(db, acc.id) if payload.skip_duplicates else set()
    existing_templates = _recurring_template_identity(db, acc.id)
    recurring_groups = _resolve_recurring_groups(rows, existing_templates)
    new_templates: dict[tuple, RecurringTransaction] = {}
    cat_lookup = _category_lookup(db, user)
    tag_lookup = _tag_lookup(db, user)
    inserted = 0
    recurring_created = 0
    recurring_linked = 0
    duplicates = 0
    for r in rows:
        category_id = _resolve_row_category(r, cat_lookup, payload.default_category_id)

        recurring_id = None
        if r["frequency"]:
            gkey = (r["frequency"], _recurring_group_key(r))
            info = recurring_groups[gkey]
            if info["status"] == "existing":
                tmpl = info["template"]
            else:
                tmpl = new_templates.get(gkey)
                if tmpl is None:
                    # Seed the new template from the group's most-recent row —
                    # its date sets the anchor/day-of-month and its amount/
                    # category/notes become the template's forward-looking
                    # baseline (individual historical rows below keep their
                    # own actual amount, so forecast-vs-actual still reflects
                    # any price drift across the series).
                    seed = info["seed_row"]
                    seed_category_id = _resolve_row_category(seed, cat_lookup, payload.default_category_id)
                    sd = date.fromisoformat(seed["date"])
                    tmpl = RecurringTransaction(
                        account_id=acc.id,
                        category_id=seed_category_id,
                        frequency=seed["frequency"],
                        day_of_month=sd.day if seed["frequency"] == "monthly_day" else None,
                        anchor_date=None if seed["frequency"] == "monthly_day" else sd,
                        end_date=date.fromisoformat(seed["end_date"]) if seed["end_date"] else None,
                        active=True,
                    )
                    tmpl.description = seed["description"]
                    tmpl.amount = Decimal(str(seed["amount"]))
                    if seed.get("notes"):
                        tmpl.notes = seed["notes"]
                    db.add(tmpl)
                    db.flush()  # populate tmpl.id for the Transaction rows below
                    new_templates[gkey] = tmpl
                    recurring_created += 1
            recurring_id = tmpl.id

        key = (r["date"], round(r["amount"], 2), r["description"].strip().lower())
        if payload.skip_duplicates and key in existing:
            duplicates += 1
            continue
        existing.add(key)  # protect against duplicates within the file too
        d = _parse_csv_date(r["date"])
        if not d:
            continue
        t = Transaction(
            account_id=acc.id,
            category_id=category_id,
            recurring_id=recurring_id,
            actual_date=d,
            forecast_date=d,
            is_actual=True,
        )
        t.description = r["description"]
        t.amount = Decimal(str(r["amount"]))
        if r.get("notes"):
            t.notes = r["notes"]
        db.add(t)
        # Explicit CSV tags first, then auto-tag rules (same ordering as the
        # manual create endpoint). Need to flush so the row has an id before
        # we touch transaction_tags.
        db.flush()
        tag_ids, _unmatched = _resolve_row_tags(r, tag_lookup)
        if tag_ids:
            _apply_tags(db, user, t, tag_ids)
        _apply_tag_rules(db, user, t)
        inserted += 1
        if recurring_id is not None:
            recurring_linked += 1
    db.commit()
    return {"ok": True, "inserted": inserted, "recurring_created": recurring_created,
            "recurring_linked": recurring_linked, "duplicates_skipped": duplicates,
            "total_rows": len(rows)}


@app.get("/api/accounts/{account_id}/import/template")
def csv_import_template(account_id: int, user: User = Depends(current_user),
                        db: Session = Depends(get_db)):
    """Downloadable starter CSV covering every importable column — Category,
    Tags, Frequency/End Date, and Recurring Group — with worked examples of
    a one-time expense, one-time income, a past-recurring bill (three
    monthly streaming charges that link to one recurring template), and a
    Recurring Group override for a series whose description text drifts."""
    _own_account(db, user, account_id)
    cats = db.query(Category).filter_by(owner_id=user.id).order_by(Category.name).limit(2).all()
    tags = db.query(Tag).filter_by(owner_id=user.id).order_by(Tag.name).limit(1).all()
    cat1 = cats[0].name if cats else "Groceries"
    cat2 = cats[1].name if len(cats) > 1 else "Subscriptions"
    tag1 = tags[0].name if tags else "reimbursable"
    buf = _csvio.StringIO()
    w = csv.writer(buf)
    w.writerow(["Date", "Description", "Amount", "Category", "Tags", "Notes",
                "Frequency", "End Date", "Recurring Group"])
    w.writerow(["2026-07-01", "Grocery store", "-84.23", cat1, "", "", "", "", ""])
    w.writerow(["2026-09-01", "Paycheck", "2500.00", "Income", "", "", "", "", ""])
    # Same description + Frequency on every row = one series. All three import
    # as real actual transactions; they're linked to a single recurring
    # template (seeded from the most recent row) instead of three unrelated
    # one-off charges.
    w.writerow(["2026-07-01", "Streaming service", "-15.99", cat2, tag1, "Streaming subscription", "Monthly", "", ""])
    w.writerow(["2026-08-01", "Streaming service", "-15.99", cat2, tag1, "", "Monthly", "", ""])
    w.writerow(["2026-09-01", "Streaming service", "-15.99", cat2, tag1, "", "Monthly", "", ""])
    # Recurring Group overrides description-based grouping — use it when a
    # bill's description text isn't identical every month (e.g. an embedded
    # statement date) but should still link to one template.
    w.writerow(["2026-08-05", "GYM MEMBERSHIP AUG", "-39.00", "", "", "", "Monthly", "", "gym"])
    w.writerow(["2026-09-05", "GYM MEMBERSHIP SEP", "-39.00", "", "", "", "Monthly", "", "gym"])
    return Response(content=buf.getvalue(), media_type="text/csv",
                    headers={"Content-Disposition": 'attachment; filename="walletweather-import-template.csv"'})


# ---------- Net worth ----------
@app.get("/api/networth")
def net_worth(window: str = "month", today: date | None = None,
              user: User = Depends(current_user), db: Session = Depends(get_db)):
    """Aggregated net worth across all visible accounts.

    For each account, runs the same forecast walk used by /api/dashboard/charts
    and sums per-day balances. Returns a single time series plus a snapshot of
    today's actual (sum of opening + cleared activity) and end-of-window
    forecast.
    """
    if window not in ALLOWED_DASHBOARD_WINDOWS:
        raise HTTPException(400, f"window must be one of {sorted(ALLOWED_DASHBOARD_WINDOWS)}")
    start, end, label = _resolve_dashboard_window(window, _viewer_today(today))

    accounts = _user_visible_accounts(db, user)
    # Per-day totals, indexed by date string
    totals_by_day: dict[str, float] = {}
    per_account = []
    opening_total = 0.0
    forecast_end_total = 0.0
    actual_end_total = 0.0
    for acc in accounts:
        data = build_forecast(db, acc, start, end)
        opening_total += data["opening_balance"]
        forecast_end_total += data["forecast_ending_balance"]
        actual_end_total += data["actual_ending_balance"]
        rows = data["rows"]
        # Same daily-balance walk as dashboard_charts
        day_to_balance: dict[str, float] = {}
        for r in rows:
            d = r.get("actual_date") or r.get("forecast_date")
            if d:
                day_to_balance[d] = r["actual_balance"]
        running = data["opening_balance"]
        d = start
        per_account_trend = []
        while d <= end:
            key = d.isoformat()
            if key in day_to_balance:
                running = day_to_balance[key]
            totals_by_day[key] = totals_by_day.get(key, 0.0) + running
            per_account_trend.append({"date": key, "balance": round(running, 2)})
            d += timedelta(days=1)
        per_account.append({
            "account_id": acc.id,
            "account_name": acc.name,
            "opening_balance": round(data["opening_balance"], 2),
            "forecast_end": round(data["forecast_ending_balance"], 2),
            "actual_end": round(data["actual_ending_balance"], 2),
            "trend": per_account_trend,
        })

    # Sorted total trend
    total_trend = [{"date": k, "balance": round(v, 2)}
                   for k, v in sorted(totals_by_day.items())]
    return {
        "window": window,
        "label": label,
        "start": start.isoformat(),
        "end": end.isoformat(),
        "opening_total": round(opening_total, 2),
        "forecast_end_total": round(forecast_end_total, 2),
        "actual_end_total": round(actual_end_total, 2),
        "trend": total_trend,
        "accounts": per_account,
    }


# ---------- Subscription audit ----------
# _MONTHLY_FACTOR is defined above, next to /api/accounts/{id}/recurring,
# which also uses it (to surface monthly_cost/yearly_cost per row).
@app.get("/api/subscriptions")
def list_subscriptions(user: User = Depends(current_user),
                       db: Session = Depends(get_db)):
    """Cross-account audit of every recurring outflow (i.e. subscription) the
    user can see. Used by the Subscriptions page.

    Inclusion rule: active, not end-dated before today, and amount is
    strictly negative (positive recurring rows are paychecks / income, not
    subscriptions). We normalize every row to a monthly magnitude using
    `_MONTHLY_FACTOR` so cadences can be compared apples-to-apples, and sort
    descending by monthly cost so the biggest drains bubble up.

    No new tables — this is pure aggregation over `recurring_transactions`.
    """
    today = date.today()
    accounts = _user_visible_accounts(db, user)
    items = []
    total_monthly = 0.0
    total_yearly = 0.0
    for acc in accounts:
        for r in acc.recurring:
            if not r.active:
                continue
            if r.end_date is not None and r.end_date < today:
                continue
            try:
                amt = float(r.amount)
            except Exception:
                continue
            if amt >= 0:
                continue  # income, not a subscription
            factor = _MONTHLY_FACTOR.get(r.frequency)
            if factor is None:
                continue  # unknown cadence — skip rather than mis-project
            monthly = abs(amt) * factor
            yearly = monthly * 12.0
            total_monthly += monthly
            total_yearly += yearly
            items.append({
                "recurring_id": r.id,
                "description": r.description,
                "amount": amt,  # signed, as stored
                "frequency": r.frequency,
                "day_of_month": r.day_of_month,
                "anchor_date": r.anchor_date.isoformat() if r.anchor_date else None,
                "end_date": r.end_date.isoformat() if r.end_date else None,
                "account_id": acc.id,
                "account_name": acc.name,
                "category_id": r.category_id,
                "category_name": r.category.name if r.category else None,
                "category_color": r.category.color if r.category else None,
                "notes": r.notes,
                "monthly_cost": round(monthly, 2),
                "yearly_cost": round(yearly, 2),
            })

    # Biggest drains first. Stable tie-break by description for deterministic
    # rendering.
    items.sort(key=lambda x: (-x["monthly_cost"], x["description"].lower()))
    return {
        "count": len(items),
        "total_monthly": round(total_monthly, 2),
        "total_yearly": round(total_yearly, 2),
        "items": items,
    }


# ---------- Calendar ----------
# Cross-account aggregation for the Calendar page. Pulls the same rich row
# dataset `build_forecast` produces (so tag chips, category colors, and
# recurring/transfer metadata travel with every event), then emits one
# flat list scoped to the caller's window. The client decides how to slice
# it (month grid vs day detail) and applies whatever filters the user has
# toggled, which is cheaper than paginating here and avoids re-fetching
# when the user flips a filter checkbox.
#
# Response shape:
#   {
#     "start": "YYYY-MM-DD", "end": "YYYY-MM-DD",
#     "events": [ { ...event... }, ... ]
#   }
# Each event carries:
#   date, account_id, account_name, description, amount,
#   category_id, category_name, category_color,
#   tags: [{id,name,color}, ...],
#   recurring_id, transaction_id, transfer_id, is_actual_real, notes
# The `date` used for placement on the grid is the forecast date when
# present (so a delayed actual still appears in the month it was planned
# for); otherwise actual_date; otherwise the row is skipped.
@app.get("/api/calendar")
def calendar_events(start: date, end: date,
                    account_id: int | None = None,
                    user: User = Depends(current_user),
                    db: Session = Depends(get_db)):
    if end < start:
        raise HTTPException(400, "end must be on or after start")
    # Cap the window at a year so a stray query doesn't chew through every
    # account's forecast.
    if (end - start).days > 366:
        raise HTTPException(400, "window exceeds 366 days")

    visible = _user_visible_accounts(db, user)
    if account_id is not None:
        visible = [a for a in visible if a.id == account_id]
        if not visible:
            raise HTTPException(404, "Account not found")

    # Per-user category color lookup (forecast rows only carry name).
    cat_meta: dict[str, dict] = {}
    for c in db.query(Category).filter_by(owner_id=user.id).all():
        cat_meta[c.name] = {"id": c.id, "color": c.color}

    events: list[dict] = []
    # Running balance per day, only computed in single-account mode ("the
    # account being viewed") — there's no one meaningful balance to show
    # across multiple accounts. Same carry-forward walk as dashboard_charts/
    # net_worth: take the last row's actual_balance on each day, carrying it
    # forward across days with no events.
    daily_balances: dict[str, float] | None = {} if account_id is not None else None
    for acc in visible:
        data = build_forecast(db, acc, start, end)
        if daily_balances is not None:
            day_to_balance: dict[str, float] = {}
            for r in data["rows"]:
                d_key = r.get("actual_date") or r.get("forecast_date")
                if d_key:
                    day_to_balance[d_key] = r["actual_balance"]
            running = data["opening_balance"]
            day = start
            while day <= end:
                key = day.isoformat()
                if key in day_to_balance:
                    running = day_to_balance[key]
                daily_balances[key] = round(running, 2)
                day += timedelta(days=1)
        for r in data["rows"]:
            d = r.get("forecast_date") or r.get("actual_date")
            if not d:
                continue
            cat_name = r.get("category")
            meta = cat_meta.get(cat_name) if cat_name else None
            events.append({
                "date": d,
                "account_id": acc.id,
                "account_name": acc.name,
                "description": r.get("description") or "",
                "amount": r.get("actual_amount")
                          if r.get("actual_amount") is not None
                          else r.get("forecast_amount"),
                "forecast_amount": r.get("forecast_amount"),
                "actual_amount": r.get("actual_amount"),
                "category_id": meta["id"] if meta else None,
                "category_name": cat_name,
                "category_color": meta["color"] if meta else None,
                "tags": r.get("tags") or [],
                "recurring_id": r.get("recurring_id"),
                "transaction_id": r.get("transaction_id"),
                "transfer_id": r.get("transfer_id"),
                "is_actual_real": r.get("is_actual_real", False),
                "notes": r.get("notes"),
            })

    # Sort by date then by account name for a stable render — the UI does
    # its own per-day sort, but a deterministic server order helps caching.
    events.sort(key=lambda e: (e["date"], e["account_name"], e["description"].lower()))
    return {
        "start": start.isoformat(),
        "end": end.isoformat(),
        "events": events,
        "daily_balances": daily_balances,
    }


# ---------- Permissions ----------
class PermissionIn(BaseModel):
    account_id: int
    user_id: int
    level: str  # 'owner' | 'edit' | 'read' | 'deny'


def _owned_account(db: Session, user: User, account_id: int) -> Account:
    """The account, for changing who has access to it: owners only (decided
    2026-11-16, #189). 404 for one the caller can't see, 403 for one they
    can see but don't own."""
    acc = _account_with_perm(db, user, account_id, "read")
    if _user_level(db, user, account_id) != "owner":
        raise HTTPException(403, "Only an owner can change who has access to this account.")
    return acc


@app.get("/api/permissions")
def list_permissions(user: User = Depends(current_user), db: Session = Depends(get_db)):
    """The accounts the caller owns and who has access to each. `users`
    holds only the caller and the people on those accounts: there's no list
    of everyone to pick from, a share starts with an invitation by email
    (POST /api/invitations)."""
    owned = [a for a in _user_editable_accounts(db, user)
             if _user_level(db, user, a.id) == "owner"]
    if not owned:
        return {"self_id": user.id, "users": [], "accounts": [], "permissions": []}
    perms = (db.query(AccountPermission)
             .filter(AccountPermission.account_id.in_([a.id for a in owned])).all())
    people = (db.query(User).filter(User.id.in_({p.user_id for p in perms} | {user.id}))
              .order_by(User.email).all())
    return {
        "self_id": user.id,
        "users": [{"id": u.id, "email": u.email, "name": u.name} for u in people],
        "accounts": [{"id": a.id, "name": a.name, "caller_level": "owner"} for a in owned],
        "permissions": [
            {"account_id": p.account_id, "user_id": p.user_id, "level": p.level}
            for p in perms
        ],
    }


@app.post("/api/permissions")
def set_permission(payload: PermissionIn,
                   user: User = Depends(current_user), db: Session = Depends(get_db)):
    """Change the level of someone who already has access, or remove them
    ("deny"). Owners only, except that anyone may remove themselves. Giving
    access to someone new is an invitation (POST /api/invitations)."""
    if payload.level not in ("owner", "edit", "read", "deny"):
        raise HTTPException(400, "Invalid level")

    leaving = payload.user_id == user.id and payload.level == "deny"
    if leaving:
        _account_with_perm(db, user, payload.account_id, "read")
    else:
        _owned_account(db, user, payload.account_id)

    target = db.get(User, payload.user_id)
    if not target:
        raise HTTPException(404, "User not found")

    existing = db.query(AccountPermission).filter_by(
        account_id=payload.account_id, user_id=payload.user_id
    ).first()
    existing_level = existing.level if existing else "deny"
    if existing is None and payload.level != "deny":
        raise HTTPException(400, "They don't have access yet. Invite them by email: "
                                 "the account appears for them once they accept.")

    # --- Last-owner guardrail ---
    # Never let the change leave an account with zero owners. This matters if
    # an owner is demoting themselves or another owner: at least one owner
    # must remain on the account.
    if existing_level == "owner" and payload.level != "owner":
        owner_count = db.query(AccountPermission).filter_by(
            account_id=payload.account_id, level="owner"
        ).count()
        if owner_count <= 1:
            raise HTTPException(
                400,
                "Cannot remove the last owner. Promote someone else to owner first.",
            )

    # --- Last-edit-user guardrail (kept from before) ---
    # If the user is being demoted from edit+ to read/deny and there would be
    # no more edit+ users on the account, refuse. This is a UX safety net,
    # distinct from the owner guardrail above.
    if existing_level in ("owner", "edit") and payload.level in ("read", "deny"):
        editor_count = db.query(AccountPermission).filter_by(
            account_id=payload.account_id
        ).filter(AccountPermission.level.in_(["owner", "edit"])).count()
        if editor_count <= 1:
            raise HTTPException(
                400,
                "Cannot remove the last user with edit access. Grant edit to "
                "someone else first.",
            )

    # --- Apply ---
    if payload.level == "deny":
        if existing:
            db.delete(existing)
            db.commit()
        return {"ok": True, "level": "deny"}

    if existing:
        existing.level = payload.level
    else:
        db.add(AccountPermission(
            account_id=payload.account_id,
            user_id=payload.user_id,
            level=payload.level,
        ))
    db.commit()
    return {"ok": True, "level": payload.level}


# ---------- Sharing by invitation (security-fixes phase 6, #189) ----------
# Decided 2026-11-16 (docs/dev/decisions/security-fixes.md): no list of every
# user to pick from. An owner types the exact email; the account appears for
# that person only once they accept. The answer to an invitation is the same
# whether or not the address has a user here, so it can't be used to find
# out who does.
INVITATION_LEVELS = ("read", "edit", "owner")
INVITATIONS_PENDING_MAX = 50      # per inviter, across their accounts


class InvitationIn(BaseModel):
    account_id: int
    email: str = Field(max_length=EMAIL_MAX)
    level: str


def _invitation_out(inv: AccountInvitation, account: Account | None, inviter: User | None) -> dict:
    return {"id": inv.id, "account_id": inv.account_id,
            "account_name": account.name if account else None,
            "email": inv.email, "level": inv.level,
            "invited_by": inviter.email if inviter else None,
            "created_at": _iso(inv.created_at)}


@app.get("/api/invitations")
def list_invitations(user: User = Depends(current_user), db: Session = Depends(get_db)):
    """`received`: invitations to the caller's address, waiting for an
    answer. `sent`: ones the caller made that haven't been answered."""
    def rows(*where):
        found = (db.query(AccountInvitation).filter(*where)
                 .order_by(AccountInvitation.created_at.desc(), AccountInvitation.id.desc()).all())
        return [_invitation_out(i, db.get(Account, i.account_id), db.get(User, i.invited_by))
                for i in found]
    return {"received": rows(AccountInvitation.email == user.email.lower()),
            "sent": rows(AccountInvitation.invited_by == user.id)}


@app.post("/api/invitations")
def create_invitation(payload: InvitationIn, user: User = Depends(current_user),
                      db: Session = Depends(get_db)):
    """Invite an address to an account the caller owns. Inviting the same
    address again changes the level it's offered."""
    acc = _owned_account(db, user, payload.account_id)
    if payload.level not in INVITATION_LEVELS:
        raise HTTPException(400, "Level must be read, edit or owner")
    email = payload.email.strip().lower()
    if not _email_ok(email):
        raise HTTPException(400, "Invalid email")
    if email == user.email.lower():
        raise HTTPException(400, "That's your own address.")
    # Someone who already has access is no secret from an owner.
    invitee = db.query(User).filter_by(email=email).first()
    if invitee and db.query(AccountPermission).filter_by(
            account_id=acc.id, user_id=invitee.id).first():
        raise HTTPException(409, "They already have access. Change their level in the table.")
    inv = db.query(AccountInvitation).filter_by(account_id=acc.id, email=email).first()
    if inv is None:
        pending = db.query(AccountInvitation).filter_by(invited_by=user.id).count()
        if pending >= INVITATIONS_PENDING_MAX:
            raise HTTPException(429, "You have too many invitations waiting. Cancel some first.")
        inv = AccountInvitation(account_id=acc.id, email=email, invited_by=user.id)
        db.add(inv)
    inv.level = payload.level
    inv.invited_by = user.id
    db.commit()
    db.refresh(inv)
    return _invitation_out(inv, acc, user)


def _invitation_for(db: Session, user: User, invitation_id: int, as_invitee_only: bool) -> AccountInvitation:
    """An invitation the caller may act on: one sent to their address, or
    (to cancel) one on an account they own. 404 for any other."""
    inv = db.get(AccountInvitation, invitation_id)
    if inv is not None:
        if inv.email == user.email.lower():
            return inv
        if not as_invitee_only and _user_level(db, user, inv.account_id) == "owner":
            return inv
    raise HTTPException(404, "Invitation not found")


@app.post("/api/invitations/{invitation_id}/accept")
def accept_invitation(invitation_id: int, user: User = Depends(current_user),
                      db: Session = Depends(get_db)):
    """Take up an invitation sent to the caller's address: the account is
    theirs to see (or edit, or own) from now on."""
    inv = _invitation_for(db, user, invitation_id, as_invitee_only=True)
    existing = db.query(AccountPermission).filter_by(
        account_id=inv.account_id, user_id=user.id).first()
    if existing is None:
        db.add(AccountPermission(account_id=inv.account_id, user_id=user.id, level=inv.level))
    elif LEVEL_RANK[inv.level] > LEVEL_RANK[existing.level]:
        existing.level = inv.level
    account_id, level = inv.account_id, inv.level
    db.delete(inv)
    db.commit()
    return {"ok": True, "account_id": account_id, "level": _user_level(db, user, account_id)}


@app.delete("/api/invitations/{invitation_id}")
def remove_invitation(invitation_id: int, user: User = Depends(current_user),
                      db: Session = Depends(get_db)):
    """Decline an invitation sent to the caller, or cancel one on an
    account the caller owns."""
    inv = _invitation_for(db, user, invitation_id, as_invitee_only=False)
    db.delete(inv)
    db.commit()
    return {"ok": True}


# ---------- Reports ----------
# Reports are user-defined views over forecast + actual amounts. The
# frontend can drive a live editor (changing any param re-runs the query)
# and can save the params as a SavedReport so the same view comes back
# next session. Both paths flow through `_compute_report()` below.
ALLOWED_GROUP_BY = {"category", "tag", "account"}
ALLOWED_RANGE_MODES = {"month", "last_30d", "last_90d", "ytd", "year", "custom"}
ALLOWED_REPORT_KINDS = {"any", "income", "spending"}
ALLOWED_CHART_TYPES = {"table", "bar", "pie"}


def _resolve_report_range(params: dict, today: date | None = None) -> tuple[date, date, str]:
    """Translate a params dict's range_mode (+ optional year/month/start/end)
    into a concrete (start, end, label) triple.

    Defaults: range_mode='month', current month if year/month absent.
    Falls back to "current month" on any unparseable input rather than
    erroring — easier to debug a wrong-but-rendered chart than a stack
    trace from a saved report someone wrote weeks ago. `today` is the
    viewer's date when known (see _viewer_today).
    """
    today = today or date.today()
    mode = params.get("range_mode") or "month"
    if mode == "month":
        y = int(params.get("year") or today.year)
        m = int(params.get("month") or today.month)
        start = date(y, m, 1)
        end = (date(y, 12, 31) if m == 12
               else date(y, m + 1, 1) - timedelta(days=1))
        label = start.strftime("%B %Y")
    elif mode == "last_30d":
        end = today
        start = today - timedelta(days=29)
        label = "Last 30 days"
    elif mode == "last_90d":
        end = today
        start = today - timedelta(days=89)
        label = "Last 90 days"
    elif mode == "ytd":
        y = int(params.get("year") or today.year)
        start = date(y, 1, 1)
        end = date(y, 12, 31) if y < today.year else today
        label = f"Year to date ({y})"
    elif mode == "year":
        y = int(params.get("year") or today.year)
        start, end = date(y, 1, 1), date(y, 12, 31)
        label = f"Full year ({y})"
    elif mode == "custom":
        try:
            start = date.fromisoformat(params["start"])
            end = date.fromisoformat(params["end"])
            if not 0 <= (end - start).days <= FORECAST_MAX_DAYS:
                raise ValueError("window out of range")   # falls back below (#185)
            label = f"{start.isoformat()} → {end.isoformat()}"
        except Exception:
            start = date(today.year, today.month, 1)
            end = (date(today.year, 12, 31) if today.month == 12
                   else date(today.year, today.month + 1, 1) - timedelta(days=1))
            label = "Current month (range fallback)"
    else:
        start = date(today.year, today.month, 1)
        end = (date(today.year, 12, 31) if today.month == 12
               else date(today.year, today.month + 1, 1) - timedelta(days=1))
        label = "Current month"
    return start, end, label


def _compute_report(db: Session, user: User, params: dict, today: date | None = None) -> dict:
    """Run a report.

    `params` is the JSON-serializable dict that we both store on
    SavedReport and accept inline from the live editor. Recognized keys:
      group_by       — 'category' | 'tag' | 'account'  (default 'category')
      range_mode     — see _resolve_report_range
      year/month     — for 'month' / 'ytd' / 'year' modes
      start/end      — ISO dates for 'custom' mode
      account_ids    — restrict to these accounts (default: all visible)
      category_ids   — keep only rows in these categories (default: all)
      tag_ids        — keep only rows that carry at least one of these tags
      kind           — 'any' | 'income' | 'spending' (sign filter)
      include_transfers — bool, default false (transfers excluded)
      chart_type     — passed through unchanged for the frontend's benefit

    The return shape is intentionally generic so the frontend can render
    one rollup pane regardless of the group_by axis: a `groups` array of
    `{key, name, color, forecast_total, actual_total, ...}` rows plus a
    summary `totals` block.
    """
    group_by = params.get("group_by") or "category"
    if group_by not in ALLOWED_GROUP_BY:
        group_by = "category"
    kind = params.get("kind") or "any"
    if kind not in ALLOWED_REPORT_KINDS:
        kind = "any"
    include_transfers = bool(params.get("include_transfers"))
    start, end, range_label = _resolve_report_range(params, today)

    # Account scoping. If the saved report was originally pinned to a set
    # of accounts that the user has since lost access to (e.g. permission
    # revoked), we silently shrink to the visible intersection rather
    # than erroring — the user may still want partial data.
    visible = _user_visible_accounts(db, user)
    visible_ids = {a.id for a in visible}
    requested_ids = params.get("account_ids") or []
    if requested_ids:
        visible = [a for a in visible if a.id in set(requested_ids) & visible_ids]

    cat_id_filter = set(params.get("category_ids") or [])
    tag_id_filter = set(params.get("tag_ids") or [])

    # Pre-load category color/name for emit-time enrichment.
    cat_meta_by_id: dict[int, dict] = {}
    cat_id_by_name: dict[str, int | None] = {None: None}
    for c in db.query(Category).filter_by(owner_id=user.id).all():
        cat_meta_by_id[c.id] = {"name": c.name, "color": c.color}
        cat_id_by_name[c.name] = c.id

    # Buckets. Key shape depends on group_by:
    #   category → category_id (or None for "(uncategorized)")
    #   tag      → tag_id
    #   account  → account_id
    # Every bucket carries forecast/actual totals + counts so the
    # frontend can render the same table layout for any axis.
    buckets: dict = {}

    def _bucket(key, name, color=None):
        if key not in buckets:
            buckets[key] = {
                "key": key, "name": name, "color": color,
                "forecast_total": 0.0, "actual_total": 0.0,
                "forecast_count": 0, "actual_count": 0,
            }
        return buckets[key]

    UNCAT_KEY = "__uncategorized__"

    for acc in visible:
        data = build_forecast(db, acc, start, end)
        for r in data["rows"]:
            if not include_transfers and r.get("transfer_id") is not None:
                continue
            f = r.get("forecast_amount")
            a = r.get("actual_amount")
            # Sign filter — applied to actual when present, otherwise forecast.
            sign_ref = a if a is not None else f
            if sign_ref is None:
                continue
            if kind == "income"   and sign_ref <= 0: continue
            if kind == "spending" and sign_ref >= 0: continue
            # Category filter
            cat_name = r.get("category")
            cat_id = cat_id_by_name.get(cat_name)
            if cat_id_filter and cat_id not in cat_id_filter:
                continue
            # Tag filter (any-of semantics: row qualifies if it carries
            # AT LEAST ONE selected tag; matches the Calendar's filter logic)
            row_tags = r.get("tags") or []
            row_tag_ids = {t["id"] for t in row_tags}
            if tag_id_filter and not (row_tag_ids & tag_id_filter):
                continue

            # Now bucket according to group_by.
            if group_by == "category":
                if cat_id is None:
                    bk = _bucket(UNCAT_KEY, "(uncategorized)", None)
                else:
                    meta = cat_meta_by_id.get(cat_id, {"name": cat_name, "color": None})
                    bk = _bucket(cat_id, meta["name"], meta["color"])
                if f is not None: bk["forecast_total"] += f; bk["forecast_count"] += 1
                if a is not None: bk["actual_total"]   += a; bk["actual_count"]   += 1
            elif group_by == "account":
                bk = _bucket(acc.id, acc.name, None)
                if f is not None: bk["forecast_total"] += f; bk["forecast_count"] += 1
                if a is not None: bk["actual_total"]   += a; bk["actual_count"]   += 1
            elif group_by == "tag":
                # A multi-tagged row contributes to every tag bucket it
                # belongs to (overlay semantics — same as the dedicated
                # tag breakdown that shipped in 1.11.0).
                if not row_tags:
                    continue  # untagged rows are simply absent from a tag axis
                for tmeta in row_tags:
                    bk = _bucket(tmeta["id"], tmeta["name"], tmeta.get("color"))
                    if f is not None: bk["forecast_total"] += f; bk["forecast_count"] += 1
                    if a is not None: bk["actual_total"]   += a; bk["actual_count"]   += 1

    # Sort: most-active first by absolute actual total, then by name.
    groups_out = list(buckets.values())
    for g in groups_out:
        g["forecast_total"] = round(g["forecast_total"], 2)
        g["actual_total"]   = round(g["actual_total"],   2)
    groups_out.sort(key=lambda g: (-abs(g["actual_total"]), g["name"].lower()))

    # Top-line totals (across the filtered, post-sign set).
    f_income = sum(g["forecast_total"] for g in groups_out if g["forecast_total"] > 0)
    a_income = sum(g["actual_total"]   for g in groups_out if g["actual_total"]   > 0)
    f_spend  = sum(g["forecast_total"] for g in groups_out if g["forecast_total"] < 0)
    a_spend  = sum(g["actual_total"]   for g in groups_out if g["actual_total"]   < 0)
    # On the tag axis groups can double-count across multi-tagged rows,
    # so the totals here are "sum of buckets" rather than a true
    # transaction-level total. The frontend labels this clearly.
    return {
        "params": {
            **params,
            "group_by": group_by,
            "range_mode": params.get("range_mode") or "month",
            "kind": kind,
            "include_transfers": include_transfers,
            "chart_type": params.get("chart_type") or "table",
        },
        "start": start.isoformat(),
        "end":   end.isoformat(),
        "range_label": range_label,
        "group_by":  group_by,
        "accounts":  [{"id": a.id, "name": a.name} for a in visible],
        "groups":    groups_out,
        "totals": {
            "forecast_income":   round(f_income, 2),
            "actual_income":     round(a_income, 2),
            "forecast_spending": round(f_spend,  2),
            "actual_spending":   round(a_spend,  2),
            "forecast_net":      round(f_income + f_spend, 2),
            "actual_net":        round(a_income + a_spend, 2),
        },
    }


@app.get("/api/report")
def report(start: date | None = None, end: date | None = None,
           account_id: int | None = None,
           user: User = Depends(current_user), db: Session = Depends(get_db)):
    """Legacy reports endpoint, preserved for backward compatibility.

    Always returns both `categories` and `tags` blocks (not just `groups`)
    because pre-1.12 frontend code expects those keys. The new flexible
    surface lives at /api/report/run.
    """
    # Default to current calendar month
    if start is None or end is None:
        today = date.today()
        start = date(today.year, today.month, 1)
        if today.month == 12:
            end = date(today.year, 12, 31)
        else:
            end = date(today.year, today.month + 1, 1) - timedelta(days=1)

    _check_window(start, end)
    # Pick accounts the user can read
    visible = _user_visible_accounts(db, user)
    if account_id is not None:
        visible = [a for a in visible if a.id == account_id]
        if not visible:
            raise HTTPException(404, "Account not found")

    # Walk every account's forecast in the window. We use build_forecast so
    # that recurring template projections are included alongside materialized
    # transactions, matching what the user sees in the forecast view.
    # Each row contributes to the category bucket twice: once for forecast,
    # once for actual (using the displayed/defaulted actual values).
    cat_buckets: dict[str, dict] = {}
    UNCAT = "(uncategorized)"
    # Tag rollup. Keyed by tag_id so we can collide correctly across
    # accounts, then enriched with name + color at emit time. Only rows
    # that actually carry tags contribute — untagged rows are simply
    # absent from the tag breakdown (they still count toward category
    # totals and overall totals, just not "by tag").
    tag_buckets: dict[int, dict] = {}

    def _bucket(name):
        if name not in cat_buckets:
            cat_buckets[name] = {
                "name": name,
                "forecast_total": 0.0,
                "actual_total": 0.0,
                "forecast_count": 0,
                "actual_count": 0,
            }
        return cat_buckets[name]

    def _tag_bucket(tag_id: int):
        if tag_id not in tag_buckets:
            tag_buckets[tag_id] = {
                "id": tag_id,
                "forecast_total": 0.0,
                "actual_total": 0.0,
                "forecast_count": 0,
                "actual_count": 0,
            }
        return tag_buckets[tag_id]

    for acc in visible:
        data = build_forecast(db, acc, start, end)
        for r in data["rows"]:
            # Same exclusion rule as the dashboard charts: transfer legs are
            # internal money movement, not real category spend or income.
            if r.get("transfer_id") is not None:
                continue
            cat = r.get("category") or UNCAT
            b = _bucket(cat)
            f = r.get("forecast_amount")
            a = r.get("actual_amount")
            if f is not None:
                b["forecast_total"] += f
                b["forecast_count"] += 1
            if a is not None:
                b["actual_total"] += a
                b["actual_count"] += 1
            # A transaction with N tags contributes the full amount to
            # each tag bucket. This is the same semantics as "sum by
            # tag" in every other finance app — tags are an overlay, so
            # double-counting across tags is expected and correct.
            for tmeta in (r.get("tags") or []):
                tb = _tag_bucket(tmeta["id"])
                if f is not None:
                    tb["forecast_total"] += f
                    tb["forecast_count"] += 1
                if a is not None:
                    tb["actual_total"] += a
                    tb["actual_count"] += 1

    # Look up the actual category records for color info. Categories are per-
    # user, not per-account, so a single query covers everything.
    cat_colors: dict[str, str | None] = {}
    for c in db.query(Category).filter_by(owner_id=user.id).all():
        cat_colors[c.name] = c.color

    categories_out = []
    for name, b in sorted(cat_buckets.items()):
        # Skip rows that are pure zero (no activity at all)
        if b["forecast_count"] == 0 and b["actual_count"] == 0:
            continue
        categories_out.append({
            "name": name,
            "color": cat_colors.get(name),
            "forecast_total": round(b["forecast_total"], 2),
            "actual_total": round(b["actual_total"], 2),
            "forecast_count": b["forecast_count"],
            "actual_count": b["actual_count"],
        })

    # Top-line totals (income = positive sums, spending = negative sums)
    f_income = sum(c["forecast_total"] for c in categories_out if c["forecast_total"] > 0)
    a_income = sum(c["actual_total"]   for c in categories_out if c["actual_total"]   > 0)
    f_spend  = sum(c["forecast_total"] for c in categories_out if c["forecast_total"] < 0)
    a_spend  = sum(c["actual_total"]   for c in categories_out if c["actual_total"]   < 0)

    # Tag rollup output — only emit rows that had any activity, and
    # enrich with name/color from the tag table (single query for the
    # whole user since tags are user-scoped).
    tags_out = []
    if tag_buckets:
        tag_ids = list(tag_buckets.keys())
        tag_meta = {
            t.id: {"name": t.name, "color": t.color}
            for t in db.query(Tag).filter(
                Tag.owner_id == user.id, Tag.id.in_(tag_ids)
            ).all()
        }
        for tid, b in tag_buckets.items():
            if b["forecast_count"] == 0 and b["actual_count"] == 0:
                continue
            meta = tag_meta.get(tid)
            if meta is None:
                # Tag was deleted between aggregation and emit — skip.
                continue
            tags_out.append({
                "id": tid,
                "name": meta["name"],
                "color": meta["color"],
                "forecast_total": round(b["forecast_total"], 2),
                "actual_total":   round(b["actual_total"],   2),
                "forecast_count": b["forecast_count"],
                "actual_count":   b["actual_count"],
            })
        # Sort by absolute actual total desc (biggest movers first), with
        # name as tiebreaker so the order is stable across reloads.
        tags_out.sort(key=lambda t: (-abs(t["actual_total"]), t["name"].lower()))

    return {
        "start": start.isoformat(),
        "end": end.isoformat(),
        "accounts": [{"id": a.id, "name": a.name} for a in visible],
        "categories": categories_out,
        "tags": tags_out,
        "totals": {
            "forecast_income":   round(f_income, 2),
            "actual_income":     round(a_income, 2),
            "forecast_spending": round(f_spend,  2),
            "actual_spending":   round(a_spend,  2),
            "forecast_net":      round(f_income + f_spend, 2),
            "actual_net":        round(a_income + a_spend, 2),
        },
    }


# ---------- New flexible reports surface ----------
class ReportParamsIn(BaseModel):
    """Inline report parameters. Accepted by /api/report/run for the
    live editor on the Reports page (so the user can preview without
    saving) and by SavedReport create/update.
    """
    group_by: str = "category"
    range_mode: str = "month"
    year: int | None = None
    month: int | None = None
    start: str | None = None  # ISO date (custom mode only)
    end: str | None = None
    account_ids: list[int] = Field(default_factory=list)
    category_ids: list[int] = Field(default_factory=list)
    tag_ids: list[int] = Field(default_factory=list)
    kind: str = "any"
    include_transfers: bool = False
    chart_type: str = "table"


def _validate_report_params(params: dict) -> None:
    """Lightweight shape check. _compute_report defends against unknown
    enum values by falling back, but we surface 400s on obvious typos
    (group_by='catagory') so the user gets a clear error in the editor."""
    gb = params.get("group_by") or "category"
    if gb not in ALLOWED_GROUP_BY:
        raise HTTPException(400, f"group_by must be one of {sorted(ALLOWED_GROUP_BY)}")
    rm = params.get("range_mode") or "month"
    if rm not in ALLOWED_RANGE_MODES:
        raise HTTPException(400, f"range_mode must be one of {sorted(ALLOWED_RANGE_MODES)}")
    k = params.get("kind") or "any"
    if k not in ALLOWED_REPORT_KINDS:
        raise HTTPException(400, f"kind must be one of {sorted(ALLOWED_REPORT_KINDS)}")
    ct = params.get("chart_type") or "table"
    if ct not in ALLOWED_CHART_TYPES:
        raise HTTPException(400, f"chart_type must be one of {sorted(ALLOWED_CHART_TYPES)}")


@app.post("/api/report/run")
def run_report_inline(payload: ReportParamsIn,
                      user: User = Depends(current_reader),
                      db: Session = Depends(get_db)):
    """Run a report from inline params. Used by the live editor so users
    can preview without saving."""
    params = payload.model_dump()
    _validate_report_params(params)
    return _compute_report(db, user, params)


# ---------- Saved reports ----------
def _serialize_saved_report(r: SavedReport) -> dict:
    try:
        params = json.loads(r.params or "{}")
    except Exception:
        params = {}
    return {
        "id": r.id,
        "name": r.name,
        "params": params,
        "pinned": bool(r.pinned),
        "sort_order": r.sort_order,
    }


def _own_saved_report(db: Session, user: User, report_id: int) -> SavedReport:
    r = db.get(SavedReport, report_id)
    if not r or r.owner_id != user.id:
        raise HTTPException(404, "Report not found")
    return r


class SavedReportIn(BaseModel):
    name: str = Field(..., min_length=1, max_length=120)
    params: dict
    pinned: bool = False
    sort_order: int = 0


@app.get("/api/saved-reports")
def list_saved_reports(user: User = Depends(current_user),
                       db: Session = Depends(get_db)):
    rows = (db.query(SavedReport)
              .filter_by(owner_id=user.id)
              .order_by(SavedReport.sort_order.asc(), SavedReport.id.asc())
              .all())
    return [_serialize_saved_report(r) for r in rows]


@app.post("/api/saved-reports")
def create_saved_report(payload: SavedReportIn,
                        user: User = Depends(current_user),
                        db: Session = Depends(get_db)):
    _validate_report_params(payload.params)
    r = SavedReport(
        owner_id=user.id,
        name=payload.name.strip(),
        params=json.dumps(payload.params),
        pinned=payload.pinned,
        sort_order=payload.sort_order,
    )
    db.add(r)
    db.commit()
    db.refresh(r)
    return _serialize_saved_report(r)


@app.patch("/api/saved-reports/{report_id}")
def update_saved_report(report_id: int, payload: SavedReportIn,
                        user: User = Depends(current_user),
                        db: Session = Depends(get_db)):
    r = _own_saved_report(db, user, report_id)
    _validate_report_params(payload.params)
    r.name = payload.name.strip()
    r.params = json.dumps(payload.params)
    r.pinned = payload.pinned
    r.sort_order = payload.sort_order
    db.commit()
    return _serialize_saved_report(r)


@app.delete("/api/saved-reports/{report_id}")
def delete_saved_report(report_id: int,
                        user: User = Depends(current_user),
                        db: Session = Depends(get_db)):
    r = _own_saved_report(db, user, report_id)
    db.delete(r)
    db.commit()
    return {"ok": True}


@app.post("/api/saved-reports/{report_id}/run")
def run_saved_report(report_id: int, today: date | None = None,
                     user: User = Depends(current_reader),
                     db: Session = Depends(get_db)):
    r = _own_saved_report(db, user, report_id)
    try:
        params = json.loads(r.params or "{}")
    except Exception:
        params = {}
    return _compute_report(db, user, params, _viewer_today(today))


# ---------- Report templates (built-in starting points) ----------
# These are pure presets — the user clones one to instantiate a saved
# report, then can edit any parameter freely. They're a constant list
# rather than a DB table because they ship with the code: per-user
# overrides aren't a feature, and shipping them as code means they get
# reviewed alongside the rest of the release.
_REPORT_TEMPLATES = [
    {
        "id": "monthly-spend-by-category",
        "name": "Monthly spending by category",
        "description": "What you spent this month, grouped by category.",
        "params": {
            "group_by": "category", "range_mode": "month",
            "kind": "spending", "include_transfers": False,
            "chart_type": "pie",
        },
    },
    {
        "id": "monthly-income-by-category",
        "name": "Monthly income by category",
        "description": "What came in this month, grouped by category.",
        "params": {
            "group_by": "category", "range_mode": "month",
            "kind": "income", "include_transfers": False,
            "chart_type": "table",
        },
    },
    {
        "id": "ytd-by-category",
        "name": "Year-to-date by category",
        "description": "Every dollar in or out this year, grouped by category.",
        "params": {
            "group_by": "category", "range_mode": "ytd",
            "kind": "any", "include_transfers": False,
            "chart_type": "bar",
        },
    },
    {
        "id": "last-30d-by-tag",
        "name": "Last 30 days by tag",
        "description": "Cross-cutting view of tagged spending and income across the last 30 days.",
        "params": {
            "group_by": "tag", "range_mode": "last_30d",
            "kind": "any", "include_transfers": False,
            "chart_type": "bar",
        },
    },
    {
        "id": "last-90d-spend-by-tag",
        "name": "Last 90 days spending by tag",
        "description": "Where tagged money went over the last quarter.",
        "params": {
            "group_by": "tag", "range_mode": "last_90d",
            "kind": "spending", "include_transfers": False,
            "chart_type": "pie",
        },
    },
    {
        "id": "monthly-spend-by-account",
        "name": "Monthly spending by account",
        "description": "Which account is doing the most damage this month.",
        "params": {
            "group_by": "account", "range_mode": "month",
            "kind": "spending", "include_transfers": False,
            "chart_type": "bar",
        },
    },
    {
        "id": "year-net-by-category",
        "name": "Full year net by category",
        "description": "Net (income + spending) per category over a full year — set the year on the report page.",
        "params": {
            "group_by": "category", "range_mode": "year",
            "kind": "any", "include_transfers": False,
            "chart_type": "table",
        },
    },
]


@app.get("/api/report-templates")
def list_report_templates(user: User = Depends(current_user)):
    """Built-in report starting points. The frontend uses these to seed
    the New Report dialog; once instantiated, the user owns the params
    blob and can edit any field freely.
    """
    return _REPORT_TEMPLATES


# ---------- Admin ----------
class AdminUserPatchIn(BaseModel):
    disabled: bool | None = None
    new_password: str | None = Field(default=None, min_length=8, max_length=128)
    # Only false means anything: an admin can switch a user's two-factor
    # sign-in off (they lost their phone), never on (#165).
    two_factor: bool | None = None


class AdminBackupConfigIn(BaseModel):
    enabled: bool
    frequency: str = "daily"  # 'daily' | 'weekly' | 'monthly'
    hour: int = 3
    retention_days: int = 30


class AppTitleIn(BaseModel):
    app_title: str = Field(..., min_length=1, max_length=APP_TITLE_MAX_LEN)


@app.get("/api/admin/app-title")
def admin_get_app_title(user: User = Depends(current_admin), db: Session = Depends(get_db)):
    return {"app_title": get_app_title(db), "default": APP_TITLE_DEFAULT}


@app.post("/api/admin/app-title")
def admin_set_app_title(payload: AppTitleIn, request: Request,
                        user: User = Depends(current_admin),
                        db: Session = Depends(get_db)):
    """Set the instance display name shown in the browser tab and UI header."""
    title = payload.app_title.strip()
    if not title:
        raise HTTPException(400, "Title cannot be empty")
    row = db.get(AdminSetting, APP_TITLE_KEY)
    if row:
        row.value = title
    else:
        db.add(AdminSetting(key=APP_TITLE_KEY, value=title))
    db.commit()
    record_event(db, "app_title_changed", request, user=user, detail=title)
    return {"app_title": title}


@app.delete("/api/admin/app-title")
def admin_reset_app_title(request: Request, user: User = Depends(current_admin),
                          db: Session = Depends(get_db)):
    """Reset to the default ('WalletWeather')."""
    row = db.get(AdminSetting, APP_TITLE_KEY)
    if row:
        db.delete(row)
        db.commit()
        record_event(db, "app_title_changed", request, user=user,
                     detail=f"reset to {APP_TITLE_DEFAULT}")
    return {"app_title": APP_TITLE_DEFAULT}


class TwoFactorRequirementIn(BaseModel):
    required: bool


def _users_to_set_up(db: Session) -> int:
    """Users the requirement covers who haven't set it up: with a password,
    not disabled, not the demo user."""
    rows = (db.query(User.email)
            .filter(User.password_hash.isnot(None), User.totp_enabled_at.is_(None),
                    User.disabled.is_(False))
            .all())
    return sum(1 for (email,) in rows if not is_demo_email(email))


@app.get("/api/admin/two-factor")
def admin_get_two_factor(user: User = Depends(current_admin), db: Session = Depends(get_db)):
    """Whether two-factor sign-in is required, and how many users it still
    waits on."""
    return {"required": two_factor_required(db), "users_to_set_up": _users_to_set_up(db)}


@app.put("/api/admin/two-factor")
def admin_set_two_factor(payload: TwoFactorRequirementIn, request: Request,
                         user: User = Depends(current_session_admin),
                         db: Session = Depends(get_db)):
    """Require two-factor sign-in of every user with a password, or stop.
    A browser session only, and the admin sets up their own first (#168)."""
    if payload.required and user.password_hash is not None and user.totp_enabled_at is None:
        raise HTTPException(409, "Set up your own two-factor sign-in first "
                                 "(Settings → Your account), then require it of everyone.")
    was = two_factor_required(db)
    row = db.get(AdminSetting, REQUIRE_TWO_FACTOR_KEY)
    if payload.required and not row:
        db.add(AdminSetting(key=REQUIRE_TWO_FACTOR_KEY, value="true"))
    elif payload.required:
        row.value = "true"
    elif row:
        db.delete(row)
    db.commit()
    if was != payload.required:
        record_event(db, "two_factor_requirement_changed", request, user=user,
                     detail="on" if payload.required else "off")
    return {"required": payload.required, "users_to_set_up": _users_to_set_up(db)}


class BankSyncSettingIn(BaseModel):
    enabled: bool


@app.get("/api/admin/bank-sync")
def admin_get_bank_sync(user: User = Depends(current_admin), db: Session = Depends(get_db)):
    """Whether users may connect a bank (#194), and how many have."""
    return {"enabled": bank_sync_enabled(db),
            "connected_users": db.query(BankConnection).count()}


@app.put("/api/admin/bank-sync")
def admin_set_bank_sync(payload: BankSyncSettingIn, request: Request,
                        user: User = Depends(current_session_admin),
                        db: Session = Depends(get_db)):
    """Switch bank sync on or off for the instance. Off stops connecting and
    syncing; connections already made stay until their users disconnect."""
    was = bank_sync_enabled(db)
    row = db.get(AdminSetting, BANK_SYNC_KEY)
    if payload.enabled and not row:
        db.add(AdminSetting(key=BANK_SYNC_KEY, value="true"))
    elif payload.enabled:
        row.value = "true"
    elif row:
        db.delete(row)
    db.commit()
    if was != payload.enabled:
        record_event(db, "bank_sync_setting_changed", request, user=user,
                     detail="on" if payload.enabled else "off")
    return admin_get_bank_sync(user, db)


class MailAlertsSettingIn(BaseModel):
    enabled: bool


@app.get("/api/admin/mail-alerts")
def admin_get_mail_alerts(user: User = Depends(current_admin), db: Session = Depends(get_db)):
    """Whether users may connect a mailbox for email alerts (#206), how many
    have, and whether the server has a Microsoft app (MS_CLIENT_ID)."""
    return {"enabled": mail_alerts_enabled(db),
            "connected_users": db.query(MailConnection).count(),
            "microsoft_configured": mailbox.available()}


@app.put("/api/admin/mail-alerts")
def admin_set_mail_alerts(payload: MailAlertsSettingIn, request: Request,
                          user: User = Depends(current_session_admin),
                          db: Session = Depends(get_db)):
    """Switch email alerts on or off for the instance. Off stops connecting
    and checking; mailboxes already connected stay until their users
    disconnect."""
    was = mail_alerts_enabled(db)
    row = db.get(AdminSetting, MAIL_ALERTS_KEY)
    if payload.enabled and not row:
        db.add(AdminSetting(key=MAIL_ALERTS_KEY, value="true"))
    elif payload.enabled:
        row.value = "true"
    elif row:
        db.delete(row)
    db.commit()
    if was != payload.enabled:
        record_event(db, "mail_alerts_setting_changed", request, user=user,
                     detail="on" if payload.enabled else "off")
    return admin_get_mail_alerts(user, db)


@app.get("/api/admin/users")
def admin_list_users(user: User = Depends(current_admin), db: Session = Depends(get_db)):
    users = db.query(User).order_by(User.id).all()
    banked = {uid for (uid,) in db.query(BankConnection.user_id)}
    mailed = {uid for (uid,) in db.query(MailConnection.user_id)}
    out = []
    for u in users:
        acct_count = db.query(AccountPermission).filter_by(user_id=u.id).filter(
            AccountPermission.level.in_(["owner", "edit", "read"])
        ).count()
        owned_count = db.query(AccountPermission).filter_by(
            user_id=u.id, level="owner"
        ).count()
        out.append({
            "id": u.id,
            "email": u.email,
            "name": u.name,
            "disabled": u.disabled,
            "is_admin": is_admin(u),
            "created_at": u.created_at.isoformat() if u.created_at else None,
            "account_count": acct_count,
            "owned_count": owned_count,
            "has_password": u.password_hash is not None,
            "has_google": u.google_sub is not None,
            "two_factor_enabled": u.totp_enabled_at is not None,
            "bank_connected": u.id in banked,
            "mail_connected": u.id in mailed,
        })
    return out


class AdminUserIn(BaseModel):
    email: str = Field(max_length=320)
    password: str = Field(min_length=8, max_length=128)
    name: str | None = Field(default=None, max_length=255)


@app.post("/api/admin/users")
def admin_create_user(payload: AdminUserIn, request: Request,
                      user: User = Depends(current_admin), db: Session = Depends(get_db)):
    """Add a user with a password the admin passes on to them (#183). This
    is how an administrator's address gets its user once the instance has
    one: nobody can register it for themselves. Works with registration
    switched off, and needs no registration code."""
    email = payload.email.strip().lower()
    if not _email_ok(email):
        raise HTTPException(400, "Invalid email")
    if is_demo_email(email):
        raise HTTPException(400, "That address belongs to the demo.")
    if ALLOWED_EMAILS and email not in ALLOWED_EMAILS:
        raise HTTPException(400, "That address isn't on ALLOWED_EMAILS. Add it there first.")
    if db.query(User).filter_by(email=email).first():
        raise HTTPException(409, "An account with that email already exists")
    created = _create_password_user(db, email, payload.name, payload.password)
    record_event(db, "user_created", request, user=user, detail=audit_target(user, created.id))
    return {"id": created.id, "email": created.email, "name": created.name,
            "is_admin": is_admin(created)}


@app.patch("/api/admin/users/{uid}")
def admin_update_user(uid: int, payload: AdminUserPatchIn, request: Request,
                      user: User = Depends(current_admin), db: Session = Depends(get_db)):
    target = db.get(User, uid)
    if not target:
        raise HTTPException(404, "User not found")
    # Protect against disabling yourself
    if payload.disabled is not None and target.id == user.id and payload.disabled:
        raise HTTPException(400, "Cannot disable your own account")
    if payload.two_factor:
        raise HTTPException(400, "Only the user can switch two-factor sign-in on.")
    events = []
    if payload.disabled is not None and bool(target.disabled) != payload.disabled:
        target.disabled = payload.disabled
        events.append("user_disabled" if payload.disabled else "user_enabled")
    if payload.new_password is not None:
        target.password_hash = hash_password(payload.new_password)
        _forget_browsers(db, target)  # a new password forgets them (#167)
        # A reset is for an account that may be in the wrong hands: every
        # browser of theirs is signed out and their API tokens stop (#186).
        _end_other_sessions(request if target.id == user.id else None, target)
        (db.query(ApiToken).filter(ApiToken.owner_id == target.id, ApiToken.revoked_at.is_(None))
         .update({ApiToken.revoked_at: datetime.utcnow()}, synchronize_session=False))
        events.append("password_reset")
    if payload.two_factor is False and target.totp_enabled_at is not None:
        _clear_two_factor(db, target)
        events.append("two_factor_disabled")
    db.commit()
    for event in events:
        record_event(db, event, request, user=user, detail=audit_target(user, target.id))
    return {"ok": True}


@app.delete("/api/admin/users/{uid}")
def admin_delete_user(uid: int, request: Request,
                      user: User = Depends(current_admin), db: Session = Depends(get_db)):
    target = db.get(User, uid)
    if not target:
        raise HTTPException(404, "User not found")
    if target.id == user.id:
        raise HTTPException(400, "Cannot delete your own account")
    # Same rule as deleting yourself (#57): an account with another owner
    # stays, and the deletion is refused while the user is the only owner of
    # an account other people can see.
    plan = _deletion_plan(db, target)
    if plan["blocking"]:
        raise HTTPException(409, {
            "message": f"{target.email} is the only owner of accounts other "
                       "people can see. Make someone else an owner of each, "
                       "or remove the other people's access, then delete "
                       "the user.",
            **_deletion_plan_json(plan),
        })
    target_id = target.id
    _delete_user(db, target, plan)
    record_event(db, "user_deleted", request, user=user, detail=audit_target(user, target_id))
    return {"ok": True}


@app.get("/api/admin/permissions")
def admin_list_permissions(user: User = Depends(current_admin), db: Session = Depends(get_db)):
    """Return ALL permissions across ALL accounts (admin view)."""
    all_accounts = db.query(Account).order_by(Account.id).all()
    all_users = db.query(User).order_by(User.email).all()
    perms = db.query(AccountPermission).all()
    return {
        "self_id": user.id,
        "users": [{"id": u.id, "email": u.email, "name": u.name} for u in all_users],
        "accounts": [{"id": a.id, "name": a.name, "caller_level": "admin"}
                     for a in all_accounts],
        "permissions": [
            {"account_id": p.account_id, "user_id": p.user_id, "level": p.level}
            for p in perms
        ],
    }


@app.post("/api/admin/permissions")
def admin_set_permission(payload: PermissionIn, request: Request,
                         user: User = Depends(current_admin), db: Session = Depends(get_db)):
    """Set any permission on any account (admin override).
    Admins bypass the owner-only restrictions and can assign any level.
    The only guardrail kept: cannot leave an account with zero owners."""
    if payload.level not in ("owner", "edit", "read", "deny"):
        raise HTTPException(400, "Invalid level")
    acc = db.get(Account, payload.account_id)
    if not acc:
        raise HTTPException(404, "Account not found")
    target = db.get(User, payload.user_id)
    if not target:
        raise HTTPException(404, "User not found")

    existing = db.query(AccountPermission).filter_by(
        account_id=payload.account_id, user_id=payload.user_id
    ).first()
    existing_level = existing.level if existing else "deny"

    # Last-owner guardrail
    if existing_level == "owner" and payload.level != "owner":
        owner_count = db.query(AccountPermission).filter_by(
            account_id=payload.account_id, level="owner"
        ).count()
        if owner_count <= 1:
            raise HTTPException(400, "Cannot remove the last owner. Promote someone else first.")

    # By account number, never its name (#133).
    detail = (f"{audit_target(user, target.id)}, account #{acc.id}: "
              f"{existing_level} → {payload.level}")

    if payload.level == "deny":
        if existing:
            db.delete(existing)
            db.commit()
            record_event(db, "permission_changed", request, user=user, detail=detail)
        return {"ok": True, "level": "deny"}

    if existing:
        existing.level = payload.level
    else:
        db.add(AccountPermission(
            account_id=payload.account_id,
            user_id=payload.user_id,
            level=payload.level,
        ))
    db.commit()
    if existing_level != payload.level:
        record_event(db, "permission_changed", request, user=user, detail=detail)
    return {"ok": True, "level": payload.level}


@app.get("/api/admin/backup-config")
def admin_get_backup_config(user: User = Depends(current_admin), db: Session = Depends(get_db)):
    sched = db.query(BackupSchedule).first()
    # Whether system backups can run at all, and why not (#193).
    passphrase = {"passphrase_set": _backup_passphrase_problem() is None,
                  "passphrase_problem": _backup_passphrase_problem()}
    if not sched:
        return {"enabled": False, "frequency": "daily", "hour": 3,
                "retention_days": 30, "last_run_at": None, "last_run_status": None,
                **passphrase}
    return {
        "enabled": sched.enabled,
        "frequency": sched.frequency,
        "hour": sched.hour,
        "retention_days": sched.retention_days,
        "last_run_at": sched.last_run_at.isoformat() if sched.last_run_at else None,
        "last_run_status": sched.last_run_status,
        **passphrase,
    }


@app.post("/api/admin/backup-config")
def admin_set_backup_config(payload: AdminBackupConfigIn, request: Request,
                            user: User = Depends(current_admin), db: Session = Depends(get_db)):
    if payload.frequency not in ("daily", "weekly", "monthly"):
        raise HTTPException(400, "Invalid frequency")
    if not (0 <= payload.hour <= 23):
        raise HTTPException(400, "Hour must be 0-23")
    if payload.retention_days < 1:
        raise HTTPException(400, "Retention must be at least 1 day")
    sched = db.query(BackupSchedule).first()
    if not sched:
        sched = BackupSchedule()
        db.add(sched)
    sched.enabled = payload.enabled
    sched.frequency = payload.frequency
    sched.hour = payload.hour
    sched.retention_days = payload.retention_days
    db.commit()
    record_event(db, "backup_settings_changed", request, user=user,
                 detail=(f"{'on' if payload.enabled else 'off'}, {payload.frequency} "
                         f"at {payload.hour}:00 UTC, keep {payload.retention_days} days"))
    return {"ok": True}


@app.get("/api/admin/backups")
def admin_list_backups(user: User = Depends(current_admin)):
    """List backup files on disk, newest first."""
    files = sorted(BACKUP_DIR.glob("system-backup-*.json"), reverse=True)
    out = []
    for f in files:
        try:
            stat = f.stat()
            # A sealed file names itself in its first bytes (#193).
            with f.open("rb") as fh:
                head = fh.read(200)
            out.append({
                "filename": f.name,
                "size": stat.st_size,
                "modified": datetime.fromtimestamp(stat.st_mtime).isoformat(),
                "encrypted": SEALED_MARKER.encode() in head,
            })
        except OSError:
            pass
    return out


@app.post("/api/admin/backups/now")
def admin_trigger_backup(request: Request, user: User = Depends(current_admin),
                         db: Session = Depends(get_db)):
    try:
        filename = _run_system_backup()
        # Update schedule status so the admin panel shows when the last backup ran
        sched = db.query(BackupSchedule).first()
        if sched:
            sched.last_run_at = datetime.utcnow()
            sched.last_run_status = f"OK (manual): {filename}"
            db.commit()
        record_event(db, "backup_made", request, user=user, detail=f"manual: {filename}")
        return {"ok": True, "filename": filename}
    except BackupPassphraseMissing as e:
        raise HTTPException(400, str(e))
    except Exception as e:
        # Some errors have no message of their own (a row that can't be
        # decrypted with this ENCRYPTION_KEY is InvalidToken): name them (#147).
        raise HTTPException(500, f"Backup failed: {str(e) or type(e).__name__}")


@app.post("/api/admin/backups/restore/{filename}")
def admin_restore_backup(filename: str, request: Request,
                         user: User = Depends(current_admin), db: Session = Depends(get_db)):
    """Restore from a local system backup file. This is a destructive operation
    that replaces ALL data for ALL users present in the backup."""
    filepath = BACKUP_DIR / filename
    if not filepath.exists() or not filepath.name.startswith("system-backup-"):
        raise HTTPException(404, "Backup file not found")
    try:
        payload = json.loads(filepath.read_text())
    except (json.JSONDecodeError, OSError) as e:
        raise HTTPException(400, f"Could not read backup: {e}")
    # A sealed file opens with BACKUP_PASSPHRASE; a plain one from an
    # earlier version still restores (#193).
    try:
        payload, encrypted = unwrap(payload, BACKUP_PASSPHRASE)
    except BackupLocked as e:
        raise HTTPException(400, ("BACKUP_PASSPHRASE isn't set in .env, so this encrypted backup "
                                  "can't be opened." if not BACKUP_PASSPHRASE else
                                  "BACKUP_PASSPHRASE in .env doesn't open this backup. It may have "
                                  "been made with an earlier passphrase. Nothing was changed."))
    except ValueError as e:
        raise HTTPException(400, str(e))
    if not payload.get("system_backup") or "users" not in payload:
        raise HTTPException(400, "Not a valid system backup file")

    # Restore each user's data. For each user in the backup, find or create
    # the user by email, then use the existing import_user in replace mode.
    from .backup import import_user
    restored = {"users": 0, "accounts": 0}
    for udata in payload["users"]:
        email = udata.get("user", {}).get("email")
        if not email:
            continue
        target = db.query(User).filter_by(email=email.lower()).first()
        if not target:
            # Create the user (no password — they can reset via admin later)
            target = User(email=email.lower(), name=udata.get("user", {}).get("name", ""))
            db.add(target)
            db.commit()
            db.refresh(target)
        counts = import_user(db, target, udata, mode="replace")
        restored["users"] += 1
        restored["accounts"] += counts.get("accounts", 0)
    n = restored["users"]
    record_event(db, "backup_restored", request, user=user,
                 detail=f"{filename}, {n} user{'' if n == 1 else 's'}")
    return {"ok": True, "restored": restored, "encrypted": encrypted}


@app.get("/api/admin/backups/download/{filename}")
def admin_download_backup(filename: str, request: Request,
                          user: User = Depends(current_admin), db: Session = Depends(get_db)):
    filepath = BACKUP_DIR / filename
    if not filepath.exists() or not filepath.name.startswith("system-backup-"):
        raise HTTPException(404, "Backup file not found")
    record_event(db, "backup_downloaded", request, user=user, detail=filename)
    return FileResponse(filepath, media_type="application/json",
                        headers={"Content-Disposition": f'attachment; filename="{filename}"'})


# ---------- Audit log viewer (#134) ----------
# Every event record_event writes. The Admin panel's filter offers these.
AUDIT_EVENT_TYPES = (
    "login", "login_failed", "login_blocked",
    "password_changed", "password_reset", "sessions_ended",
    "user_registered", "registration_refused",
    "user_created", "user_disabled", "user_enabled", "user_deleted", "password_removed",
    "permission_changed", "app_title_changed", "backup_settings_changed",
    "backup_made", "backup_downloaded", "backup_restored",
    "backup_exported", "backup_imported", "data_downloaded",
    "token_created", "token_revoked",
    "two_factor_asked", "two_factor_enabled", "two_factor_disabled",
    "recovery_code_used", "recovery_codes_remade",
    "browser_remembered", "browser_forgotten", "two_factor_requirement_changed",
    "bank_connected", "bank_disconnected", "bank_account_created", "bank_sync_run", "bank_sync_failed",
    "bank_sync_setting_changed",
    "mail_connected", "mail_disconnected", "mail_sender_taught", "mail_check_run",
    "mail_check_failed", "mail_alerts_setting_changed",
)
_AUDIT_USER_REF = re.compile(r"\buser #(\d+)")


@app.get("/api/admin/audit")
def admin_audit(event: str | None = None, email: str | None = None,
                before: int | None = None, limit: int = 50,
                user: User = Depends(current_admin), db: Session = Depends(get_db)):
    """Audit events, newest first. `event` matches exactly; `email` is any
    part of the email, in any case. Paged: pass the response's `next` as
    `before` for the page after. `users` gives the email of each user a page
    refers to (by `user_id` or "user #7" in a detail) who still exists, so
    the panel can name them; the log itself keeps only the number."""
    limit = max(1, min(limit, 200))
    q = db.query(AuditEvent)
    if event:
        q = q.filter(AuditEvent.event == event)
    needle = (email or "").strip().lower()
    if needle:
        needle = needle.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
        q = q.filter(func.lower(AuditEvent.email).like(f"%{needle}%", escape="\\"))
    if before is not None:
        q = q.filter(AuditEvent.id < before)
    rows = q.order_by(AuditEvent.id.desc()).limit(limit + 1).all()
    more = len(rows) > limit
    rows = rows[:limit]
    ids = {r.user_id for r in rows if r.user_id is not None}
    ids |= {int(n) for r in rows for n in _AUDIT_USER_REF.findall(r.detail or "")}
    users = ({str(u.id): u.email for u in db.query(User).filter(User.id.in_(ids))}
             if ids else {})
    return {
        "events": [{"id": r.id, "created_at": _iso(r.created_at), "event": r.event,
                    "user_id": r.user_id, "email": r.email, "ip": r.ip,
                    "detail": r.detail} for r in rows],
        "users": users,
        "next": rows[-1].id if more else None,
        "event_types": list(AUDIT_EVENT_TYPES),
        "retention_days": AUDIT_RETENTION_DAYS,
    }


# ---------- Static frontend ----------
# The SPA lives in apps/web, a sibling of apps/server. The Docker image keeps
# the same layout (/app/server, /app/web), so this resolves in both places;
# WEB_DIR overrides it.
STATIC_DIR = Path(os.environ.get("WEB_DIR")
                  or Path(__file__).resolve().parent.parent.parent / "web")
if STATIC_DIR.exists():
    app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")

    @app.get("/")
    def index():
        # no-cache = "revalidate every time" (the ETag makes that a cheap
        # 304), so a freshly deployed SPA shows up on the next load instead
        # of the browser heuristically reusing a stale copy.
        return FileResponse(STATIC_DIR / "index.html",
                            headers={"Cache-Control": "no-cache"})

    # Installable web app (#41). The service worker is served from the root
    # so it covers the whole site; no-cache so a new release's worker is
    # picked up on the next open.
    @app.get("/sw.js")
    def service_worker():
        return FileResponse(STATIC_DIR / "sw.js", media_type="text/javascript",
                            headers={"Cache-Control": "no-cache"})

    # The "sign in an app" page (#87), opened by the native app in the
    # phone's sign-in sheet. Its script does the work (see "Signing in an app").
    @app.get("/app-sign-in")
    def app_sign_in_page():
        return FileResponse(STATIC_DIR / "app-sign-in.html",
                            headers={"Cache-Control": "no-cache"})


# The manifest is built here rather than kept as a file so the installed
# app takes the instance's title (an admin's custom title, or "WalletWeather
# Demo" in demo mode). Public, like /api/auth/config, which shows the title
# too. Colors are the default dark theme's background.
MANIFEST_BG = "#0f1419"


@app.get("/manifest.webmanifest")
def web_manifest(db: Session = Depends(get_db)):
    title = get_app_title(db)
    icons = "/static/icons/"
    return JSONResponse(
        {
            "name": title,
            "short_name": title,
            "description": "Track balances, forecast cashflow, compare planned vs actual.",
            "id": "/",
            "start_url": "/",
            "scope": "/",
            "display": "standalone",
            "background_color": MANIFEST_BG,
            "theme_color": MANIFEST_BG,
            "icons": [
                {"src": icons + "icon-192.png", "sizes": "192x192", "type": "image/png", "purpose": "any"},
                {"src": icons + "icon-512.png", "sizes": "512x512", "type": "image/png", "purpose": "any"},
                {"src": icons + "icon-maskable-512.png", "sizes": "512x512", "type": "image/png", "purpose": "maskable"},
            ],
        },
        media_type="application/manifest+json",
        headers={"Cache-Control": "no-cache"},
    )
