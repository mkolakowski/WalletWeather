#!/usr/bin/env bash
# Archive the iOS app and upload it to TestFlight (#92).
#
# Run from anywhere on the Mac that builds the app:
#   apps/ios/Scripts/testflight.sh
#
# It needs two gitignored files in apps/ios/Config/ (see apps/ios/README.md):
#   Signing.local.xcconfig     DEVELOPMENT_TEAM = <team ID>
#   AppStoreConnect.local.env  ASC_KEY_ID=..., ASC_ISSUER_ID=...,
#                              and optionally ASC_KEY_PATH (the .p8 file;
#                              default ~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8)
#
# The build number is the count of commits on HEAD, so every upload from a
# newer commit is higher than the last. MARKETING_VERSION comes from
# project.yml as usual. Builds can go to external testers (decided
# 2026-11-24, #335, before the name check in #49): a build uploaded as
# internal-only can never be given to them. TESTFLIGHT_INTERNAL_ONLY=true
# keeps one internal.
set -euo pipefail

IOS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="$IOS_DIR/Config"
BUILD_DIR="$IOS_DIR/build/testflight"

fail() { echo "testflight: $*" >&2; exit 1; }

[[ -f "$CONFIG/Signing.local.xcconfig" ]] || fail "missing Config/Signing.local.xcconfig (DEVELOPMENT_TEAM)"
TEAM_ID="$(sed -nE 's/^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*([A-Z0-9]+).*/\1/p' "$CONFIG/Signing.local.xcconfig" | head -1)"
[[ -n "$TEAM_ID" ]] || fail "no DEVELOPMENT_TEAM in Config/Signing.local.xcconfig"

[[ -f "$CONFIG/AppStoreConnect.local.env" ]] || fail "missing Config/AppStoreConnect.local.env (ASC_KEY_ID, ASC_ISSUER_ID)"
# shellcheck disable=SC1091
source "$CONFIG/AppStoreConnect.local.env"
: "${ASC_KEY_ID:?set ASC_KEY_ID in Config/AppStoreConnect.local.env}"
: "${ASC_ISSUER_ID:?set ASC_ISSUER_ID in Config/AppStoreConnect.local.env}"
ASC_KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8}"
[[ -f "$ASC_KEY_PATH" ]] || fail "API key not found at $ASC_KEY_PATH"

INTERNAL_ONLY="${TESTFLIGHT_INTERNAL_ONLY:-false}"
[[ "$INTERNAL_ONLY" == true || "$INTERNAL_ONLY" == false ]] || fail "TESTFLIGHT_INTERNAL_ONLY must be true or false"
BUILD_NUMBER="$(git -C "$IOS_DIR" rev-list --count HEAD)"
AUTH=(-allowProvisioningUpdates
      -authenticationKeyPath "$ASC_KEY_PATH"
      -authenticationKeyID "$ASC_KEY_ID"
      -authenticationKeyIssuerID "$ASC_ISSUER_ID")

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

cat > "$BUILD_DIR/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>${TEAM_ID}</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
  <key>testFlightInternalTestingOnly</key><${INTERNAL_ONLY}/>
</dict>
</plist>
PLIST

echo "testflight: archiving build $BUILD_NUMBER"
xcodebuild archive \
  -project "$IOS_DIR/WalletWeather.xcodeproj" \
  -scheme WalletWeather \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$BUILD_DIR/WalletWeather.xcarchive" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  "${AUTH[@]}"

# App Store Connect turns a build away after the upload is accepted when an
# App Intent's title, description or phrase names Apple's products (ITMS-90626
# "Invalid Siri Support"); builds 482 to 489 were lost that way (#337).
echo "testflight: checking the App Intents metadata"
python3 -I - "$BUILD_DIR/WalletWeather.xcarchive" <<'PY' || fail "an App Intent names an Apple product (see above); reword it in WalletWeather/Shortcuts.swift"
import json, pathlib, re, sys
bad = re.compile(r"(?i)\b(iphone|ipad|siri|apple)\b")
found = []
def walk(value, where):
    if isinstance(value, dict):
        for item in value.values(): walk(item, where)
    elif isinstance(value, list):
        for item in value: walk(item, where)
    # Words people see, not identifiers such as com.apple.link.….
    elif isinstance(value, str) and bad.search(value) and not re.fullmatch(r"[\w$-]+(\.[\w$-]+)+", value):
        found.append((where, value))
for data in pathlib.Path(sys.argv[1]).rglob("Metadata.appintents/extract.actionsdata"):
    walk(json.loads(data.read_text()), data.parent.parent.name)
for where, text in found:
    print(f"testflight: {where}: {text}")
sys.exit(1 if found else 0)
PY

echo "testflight: exporting and uploading"
xcodebuild -exportArchive \
  -archivePath "$BUILD_DIR/WalletWeather.xcarchive" \
  -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
  -exportPath "$BUILD_DIR/export" \
  "${AUTH[@]}"

echo "testflight: uploaded build $BUILD_NUMBER; App Store Connect processes it before it shows in TestFlight."
echo "testflight: \"uploaded\" isn't \"accepted\": if it never shows, its processing failed (App Store Connect's email, or buildUploads in the API, says why)"
