# Account picker: your picture, and a way back from the demo

Tracking issue: #380

## Status

| Phase | Issue | State |
| --- | --- | --- |
| 1. Profile pictures on the server | #377 | Open |
| 2. Your picture in the web app | #378 | Open |
| 3. The account picker on the iPhone | #379 | Open; waits for open question 1 |

Planned 2026-11-25, asked for as "can you add an account picker to the ios app where the image is the users profile image from the profile/server. this will be used to change back from demo." Scoped the same morning in one round of questions: the server learns to keep a picture (nothing keeps one today), set from the web app's Your account and taken from Google at sign-in; the iPhone shows it, with initials until one is set. Where the button sits is shown both ways on the *Account picker: where it sits* page of the WalletWeather artifact, for Matthew to pick.

Sessions: may span — a server phase with a schema change, a web phase and an iPhone phase that waits for a choice.

## Agents and tools

| Phase | Main session | Subagents | Why |
| --- | --- | --- | --- |
| 1. Profile pictures on the server | Opus | Sonnet: the endpoint tests, once the endpoints are written | A schema change, an upload checked byte by byte, a fetch from Google at sign-in, and the security guards. |
| 2. Your picture in the web app | Sonnet | None | A panel and a button following the Your account panels and the initials button already there. |
| 3. The account picker on the iPhone | Opus | None | A new control in the bar of two pages, pictures kept per connection, the lock's rules in the demo. |

## Open questions

1. **Where the picker sits** (blocks phase 3). In the top-right corner of the Dashboard and Settings, either *replacing* the connection chip under the title, or *beside* it with the chip kept. Both are drawn on the artifact page *Account picker: where it sits*.
2. **Google's picture** (phase 1 builds the rest without it). Recommended: copy it at a Google sign-in only when the person has no picture yet, so one set by hand is never replaced. Other choices: copy it at every Google sign-in (follows a change at Google, overwrites one set by hand), or never (only a picture set by hand).

## The plan

**Goal:** a round button with your picture (your initials until there is one) that opens the list of connections, each with its own picture, so leaving the demo, or switching, is one tap from a page you're on. The same picture shows on the web app's account button.

**Decided 2026-11-25** (by Matthew, in the scoping round):

- **The picture lives on the server,** set in the web app's Settings → Your account and taken from Google at sign-in (open question 2 says when), and the iPhone reads it from the server. Initials until one is set. Not Gravatar: that would send each email's hash to a third party.
- **Placement is shown both ways first,** on a page of the WalletWeather artifact, before phase 3 is built.

**Out of scope:**

- Seeing other people's pictures (a shared account's owner, Admin → Users). Each person sees only their own.
- A picture for the household on this iPhone or the demo: they keep their icons (iPhone, sparkles).
- Cropping or filters beyond a square cut from the middle.

**What's there today:**

- `users` has no picture; `GET /api/me` gives `name` and `email`. Google sign-in (`/auth/callback`) reads `userinfo` (`sub`, `email`, `email_verified`) and asks for the `profile` scope, so the `picture` claim is already in what Google returns.
- The web app's top bar has a round initials button (`#userMenuBtn`, `_userInitials`, web-refresh phase 8, #288) opening the account menu.
- The iPhone has the connection chip (#302) under the Dashboard's title and at the top of Settings, opening the menu of connections and Manage connections…; it shows only with two or more connections or in the demo.
- The server has no image library; data at rest is encrypted with Fernet (`*_enc` columns).

### Phase 1: Profile pictures on the server

- Schema 40: `users.picture_enc` (the image, encrypted like the other `*_enc` columns), `users.picture_type` (`image/png`, `image/jpeg` or `image/webp`) and `users.picture_updated_at`.
- `PUT /api/me/picture` takes the image as the request body, at most 256 KB, and checks its first bytes really are PNG, JPEG or WebP; the client sends it already square and small (512 px at most), so the server needs no image library. `DELETE /api/me/picture` removes it. `GET /api/me/picture` gives the signed-in person's own picture with an `ETag` (404 when none). A read-only token may read it but not change it.
- `GET /api/me` gains `picture_updated_at` (null when none), so a client knows when to fetch it again.
- Google sign-in copies the `picture` claim's image (per open question 2), fetched with a short time limit and the same size and type checks; a failure leaves sign-in as it was.
- Tests: each endpoint's happy path and its refusals (too big, not an image, not signed in, read-only token); the security guards list the new routes.

### Phase 2: Your picture in the web app

- Settings → Your account gains *Profile picture*: choose a file, see it cut square from the middle and made small in the browser (a canvas), Save; Remove.
- The top bar's initials button shows the picture when there is one.

### Phase 3: The account picker on the iPhone

- A round button with the picture of whoever is signed in to the server in front (initials until one is set; the demo's sparkles in the demo), placed as open question 1 decides. Tapping it opens the list of connections, each server with its own picture, the household and the demo with their icons, a tick on the one in front, then Manage connections….
- Each saved server's picture is kept on the phone with that connection, fetched again when `picture_updated_at` changes while it's in front, and deleted with the connection. Nothing is fetched from a server that isn't in front.
- Locked in the demo, the pictures don't show (initials don't either): names and icons only, as Connections does now.
- A line in `apps/ios/UITests/Screens.swift` for the open menu.
