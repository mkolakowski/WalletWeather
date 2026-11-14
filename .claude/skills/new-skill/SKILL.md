---
name: new-skill
description: Create a new project skill in .claude/skills/ for a task that keeps coming back, asking the user about its trigger, inputs, outputs and the files it touches, then listing it in CLAUDE.md and offering a dry run. Use when the user says "make this a skill", "we'll do this for every X", when the same task has now been done twice, or when they run /new-skill. Argument - the task to turn into a skill.
---

<!-- claude-playbook skill v1.2.0 -->

# New skill

Turns a repeatable task into a skill, so the next time costs one line
instead of a re-explanation. It changes tracked files, so work from an issue
as the project's rules say.

## 1. Understand the task

From the argument and the recent conversation, draft: what the task is, when
it comes back, what a good result looks like, and which steps were the same
each time. Read one or two existing skills in `.claude/skills/` to match
their structure and tone. If a skill already covers most of it, propose
extending that one instead.

## 2. Ask (one or two AskUserQuestion rounds)

- **Trigger**: when should Claude reach for it? This drives the
  `description`, so collect the phrases the user would actually say.
- **Kind**: asks questions and writes something, checks and reports,
  plans, or runs a fixed routine.
- **Inputs**: what must be asked each time, and what can be worked out.
- **Outputs**: which files it creates or updates, and whether it commits,
  pushes or only reports.
- **Name**: offer two or three lowercase names joined by `-` (`new-<thing>`
  for a skill that creates something).

## 3. Write it

`.claude/skills/<name>/SKILL.md`:

```markdown
---
name: <name>
description: <what it does and when to use it, in the third person, with the phrases that trigger it and its arguments>
---

# <Title>

<Two or three lines: what it's for and what it never does.>

## 1. …     the steps, in order, each one checkable
## n. Wrap up    what to report, which files changed
```

- Under about 120 lines. Long reference material goes in a file beside it,
  linked from the skill.
- Steps that are mechanical (several commands, parsing, checks) go in a
  script beside the skill, using only what the project already has
  installed, and the skill calls it.
- Say what the skill must not do (commit, push, touch a locked area) as
  plainly as what it does.
- Follow the project's rules where they apply (issues, tests, shared locks).

## 4. List it

- Add it to the skills list in `CLAUDE.md`, with one line on when to use it.
- Add it to the project's skills catalog, if it keeps one.

## 5. Offer a dry run

Ask whether to run the new skill now on a real example. Fix the skill from
what that shows before calling it done.
