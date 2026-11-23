---
name: test-review
description: Review this project's test suite itself - where the time goes, tests in the wrong tier (fast, slow, live), tests that always skip, tests that repeat each other, helpers copied between files, and code no test touches - then update the tiers when that's safe and list what to merge or remove for the user to decide. It never edits or removes a test by itself. Use when the user asks to "review the tests", "why are the tests slow?", "are the tests redundant?", "update the test tiers", after a big run, before a release review, or when they run /test-review. Argument - "run" to do a fresh full run first, or "update" to apply the tier changes.
---

<!-- claude-playbook skill v1.6.0 -->

# Review the tests

The "Tests" rule in this project's `CLAUDE.md` says how tests are run and
tiered. This skill looks at the suite as a whole and keeps the tiers true.
It never edits, merges or removes a test by itself: that goes to the user
first. Where the project has its own script for any step below, use it.

## 1. Get a run to read

Use the project's test command, with whatever makes it report a time per
test or per file (`pytest --durations=0`, `jest --verbose`, `go test -v`,
`cargo test -- --report-time`, an Xcode result bundle). Run the fast tier;
run the slow tier too when the argument is `run`, or the code it covers
changed. Follow the project's rules on shared resources (one simulator job
at a time, a running container). With no run needed, read the newest saved
result.

## 2. Measure

- **Time:** the slowest test files or classes and their share of the whole;
  how many tests are near-instant; any failure.
- **Tiers:** a fast-tier file that has grown slow belongs in the slow tier;
  a slow one that's now quick can leave it. Use the project's thresholds, or
  propose them (a few seconds per file is a reasonable line).
- **Skips:** a test that always skips but isn't listed as live (needing a
  server, a device or a flag).
- **Repeats:** the same test name in more than one file, helpers copied
  between files, hand-made setup a shared fixture could replace, fixed
  sleeps, near-identical tests a table could replace.
- **Gaps:** source files no test mentions, so a change to one picks no
  tests.

## 3. Update what's safe

With the user's OK, or when the argument is `update`: move files across the
tier lines, add new live tests to the live list with what each needs, and
keep the doc that describes the tiers in step.

## 4. Redundancy needs a decision

For each repeat, say what covers what and propose the merge. Before
anything goes:

- line coverage of the code under test must not drop
- the behavior is broken once on purpose, to see a remaining test fail
- same names and same shapes aren't always repeats: check what each test
  actually drives before calling it one

Tests the project's rules lock (golden files, layout locks, checks that
back a rule) are never merged or re-recorded here.

## 5. Report

A few lines, not the raw output: the total time and the share of the slowest
files, the tier moves made, what always skips, the repeats worth merging
(for the user to pick), and the biggest gaps. Changes to tracked files
follow the project's rules: an issue, a commit, a push.
