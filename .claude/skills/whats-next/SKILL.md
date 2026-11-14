---
name: whats-next
description: Survey what to work on next in this project - open GitHub issues and pull requests, each plan's progress and open questions, the changelog's known limitations, uncommitted or unpushed work, and TODOs in the code - then offer the strongest candidates as a clickable multiple choice. It only looks; nothing changes until the user picks. Use when the user asks "what's next?", "what should we work on?", "anything left to do?", or runs /whats-next.
---

<!-- claude-playbook skill v1.6.0 -->

# What's next

Gathers every sign of outstanding work, weighs it, and offers the strongest
candidates as an `AskUserQuestion` multiple choice. It only looks: it
changes nothing until the user picks.

## 1. Gather

From the repo's root, in one read-only command:

```bash
bash "<this skill's folder>/scripts/whats-next-context.sh"
```

It prints, in sections:

- the version, where it can find one
- open GitHub issues (with the start of each body) and pull requests
- each plan's `## Status`, and its open questions that aren't struck through
- the "Known limitation" notes from the last six changelog versions
- the working tree, unpushed commits and the last few commits
- TODO and FIXME lines in tracked files

If GitHub can't be reached, say so in one line and carry on without the
issues. For an issue whose body is too short to act on, read the rest with
`gh issue view <n>`. If this project's `CLAUDE.md` names other upkeep (a
device build that goes stale, a weekly check), look at that too.

## 2. Weigh it

Roughly in this order:

1. **Bugs** in the issues: something broken, not a feature request. The
   user filed them, so they come first. So do issues opened by a scheduled
   check.
2. **The plan in flight:** what its Status says is next or left in the
   current phase.
3. **Feature issues**, above all ones that fit the plan in flight. Say so
   when an issue folds into the current phase.
4. **Known limitations** from the last few versions: gaps the work itself
   said it left.
5. **Open questions that block work.** Skip ones the plan's Status or a
   decision already settled. Offer only what a phase is waiting on
   (`/resolve-open-questions` works through them).
6. **Upkeep:** uncommitted work that's this session's, unpushed commits,
   plans not started (offer once, as a bigger item), and whatever upkeep this
   project's rules name.

Leave out:

- Untracked or modified files from another session. Mention them; never act
  on them.
- Anything finished since its source was written. If an issue, a to-do line
  or a limitation looks done, check the code or `git log` before offering it.

## 3. Say where things stand

In a few short lines: the version, the plan in flight and its phase, how
many issues are open (naming any bugs), and anything that needs attention.
No table of everything gathered. The choices are the point.

## 4. Offer the choices

With `AskUserQuestion`:

- **One to three questions**, each a category with two to four options:
  **Issues** (labelled with the number, such as `#12 Search is slow`),
  **Plan** (next steps in the plan in flight, and known limitations) and
  **Upkeep**. Drop a category with nothing worth offering; use one question
  when there are only a few candidates.
- `multiSelect: true`, so several can be picked at once.
- Labels of one to five words. The description says what doing it means in a
  sentence: the result the user would see, and the size of the change when
  that's clear.
- The single best pick goes first in its question, with " (Recommended)" on
  its label, and the model it needs when the project's rules say which.
  Only one Recommended across all the questions.
- Headers of 12 characters or fewer: `Issues`, `Plan`, `Upkeep`.

## 5. Do what was picked

Start with the Recommended one if it's among them. Each piece of work
follows the project's `CLAUDE.md` as usual (an issue, the version and
changelog, tests, commit, push), and ends with the usual next-step choices.
