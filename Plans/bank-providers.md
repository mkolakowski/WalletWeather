# Bank providers: Teller and Plaid next to SimpleFIN

Tracking issue: #259

## Status

| Phase | Apps | Issue | State |
| --- | --- | --- | --- |
| 1. Teller and Plaid connect and sync | Server, Web | #254 | Not started |
| 2. Their categories onto yours | Server, Web | #255 | Not started; waits for open question 3 |
| 3. The bank's balance next to yours | Server, Web | #256 | Not started; waits for open question 4 |
| 4. Every connection in the iPhone app | iOS | #257 | Not started |
| 5. Connect a bank from the iPhone | iOS, Server | #258 | Waits (your call, 2026-11-20) |

Planned 2026-11-20 after your SimpleFIN connections (SimpleFIN Bridge runs on MX) wouldn't work with your banks. Three calls were made that day ([decision](../docs/dev/decisions/bank-sync.md)): connecting happens on the provider's own page; both providers come in one phase; only connecting from the iPhone waits.

Sessions: may span — phase 1 needs your own Teller and Plaid accounts, and each phase ends with a release and your try on your own instance before the next starts.

## Agents and tools

| Phase | Apps | Main session | Subagents | Why |
| --- | --- | --- | --- | --- |
| 1. Teller and Plaid connect and sync | Server, Web | Opus | Sonnet: tests against stand-in Teller and Plaid; Haiku: find every place that assumes one connection per user | Two new services the server calls, two new stored tokens, an mTLS certificate, a schema change from one connection to many, and a page with its own Content-Security-Policy. |
| 2. Their categories onto yours | Server, Web | Sonnet | Sonnet: tests for the mapping cases | One mapping table and one screen on top of phase 1's lines. |
| 3. The bank's balance next to yours | Server, Web | Sonnet | Sonnet: tests per provider | A stored number per sync and a figure on an existing screen. |
| 4. Every connection in the iPhone app | iOS | Sonnet | Sonnet: screenshots | The existing Bank sync card turned into a list, against an endpoint phase 1 makes. |
| 5. Connect a bank from the iPhone | iOS, Server | Opus | Sonnet: tests | A sign-in sheet and a hand-back of a bank token to the server. |

## Open questions

1. **One admin switch, or one per provider?** Blocks nothing; phase 1 is built on this unless you say otherwise. Assumed: the existing Admin → Bank sync switch covers all three, and each provider is offered only when its keys are in `.env` (as email alerts need `MS_CLIENT_ID`).
2. **The same bank account through two connections** (say SimpleFIN and Teller both reach one checking account). Blocks nothing; phase 1 is built on this unless you say otherwise. Assumed: each of your accounts links to one bank account across all your connections, and a second link is refused with a message naming the connection that has it, so no line comes in twice.
3. **How their categories map onto yours.** Blocks phase 2. For example: a table you fill in once per provider category; suggested matches by name that you confirm; or a category only when no auto-tag rule applies.
4. **Where the bank's balance shows, and what a gap means.** Blocks phase 3. For example: next to the account's balance on the Accounts screen; in the account's sync log; a warning when the two differ by more than an amount you set.

## The plan

**Goal:** bank sync works with the banks SimpleFIN can't reach, by adding Teller and Plaid as providers a user can pick per bank, with every synced line going through the same path as today. It extends roadmap item 29 and follows `Plans/bank-sync.md` (#198).

**Decided 2026-11-20** (asked while planning; [decision page](../docs/dev/decisions/bank-sync.md)):

- **Teller and Plaid, next to SimpleFIN.** This reverses 2026-11-16's "Plaid is not planned". Each instance brings its own keys, as Google sign-in does.
- **Connecting happens on the provider's page, not inside the web app.** Plaid through Hosted Link: the server asks Plaid for a link, it opens on Plaid's site in a new tab, and the server checks back for the result, so no webhook and no public address are needed. Teller only offers a script, so it runs on one small separate page, the only page allowed to load `cdn.teller.io`; the rest of the web app still loads nothing from other sites, and `PRIVACY.md` names the exception.
- **Both providers in one phase**, on a reworked base where a user can have many connections.
- **Connecting from the iPhone waits** (phase 5). Categories and balances are planned (phases 2 and 3).
- **Done means** API tests in CI against stand-in providers, then a release and your try on your own instance, phase by phase.

**Out of scope:**

