#!/bin/bash
# Says plainly when a folder that lives on an external drive can't be
# reached, instead of letting a build fail part-way on a link to nowhere.
# Silent when every link resolves; exit 1 (naming each) when one dangles,
# and exit 1 when the drive is mounted but doesn't answer within
# CHECK_LINKS_TIMEOUT seconds (default 5).
# Installed by the playbook's /offload-to-drive skill; run it first from the
# scripts that build or run tests.
#
#   scripts/check-links.sh

BUILD_DIR=build                 # links one or two levels down in here are checked
EXTRA_LINKS=()                  # other linked paths, e.g. ("$HOME/Library/Developer/Xcode/iOS DeviceSupport")
DRIVE_NAME="the external drive"

cd "$(dirname "$0")/.." || exit 1
missing=()
while IFS= read -r link; do
    [ -e "$link" ] || missing+=("$link -> $(readlink "$link")")
done < <(find "$BUILD_DIR" -maxdepth 2 -type l 2>/dev/null)
for link in "${EXTRA_LINKS[@]}"; do
    [ -L "$link" ] && [ ! -e "$link" ] && missing+=("$link -> $(readlink "$link")")
done
if [ ${#missing[@]} -gt 0 ]; then
    echo "check-links: $DRIVE_NAME isn't connected, so these can't be reached:" >&2
    printf '  %s\n' "${missing[@]}" >&2
    echo "Plug it in and run it again." >&2
    exit 1
fi

# A drive can stay mounted while every read and write on it hangs, and the
# check above still passes. So list each linked folder and
# write a small file there in the background, and give up after a few seconds
# rather than let a build or test run hang for hours.
targets=()
while IFS= read -r link; do
    [ -e "$link" ] && targets+=("$link/")
done < <(find "$BUILD_DIR" -maxdepth 2 -type l 2>/dev/null; for l in "${EXTRA_LINKS[@]}"; do [ -L "$l" ] && echo "$l"; done)
if [ ${#targets[@]} -gt 0 ]; then
    limit="${CHECK_LINKS_TIMEOUT:-5}"   # seconds
    (
        for t in "${targets[@]}"; do
            ls "$t" >/dev/null || exit 1
            f="$t.check-links-probe.$$"
            : > "$f" && rm -f "$f"
        done
    ) </dev/null >/dev/null 2>&1 &
    probe=$!
    tenths=0
    while kill -0 "$probe" 2>/dev/null; do
        if [ "$tenths" -ge $((limit * 10)) ]; then
            kill -9 "$probe" 2>/dev/null
            echo "check-links: $DRIVE_NAME is connected but not answering (no reply in ${limit}s from ${targets[0]%/})." >&2
            echo "Unplug it for ~10 seconds and plug it back in; if it stays stuck, restart the computer (a hung drive can't be ejected)." >&2
            exit 1
        fi
        sleep 0.1
        tenths=$((tenths + 1))
    done
    if ! wait "$probe"; then
        echo "check-links: $DRIVE_NAME can't be read (${targets[0]%/})." >&2
        exit 1
    fi
fi
