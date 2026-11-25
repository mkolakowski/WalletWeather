#!/bin/bash
# Takes a set of pictures for the iOS before-and-after page (#352): the top of
# every screen in the demo, on an iPhone 17 and on the Duo open on its side,
# with the app's date pinned so that sets taken on different days compare.
#
#   Scripts/ui-snapshot.sh             a set of this checkout's app, as <version>-<build>
#   Scripts/ui-snapshot.sh --check     two sets from one build, compared: nothing may differ
#   Scripts/ui-snapshot.sh --keep      also file the set on the screenshots branch and push
#   Scripts/ui-snapshot.sh --label 0.70.0-506 --commit 083c208 --out <folder>
#                                      for a set of an earlier commit, taken from a worktree of it
#
# A set lands in build/ui-sets/<label>/ (not tracked): set.json and
# <configuration>/<screen>.jpg. Scripts/ui-before-after.py then compares each
# set with the one before it and writes the page. About 16 minutes, under the
# simulator lock (Scripts/ui-walk.sh).
set -euo pipefail

ios=$(cd "$(dirname "$0")/.." && pwd)
repo=$(cd "$ios/../.." && pwd)
pinned="2026-11-15T10:00"   # never change it: every set is taken as of this moment
configs=(iphone.light.large:shot duo-open.light.large:shot)

check=0; keep=0; label=""; commit=""; out="$ios/build/ui-sets"; build_flag=()
while [ $# -gt 0 ]; do
    case "$1" in
        --check) check=1 ;;
        --keep) keep=1 ;;
        --no-build) build_flag=(--no-build) ;;
        --label) label=$2; shift ;;
        --commit) commit=$2; shift ;;
        --out) out=$2; shift ;;
        -h|--help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "ui-snapshot: don't know '$1' (try --help)" >&2; exit 64 ;;
    esac
    shift
done

version=$(sed -n 's/^ *MARKETING_VERSION: *"\(.*\)"/\1/p' "$ios/project.yml" | head -1)
[ -n "$commit" ] || commit=$(git -C "$ios" rev-parse --short HEAD)
build=$(git -C "$repo" rev-list --count "$commit")
[ -n "$label" ] || label="$version-$build"
uncommitted=$(git -C "$ios" status --short -- WalletWeather Widgets Notifications WalletWeatherKit/Sources | grep -cv '^??' || true)

take() {   # take <label>: one walk, filed as a set
    local args=()
    for config in "${configs[@]}"; do args+=(--config "$config"); done
    local log
    log=$(mktemp -t ui-snapshot)
    WW_UI_TODAY=$pinned "$ios/Scripts/ui-walk.sh" ${build_flag[@]+"${build_flag[@]}"} "${args[@]}" | tee "$log"
    local run
    run=$(sed -n 's/^ui-walk: \(\/.*\)$/\1/p' "$log" | tail -1)
    rm -f "$log"
    [ -d "$run" ] || { echo "ui-snapshot: the walk left no run folder" >&2; exit 70; }
    local set="$out/$1"
    rm -rf "$set"
    for config in "${configs[@]}"; do
        local name=${config%%:*}
        mkdir -p "$set/$name"
        for picture in "$run/$name"/*.top.jpg; do
            [ -e "$picture" ] || continue
            local screen
            screen=$(basename "$picture" .top.jpg)
            case "$screen" in self-test|use-*) continue ;; esac
            cp "$picture" "$set/$name/$screen.jpg"
        done
        # A screen that isn't the one its name says would file the wrong picture under it.
        if grep -qs '"check" : "not-what-it-says"' "$run/$name/walk.json"; then
            echo "ui-snapshot: a screen in $name isn't the one its name says; see $run/report.md" >&2
        fi
    done
    printf '{"label": "%s", "version": "%s", "build": %s, "commit": "%s", "uncommitted": %s, "pinned": "%s", "configurations": ["%s", "%s"]}\n' \
        "$1" "$version" "$build" "$commit" "$uncommitted" "$pinned" "${configs[0]%%:*}" "${configs[1]%%:*}" >"$set/set.json"
    echo "ui-snapshot: $(find "$set" -name '*.jpg' | wc -l | tr -d ' ') pictures in $set"
}

if [ "$check" = 1 ]; then
    take "$label-check-a"
    build_flag=(--no-build)
    take "$label-check-b"
    # Same build, so anything that differs is the pictures, not the app.
    python3 "$ios/Scripts/ui-before-after.py" --check "$label-check-a" "$label-check-b" && echo "ui-snapshot: two sets from one build compare as the same"
    status=$?
    rm -rf "$out/$label-check-a" "$out/$label-check-b"
    exit $status
fi

take "$label"

if [ "$keep" = 1 ]; then
    # The screenshots branch, through a worktree of its own: this checkout's branch never changes.
    tree=$(mktemp -d -t ww-screenshots)
    git -C "$repo" fetch -q origin screenshots
    git -C "$repo" worktree add -q --detach "$tree" origin/screenshots
    mkdir -p "$tree/ui-sets"
    rm -rf "$tree/ui-sets/$label"
    cp -R "$out/$label" "$tree/ui-sets/$label"
    rm -f "$tree/ui-sets/$label"/compare.*.json
    git -C "$tree" add "ui-sets/$label"
    git -C "$tree" commit -q -m "iOS $version (build $build): a set of pictures for the before-and-after page (#352)"
    git -C "$tree" push -q origin HEAD:screenshots
    git -C "$repo" worktree remove --force "$tree"
    echo "ui-snapshot: $label is on the screenshots branch"
fi
