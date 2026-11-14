---
name: session-title
description: Turn automatic session renaming on or off for this thread, show whether it's on, or rename the session now. Claude renames each Claude Code Remote session to match the work being done (on by default, see the "Session titles" rule in CLAUDE.md, from claude-playbook); this skill switches that off or back on for the current session only. Use when the user says "stop renaming this session", "turn titles back on", "rename this session", "is auto-title on?", or runs /session-title. Argument - on | off | status | a title to set now (empty = rename now from the work).
---

<!-- claude-playbook skill v1.0.0 -->

# Session titles, per thread

Claude keeps each remote session's title in step with the work (the rule is
"Session titles" in CLAUDE.md, from claude-playbook). It's on for every session
unless that session has been switched off here. The switch lives in a file
per session, so it lasts through `/clear` and container restarts:

- Off: `~/.claude/session-titles/off/<ccr session id>` exists.
- On: no such file (the default).

The ccr session id is the `ccr.id` from `get_session` (claude-code-remote MCP
server) called with no `session_id`, e.g. `session_0118…`. It is also the id
`set_session_title` takes. Don't use `$CLAUDE_CODE_SESSION_ID` (a local id).

## Steps

1. Call `get_session` with no arguments. Note `ccr.id` and `ccr.title`.
   If the claude-code-remote tools aren't available, say this only works in
   a Claude Code Remote session and stop.
2. Act on the argument, in one Bash call:
   - `off`: `mkdir -p ~/.claude/session-titles/off && touch ~/.claude/session-titles/off/<id>`.
     Leave the current title as it is.
   - `on`: `rm -f ~/.claude/session-titles/off/<id>`, then rename the session
     now (step 3).
   - `status` or no argument: `test -e ~/.claude/session-titles/off/<id> && echo off || echo on`.
     With no argument and the switch on, also rename now (step 3).
   - Anything else is a title: set it as given with `set_session_title`
     (step 3 without writing your own). Doesn't change the switch.
3. Rename: `set_session_title` with `session_id` = `ccr.id` and a title
   following the "Session titles" rule in CLAUDE.md: an
   issue's number first (`#183: User Feedback: Update feedback`), and for a
   plan's phase the slug and phase out of the total too
   (`#179: tab-bar-magnifier: 3/4: The pill grows, with names`).
4. Reply in one or two lines: on or off for this session, and the title now.
