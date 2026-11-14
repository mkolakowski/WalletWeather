# WalletWeather for Android

Placeholder for a native Android app. Nothing here is built or published
yet, and changes in this folder don't trigger the container build.

## Getting started

1. In Android Studio, create a new project (Empty Activity, Kotlin +
   Jetpack Compose) with **this folder** as its location, so the Gradle
   wrapper and `settings.gradle.kts` sit directly in `apps/android/`.
2. Point the app at your server's `APP_BASE_URL` and talk to the same JSON
   API the web client uses (`/api/...`). The live schema is at
   `<APP_BASE_URL>/docs` (and `/openapi.json`) on a running server.

## Things to know

- Sign-in is cookie-based today (`POST /api/auth/login` sets a session
  cookie). Use a persistent cookie jar (e.g. OkHttp's `CookieJar`); a
  token-based login can be added to the server later if needed.
- Keep `local.properties`, keystores and signing passwords out of the repo.
- Gradle and Android Studio build output is already ignored in the root
  `.gitignore`.

## Before listing in Google Play

- The store asks for a privacy policy URL. It is
  <https://mkolakowski.github.io/WalletWeather/privacy> (the source is
  `docs/privacy.md`). Read it against what the app really does before
  submitting, and update it first if the app stores or sends anything it
  doesn't mention.
- The Data safety form: the honest answer today is that no data is collected, because the
  app talks only to the user's own server. Adding analytics, crash reporting
  or ads would change that answer and the policy.
- The name "WalletWeather" should be cleared first (`Plans/legal-risk.md`,
  phase 5).
- The first sign-in must show the Important notice, as the web app does:
  `GET /api/me` returns `notice_required`, and
  `POST /api/me/acknowledge-notice` records the agreement.
