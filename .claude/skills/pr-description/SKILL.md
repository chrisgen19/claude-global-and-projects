---
name: pr-description
description: Generate a structured PR description and ready-to-use `gh pr create` command. Use when the user asks to create a PR, write a PR description, or types `/pr-description`.
---

You are generating a pull request description for the current branch.

## Steps

1. **Detect the base branch** — check for `main`, `master`, or `develop` (in that order).

2. **Gather context:**
   - Run `git log <base>..HEAD --oneline` to get all commits on this branch.
   - Run `git diff <base>...HEAD --stat` for a file-level summary.
   - Run `git diff <base>...HEAD` for the full diff (skim for key changes).

3. **Generate the PR description** with this structure:

   - **Title** — short, under 70 chars, conventional commit style (e.g., `feat(cart): add discount code validation`).
   - **Summary** — 1–3 bullet points explaining what changed and why.
   - **Changes** — group by area when there are multiple concerns:
     - Frontend, API, Database, Config, Tests, Docs, etc.
     - Use bullet points with file paths where helpful.
   - **Test plan** — checklist of how to verify the changes work.
   - **Notes** — only include if relevant:
     - Breaking changes
     - Migration steps
     - New environment variables needed
     - Dependencies added/removed

4. **Output a ready-to-use command:**

   ```bash
   gh pr create --title "the title" --body "$(cat <<'EOF'
   ## Summary
   - ...

   ## Changes
   ### Area
   - ...

   ## Test plan
   - [ ] ...

   ## Notes
   - ...
   EOF
   )"
   ```

## Rules

- Follow the conventional commit style from CLAUDE.md for the title.
- Keep the summary focused on the "why", not just the "what".
- If the branch has only 1 commit, the PR can be simpler (skip grouping by area unless the diff is large).
- If there are uncommitted changes, warn the user before generating.
- Never push or create the PR automatically — only output the command for the user to review and run.
