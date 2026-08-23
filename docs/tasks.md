---
title: Task register
subtitle: Every phase, and where each plan stands
status: living
---

# Task register

One line per task, an explicit *done when*, and nothing tracked that git cannot
confirm. This is the current document; the plans are the reasoning behind it and
are not rewritten once shipped.

Legend: `[ ]` open · `[~]` in progress · `[x]` done

## The plans

| | | where it stands |
|---|---|---|
| [`architecture-plan.md`](architecture-plan.md) | one door, one shell — phases A–E | delivered. §2 and §4 describe the shell F6 replaced |
| [`workspace-plan.md`](workspace-plan.md) | the first workspace: index, correlate, trust boundary | delivered, and superseded in shape by the above |
| [`review-design.md`](review-design.md) | the annotation layer and its verbs | shipped, hardened since (F8) |
| [`watch-plan.md`](watch-plan.md) | refresh when a file changes | shipped as E1, over SSE rather than polling |
| [`conversations-plan.md`](conversations-plan.md) | reading a session | G1 shipped · G2–G3 partly · see its §7b |
| [`documents-plan.md`](documents-plan.md) | PDF and Word | H1–H4 shipped · H5–H7 open |
| [`continue-plan.md`](continue-plan.md) | adding a turn to a session from the window | agreed in shape, unbuilt |

---

## Phase A — one door, one reader ✅

Three shells, two markdown renderers, and an annotation layer that only one of
them had. Now: one grammar, one renderer, one review layer that mounts wherever
a document is opened.

- [x] **A1 · CLI grammar.** The argument decides: file → reader, directory or
      nothing → workspace. `md <dir>` stops erroring. `-w` stays as an explicit
      alias. `RUBRICATOR_BARE=readme` restores the old bare behaviour.
      *Done when:* `md`, `md .`, `md docs/`, `md file.md`, `md -`, `md -w` all do
      the right thing, `md --help` describes it, and zsh completion offers
      directories as well as files.

- [x] **A2 · Extract `render.js`.** Lift the document assembly out of
      `template.html` into one module: front matter, `marked.parse`, relative URL
      resolution, heading ids and anchors, GitHub alerts, task lists, table
      wrappers, code blocks with copy buttons, highlight.js, mermaid.
      *Done when:* `template.html` calls `MD.render()` and the reader is
      byte-for-byte equivalent in behaviour — anchors, mermaid, copy buttons,
      alerts, deep links all still work.

- [x] **A3 · Make the review layer mountable.** `review.js` stops being a
      one-shot IIFE bound to `window.__md` and exposes `MDReview.open(doc)`, so a
      second document can be loaded into the same chrome without duplicate
      listeners or leaked state.
      *Done when:* the reader behaves exactly as before, and calling
      `MDReview.open()` twice leaves one set of annotations, one highlight range,
      and no doubled keyboard handlers.

- [x] **A4 · The workspace mounts the real reader.** Delete the workspace's
      private `marked.parse` path. Its reader pane gets the review chrome (pop,
      composer, tray, toast) and calls `MD.render()` + `MDReview.open()`.
      *Done when:* a document opened from the workspace can be annotated with
      every verb, the tray exports, and the notes appear in the Notes view.

- [x] **A5 · Regression pass.** Reader, workspace, workspace + sessions, hook.
      *Done when:* all four paths verified in a real browser, not by inspection.

---

## Phase B — the browsers ✅

Data the indexer already produced, now presented as something you can move
through: a Library you can navigate and read from, and a Sessions browser that
is honest about which sessions can still be picked up.

- [x] **B1 · Library view.** Directory tree with a flat mode, note counts,
      staleness marks, sort by recency · staleness · notes · size · title,
      facets for has-notes · stale · untracked · front-matter tag.
- [x] **B2 · Library detail.** Selecting a row opens it in the reader pane beside
      the tree, rather than as a full-screen overlay.
- [x] **B3 · Session metadata.** Extend `sessions.py`: per session — title (first
      non-slash prompt), project, first/last timestamp, prompt count, and whether
      a transcript still exists.
