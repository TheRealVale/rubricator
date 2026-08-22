---
title: Task register
subtitle: Phases A–E from docs/architecture-plan.md
status: living
---

# Task register

Companion to [`architecture-plan.md`](architecture-plan.md). One line per task, an
explicit *done when*, and nothing tracked that git cannot confirm.

Legend: `[ ]` open · `[~]` in progress · `[x]` done

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
- [x] **D2 · Terminal dispatch.** A `.command` launcher handed to Terminal through
      LaunchServices, which needs no Automation permission. Naming a terminal in
      the config drives it over AppleScript instead — that does need permission,
      and the error says so rather than hanging.
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

## Done

All five phases are in. What the plan called *room deliberately left* is now
reachable rather than hypothetical: a provider is a file in
`~/.config/rubricator/providers/`, a view is a file in
`~/.config/rubricator/views/`, and a workspace can hold more than one repo.

What is deliberately still missing, and why:

- **No daemon by default.** `md serve` exists for when you want one, but the
  ordinary path still starts a server that dies with its window.
- **No cloud, no sync, no account.** Session history never leaves the machine;
  `--sessions` still refuses `--out`.
- **macOS only.** The window handling, the terminal dispatch and the Finder
  verbs are all platform-specific. Nothing else is.
