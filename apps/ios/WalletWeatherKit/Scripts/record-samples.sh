#!/bin/sh
# Records the responses WalletWeatherKit's tests decode, from a demo server
# (DEMO_MODE=true; its admin login is public). Usage, from anywhere:
#   apps/ios/WalletWeatherKit/Scripts/record-samples.sh http://localhost:8300
# Then run `swift test` in apps/ios/WalletWeatherKit and commit the samples.
set -eu
BASE="${1:?usage: record-samples.sh <demo server address>}"
OUT="$(cd "$(dirname "$0")/.." && pwd)/Tests/WalletWeatherKitTests/Samples"
TODAY="$(date +%F)"
mkdir -p "$OUT"
json() { python3 -m json.tool; }

curl -fsS -X POST "$BASE/api/auth/token" -H 'Content-Type: application/json' \
  -d '{"email":"admin@demo.walletweather.local","password":"demo1234","name":"iPhone Duo","access":"read"}' > "$OUT/token.json"
TOKEN="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["token"])' "$OUT/token.json")"
# The recorded token is replaced: the samples never hold a working one.
python3 - "$OUT/token.json" <<'PY'
import json, sys
p = sys.argv[1]; t = json.load(open(p)); t["token"] = "ww_sample-token-not-real"
json.dump(t, open(p, "w"), indent=4)
PY

get() { curl -fsS -H "Authorization: Bearer $TOKEN" "$BASE$1" | json > "$OUT/$2.json"; }
get /api/version version
get /api/me me
get "/api/accounts?today=$TODAY" accounts
get "/api/dashboard?today=$TODAY" dashboard
get "/api/dashboard/charts?window=month&today=$TODAY" charts-month
get "/api/dashboard/charts?window=90d&today=$TODAY" charts-90d
get /api/saved-reports saved-reports
# Search across everything (#111, #112): "e" finds something in every group the demo has.
get "/api/search?q=e&today=$TODAY" search-everything
curl -fsS -X POST -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{}' \
  "$BASE/api/saved-reports/1/run" | json > "$OUT/report-run.json"
curl -sS -H "Authorization: Bearer ww_not-a-token" "$BASE/api/me" > "$OUT/error-revoked.json"
echo "Recorded $(ls "$OUT" | wc -l | tr -d ' ') samples in $OUT"