- [x] **B4 · Sessions browser.** Grouped by recency, filterable to this repo
      (falling back to everywhere when the repo has no history of its own),
      `● resumable` / `○ archived` computed from transcript presence.
- [x] **B5 · Session detail.** Scrubbed prompts, files touched, correlated
      documents, copyable session id.
- [x] **B6 · Reverse correlation.** Given a session, rank this repo's documents;
      the existing ranking run the other way round.

---

## Phase C — the live tier ✅

- [x] **C1 · Extract `serve.py`** from `hook.py`: ephemeral port, per-run token,
      origin and `Sec-Fetch-Site` checks, `Referrer-Policy: no-referrer`, idle exit.
- [x] **C2 · Capability handshake.** The page is told what it may do
      (`META.caps`); every action-bearing control is hidden without its capability.
- [x] **C3 · Tier selection in `bin/md`** — live when python3 is present, static
      otherwise, `--static` to force. Static stays shareable.
- [x] **C4 · Live reindex.** `POST /reindex` rebuilds and the page refreshes in
      place, no regeneration round-trip.
- [x] **C5 · Documents fetched on open** in the live tier, so the page stops
      embedding every document body — and the libraries are served too. Search
      answers from titles and headings immediately, then pulls every body once.
- [x] **C6 · Notes on disk.** `.rubricator/notes.json` at the repo root, with
      `localStorage` as the static-tier fallback and a one-time migration.
- [x] **C7 · Index cache.** `~/.cache/rubricator/index/<roothash>.json`,
      invalidated by mtime + git HEAD; sessions cached separately.

---

## Phase D — actions ✅

Everything here is off by default. This is where a local page gains the power to
start a process, and it should look like it.

- [x] **D1 · Action bus.** `POST /act {verb, id}` — verb allowlist, every path
      and argument resolved server-side. Nothing from the page reaches a shell.
- [x] **D2 · Terminal dispatch.** A `.command` launcher handed to your terminal
      through LaunchServices — iTerm by default where it is installed, Terminal
      otherwise, or whatever Settings says. Every terminal in the list runs a
      `.command` when opened with one, so no Automation permission is involved
      and no dialog ever appears. *(AppleScript, which does need permission and
      whose dialog blocks, was removed.)*
- [x] **D3 · Launch with the dossier.** New session in the document's repo root,
      first prompt seeded from the annotations.
- [x] **D4 · Resume / fork.** `claude -r <sid>` and `--fork-session`, offered
      only for sessions that still have a transcript.
- [x] **D5 · Reveal in Finder · open in `$EDITOR`.**
- [x] **D6 · Opt-in gate.** `--allow-launch` or a config line; a fresh install can
      spawn nothing. Document the threat model in the README.

---

## Phase E — extensions ✅

- [x] **E1 · Watch mode over SSE** — `docs/watch-plan.md`, now a small addition.
- [x] **E2 · Per-file timeline** — commits and sessions on one axis.
- [x] **E3 · Correlation graph** — the mindmap view, gated behind a node budget.
- [x] **E4 · Subagent transcripts** (`--deep`) so delegated file edits are attributed.
- [x] **E5 · `md serve`** — a persistent workspace on a stable port.
- [x] **E6 · Provider interface** — commits, GitHub issues, a notes folder.
- [x] **E7 · User views** — `~/.config/rubricator/views/*.js`, loaded if present.
- [x] **E8 · Multi-root workspace.**

---

## Open decisions

Carried from the plan; unresolved ones block the tasks that depend on them.

| # | Decision | Blocks | Status |
|---|---|---|---|
| 1 | Bare `md` opens the workspace with the README pre-opened | A1 | **accepted** |
| 2 | Launch is opt-in behind a flag | D6 | **accepted** — `md --allow-launch`, or `{"allow_launch": true}` in the config |
| 3 | Notes move to `.rubricator/notes.json` | C6 | **accepted** — kept out of git via `.git/info/exclude`, so nothing tracked is touched and committing it stays a choice |
| 4 | A+B ships as its own release before C+D | — | superseded — A through E shipped in sequence, each on its own commit |


---

## Planned — reading the conversation

