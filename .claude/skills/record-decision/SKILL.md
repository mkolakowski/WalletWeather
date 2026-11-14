---
name: record-decision
description: Record a decision the user has settled as a dated decision page (docs/dev/decisions/, or the project's own decisions folder), link it from the rule or doc it changes, and clear the open question it answers. Use when the user settles a question ("let's go with X", "decided"), when a rule in CLAUDE.md is gathering history that belongs on its own page, or when they run /record-decision. Argument - the decision or the question.
---

<!-- claude-playbook skill v1.2.0 -->

# Record a decision

A rule in `CLAUDE.md` holds the rule and one line of why. How it came about
(the question, what was considered, what was tried) goes on a decision page,
so it isn't lost and doesn't crowd the rules. This skill writes that page
and ties it in. It changes tracked files, so work from an issue as the
project's rules say.

## 1. Pin the decision down

From the argument and the conversation, work out: the question, the options
that were considered, the choice, why, and what it changes (a rule, a doc, a
default, code).

If the choice isn't actually made yet, ask (AskUserQuestion: two to four
options, the recommended one first, one sentence of trade-off each). Never
record a decision the user hasn't made.

## 2. Find where decisions live

Use the first that exists: `docs/dev/decisions/`, `docs/decisions/`,
`docs/adr/`. If none does, create `docs/dev/decisions/`.

Follow what's already there:

- **Numbered pages** (`0007-title.md`): the next number, same padding. Never
  renumber or reuse a number.
- **Named pages** (`topic.md`): add to the topic's page if it has one, under
  a new dated heading; otherwise a new page named for the topic.
- **Front matter**, if the project's docs carry it (`audience`, `describes`,
  `checked`): fill it in the same way as the neighbouring pages.

## 3. Write the page

Keep it short and plain:

- **Title**: the decision, as a statement.
- **Decided**: the date (Eastern), and who decided.
- **Status**: accepted, or proposed if it's tentative.
- **The question**: what had to be settled, and why it came up.
- **Options considered**: each in a line or two, with what counted against it.
- **The decision**: what was chosen and why.
- **What it changes**: the rule, docs, defaults and code affected, with the
  version when there is one.

If it replaces an earlier decision, mark that one "replaced by" with a link.
Don't delete it.

## 4. Tie it in

- **The rule**: in `CLAUDE.md` (or the doc that states it), leave the rule,
  its date ("Decided 2026-11-14") and one line of why, and move the rest to
  the page. Link the page from the rule.
- **Docs**: replace any "TBD" or draft value the decision settles, and link
  the page.
- **Open questions**: if the project keeps a list (an open-questions file, a
  plan's open questions, an issue), move the item to resolved with a link.
- **Index**: add the page to the decisions index or docs index if there is
  one, in the same commit.

## 5. Wrap up

List the files changed in one short list, and commit as the project's rules
say.