- **Teller and Plaid on a phone without a server** (standalone phase 8, #239). Teller's certificate and Plaid's secret key must stay on a server and never ship in an app, so a standalone phone stays SimpleFIN-only.
- Pending transactions (still synced only once posted, as decided 2026-11-16); webhooks; investments and loans; moving money; Plaid's paid products beyond Transactions.

**What's there today:**

- `apps/server/app/simplefin.py` makes the SimpleFIN calls; `main.py` (around `bank_sync_enabled`, `_bank_sync_locked`, `run_due_bank_syncs`) holds the routes, the landing path, the daily scheduler and the 20-a-day guard.
- `BankConnection` in `apps/server/app/db.py` is one per user (`user_id` unique) and holds the SimpleFIN access address encrypted with `ENCRYPTION_KEY`; `BankAccountLink` matches a bank account to one of the user's accounts; `transactions.bank_ref` is a hash of the bank's ids for de-duplication.
- The web app sends `frame-ancestors 'none'; base-uri 'self'; object-src 'none'` as its Content-Security-Policy (`main.py`).
- `httpx` is pinned, and takes a client certificate, so neither provider needs an SDK.

**What each provider costs you** (checked 2026-11-20): Teller's development tier is free up to 100 bank logins, then $0.30 per login per month for transactions. Plaid's Trial plan allows 10 bank logins free, Chase, Bank of America and Wells Fargo included; after that its Pay-as-you-go plan, whose prices Plaid shows only when you apply for production. Applying ends the Trial plan for good.

### Phase 1: Teller and Plaid connect and sync (#254)

- **Many connections:** `bank_connections` gets a provider and loses its one-per-user rule; the SimpleFIN connection you have becomes the first of your list. Teller enrollments and Plaid Items each cover one bank login, so a user with three banks has three connections.
- **Teller:** `TELLER_APP_ID`, `TELLER_ENV`, `TELLER_CERT_FILE` and `TELLER_KEY_FILE` in `.env` (the certificate and key mounted read-only into the server's container). The connect page hands the access token to the server, which stores it encrypted and asks for accounts and posted transactions over mTLS.
- **Plaid:** `PLAID_CLIENT_ID`, `PLAID_SECRET` and `PLAID_ENV` in `.env`. Hosted Link in a new tab; the server checks the link token for the result, exchanges it for an access token stored encrypted, and syncs with `/transactions/sync`, keeping its cursor.
- Every connection uses the daily rhythm, Sync now, the landing path, the auto-tag rules, bill matching, the Unmatched list and the sync log. Disconnecting removes the connection at the provider too; deleting a user removes theirs. Encrypted backups carry the connections, as they carry SimpleFIN's.
- **Web:** Settings → Bank sync lists the connections; "Connect a bank" offers each provider whose keys are set.
- `/api/bank/status` keeps its shape, so the iPhone app as released keeps working.
- `PRIVACY.md`, `docs/privacy.md`, `SECURITY.md`, `README.md`, `.env.example` and `docs/bank-sync.md` updated.
- **You:** a Teller developer account with its certificate and key; a Plaid account on the Trial plan; the keys in `.env`; try your banks.
- **Done when:** API tests pass against stand-in Teller and Plaid (connect, sync, posted only, de-duplication, disconnect at the provider, a second link refused); the screens pass a headless browser check with no console errors; the release is out and at least one of your banks syncs through Teller or Plaid.

### Phase 2: Their categories onto yours (#255)

Keep the category each line comes with (Teller's `details.category`, Plaid's `personal_finance_category`) and map it onto your categories as lines land, with the auto-tag rules still winning. The screen waits for open question 3. **Done when:** API tests cover a mapped, an unmapped and a rule-overridden line; the release is out and your synced lines land in your categories.

### Phase 3: The bank's balance next to yours (#256)

Keep each provider's balance for a linked account at each sync (SimpleFIN and Plaid give it with the accounts; Teller's balance call is free in development and billed in production) and show it next to the forecast's. Where, and what a gap means, wait for open question 4. **Done when:** API tests cover each provider and one that gives none; the release is out and your linked accounts show both.

### Phase 4: Every connection in the iPhone app (#257)

The Bank sync card in Settings lists every connection with its status and Sync now; Try the demo shows two. **Done when:** `swift test` covers each state and an older server; simulator screenshots; the release is out and Sync now works from your phone.

### Phase 5: Connect a bank from the iPhone (#258)

Plaid's Hosted Link and Teller's connect page opened in a sign-in sheet (`ASWebAuthenticationSession`), the result handed to the server; no provider SDK unless the sheet can't do it. Waits for your say. **Done when:** a bank connects from your phone on your instance.
