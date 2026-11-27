#!/bin/bash
# The simulator walk (Plans/ios-ui-review.md, #345): runs the UI tests in
# apps/ios/UITests once per configuration (a device or a Duo pose, a look, a
# text size), each visiting every screen in the demo, and leaves pictures and
# findings in apps/ios/build/ui-review/<run>/, which isn't tracked. Then
# Scripts/ui-report.py turns the run into one summary.
#
#   Scripts/ui-walk.sh                 the standard run
#   Scripts/ui-walk.sh quick           the closed Duo, light, Large: a few minutes
#   Scripts/ui-walk.sh full            every Duo pose, every look, three text sizes
#   Scripts/ui-walk.sh --only forecast,line-editor     only those screens (a name or the start of one;
#                                      'forecast$' for that screen alone)
#   Scripts/ui-walk.sh --only use      only the flows that use the app (testUse)
#   Scripts/ui-walk.sh --config duo-open.dark.large    only that configuration (may be given more than once)
#   Scripts/ui-walk.sh --no-audit      leave out Apple's accessibility audit (about half the time)
#   Scripts/ui-walk.sh --no-build      use the build that's there
#
# A configuration is <device>.<look>.<text>[.iso][:<how deep>]:
#   device  duo-closed, duo-open (open on its side), duo-open-up, duo-book-up,
#           duo-book-side, duo-closed-side, iphone (an iPhone 17)
#   look    light, dark, amoled, sepia, a web theme (nord, …), custom-light or custom-dark
#   text    large, xxxl, ax-l, ax-xxxl
#   .iso    dates written 2026-11-12, to find a date that ignores the setting
#   :deep   every screenful, Apple's whole audit, the phone turned on its side,
#           and the app used as a person would (testUse: tabs, a line opened
#           and closed, a transaction added, months, search, Settings and back)
#   :scroll every screenful, no audit
#   :shot   the top of each screen and nothing else (Scripts/ui-snapshot.sh)
#   :top    the top of each screen only (the default), with the part of the
#           audit the configuration is for: contrast in a dark look, text at a
#           large text size
#
# WW_UI_TODAY=2026-11-15T10:00 in front pins the app's date and clock (#352);
# WW_UI_ENV=NAME=value,NAME=value adds launch settings to every screen's.
#
# It holds mkplus's simulator lock (with-simulator.sh) for the whole run, so
# other sessions wait rather than have their simulator shut down half way. The
# iPhone 17 is booted in the Duo's place and shut down again afterwards: one
# simulator at a time. It only ever uses the demo and the sample household
# (WW_DEBUG_LOCAL=sample, which replaces the household the SIMULATOR's app
# holds); nothing reaches a server.
set -euo pipefail

ios=$(cd "$(dirname "$0")/.." && pwd)
mkplus=${MKPLUS:-$HOME/GitHub/mkplus}
with_simulator="$mkplus/Scripts/with-simulator.sh"
duo_set="$mkplus/Scripts/duo-set.sh"
duo=${DUO_UDID:-C22FEE5F-91EA-457F-8428-29304CD86498}
dd="$ios/build/sim-dd"

mode=standard
only=""
audit=1
build=1
locked=0
run=""
configs=()
while [ $# -gt 0 ]; do
    case "$1" in
        quick|standard|full) mode=$1 ;;
        --only) only=$2; shift ;;
        --config) configs+=("$2"); shift ;;
        --no-audit) audit=0 ;;
        --no-build) build=0 ;;
        --locked) locked=1; run=$2; shift ;;
        -h|--help) sed -n '2,33p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "ui-walk: don't know '$1' (try --help)" >&2; exit 64 ;;
    esac
    shift
done

if [ ${#configs[@]} -eq 0 ]; then
    case "$mode" in
        quick) configs=(duo-closed.light.large:scroll) ;;
        # Each device once in full or by the screenful; dark and large text
        # where they differ most. About an hour.
        standard) configs=(iphone.light.large:deep iphone.dark.large iphone.light.ax-l:scroll iphone.light.large.iso
                           duo-closed.light.large:scroll duo-closed.light.ax-l
                           duo-open.light.large:scroll duo-open.dark.large duo-open.light.ax-l) ;;
        full) configs=()
              for device in iphone duo-closed duo-open duo-open-up duo-book-up duo-book-side duo-closed-side; do
                  configs+=("$device.light.large:deep")
                  for look in dark amoled sepia; do configs+=("$device.$look.large"); done
                  configs+=("$device.light.xxxl:scroll" "$device.light.ax-l:scroll" "$device.dark.ax-l")
              done
              configs+=(iphone.light.large.iso duo-open.light.large.iso) ;;
    esac
fi

