---
name: deep-dive
description: Research a system, integration or problem thoroughly, then produce a comprehensive explanation document as both Markdown (mermaid diagrams) and a print-ready PDF (inline SVG diagrams). Use when the user wants something investigated and written up properly, asks for a PDF, or types `/deep-dive`. Trigger phrases include "research and investigate", "write this up properly", "comprehensive doc", "make a PDF", "explain the whole thing", "document this integration".
---

You are producing a document that explains something complex well enough that the user,
and anyone they forward it to, understands it without needing you.

Two outputs: a `.md` (mermaid diagrams, renders on GitHub and Confluence) and a `.pdf`
(inline SVG diagrams, print-ready). Same content, different diagram technology.

This is not a summary of what you were told. It is an investigation.

## 1. Research before writing

**Trust source over documentation.** Specs go stale; code does not. Every load-bearing
claim should be traced to something you verified yourself.

- Read every document the user gives you, plus the ones they reference. Follow the
  chain. Note publication dates and versions.
- **Establish supersession explicitly.** When several documents cover the same thing,
  work out which one wins and say so. Parent/child page relationships, "this
  supersedes" notes, and edit dates all help. Never blend a superseded spec with a
  current one.
- **Cross-check every claim against the actual source.** If a doc says a service is
  not deployed, look at the deploy script. If it says a field is parsed, find the
  parser. Contradictions between docs and code are among the most valuable things you
  will find, and they are common.
- **Verify empirically where you can.** `curl` the URL. Run the function. Submit the
  form. A doc saying an endpoint returns JavaScript is not the same as observing
  `200 text/javascript`.
- **Note what you could not verify**, and why. This is as important as what you could.

Use the tools available: Confluence/Jira MCP, `gh`, `curl`, `vercel`, reading adjacent
repos on disk. If a related codebase exists locally, read it rather than guessing at
its behaviour.

## 2. Structure

Adapt to the subject, but this order works and earns its keep:

1. **The problem** — what is broken or missing, with evidence. Numbers if they exist.
   Include the root cause if you found one, with the reproduction.
2. **End-to-end flow** — the main diagram. Where does the work sit relative to
   everything around it.
3. **Why the design is what it is** — the non-obvious structural reason. Often "all
   these paths converge on one function", or "this boundary is where X changes hands".
4. **What changed / what exists** — the concrete inventory, with a table.
5. **Alignment** — if there is a spec, a line-by-line conformance table with an
   explicit status per row. Every deviation gets its own subsection: what the spec
   said, what you did, why, and what the effect is.
6. **Verification** — commands, output, live results. Then a **limits** subsection
   stating plainly what was *not* tested.
7. **Outstanding** — a table of open items with an **owner** column. Separating "ours"
   from "theirs" is usually the most actionable thing in the document.
8. **Risk and rollback** — kill switches, what is safe to merge, how to undo.
9. **Diagrams** — if they did not fit inline.

## 3. Quality bar

- **Cite file:line for verifiable claims.** `functions/index.js:1242` lets a reader
  check you in one grep. Unverifiable assertions about other systems are the main way
  these documents go stale.
- **Quote the source when it matters.** A short verbatim quote from a spec or a code
  comment settles arguments that paraphrase does not.
- **Record contradictions rather than resolving them silently.** If a spec's code and
  its stated example disagree, say so and say which you followed.
- **Own the uncertainty.** "Appears deployed, based on X; the real gate is Y" beats
  either false confidence or vagueness.
- **Separate boundaries.** Make it unmistakable which parts are the user's
  responsibility and which belong to another team.
- **No filler.** Every section should carry information a reader would act on.

## 4. Diagrams

**In the `.md`:** mermaid in ```mermaid fences. Verify they parse before finishing.

**In the PDF:** hand-authored inline `<svg>`. Mermaid does not render in a headless
print, and hand-authored SVG gives better control of layout and colour.

Rules for both:

- Lanes/subgraphs for systems, so ownership boundaries are visible at a glance.
- Style the subject of the document distinctly from surrounding context, and caption
  which is which.
- Label edges with what passes along them, not bare arrows.
- **Prefer orthogonal paths to long diagonals** when crossing lanes: `M675,104 V134
  H140 V172` reads far better than a diagonal cutting through boxes. Put a small
  opaque `<rect>` behind any label that sits on a line.
- Roughly 12 nodes per diagram. Split rather than crowd.

## 5. Producing the PDF

Write an HTML file (scratchpad, not the user's repo), then:

```bash
google-chrome-stable --headless --disable-gpu --no-sandbox \
  --no-pdf-header-footer --print-to-pdf=/path/Output.pdf input.html
```

`dbus`/`UPower` errors on stderr are benign; look for `N bytes written to file`.

Print CSS that works:

```css
@page { size: A4; margin: 14mm 13mm; }
body { font-size: 9.6pt; line-height: 1.5;
       -webkit-print-color-adjust: exact; print-color-adjust: exact; }
h2 { break-after: avoid; }
pre, table, figure, .callout { break-inside: avoid; }
pre { white-space: pre-wrap; word-break: break-word; }
.pagebreak { break-before: page; }
svg { display: block; width: 100%; height: auto; }
```

Gotchas that will bite you:

- Without `print-color-adjust: exact`, backgrounds and coloured table cells vanish.
- Scope callout title styling to `.callout > b:first-child`. A bare `.callout b`
  turns every bold word inside the paragraph into a block and shreds the sentence.
- `<pre>` needs `white-space: pre-wrap` or long lines run off the page.
- Escape `<`, `>` and `&` inside `<pre><code>` blocks.

## 6. Verify the output — do not assume it rendered

Both formats, every time:

- **Page count and size:**
  ```bash
  python3 -c "import re;d=open('Out.pdf','rb').read();print(len(re.findall(rb'/Type\s*/Page[^s]',d)),'pages')"
  ```
- **Visual check:** `pdftoppm` is often not installed, and Playwright blocks `file://`.
  Serve the HTML over `python3 -m http.server` and screenshot it in the browser, then
  actually look at the image. Check diagram legibility, page breaks, and that no
  paragraph is broken by a stray style rule.
- **Mermaid check** for the `.md`: extract the fenced blocks into a scratch HTML page
  with `<meta charset="utf-8">` and mermaid from a CDN, then assert each `pre.mermaid`
  contains an `svg`. Without the charset the page mangles UTF-8 and you will chase a
  bug that is not there.
- Stop any background servers and delete scratch artefacts from the user's repo.

## 7. Keeping it current

If the work continues after the document is written, **update it rather than letting it
drift**. Re-verify claims that new findings touch, and regenerate the PDF from the same
HTML source so both formats stay in step. Say plainly what changed and why.

## 8. Report back

Where both files are, how the document is structured, the most important findings
(especially contradictions between docs and reality), and what remains unverified.
