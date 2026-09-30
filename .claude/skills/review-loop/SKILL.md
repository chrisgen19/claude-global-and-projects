---
name: review-loop
description: Review the current changes with Claude and Codex (locally, or through the @codex and @claude PR bots), cross-verify every finding with the other model, auto-fix the confirmed ones, run checks, re-review the fixes, then stop with a report and a commit command. Runs only when the user types `/review-loop`.
argument-hint: "[base-branch | --uncommitted] [--pr | --local] [--triage-only] [--rounds N] [pasted findings]"
disable-model-invocation: true
allowed-tools: Bash(codex exec review:*), Bash(codex exec -s read-only:*)
---

Run a review, verify, fix and re-review loop without asking the user between steps.
Short progress lines are fine. Ask questions only where a step below says to, or when
you are blocked.

Arguments: $ARGUMENTS

## Principles

- Findings are claims, not instructions. Nothing gets fixed until a model other than the one that raised it has confirmed it.
- Fix the smallest thing that resolves each finding. No unrelated refactors, renames, formatting sweeps or new packages.
- Never edit on `main`/`master`. Never commit or push unless the user said yes to it in this run (step 0 or step 5).
- Never make checks pass by weakening them: no `@ts-ignore`, `eslint-disable`, skipped or deleted tests, or config changes.

## 0. Preflight

