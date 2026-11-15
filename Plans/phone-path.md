# Phone path: installable web app and API tokens

Tracking issue: #44

## Status

| Phase | Issue | State |
| --- | --- | --- |
| 1. Installable web app | #41 | Released in 1.42.0 (web 1.65.0) |
| 2. API tokens | #42 | Released in 1.41.0 (web 1.63.0, schema 16) |
| 3. Token extras | #43 | Expiry, last used and the Admin token list built in 1.43.0 (web 1.66.0, schema 17), not yet released. `POST /api/auth/token` waits on login rate limiting (roadmap item 15). |

Phase 3 built in part 2026-11-15 in app 1.43.0 / web 1.66.0 / schema 17, not yet released: expiry (30/90/365 days or never, 90 days pre-selected in Settings), last-used time, and the Admin panel's token list with Revoke (browser session only, so no token can revoke tokens). Verified by 24 new tests (98 in all pass) and on a throwaway server upgraded from 1.41.0's database: an old token kept working and never expires. `POST /api/auth/token` is not built: it needs login rate limiting first (roadmap item 15), so #43 stays open for it.

Phase 1 released 2026-11-15 in v1.42.0 (web 1.65.0; release issue #126). Verified by 7 new route tests (78 in all pass), the service worker exercised in Node with stand-in browser APIs (`/api` and `/auth` left alone, page cached online and served offline, a Cloudflare redirect passed through and not cached), and the routes checked on a throwaway server. Not yet tried on a phone.

Phase 2 released 2026-11-15 in v1.41.0 (web 1.63.0, schema 16; release issue #124). Verified by 19 new API tests (71 in all pass) and, against a throwaway server, a token of each level used with `curl`: read-only refused on a write (403), full refused on `/api/admin/users` (403), admin allowed there, a revoked token refused at once (401).

Sessions: may span — each phase ends with a release and your check on a phone before the next starts.

## Agents and tools

| Phase | Main session | Subagents | Why |
| --- | --- | --- | --- |
| 1. Installable web app | Sonnet | none | Follows known patterns (manifest, a small service worker); one file each. Switch to Opus if the Cloudflare Access sign-in loop misbehaves. |
| 2. API tokens | Opus | Sonnet: write the endpoint tests once the design is in | Changes how every request is authenticated, and adds a table. |
| 3. Token extras | Sonnet | none | Four small additions on top of phase 2's design. |

## Open questions

1. **How do scripts and native apps get past Cloudflare Access?** (affects using phase 2 from outside your network, not building it) The server sits behind a Cloudflare Tunnel with Zero Trust rules, which turn away any request that hasn't signed in through Cloudflare, before WalletWeather sees the token. The choices are a Cloudflare service token sent beside the WalletWeather token, or an Access rule that lets `/api/*` through and leaves the WalletWeather token as the only check. Working assumption: phase 2 is built and tested against the server directly, and its README section describes both ways without picking one. For the iOS app this was settled on 2026-11-14 (`docs/dev/decisions/ios-app.md`): the app signs in to Cloudflare itself by default and takes a service token as the alternative. It is still open for scripts.
2. ~~**Can a full-access token use the Admin panel's endpoints?**~~ Settled 2026-11-15 ([decision](../docs/dev/decisions/phone-path.md)): no, but there is a third access level, **admin**, that can. Only an admin can create one, and it stops reaching `/api/admin/*` as soon as its owner stops being an admin.

## The plan

**Goal:** WalletWeather feels like an app on a phone now, and the server is ready for native iOS and Android apps (`apps/ios`, `apps/android`) to sign in later.

**Decided 2026-11-14:**
- The server is reached over HTTPS through a Cloudflare Tunnel with Zero Trust rules.
- Offline, the installed app opens and says it's offline. No balances or transactions are stored on the phone.
- Each token is read-only, full access or admin, chosen when it's created (the admin level decided 2026-11-15).
- Expiry dates, last-used times, the admin view of tokens and password sign-in that returns a token wait for phase 3.

**Out of scope:** the native apps themselves, push notifications, offline viewing or editing of data, limiting a token to chosen accounts. The native iOS app has its own plan, `Plans/ios-app.md` (#93); its first phase waits on phase 2 here.

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

Roadmap item 16.

- A new `api_tokens` table (the next schema number; 14 went to the Important notice, #46): owner, name, access (`read`, `full` or `admin`), a SHA-256 hash of the token, created date, revoked date. The token itself is shown once, at creation, and never stored.
- `Authorization: Bearer <token>` is accepted wherever the session cookie is. A read-only token gets 403 on anything that changes data. Only an admin token reaches `/api/admin/*`; read-only and full tokens get 403 there. An admin token works as full access everywhere else, and loses its admin reach (403) the moment its owner is no longer in `ADMIN_EMAILS`. Working assumption: no token can create or revoke tokens, whatever its level; that needs a signed-in browser. A revoked token, or one whose owner is disabled, gets 401.
- `GET/POST/DELETE /api/tokens` to list, create and revoke your own tokens, from a signed-in browser session only.
- Settings page: a "API tokens" section to create (name + access; the admin level is offered only to admins), copy once, and revoke.
- Tests for each endpoint and for the bearer path: read-only, full, admin (allowed on `/api/admin/*` for an admin, refused once the owner loses admin), full refused on `/api/admin/*`, revoked, and a token refused on the token endpoints.
- README: how to call the API with a token, and the two ways through Cloudflare Access (open question 1).

**You:** create a token in Settings and run the README's example `curl` with it.

**Done when:** tests pass; a token made in Settings fetches `/api/accounts`; a read-only one is refused on a write; a full one is refused on the Admin endpoints and an admin one isn't; a revoked one stops working at once.

### Phase 3: Token extras

Depends on phase 2. Each part can ship on its own.

- Expiry: 30 days, 90 days, a year or never, chosen at creation.
- Last-used time shown per token.
- Admin panel: list and revoke any user's tokens.
- `POST /api/auth/token`: email + password returns a token, for native apps. It needs login rate limiting first (roadmap item 15), and can't cover Google-only accounts.

**Done when:** tests pass for each part; an expired token is refused; the Admin panel lists and revokes another user's token.
