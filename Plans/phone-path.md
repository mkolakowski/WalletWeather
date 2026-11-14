# Phone path: installable web app and API tokens

Tracking issue: #44

## Status

| Phase | Issue | State |
| --- | --- | --- |
| 1. Installable web app | #41 | Open |
| 2. API tokens | #42 | Open (waits on open question 2) |
| 3. Token extras | #43 | Open (after phase 2) |

Nothing shipped yet.

Sessions: may span — each phase ends with a release and your check on a phone before the next starts.

## Agents and tools

| Phase | Main session | Subagents | Why |
| --- | --- | --- | --- |
| 1. Installable web app | Sonnet | none | Follows known patterns (manifest, a small service worker); one file each. Switch to Opus if the Cloudflare Access sign-in loop misbehaves. |
| 2. API tokens | Opus | Sonnet: write the endpoint tests once the design is in | Changes how every request is authenticated, and adds a table. |
| 3. Token extras | Sonnet | none | Four small additions on top of phase 2's design. |

## Open questions

1. **How do scripts and native apps get past Cloudflare Access?** (affects using phase 2 from outside your network, not building it) The server sits behind a Cloudflare Tunnel with Zero Trust rules, which turn away any request that hasn't signed in through Cloudflare, before WalletWeather sees the token. The choices are a Cloudflare service token sent beside the WalletWeather token, or an Access rule that lets `/api/*` through and leaves the WalletWeather token as the only check. Working assumption: phase 2 is built and tested against the server directly, and its README section describes both ways without picking one.
2. **Can a full-access token use the Admin panel's endpoints?** (blocks phase 2) Working assumption: no. A token can never reach `/api/admin/*` or create and revoke tokens; those need a signed-in browser session.

## The plan

**Goal:** WalletWeather feels like an app on a phone now, and the server is ready for native iOS and Android apps (`apps/ios`, `apps/android`) to sign in later.

**Decided 2026-11-14:**
- The server is reached over HTTPS through a Cloudflare Tunnel with Zero Trust rules.
- Offline, the installed app opens and says it's offline. No balances or transactions are stored on the phone.
- Each token is full access or read-only, chosen when it's created.
- Expiry dates, last-used times, the admin view of tokens and password sign-in that returns a token wait for phase 3.

**Out of scope:** the native apps themselves, push notifications, offline viewing or editing of data, limiting a token to chosen accounts.

### Phase 1: Installable web app

Roadmap item 17.

- `apps/web/manifest.webmanifest`: name, colors, `display: standalone`, icons. PNG icons (192, 512, maskable, and a 180 px Apple touch icon) made from `favicon.svg`.
- `apps/web/sw.js`, served from `/sw.js`: caches only the page shell (`/`, the icons, the manifest). `/api/*` and `/auth/*` are never cached. A new release replaces the cached page on the next open.
- Offline: the cached page opens and shows a plain "You're offline" notice with a retry button, in place of data.
- Cloudflare Access: the manifest link is loaded with credentials, and the service worker never caches a redirect to the Cloudflare sign-in page, so an expired Cloudflare session leads to the sign-in page and not a broken app.
- The demo title ("WalletWeather Demo") and an admin's custom title keep working.
- Server: routes for `/sw.js` and `/manifest.webmanifest` with the right headers, with tests. App and web versions bump (minor).

**You:** after the release is deployed, add it to your phone's home screen and try it once in airplane mode.

**Done when:** tests pass; on your phone it installs from the browser, opens full screen with its own icon, and offline it opens to the offline notice.

### Phase 2: API tokens

Roadmap item 16. Depends on open question 2.

- A new `api_tokens` table (the next schema number; 14 went to the Important notice, #46): owner, name, access (`full` or `read`), a SHA-256 hash of the token, created date, revoked date. The token itself is shown once, at creation, and never stored.
- `Authorization: Bearer <token>` is accepted wherever the session cookie is. A read-only token gets 403 on anything that changes data. A revoked token, or one whose owner is disabled, gets 401.
- `GET/POST/DELETE /api/tokens` to list, create and revoke your own tokens, from a signed-in browser session only.
- Settings page: a "API tokens" section to create (name + access), copy once, and revoke.
- Tests for each endpoint and for the bearer path: full, read-only, revoked, admin refused.
- README: how to call the API with a token, and the two ways through Cloudflare Access (open question 1).

**You:** create a token in Settings and run the README's example `curl` with it.

**Done when:** tests pass; a token made in Settings fetches `/api/accounts`; a read-only one is refused on a write; a revoked one stops working at once.

### Phase 3: Token extras

Depends on phase 2. Each part can ship on its own.

- Expiry: 30 days, 90 days, a year or never, chosen at creation.
- Last-used time shown per token.
- Admin panel: list and revoke any user's tokens.
- `POST /api/auth/token`: email + password returns a token, for native apps. It needs login rate limiting first (roadmap item 15), and can't cover Google-only accounts.

**Done when:** tests pass for each part; an expired token is refused; the Admin panel lists and revokes another user's token.