if [ "$locked" = 0 ]; then
    # A full disk breaks a simulator run part-way and stops Docker Desktop.
    free=$(df -g /System/Volumes/Data | awk 'NR==2 {print $4}')
    if [ "$free" -lt 5 ]; then
        echo "ui-walk: only ${free} GB free; it needs 5. Clear the caches that grow back ($mkplus/Scripts/free-space.py) and try again." >&2
        exit 69
    fi
    [ -x "$with_simulator" ] || { echo "ui-walk: no simulator lock at $with_simulator" >&2; exit 69; }
    if [ "$build" = 1 ]; then
        echo "ui-walk: building…"
        log=$(mktemp -t ui-walk-build)
        if ! (cd "$ios" && xcodebuild build-for-testing -project WalletWeather.xcodeproj -scheme WalletWeatherUITests \
                -destination 'generic/platform=iOS Simulator' -derivedDataPath "$dd" >"$log" 2>&1); then
            grep -E "error:|BUILD FAILED" "$log" | head -30 >&2
            echo "ui-walk: the build failed (the whole log: $log)" >&2
            exit 65
        fi
        rm -f "$log"
    fi
    run="$ios/build/ui-review/$(date +%Y%m%d-%H%M)-$mode"
    mkdir -p "$run"
    touch "$run/.started"
    args=(--locked "$run" "$mode")
    [ -n "$only" ] && args+=(--only "$only")
    [ "$audit" = 0 ] && args+=(--no-audit)
    for config in "${configs[@]}"; do args+=(--config "$config"); done
    SIMULATOR_UDID=$duo "$with_simulator" "$0" "${args[@]}"
    # The app's crash reports from this run. macOS can take a minute to write one.
    reports="$HOME/Library/Logs/DiagnosticReports"
    if grep -qs '"check" : "crashed"' "$run"/*/walk.json "$run"/*/use.json; then
        for _ in $(seq 20); do
            [ -n "$(find "$reports" -name 'WalletWeather-*.ips' -newer "$run/.started" 2>/dev/null | head -1)" ] && break
            sleep 3
        done
    fi
    find "$reports" -name 'WalletWeather-*.ips' -newer "$run/.started" 2>/dev/null | while read -r report; do
        mkdir -p "$run/crashes" && cp "$report" "$run/crashes/"
    done
    # The source check's own report goes in beside the walk's (no simulator).
    (cd "$ios/WalletWeatherKit" && WW_UI_SOURCE_REPORT="$run/source.json" swift test --filter UISourceTests >/dev/null 2>&1) \
        || echo "ui-walk: the source check failed or found a new slip; run swift test --filter UISourceTests" >&2
    python3 "$ios/Scripts/ui-report.py" --sheets "$run"
    # Keep the last three runs: the pictures add up.
    ls -1d "$ios"/build/ui-review/*/ 2>/dev/null | sort -r | tail -n +4 | while read -r old; do rm -rf "$old"; done
    echo "ui-walk: $run"
    exit 0
fi

# From here on the simulator lock is held.
xctestrun=$(ls -t "$dd"/Build/Products/WalletWeatherUITests_*.xctestrun 2>/dev/null | head -1)
[ -n "$xctestrun" ] || { echo "ui-walk: no test build in $dd; run without --no-build" >&2; exit 66; }
phone=$(xcrun simctl list devices available | sed -n 's/^ *iPhone 17 (\([0-9A-F-]\{36\}\)).*/\1/p' | head -1)
version=$(sed -n 's/^ *MARKETING_VERSION: *"\(.*\)"/\1/p' "$ios/project.yml" | head -1)
started=$(TZ=America/New_York date '+%Y-%m-%d %-I:%M %p ET')
commit=$(git -C "$ios" rev-parse --short HEAD)
dirty=$(git -C "$ios" status --short -- . | grep -cv '^??' || true)   # grep finds nothing in a clean checkout, and says so by failing

booted=""
boot() {   # the one simulator: shut the other down first
    [ "$booted" = "$1" ] && return 0
    xcrun simctl list devices booted | sed -n 's/.*(\([0-9A-F-]\{36\}\)) (Booted).*/\1/p' | while read -r other; do
        [ "$other" = "$1" ] || xcrun simctl shutdown "$other" >/dev/null 2>&1 || true
    done
    xcrun simctl bootstatus "$1" -b >/dev/null 2>&1
    booted=$1
}

pose=""
finish() {
    # Leave things as other sessions expect them: the Duo closed, the iPhone 17 shut down.
    if [ -n "$phone" ] && [ "$booted" = "$phone" ]; then xcrun simctl shutdown "$phone" >/dev/null 2>&1 || true; fi
    if [ -n "$pose" ] && [ "$pose" != closed-up ]; then boot "$duo"; SIMULATOR_UDID=$duo "$duo_set" closed-up >/dev/null 2>&1 || true; fi
}
trap finish EXIT

