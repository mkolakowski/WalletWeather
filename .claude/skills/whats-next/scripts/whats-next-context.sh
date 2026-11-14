#!/bin/bash
# Prints what /whats-next weighs, in one go: the version, open GitHub issues
# and pull requests, each plan's Status and open questions, the changelog's
# latest "Known limitation" notes, the working tree, and TODOs in tracked
# files. Read-only. Run it from anywhere inside the repo.
#
#   bash whats-next-context.sh

cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1
section() { printf '\n===== %s =====\n' "$1"; }

section "VERSION"
found=""
for f in VERSION Apple/project.yml project.yml package.json pyproject.toml Cargo.toml pubspec.yaml; do
    [ -f "$f" ] || continue
    line=$(grep -m1 -E '^v?[0-9]+\.[0-9]+|MARKETING_VERSION|"version"|^version' "$f" 2>/dev/null)
    [ -n "$line" ] && { echo "$f: $(echo "$line" | sed 's/^ *//')"; found=1; break; }
done
if [ -z "$found" ]; then
    git grep -n -m1 -E '^(readonly +)?[A-Z_]*VERSION *= *"?[0-9]+\.[0-9]+' -- '*.py' '*.sh' 2>/dev/null | grep -v SCHEMA | head -1
fi
[ -f CHANGELOG.md ] && echo "changelog: $(grep -m1 -E '^## ' CHANGELOG.md)"

section "OPEN ISSUES (github)"
gh issue list --state open --limit 30 \
    --json number,title,labels,createdAt,comments,body \
    --jq '.[] | "#\(.number) \(.title)  [\(.labels | map(.name) | join(", "))]  opened \(.createdAt[:10]), \(.comments | length) comments\n    \(.body | gsub("\r?\n"; " ") | .[:300])"' 2>/dev/null \
    || echo "(couldn't reach GitHub, or this isn't a GitHub repo)"

section "OPEN PULL REQUESTS (github)"
gh pr list --state open --limit 10 --json number,title,headRefName,isDraft \
    --jq '.[] | "#\(.number) \(.title) (\(.headRefName))\(if .isDraft then " [draft]" else "" end)"' 2>/dev/null \
    || echo "(couldn't reach GitHub)"

plans=""
for d in Plans plans docs/plans planning; do
    [ -d "$d" ] && plans="$d" && break
done

section "PLANS: Status sections"
if [ -n "$plans" ]; then
    for plan in "$plans"/*.md; do
        [ -f "$plan" ] || continue
        changed=$(git log -1 --format=%cs -- "$plan" 2>/dev/null)
        printf '\n--- %s (last committed: %s)\n' "$plan" "${changed:-never, untracked}"
        # From "## Status" to the next "## " heading, 60 lines at most.
        awk '/^## Status/{on=1; next} on && /^## /{exit} on' "$plan" | head -60
    done
else
    echo "(no plans folder)"
fi

section "PLANS: open questions not yet struck through"
if [ -n "$plans" ]; then
    for plan in "$plans"/*.md; do
        [ -f "$plan" ] || continue
        questions=$(awk '/^## Open questions/{on=1; next} on && /^## /{exit} on' "$plan" | grep -E '^[0-9]+\.|^- ' | grep -v '~~')
        [ -n "$questions" ] && printf -- '--- %s\n%s\n' "$plan" "$questions"
    done
fi

section "KNOWN LIMITATIONS: last 6 versions"
if [ -f CHANGELOG.md ]; then
    awk '
        /^## \[?v?[0-9]/ { version = $2; versions++; if (versions > 6) exit; next }
        /^### Known limitation/ { on = 1; print "--- " version; next }
        /^### / || /^Verified/ { on = 0 }
        on && NF { print }
    ' CHANGELOG.md
else
    echo "(no CHANGELOG.md)"
fi

section "WORKING TREE"
git status --short | head -40
unpushed=$(git log --oneline '@{u}..' 2>/dev/null)
[ -n "$unpushed" ] && printf 'Unpushed commits:\n%s\n' "$unpushed"
echo "Last commits:"
git log --oneline -8 2>/dev/null

section "TODO / FIXME in tracked files"
hits=$(git grep -n -I -w -E 'TODO|FIXME' -- . ':!*.md' ':!*.lock' ':!*.json' 2>/dev/null)
echo "$hits" | head -20
echo "($(echo "$hits" | grep -c . ) in all)"
echo "Today: $(date +%F)"
