---
title: rubricator — watch mode
status: shipped as E1 — SSE, not polling
date: 2026-08-19
---

# Watch mode — refresh when the file changes

> Keep a plan open while an agent rewrites it, and have the window follow along —
> showing you *what changed* rather than making you re-read it.

## The constraint that decides the design

`fetch()` of a `file://` URL is **blocked in Chrome**. Measured, not assumed: it's the
same restriction that pushed the review layer towards clipboard export in the first place.
A static `file://` page cannot poll its own source, full stop.

So watch mode means the page is **served**, over the same `127.0.0.1` machinery that
`--hook` and `--review` already use: random port, path token, single-tab window, auto-close.
That part is built and tested; watch mode is a new entry point into it, not new plumbing.

One alternative, since the API is available on `file://`: hold a `FileSystemFileHandle`
from `showOpenFilePicker` and poll it. Rejected — it costs a file-picker click per document
and Chrome may not persist the permission across reloads. A flag is better than a dialog.

## Two levels

### Level 1 — reload and restore *(~40 lines)*

On change: stash `scrollY` in `sessionStorage`, reload, restore. Annotations already
survive — they live in local storage and re-anchor by content.

Honest about the cost: a visible flash, mermaid's 3.4 MB bundle re-parsed on every save,
and search state lost.

### Level 2 — re-render in place *(~1–2 hours)* ← build this

The server pushes the new markdown over SSE; the page re-runs the render pipeline into the
existing DOM. Scroll, search, theme, panel width and the open composer all survive. Nothing
blinks.

The work is a refactor, not new logic: the render pipeline is currently a run-once IIFE and
needs to become a callable `render(markdown)`. Then, on each update, three things rebuild —
the line map (`review.js`), the block index and markers, and the search index (`ui.js`).

## Why it's worth level 2: changed-section badges

The refresh isn't the point. The point is what we can do *at the moment of change*.

Re-anchoring already exists, so on every update the page can hash each section of the new
source, compare against the previous render, and badge exactly what moved:

- section changed → an amber marker in the gutter and a dot in the outline
- your notes on untouched sections stay put
- your notes whose text is gone flip to *resolved*, as they already do

The agent rewrites a 3,000-word plan; instead of re-reading it you see three marked
sections and your still-open questions beside them. That is the Tier 1 feature from
`review-design.md`, and watch mode is most of the way there.

## Where it does and doesn't matter

**Not needed for the hook loop.** There the agent is *blocked* waiting for you, so the file
cannot change under you, and the next plan opens a fresh window.

**Needed for the ambient case:** `md --watch spec.md` open on a second monitor while the
agent works. That's the scenario worth building for.

## Phases

1. `md --watch FILE` serving + mtime polling + SSE, level-1 reload. *(half a session)*
2. Extract `render(markdown)`; swap to in-place re-render. *(one session)*
3. Per-section hashing → changed badges in gutter and outline. *(half a session)*
4. Reconnect handling: server gone → banner, not a dead page. *(small)*

## Open questions

- [ ] Poll interval, or `fswatch`/`FSEvents` when available? Polling `mtime` every 300 ms
      costs nothing and has no dependency — probably just do that.
- [ ] What if the file is deleted or briefly truncated mid-write? Debounce, and ignore an
      empty read rather than blanking the page.
- [ ] Should `--watch` be implied when the file is inside a git worktree and an agent is
      running? No — implicit modes surprise people. Keep it a flag.
- [ ] Does the window stay open when the server exits, showing a "disconnected" banner, or
      close itself? Banner: losing a page of annotations to a dropped socket would be rude.
