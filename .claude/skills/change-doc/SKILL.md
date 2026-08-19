---
name: change-doc
description: Generate a detailed file-by-file explanation document for a change, with mermaid diagrams, so the user can understand what was built and why. Use after finishing a feature, bug fix, refactor, or PR, or when the user types `/change-doc`. Trigger phrases include "explain what you did", "document the changes", "file by file breakdown", "what did we change", "write it up".
---

You are writing a document that explains a completed change to the user, file by file.

The audience is the person who asked for the work. They want to understand **what
each file does, what changed in it, and why it was done that way** — not a diff
restatement. Assume they will read this weeks later, or hand it to a teammate.

## 1. Gather the real change

Never work from memory or assumption. Establish the exact scope first:

- `git log --oneline <base>..HEAD` — the commits in scope
- `git show --stat --format="" <sha>` or `git diff --stat <base>...HEAD` — the file list
- `git diff <base>...HEAD` — the actual changes

If the work is committed, prefer the commit SHA as the source of truth. If it is still
in the working tree, use `git status --short` plus `git diff`.

For any file whose purpose is not obvious from the diff alone, **read the file and its
neighbours** so you can explain what it is for, not just what changed. A file-by-file
doc that cannot say what a file does has failed at its job.

## 2. Where to save it

Default to the repo's **parent directory**, named `<Topic>-Files-Changed.md` — for
example `~/ag-projects/UID-Files-Changed.md`. These are personal understanding
documents, not repo deliverables, so they usually should not be committed.

Ask only if the location is genuinely ambiguous. If the user names a path, use it.

## 3. Structure

Follow this shape. Skip sections that would be empty rather than padding them.

**Title + one-line scope.** Commit subject, SHA, branch, PR link. Then the totals:
`N files · +X / −Y — A new, B modified`.

**The shape of the change.** A short table mapping *what had to happen* onto *which
group of files*. This is the orientation paragraph — a reader who stops here should
still understand the change.

**Grouped file sections.** Group by **purpose, not alphabetically**. Typical groups:
new files, core logic, wiring, configuration/plumbing, tests, incidental fixes. For
each file give:

- Path as a heading, with `+X / −Y · new` or line count
- What the file **is** and what it is for
- What changed and why
- Any decision a reviewer would question, stated plainly

**Verification.** The commands run and their results. Real output, not aspiration.

**Not in this change.** Deliberate exclusions, follow-up tickets, known gaps. This
prevents a reader assuming something was covered when it was not.

**Diagrams.** Always last — see below.

## 4. Diagrams (required, at the bottom)

Two mermaid diagrams, in this order, after all prose:

1. **Architecture / structure diagram** — how the changed pieces relate to each other
   and to what surrounds them. `flowchart` with subgraphs works well. Highlight the
   files that changed so they stand out from existing context.
2. **Flowchart** — the runtime flow or decision logic the change introduces. Show the
   conditional paths, especially feature flags, fallbacks, and error branches.

Rules:

- Use ```mermaid fenced blocks so they render on GitHub.
- Label edges with what actually passes along them (a cookie, an id, an event), not
  just arrows.
- Style the changed nodes distinctly, and say in a caption which is which.
- Keep each diagram to roughly 12 nodes. Two clear diagrams beat one crowded one.
- Do not invent structure to fill the diagram. If the change is genuinely linear, a
  simple flowchart is the honest picture.

## 5. Quality bar

This is what separates a useful document from a generated one:

- **Explain why, not just what.** "Added `contactID` to the event type" is a diff.
  "NetSuite adopts this id and echoes it back, which is how the return path re-anchors
  the record to a person" is an explanation.
- **Surface the decisions.** Anywhere you deviated from a spec, chose between two
  approaches, or did something that looks wrong at first glance — say so and give the
  reason. These are the parts the user most needs.
- **Name the constraint.** If a change exists only because of a project convention, an
  env-var pattern, or a framework quirk, say which one. "Required because the code
  reads it via `process.env` directly" beats "added for completeness".
- **Cross-check coverage before finishing.** Every file in the diff must appear in the
  document. Verify it mechanically:

  ```bash
  for f in $(git show --stat --format="" --name-only <sha>); do
    grep -q "$(basename "$f")" <doc> && echo "ok   $f" || echo "MISS $f"
  done
  ```

- **Be honest about what is untested.** State the limits of verification explicitly.
- **No padding.** If a file changed by one line, one sentence is the right length.
  Match the surrounding project's tone and the user's stated preferences.

## 6. After writing

Report to the user:

- Where the file was saved
- How the sections are grouped
- The specific decisions you documented, so they know what to look at
- Anything you could not determine and want them to confirm