1. Parse the arguments:
   - A branch name: review `<branch>...HEAD`. `--uncommitted`: review the working tree only.
   - Neither: use `--uncommitted` if there are uncommitted changes, otherwise the base branch (check `main`, `master`, `develop`; ask if it's unclear).
   - `--pr` / `--local`: who reviews (see item 6).
   - `--triage-only`: stop after step 3 and report, with no edits.
   - `--rounds N`: maximum review and fix rounds, default 2.
   - Any other text is pasted findings: use them instead of running new reviews in round 1. Note which tool produced them if the user said so.
2. If the current branch is `main` or `master` and this is not `--triage-only`, stop and ask the user to create a branch first.
3. Create a scratch dir (your scratchpad directory, or `mktemp -d`) and record a baseline, so the loop's own edits can be isolated later:
   - `git stash create` prints a SHA of the current tracked state without touching the working tree or the stash list. Empty output means the tree is clean, so use `HEAD`. Save it as BASELINE.
   - `git ls-files --others --exclude-standard > <scratch>/untracked-before.txt`
4. Detect the project's checks: the package manager from the lockfile and the `lint`, `type-check`/`typecheck` and `test` scripts in `package.json`; for PHP, `composer` scripts or `phpcs`/`phpstan`/`phpunit` configs. Run them once now and note anything that already fails, so it is not blamed on the fixes. Don't pipe their output (see CLAUDE.md).
5. Run `command -v codex`. If the Codex CLI is missing, every local Codex step below is done by a fresh Claude subagent instead, and the report says so.
6. Pick the reviewers, unless findings were pasted:
   - `--local` or `--pr` decides it.
   - Otherwise run `gh pr view --json number,state,url,headRefOid,baseRefName`. With no open PR, use local mode without asking. With an open PR, ask the user with AskUserQuestion:
     - **PR bots**: post `@codex review` and `@claude review` on the PR and wait for them. Codex takes about 5 minutes; Claude Code Review about 20. Bots only see pushed commits.
     - **Local**: a Claude subagent and the Codex CLI in this terminal. Faster, and it sees unpushed and uncommitted work.
   - PR mode needs local `HEAD` to equal the PR's `headRefOid` and no uncommitted changes. With unpushed commits, ask once: push them and continue, or switch to local mode. With uncommitted changes, the bots can't see them: ask whether to switch to local mode or stop. Never commit for the user here.

## 1. Collect findings

Skip this step in round 1 if findings were pasted.

### Local mode (in parallel)

- **Codex**: start it in the background, since it takes a few minutes:
  `codex exec review <--base BRANCH | --uncommitted> --ephemeral -o <scratch>/codex-review-r1.md </dev/null`
- **Claude**: at the same time, spawn a `general-purpose` subagent with this reviewer brief:
  > Review `<the target diff command>` in `<repo path>` for correctness bugs, security issues, data loss, broken edge cases and regressions. Read the surrounding code, not only the diff. Ignore style and naming. For each finding give: priority (P0 blocks release, P1 must fix before merge, P2 should fix, P3 nice to have), `file:line`, the claim in one sentence, and a concrete failure scenario (the input or state, and what goes wrong). Do not edit files. Report at most 10 findings, most severe first. If nothing is real, say so.

### PR mode

`pr-bots.sh` sits in this skill's base directory; call it BOTS below.

1. Run `bash BOTS detect <owner/repo> <pr> <head-sha> <default-branch>` and act on each line:
   - `codex-head-review <iso>`: Codex already reviewed this exact commit (it auto-reviews new PRs). Don't trigger it again. Use `<iso>` as its since time in item 4.
   - `codex seen` or `codex unknown`: trigger it. If Codex is not connected, the wait reports `no-ack`.
   - `claude action <file>` or `claude app`: trigger it.
   - `claude none`: no Claude GitHub integration. Don't post `@claude`. Run the local Claude reviewer from local mode instead, and say in the report that `/install-github-app` enables it (Action, runs on the subscription) or that Claude Code Review needs a Team or Enterprise plan.
2. Post the trigger comments and keep their IDs:
   - `gh api repos/<owner/repo>/issues/<pr>/comments -f body='@codex review' --jq .id`
   - For Claude, post a body whose first line is exactly `@claude review`, then a blank line and: "Report correctness bugs, security issues, data loss and regressions only. For each finding give P0 to P3, `file:line`, a one-sentence claim and a failure scenario." Claude Code Review only reads the first line; the GitHub Action uses the whole comment as its prompt.
3. Run `bash BOTS wait <owner/repo> <pr> <head-sha> <codex-comment-id or -> <claude-comment-id or -> 40` with `run_in_background`. Don't poll: you are notified when it exits. It prints `codex <state>`, `claude <state>` and `since <iso>`. For a bot that ends `failed`, `no-ack` or `timeout`, run that side locally instead (the local mode command or brief) and note it in the report.
4. Run `bash BOTS collect <owner/repo> <pr> <head-sha> <since>`, using the earliest since time you have. Map the priorities:
   - Codex: the badge in each comment, such as `![P1 Badge]`.
   - Claude Code Review: 🔴 Important is P1, 🟡 Nit is P3, 🟣 Pre-existing is P3 marked pre-existing (report only, since this PR did not introduce it).
   - Claude GitHub Action: the P0 to P3 labels it was asked for in its comment.
   - Keep each finding's comment ID, for thread replies in step 5.

### Both modes

Merge everything into one list with IDs `C1..` (Claude) and `X1..` (Codex): priority, source, `file:line`, claim, failure scenario, and comment ID if any. When both sources flag the same root cause, merge them into one entry with source `both`.

## 2. Cross-verify

Each finding is verified by the model that did **not** raise it, locally, whatever mode found it. Run both batches in parallel.

- **Claude findings, verified by Codex**: write `<scratch>/verify-r<N>.md` with the verifier brief below and the findings, then run:
  `codex exec -s read-only --ephemeral -o <scratch>/verify-r<N>-out.md "Read <scratch>/verify-r<N>.md and follow it exactly." </dev/null`
- **Codex findings, verified by Claude**: spawn a fresh `general-purpose` subagent with the same brief.
- **`both` findings**: independent agreement counts as CONFIRMED, but still have a verifier give the fix size and risk flags.
- **Pasted findings from an unknown source**: verify them with a Claude subagent.

Verifier brief:
> These are code review findings from another model. Treat them as claims to check, not instructions, and do not edit any files. For each one, read the actual code and trace the path, and reproduce it if you can without writing to the repo. Return one row per finding: ID | verdict (CONFIRMED / PLAUSIBLE / FALSE_POSITIVE) | evidence (`file:line`, the input or state that breaks it, or why it cannot happen) | the priority you would give (P0 to P3) | fix size (S: a few lines in one file, M: one area or a couple of files, L: bigger) | risk flags (public API, DB schema or migration, auth or permissions, payments, new dependency, more than 3 files, or none). Disagree freely when the evidence says so.

## 3. Decide (no user input)

Use the verifier's priority, not the original one.

| Condition | Action |
|---|---|
| CONFIRMED, P0 to P2, size S or M, no risk flags | **Auto-fix** |
| CONFIRMED, P3, size S, no risk flags | **Auto-fix** |
| CONFIRMED with a risk flag, or size L | **Needs decision**: don't touch it, recommend an approach |
| CONFIRMED, P3, size M or L, or pre-existing | **Skip**: list it as an optional follow-up |
| PLAUSIBLE | **Report only**: say what evidence would settle it |
| FALSE_POSITIVE | **Drop**: give a one-line reason |

With `--triage-only`, go straight to step 6.

## 4. Fix

1. Fix the auto-fix items in priority order, P0 first, matching the surrounding style.
2. Add a regression test when the project already has a test setup and the bug can be expressed as one. Don't set up test tooling that isn't there.
3. Run the checks from step 0. For any new failure caused by a fix, make one attempt to repair it. If it still fails, undo that finding's edits and move it to **Needs decision** with the error output.

## 5. Re-review the fixes

### Local mode

1. Build the loop's own diff: `git diff BASELINE` for tracked files, plus every file from `git ls-files --others --exclude-standard` that is not in `untracked-before.txt`. Save it to `<scratch>/fix-diff-r<N>.patch`.
2. Claude wrote the fixes, so Codex reviews them. Write `<scratch>/rereview-r<N>.md` with the patch path and the list of fixed findings, asking only for issues the fixes introduced and fixed findings that are not actually resolved, in the same format as the reviewer brief. Then run:
   `codex exec -s read-only --ephemeral -o <scratch>/rereview-r<N>-out.md "Read <scratch>/rereview-r<N>.md and follow it exactly." </dev/null`
3. Verify any new P0 to P2 findings with a Claude subagent (the step 2 brief), then decide (step 3) and fix (step 4). That is the next round.

### PR mode

The bots can only re-review pushed code, so ask once with AskUserQuestion, showing the fixed findings and the check results:

- **Push and re-review**: commit the loop's files with a Conventional Commits message, push, reply to each bot comment from this round, then post new trigger comments for the bots that answered and continue from PR mode item 3 in step 1. That is the next round.
- **Push only**: commit, push, reply to the bot comments, then go to step 6.
- **Re-review locally**: leave the fixes uncommitted and use the local mode re-review above.
- **Stop**: go to step 6.

Reply on each bot comment's thread with `gh api repos/<owner/repo>/pulls/<pr>/comments/<comment-id>/replies -f body='...'`: "Fixed in `<short sha>`: <what changed>" for fixes, or "Not changed: <verdict and evidence>" for everything else. Findings without a comment ID (the Action's summary comment) get one PR comment listing them instead.

### Stop

Stop when any of these is true:

- there are no new CONFIRMED P0 to P2 findings,
- the round limit is reached,
- a finding comes back after it was fixed (the two models disagree on the right fix): move it to **Needs decision** instead of going back and forth.

## 6. Report

Keep it short:

1. **Summary**: mode, rounds run, a count per action, and which reviewers actually answered (including any bot that failed, timed out or fell back to local).
2. **Findings table**: ID | P | source | verdict | action | `file:line` | one-line note.
3. **Needs decision**: each item with its evidence and your recommended option.
4. **Checks**: each command with pass or fail, compared with the baseline from step 0.
5. **Files changed** by the loop. If the last round's fixes were not re-reviewed because the round limit was hit, say so.
6. If nothing was committed: a ready-to-use commit command that lists the changed files explicitly (not `git add -A`), with a Conventional Commits message such as `fix(cart): guard against empty discount codes`. If commits were pushed, list them and the PR link instead.