See [`conversations-plan.md`](conversations-plan.md). Four decisions open at the
end of it.

- [x] **G1 · The conversation model.** `transcript.py` parses one transcript into
      turns; `GET /session?id=` serves it. On demand, never indexed, never
      embedded — 17 MB in 0.05 s, 350 turns, a 259 KB payload. Two findings:
      `promptSource` is what separates what you typed from what the harness
      injected wearing your name, and one reply is many messages, so speaking
      again after running tools starts a new turn.
- [~] **G2 · Read a session.** Built as a *conversation*, not as a document:
      your turns on the right, Claude's on the left, thinking as a count, tool
      calls behind a disclosure, runs of replies grouped under one clock. The
      plan's *render it as markdown and get the review layer free* was traded
      for that, deliberately — see §7b of the plan for the cost and the way
      back. Still open: annotating a turn, the three densities, the ribbon.
- [ ] **G2b · Actions on a turn.** Copy it · reuse it in a new session ·
      continue from here · pick it into the tray.
- [~] **G3 · What it changed.** Files created and edited appear as chips on the
      turn that wrote them, from `toolUseResult.type`. That record only exists
      for the Write and Edit tools, so a session that edits through Bash shows
      none — the session's file list, from the index, stays the honest answer.
- [ ] **G4 · The reverse index.** document → sessions, from the same pass:
      482 pairs across 38 sessions, 0.97 s for the corpus, cached with the rest.
- [ ] **G5 · Provenance in the reader.** Who created this document and who has
      worked on it since, with the existing timeline finally labelled.
- [ ] **G6 · Finish.** `ai-title` as the session title, compaction markers, and
      jumping from a search hit to the turn that matched.

---

## PDF and Word — extraction done, the original view unblocked

See [`documents-plan.md`](documents-plan.md). The shell has since shipped, so
H5 is what it was always meant to be: a second tab on the same document.
Both extractors ship with macOS:
`textutil` for Word, PDFKit through the JXA bridge for PDF — measured here at
0.19 s per PDF across 16 of them, 0.76 s for 3 Word files.

- [x] **H1 · `extract.py`.** One function per kind, page-aware for PDF, results
      cached on mtime + size like the session index.
- [x] **H2 · Index them.** `find_docs` widens to `.pdf .docx .doc .rtf`;
      documents carry a kind and a page count; extraction stays lazy so the
      workspace still opens instantly.
- [x] **H3 · Read one.** Extracted text rendered as blocks with a heading per
      page, pre-mapped to a synthesised source — which hands it the reader, the
      review layer, the outline and the export unchanged. A PDF can be
      annotated and picked into a dossier like anything else.
- [x] **H4 · Search them** alongside markdown.
- [ ] **H5 · The original view.** Chrome's PDF viewer over the asset route,
      `textutil -convert html` for Word, and `object-src 'self'` in the policy.
- [ ] **H6 · Background warm-up** with progress over the SSE channel.
- [ ] **H7 · OCR on request** through Vision, for the scans.

---

## Planned — continuing a session

See [`continue-plan.md`](continue-plan.md). Agreed: the window is where you
think, the terminal is where you work, and they are the same session — a turn
taken here appends to the same transcript, verified.

- [ ] **J1 · `converse.py`.** One long-lived `claude -p --resume --input-format
      stream-json` per session, a lock file so two windows cannot drive one, and
      a hard stop. `POST /say {sid, text}` in, the existing SSE channel out.
- [ ] **J2 · The composer.** At the foot of the conversation; a bubble that
      fills from `content_block_delta` and finalises on `assistant`. Cost from
      `result` on the status strip.
- [ ] **J3 · Read-only by construction.** `--disallowedTools Bash Write Edit
      NotebookEdit`, enforced by the agent in subagents too, and *said* on the
      surface rather than discovered. *Resume in a terminal* sits beside it.
- [ ] **J4 · Survive the window.** A turn in flight when the page closes: the
      process detaches, and the page reattaches by re-reading the transcript,
      which is already the source of truth.

