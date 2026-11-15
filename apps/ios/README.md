# WalletWeather for iOS

Placeholder for a native iOS app. Nothing here is built or published yet,
and changes in this folder don't trigger the container build.

## The plan

[`Plans/ios-app.md`](../../Plans/ios-app.md) (tracking issue #93) is the plan
for this app: what it covers, how it signs in, how it uses the iPhone Duo's
inner screen, and the phases it ships in. This folder stays a placeholder
until that plan's phase 1.

## Things to know

- The app will be a SwiftUI project in this folder
  (`apps/ios/WalletWeather.xcodeproj`) with a local Swift package for the API
  client (`apps/ios/WalletWeatherKit`), and no third-party packages.
- It talks to the same JSON API the web client uses (`/api/...`). The live
  list of endpoints is at `<APP_BASE_URL>/docs` (and `/openapi.json`) on a
  running server; it doesn't describe what each one returns, so the plan adds
  tests for the responses the app reads.
- Sign-in will use an API token (`Plans/phone-path.md`, phase 2), not the
  session cookie the web client uses.
- Keep secrets (server addresses, tokens, signing files) out of the repo.
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