names=()
for config in "${configs[@]}"; do
    depth=top
    case "$config" in *:*) depth=${config##*:}; config=${config%%:*} ;; esac
    IFS=. read -r device look text extra <<<"$config"
    # What this configuration is for decides how much of the audit runs.
    case "$depth" in
        deep) kinds=all; stops=4; turn=1; use=1 ;;
        scroll) kinds=0; stops=4; turn=0; use=0 ;;
        shot) kinds=0; stops=0; turn=0; use=0 ;;   # one picture a screen, for Scripts/ui-snapshot.sh
        top) stops=0; turn=0; kinds=0; use=0
             case "$text" in ax-*|xxxl) kinds=text ;; esac
             case "$look" in dark|amoled) kinds=contrast ;; esac ;;
        *) echo "ui-walk: no depth called '$depth' in $config" >&2; continue ;;
    esac
    [ "$audit" = 0 ] && kinds=0
    [ "$extra" = iso ] && kinds=0
    case "$device" in
        iphone)
            [ -n "$phone" ] || { echo "ui-walk: no iPhone 17 simulator; skipping $config" >&2; continue; }
            udid=$phone; want="" ;;
        duo-closed) udid=$duo; want=closed-up ;;
        duo-open) udid=$duo; want=open-side ;;
        duo-open-up) udid=$duo; want=open-up ;;
        duo-book-up) udid=$duo; want=book-up ;;
        duo-book-side) udid=$duo; want=book-side ;;
        duo-closed-side) udid=$duo; want=closed-side ;;
        *) echo "ui-walk: no device called '$device' in $config" >&2; continue ;;
    esac
    boot "$udid"
    if [ -n "$want" ] && [ "$want" != "$pose" ]; then
        SIMULATOR_UDID=$duo "$duo_set" "$want" >/dev/null
        pose=$want
    fi
    mkdir -p "$run/$config"
    began=$(date +%s)
    printf 'ui-walk: %-26s %-6s ' "$config" "$depth"
    for attempt in 1 2; do
        env TEST_RUNNER_WW_UI_OUT="$run" TEST_RUNNER_WW_UI_CONFIG="$config" TEST_RUNNER_WW_UI_LOOK="$look" \
            TEST_RUNNER_WW_UI_TEXT="$text" TEST_RUNNER_WW_UI_DATES="$([ "$extra" = iso ] && echo iso || echo short)" \
            TEST_RUNNER_WW_UI_ONLY="$only" TEST_RUNNER_WW_UI_TREE="${WW_UI_TREE:-0}" TEST_RUNNER_WW_UI_TODAY="${WW_UI_TODAY:-}" \
            TEST_RUNNER_WW_UI_ENV="${WW_UI_ENV:-}" \
            TEST_RUNNER_WW_UI_AUDIT="$kinds" TEST_RUNNER_WW_UI_SCROLL="$stops" TEST_RUNNER_WW_UI_ROTATE="$turn" \
            xcodebuild test-without-building -xctestrun "$xctestrun" -destination "id=$udid" \
                $([ "$only" = use ] || echo "-only-testing:WalletWeatherUITests/WalkTests/testWalk") \
                $( { [ "$only" = use ] || { [ "$use" = 1 ] && [ -z "$only" ]; }; } && echo "-only-testing:WalletWeatherUITests/WalkTests/testUse") \
                -collect-test-diagnostics never -test-timeouts-enabled YES \
                -default-test-execution-time-allowance 3600 -maximum-test-execution-time-allowance 3600 \
                >"$run/$config/xcodebuild.log" 2>&1 && outcome=ran || outcome="FAILED (see $config/xcodebuild.log)"
        [ -f "$run/$config/walk.json" ] || [ -f "$run/$config/use.json" ] && break
        [ "$attempt" = 1 ] && printf 'nothing written, trying once more… ' || true
    done
    if [ -f "$run/$config/walk.json" ]; then
        python3 - "$run/$config/walk.json" <<'EOF'
import json, sys
walk = json.load(open(sys.argv[1]))
screens = walk["screens"]
found = sum(len(s["findings"]) + sum(len(c["findings"]) for c in s["captures"]) for s in screens if s["name"] != "self-test")
print(f'{len(screens)} screens, {sum(len(s["captures"]) for s in screens)} pictures, {found} findings', end=", ")
EOF
    else
        printf 'nothing written, '
    fi
    echo "$(( $(date +%s) - began )) s, $outcome"
    names+=("{\"name\": \"$config\", \"depth\": \"$depth\", \"seconds\": $(( $(date +%s) - began ))}")
done

printf '{"mode": "%s", "started": "%s", "version": "%s", "commit": "%s", "uncommitted": %s, "only": "%s", "audit": %s, "configs": [%s]}\n' \
    "$mode" "$started" "$version" "$commit" "$dirty" "$only" "$audit" "$(IFS=,; echo "${names[*]:-}")" >"$run/run.json"