Not planned: a permission UI. Headless Claude does not ask — verified, including
under `--permission-mode manual` — and the callback that would let rubricator
ask on its behalf lives in the Agent SDK, which is a Node dependency this tool
does not otherwise need.

---

## Look and feel

Design canvas: the shell, the session reader, and the direction exploration.

- [x] **F2 · Three themes.** Rubric (default), Slate and Bone, defined once in
      `template.html` and inherited by every surface. `data-mode` carries light
      vs dark for the handful of rules that must know; the old `dark` / `light`
      values still resolve. Chosen in Settings, cycled with `t`, or `--theme`.
- [x] **F3 · Selection without the accent bar.** The mark moved into a gutter
      column every row shares, so it lines up down the list and the row itself
      is never decorated — no fill, no inset accent, no rounded pill.
- [x] **F4 · A tray made of type.** No card and no left border: a hairline, the
      verb in mono caps carrying the colour, and the quote ruled at 1px.
- [x] **F5 · The divider is the control.** 1px at rest, 11px of hit area, and it
      brightens and switches the cursor rather than growing a grip.
- [x] **F6b · All, and the whole tree at once.** A fourth navigator mode that
      searches documents, sessions and notes in one field — because you
      remember what something was about, not whether you wrote it down or said
      it. Plus expand-all and collapse-all on the tree.
- [x] **F6a · Tabs per pane, not per window.** The one disagreement with the
      brief, argued on the canvas and kept: with splits, a single bottom strip
      cannot say which pane a tab belongs to, and per-pane tabs give each pane
      its own history.
- [x] **F7 · Open a project.** The repository name in the bar is a switcher:
      recents the server remembered, plus a native folder chooser it opens
      itself. A second project opens in its own window. The page never sends a
      path — it asks for the picker or names something already on the list.
- [x] **F8 · Treat the document as untrusted.** Markdown carries raw HTML and
      an `<img onerror>` executed — in `review.js`'s line mapper, which parsed
      every token into a live `<div>`. Both halves fixed: the renderer sanitises
      inside an inert `<template>`, and the served page carries a nonce-based
      CSP so an inline handler cannot run even if the sanitiser misses one.
- [x] **F6 · The shell itself.** One window: a navigator with three modes down the
      left, panes with their own tabs in the middle, the review tray down the
      right, a status strip along the bottom, and `⌘K` across all of it. The
      page-level tab strip is gone — it mixed *which list am I looking at* with
      *which document am I reading*, and separating those is what made room for
      panes. `share/shell.js` owns the window and knows a surface only as
      something that renders into a div; `share/workspace.js` owns what the
      surfaces are. A tab keeps its DOM for as long as it lives, so a document
      leaves and comes back with its annotations, its diagrams and its scroll
      position intact. The tray follows focus rather than multiplying per pane.
      The layout — panes, tabs, navigator mode and width — survives a reload.

---

## After the plan

- [x] **F1 · Settings screen.** Terminal, launching, editor and deep indexing,
      changed from the workspace and persisted to `~/.config/rubricator/config.json`
      at mode 0600. Only known keys, each value validated server-side; a CLI flag
      still wins and the screen says when it has.

---

## Done

All five phases are in, plus the shell they were leading to. What the plan called
*room deliberately left* is now reachable rather than hypothetical: a provider is
a file in `~/.config/rubricator/providers/`, a view is a file in
`~/.config/rubricator/views/`, and a workspace can hold more than one repo.

What is deliberately still missing, and why:

- **No daemon by default.** `md serve` exists for when you want one, but the
  ordinary path still starts a server that dies with its window.
- **No cloud, no sync, no account.** Session history never leaves the machine;
  `--sessions` still refuses `--out`.
- **No agent loop in the window.** A session can be read here and continued
  here (J1–J4), but only for thinking — the tools that change your repo stay in
  the terminal. See [`continue-plan.md`](continue-plan.md) for why that is a
  decision rather than a gap.
- **A conversation is not annotatable.** The review layer binds to a document
  and a chat bubble is not one; §7b of the conversations plan says what it would
  take.
- **macOS only.** The window handling, the terminal dispatch and the Finder
  verbs are all platform-specific. Nothing else is.
