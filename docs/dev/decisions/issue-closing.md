# Issues close when their change is released

## 2026-11-14: close on release, not on Matthew's check

**Decided:** 2026-11-14, by Matthew (#97). **Status:** accepted. Replaces the release-issue exception decided the same day in #84.

**The question:** when does an issue close? Until now every issue waited for Matthew's OK after he had tried the change. The one exception (#84) was release issues, which closed once their release and image build were done. Over the 2026-11-14 usability work this left more than a dozen built and released issues open at once, waiting on checks.

**Options considered:**
- Keep asking before closing each issue: Matthew's check stays the gate, but released work piles up as open issues and every turn ends with a "close these?" question.
- Close release issues only (#84): it tidies the release bookkeeping but not the change issues.
- Close every issue once the version carrying it is released: chosen. An issue can be reopened, so closing isn't a loss. Matthew's check still happens; if something's wrong he reopens the issue or files a new one.

**The decision:**
- When a GitHub Release is published and its "Build and push to GHCR" run has passed, the session closes the release issue and every issue that release shipped. Each gets a comment naming the release.
- Work that never goes through a release (docs, tooling, plans) closes when it's pushed.
- Plans: a phase issue closes when its release is out; the tracker closes when the last phase's release is out.
- An issue whose work isn't finished stays open.

**What it changes:** `CLAUDE.md` ("The end of a turn", "Work from an issue" step 5, "Plans", "Issues: agents and tools"), the same rules in claude-playbook, and `~/.claude/CLAUDE.md`.
