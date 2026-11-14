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
