---
name: orchestrate
description: Run one task as an orchestrator - this thread splits it into pieces, hands them to background subagents and (for long self-contained pieces) a capped number of child sessions, gates every start on the machine's live memory, CPU, disk and shared locks so a small Mac isn't swamped, and keeps all talk with the user in this one thread (workers never ask the user; their questions and reports come back here). Only the orchestrator commits. Use when the user says "orchestrate this", "work on this in parallel", "split this up and run it", "use sub threads / subagents for this", "coordinate the Mac's resources", or runs /orchestrate. Argument - the task (or an issue or plan phase); "status" to show what's running on the machine.
---

<!-- claude-playbook skill v1.14.2 -->

# Orchestrate

This thread is the only one the user talks to. It plans the task, starts
workers only when the machine has room, relays their questions, checks their
work, and ships it once. Workers never ask the user anything, never commit,
push, bump a version, install on a device or close an issue.

`O` below is `<repo root>/.claude/skills/orchestrate/scripts/orchestrate.py`
(absolute path in worker briefs). It shares one state folder with every
session on the machine, so its limits hold across threads and projects.
Limits and extra locks come from `.claude/orchestrate.json` (defaults in the
script). `/orchestrate status` is just `O status`, reported in a few lines.

## 1. Take the task

- Work from an issue (or plan phase) as the project's rules say, and set the
  session title to it. Get this session's id (`get_session`, `ccr.id`; no
  claude-code-remote tools: a short name) - it's the **owner** of every slot.
- Settle design calls first, here, with AskUserQuestion. A worker never makes
  one.

## 2. Split it

Break the task into pieces, each with: what it produces, the files it
touches, what it waits on, and its weight. Post the plan as a short table.

| Piece kind | Who | Weight |
| --- | --- | --- |
| Find, read logs, mechanical edits | subagent, cheapest model the project allows | light |
| Routine code, tests, docs, review | subagent, the project's default model | light; its build/test runs go through `O heavy` |
| Long, self-contained (many steps, own issue) | child session (`create_session`) | session slot |
| Design, tricky debugging, final check, release | this thread | - |

- Two pieces that edit the same file never run at once.
- Code-editing pieces run one at a time in the main checkout. Use a worktree
  (`isolation: "worktree"`) only when two must overlap and touch different
  files: a worktree builds from scratch, which is a heavy job and costs disk.
- Builds, test runs and anything using a simulator or emulator are **heavy**:
  one at a time machine-wide, always as
  `O heavy --label "<piece>" -- <command>` (inside it, still the project's
  simulator wrapper when it has one).

## 3. Start what fits

Before each start, `O status`. Then for the next ready piece:

1. `O claim worker|session --label "<piece>" --owner <owner>` - prints a slot
   id; exit 75 means the machine is full: start nothing, and wait for a
   running piece to finish (or, when only other sessions fill it, re-check in
   ~10 minutes with `send_later`). `--force` only when the user says so.
   A heavy job that `status` marks POSSIBLY STUCK belongs to someone else:
   tell the user (its age, pid, command) and stop it only on their OK.
2. **Subagent:** the Agent tool, `run_in_background: true`, the model by the
   project's rules, the prompt from [worker-brief.md](worker-brief.md).
3. **Child session:** `create_session` with the brief as `prompt`, its
   "Child sessions" lines as `append_system_prompt`, a title of
   `<project prefix>↳ <piece>`, tags `["orchestrate:<owner>"]`, the same
   environment. In a bridge (Remote Control) environment children run on
   this machine, in its checkout; they count against `max_sessions` either
   way. The Claude app lists them under Recents, not in the orchestrator's
   group: tags and `create_session` options don't change that, so the title
   prefix is what puts them beside it.
4. Tell the user in one line: what started, on what, and what's waiting.

## 4. While they run

- Don't poll. Subagents notify when done; children `send_message` here when
  done or blocked. Set one `send_later` fallback (~30 min) per child, delete
  it (`delete_trigger`) once the child reports, and if it fires first, check
  the child with `get_session` and `list_events`.
- A message from the user mid-run is answered here without stopping the
  workers; change a running piece only if the message changes its goal.
- **A question from a worker** comes to the user here, batched with any
  others, as AskUserQuestion (say which piece asks). Answer a child with
  `send_message`; a subagent with `SendMessage` (or a new one with the
  answer, if it already stopped).
- **Each piece that finishes:** `O release <slot>`; log the run where the
  project logs agent runs; check the work (read the diff, run its check under
  `O heavy`); one line to the user; then start the next ready piece (step 3).
- A piece that failed or drifted: stop it (`TaskStop` / `interrupt_session`),
  say what went wrong, retry once with a sharper brief or take it over here.
  Never get past a failure destructively.

## 5. Bring it together

- Merge any worktrees, then run the project's tests once (`O heavy`).
- Do the project's release routine once (version, changelog, commit naming
  the files, push, device install), then comment on and close the issues as
  its rules say.

## 6. Wrap up

- `O release --owner <owner>` (frees anything left), and `O status` to show
  the machine is clear.
- Report: a table of pieces - who did each, on what model, the outcome - and
  what's left.
- End with choices; offer archiving finished child sessions
  (`archive_session`) only as a choice, never on your own.
