---
name: resolve-open-questions
description: Work through this project's open questions with the user in short rounds - the ones blocking work first - offering options with their consequences and a recommendation, then record each answer as a decision and take it off the list. Use when the user says "let's settle the open questions", "what's still undecided?", "resolve the questions on <plan>", when a phase is waiting on a choice, or when they run /resolve-open-questions. Argument - a plan, an area, or nothing for whatever blocks work.
---

<!-- claude-playbook skill v1.6.0 -->

# Resolve open questions

Open questions are choices that are the user's to make and aren't made yet.
They live in a plan's `## Open questions` section, in an open-questions
file if the project keeps one, or on an issue. This skill gets them
answered a few at a time and makes sure each answer is written down where
it will be found.

## 1. Pick the batch

Read the open questions in scope (the argument; otherwise every plan's
section), with the plan's Status and the docs they touch. Leave out the ones
already struck through or settled by a later decision. Take first the ones
a phase is waiting on, then the ones for the next phase. Choose up to four
related questions for a round.

## 2. Ask

One AskUserQuestion call for the round, a question each:

- two to four concrete options, the one you'd pick first, marked
  "(Recommended)"
- in each option's description, what choosing it means in a line: what the
  user would see, and what it costs to build
- a `preview` when comparing layouts, wording or numbers side by side

"Not sure yet" is a fine answer: the question stays open, with a note of
what would help decide it. Never record a choice the user didn't make.

## 3. Record each answer

For every question answered, follow the `/record-decision` skill: a
decision page, the rule or doc it changes, and the question moved from open
to resolved with a link. Closely related answers can share one page. If the
answer changes a phase (it's bigger, smaller, or not needed), update the
plan's Status and the phase's issue too.

## 4. Another round, or stop

Show what's still open in scope and ask: **another round**, **a different
plan or area**, or **stop here**. When stopping, list the decisions made,
with links, and what they unblock.

It changes tracked files, so work from an issue as the project's rules say:
the plan's tracker, or the phase the questions were blocking.
