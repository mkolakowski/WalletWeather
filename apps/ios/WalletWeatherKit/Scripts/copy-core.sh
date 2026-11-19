#!/bin/sh
# Copies the shared JavaScript core into this package (SwiftPM can't take a
# resource from outside it). Run after changing packages/core/walletweather-core.js;
# CoreTests fails until the copy matches.
set -eu
KIT="$(cd "$(dirname "$0")/.." && pwd)"
cp "$KIT/../../../packages/core/walletweather-core.js" "$KIT/Sources/WalletWeatherKit/Core/walletweather-core.js"
echo "Copied the core into $KIT/Sources/WalletWeatherKit/Core"
