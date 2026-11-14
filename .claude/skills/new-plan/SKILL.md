---
name: new-plan
description: Turn a piece of work that ships in stages into a plan in this project's plan format - read what exists, clear or park the questions that block it, ask the user how big the first slice is, what's in and what waits, and how it will be checked, then write the plan file, the labels, one issue per phase and the tracking issue, and say which model to start on. Use when the user says "plan this", "make a plan for X", "this needs phases", when a request won't finish in one session or needs their check between steps, or when they run /new-plan. Argument - what to plan.
---

<!-- claude-playbook skill v1.6.0 -->

# New plan

The plan's format is the "Plans" rule in this project's `CLAUDE.md` (the
slug, the plan file with its Status table, one issue per phase, a tracking
issue, the labels). This skill does the legwork around that rule. Where the
two differ, the rule wins.

## 1. Gather what exists

- The request, and any issue it came from.
- The plans folder: is there already a plan this belongs in, or one it
  depends on? A phase added to an existing plan beats a second plan.
- The docs and decision pages that touch it, and the code it will change
  (find the files; read in slices).
- Open questions already written down about it.

## 2. Check what blocks it

List the open questions the work can't start without. If there are any, ask
whether to settle them now (the `/resolve-open-questions` flow, on just
those) or to plan around them with a stated assumption. Never settle a
design call silently to get the plan written.

## 3. Scope it with the user (one AskUserQuestion round)

- **The first slice:** the smallest version worth having / a usable version
  / the whole thing polished.
- **In now or later:** offer the three or four parts you'd cut first, as a
  multiple choice of what waits for a later phase.
- **How it's checked:** what "done" means for a phase (tests, a look on a
  device, a number).

## 4. Write the plan file

In the plans folder, named for a slug of 18 characters at most. In this
order:

1. `## Status`: a table of the phases with their issue numbers and state.
   Under it, a `Sessions:` line (`one`, or `may span — <why>`).
2. `## Agents and tools`: one row per phase: the main session's model, the
   subagents and their models, one line of why.
3. `## Open questions`: what isn't decided yet, and which phase each blocks.
4. The plan: the goal, what's out of scope, then each phase with what it
   changes, what the user has to do, and its "Done when".

Order the phases so each one leaves the project working and shippable on its
own, with the riskiest unknown early.

## 5. Create the issues

As the rule says: the labels first (`gh label create --force`), one issue per
phase titled `[<slug>] Phase N: <name>`, then the tracking issue last,
titled `[<slug>] Plan: <title>`, with a checklist of the phases and the
plan. Put the issue numbers back into the plan file's Status table. If the
project has a script for opening issues, use it.

## 6. Hand it over

Commit the plan file as the project's rules say (it's a tracked file, so it
has an issue: the tracker). Then present the plan in a few lines: the
phases, what's parked as an open question, and which model to start the
first phase on. End by offering to start it, as the first choice.
