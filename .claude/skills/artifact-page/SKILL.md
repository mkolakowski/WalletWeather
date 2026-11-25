---
name: artifact-page
description: Add a page to the one WalletWeather artifact, or update one that's there, instead of publishing a separate artifact - list the page, wrap its content in the shared header, rebuild Home from the list and publish the changed files to the same link. Use whenever something about WalletWeather would be published as an artifact (a review, a write-up of what changed, a picture page, a comparison), when the user says "add a page", "put that on the WalletWeather artifact", "update the before and after page", or runs /artifact-page. Argument - the page's name, or nothing to rebuild Home.
---

<!-- WalletWeather's own skill (#351), written 2026-11-24. Not from claude-playbook. -->

# A page in the WalletWeather artifact

WalletWeather has one artifact, with a Home page and a page for each thing
that would otherwise be published separately. Its link is the `url` in
[`pages.json`](pages.json). This skill adds or updates a page there. It
never makes a second artifact for this project, never puts a picture on
`main`, and never puts anything private on a page (a token, a real server's
address, a real account's numbers): the demo and sample data only.

## 1. List the page

Add it to `pages.json` (or change its `updated` date when updating one):

- `slug`: lowercase words joined by `-`. It's the page's address, so it
  never changes once published.
- `kind`: `standing` for a page that's kept up to date (the iOS before and
  after page), `dated` for one written once (a review, a write-up).
- `title`, `about` (one line, what a person finds there), `updated`
  (`YYYY-MM-DD`, Eastern), `issue`.

## 2. Write the page's content

A file with the page's own `<style>` (only what the shared style lacks) and
one `<main>…</main>`. No `<html>`, `<head>` or `<body>`: the wrapper adds
them. The shared style (`pages.css`, written by the script) already covers
the body, headings, `.lede`, tables in a `.scroll` box, lists and `code`,
with colour tokens `--paper`, `--ink`, `--soft`, `--rule`, `--panel`,
`--accent`, `--good`, `--bad`, `--warn` for both themes. Use the tokens;
never a colour that reads in one theme only.

Pictures: a few small ones can be embedded as `data:` URIs. Many, or large
ones, go beside the page as files (`<slug>/<name>.jpg`, referenced
relatively) so the page stays light; put them under
`apps/ios/build/artifact/<slug>/`.

A page built by a script (the UI review's `review_kit.py`, the before and
after page's `ui-compare.py`) writes this content file itself.

## 3. Build

```bash
python3 .claude/skills/artifact-page/scripts/pages.py wrap <slug> <content file>
python3 .claude/skills/artifact-page/scripts/pages.py home
```

Both write into `apps/ios/build/artifact/` (not tracked). Home is written
from `pages.json` and nothing else.

## 4. Publish to the same link

In a session that hasn't published the artifact yet, read it first
(`Artifact`, `action: "read"`, the `url` from `pages.json`), then publish
with that `url`. Publish `apps/ios/build/artifact/index.html` as the page,
`root` set to that folder, and in `files` only what changed: `pages.css`,
the page's `<slug>.html`, and its pictures. Files left out of a publish stay
as they are, so the other pages don't need to be on this Mac.

A page is removed only when Matthew asks: take it out of `pages.json`,
rebuild Home, and publish with its files set to `null`.

## 5. Wrap up

- Commit `pages.json` by name, the summary ending with the issue's number.
- Give Matthew the artifact's link and the page's name. Don't say a page
  works on a phone unless it's been looked at there: no browser on this Mac
  can open it.
