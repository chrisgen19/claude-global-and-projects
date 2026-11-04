---
name: handoff
description: Pick up a Claude Code session that ran in another account (dev, work, personal), for example after that account hit its usage limit, and continue what it left. Use when the user asks to continue, pick up or carry over another session or account's work, gives a session id like `fff7b432`, or types `/handoff`.
---

You are continuing work another Claude Code session started, usually in a different account. Use the `claude-handoff` command (deployed to `~/.local/bin` by `install.sh`). If it is missing, tell the user to run `./install.sh` from the `claude-global-and-projects` repo, and stop.

## Steps

1. **Find the session.** Run `claude-handoff list` from the project directory.
   - If the user gave an id or prefix, use that.
   - Otherwise take the newest session that is not this one. This session's id is in the status line (`id:xxxxxxxx`), and it is usually the newest row.
   - If the project has no sessions, try `claude-handoff list --all`: the other session may have run in a worktree.
   - If several sessions could be the one the user means, list them (account, id, last active, last prompt) and ask which.

2. **Read the brief.** Run `claude-handoff brief <id>`, and use `-n 30` if the default 12 messages don't show what was left. Never cat or read the raw `.jsonl`: transcripts run 5 to 30MB.

3. **Check it against the live state.** The transcript can be stale, and other sessions may have moved things since.
   - `git status -sb`, `git log --oneline -10`, and the branch the brief names.
   - For any PR it mentions: `gh pr view <n> --json state,mergeable,mergeStateStatus,headRefOid` and `gh pr checks <n>`.
   - Running dev servers or background jobs it started (`pgrep -af "next dev"`, etc.), and which directory they run in.

4. **Report before acting.** Say which session you found (account and short id) and what it finished, with evidence. Then list what is left as numbered steps.

5. **Ask before anything outward-facing:** merges, pushes, deletes, deploys, PR comments. Approval the user gave the old session does not carry over. The exception is when the user's message to you already asks for those steps.

## Full context instead of a brief

If the user needs the old session's whole context, not a summary, tell them to run:

```bash
claude-handoff copy <id> --to <this account>   # dev, work, personal or default
claude-<account> --resume <full id>            # from the session's directory
```

Resuming reloads the whole transcript, which uses a lot of the new account's limit, so suggest it only when the brief is not enough. Don't run `copy` yourself: the user resumes in a new terminal.
