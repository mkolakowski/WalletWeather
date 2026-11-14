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
