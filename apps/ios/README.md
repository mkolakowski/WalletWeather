# WalletWeather for iOS

Placeholder for a native iOS app. Nothing here is built or published yet,
and changes in this folder don't trigger the container build.

## Getting started

1. In Xcode, create a new project (App, SwiftUI) named `WalletWeather` and
   save it **in this folder**, so you end up with
   `apps/ios/WalletWeather.xcodeproj`.
2. Point the app at your server's `APP_BASE_URL` and talk to the same JSON
   API the web client uses (`/api/...`). The live schema is at
   `<APP_BASE_URL>/docs` (and `/openapi.json`) on a running server.

## Things to know

- Sign-in is cookie-based today (`POST /api/auth/login` sets a session
  cookie). `URLSession` keeps cookies by default, so that works for a first
  version; a token-based login can be added to the server later if needed.
- Keep secrets (server URL presets, OAuth client IDs) out of the repo.
- Xcode build output is already ignored in the root `.gitignore`.

## Before listing in the App Store

- The store asks for a privacy policy URL. It is
  <https://mkolakowski.github.io/WalletWeather/privacy> (the source is
  `docs/privacy.md`). Read it against what the app really does before
  submitting, and update it first if the app stores or sends anything it
  doesn't mention.
- The App Privacy questions (the "nutrition label"): the honest answer today is that no data is collected, because the
  app talks only to the user's own server. Adding analytics, crash reporting
  or ads would change that answer and the policy.
- The name "WalletWeather" should be cleared first (`Plans/legal-risk.md`,
  phase 5).
- The first sign-in must show the Important notice, as the web app does:
  `GET /api/me` returns `notice_required`, and
  `POST /api/me/acknowledge-notice` records the agreement.
