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
Effort: **S** an evening or less · **M** a day or two · **L** about a week

## The plans

| | | where it stands |
|---|---|---|
| [`architecture-plan.md`](architecture-plan.md) | one door, one shell — phases A–E | delivered. §2 and §4 describe the shell F6 replaced |
| [`workspace-plan.md`](workspace-plan.md) | the first workspace: index, correlate, trust boundary | delivered, and superseded in shape by the above. §5.3's *the one that pays immediately* is retired by `signals-plan.md` §6 |
| [`review-design.md`](review-design.md) | the annotation layer and its verbs | shipped, hardened since (F8). §6's quote-hash was never built — see `anchoring-plan.md` |
| [`watch-plan.md`](watch-plan.md) | refresh when a file changes | shipped as E1, over SSE rather than polling |
| [`conversations-plan.md`](conversations-plan.md) | reading a session | G1 shipped · G2–G3 partly · see its §7b |
| [`documents-plan.md`](documents-plan.md) | PDF and Word | H1–H4 shipped · H5–H7 open |
| [`continue-plan.md`](continue-plan.md) | adding a turn to a session from the window | agreed in shape, unbuilt. Two rows of its §1 table were confounded — O3 |
| [`install-plan.md`](install-plan.md) | the documented install, and how CI keeps it honest — phase K | plan, unstarted |
| [`signals-plan.md`](signals-plan.md) | what the surfaces claim and what they can support — phase L | plan, unstarted |
| [`anchoring-plan.md`](anchoring-plan.md) | a mark survives the rewrite — phase M | plan, unstarted |
| [`retention-plan.md`](retention-plan.md) | what the tool keeps, and what it must not — phase N | plan, unstarted |
| [`scope-plan.md`](scope-plan.md) | what this is for, and what it will never be — phases O and P, the standing rules, the killed list | plan, unstarted |

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
| 3 | Notes move to `.rubricator/notes.json` | C6 | **accepted**, second half superseded — the move stands; keeping them out of git via `.git/info/exclude` does not. Standing rule 3 was withdrawn on 2026-08-24: committing the notes is the supported path, and M6 stops appending that line and removes the one already written |
| 4 | A+B ships as its own release before C+D | — | superseded — A through E shipped in sequence, each on its own commit |


---

## Planned — reading the conversation

See [`conversations-plan.md`](conversations-plan.md). Four decisions open at the
end of it.

- [x] **G1 · The conversation model.** `transcript.py` parses one transcript into
      turns; `GET /session?id=` serves it. On demand, never indexed, never
      embedded — the largest transcript here is 105.0 MB and parses in 0.28 s
      into 795 turns (measured 2026-08-23). Two findings:
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

Not planned: a permission UI. There is nothing to prompt with and nothing to
answer: under `claude -p` the call is **auto-denied** — visibly, as an entry in
`result.permission_denials` — and the documented `PermissionRequest` hook, which
would be the channel for asking, fired zero times on 2.1.241 across five
configurations, top level and subagent alike. (The earlier *ran anyway, even
under `--permission-mode manual`* measured this machine's own `defaultMode:
auto`; the corrected §1 of [`continue-plan.md`](continue-plan.md) has the
detail.) The callback that would let rubricator ask on Claude's behalf lives in
the Agent SDK, which is a Node dependency this tool does not otherwise need.

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

---

## Phases K–Q

> **Where this stands.** K1–K4 shipped with the commit that added these plans:
> the install copies every file in `share/` rather than eight of eighteen, the
> installer renders a test page and exits non-zero if it cannot, `tests/smoke.sh`
> holds eight assertions and CI runs them. K5 is deliberately not done — it turns
> on a measurement only a human at a keyboard can take: standing rule 12 wants the
> hook fired once against the installed build before the code is written. That
> same fire answers open question 5, which is now the only one of the six still
> open — and it is waiting on a measurement rather than on an answer. So the
> defect this programme opens with is closed; the rest of it is not.
>
> **The order changed on 2026-08-24: K, then N, then L, M, O, P, Q.** Phase N sat
> fourth on one measurement — that the only person whose prompts are in the cache
> is the person who wrote it. The owner has answered open question 3:
> `md --sessions` already runs on a machine with client work on it. Not one word
> of phase N's content changes; what changes is whose material the 33
> world-readable files, the 8 MB static page and the unscoped `⌘K` hold. N4 stops
> being an embarrassment and becomes a disclosure, N3 stops being a false comment
> and becomes a false assurance about somebody else's credentials, and the
> register's own condition — *it moves ahead of M the day there is client work on
> the machine* — is met. It moves ahead of L as well, and the *probably* resolves
> on a distinction the register did not draw: L's defects are the tool lying to
> its own user, which the maintainer can decide to tolerate for a week, and N's
> are other people's material at mode 0644 in the one cache directory the backup
> does not skip, which he cannot decide on their behalf. N is also the cheaper
> phase to front-load — six items, every one an evening, five of them
> subtractions — so L is delayed by about a week and nothing in L is made harder
> by the wait. The `## Phase` sections below stay in letter order: K1–K4 shipped
> under their letters and every plan document cites its items by theirs, so the
> letters are names and this paragraph is the order.
>
> **What was already good, since the list below is nine indictments long and does
> not say so.** The reader is finished work. The review layer's verbs, its
> section-covering behaviour, its line-anchored export and its notes-versus-changes
> distinction are all sound and were not the subject of a single finding. The
> indexer is fast for the reason its docstring claims rather than by luck — 950 MB
> of transcripts in 0.98 s, the worst git pass 0.68 s — and every attempt to find
> a scale bomb in it failed. PDF and Word extraction works, adds no dependency, and
> hands the whole review layer to a contract you can quote a page from. The action
> bus is carefully argued and holds. Forty-four repairs against that is a short
> list, and 35 of them are an evening or less.

A–J were features. K–Q are repairs, and there are 44 of them. Every item below
is justified by a claim that was independently re-measured and survived a
hostile re-read that tried to kill it. Where the re-measurement corrected the
original claim, the item below carries the corrected version rather than the one
the register was written with, and the plan document says what moved.

The verdict in one line: the install command on the front page copies **8 of
the 18 files** in `share/`, so every developer who has ever followed the README
got a beautiful empty window and exit code 0. That is not an isolated bug. It
is the tool's characteristic failure in its purest form — **it reports
confidence it has not earned** — and the same shape recurs. A search that
returns nothing for 25 of 37 realistic two-word queries, in the same words it
uses for an empty corpus. An *all clear* computed from a detector that resolved
zero targets for 87 of 99 documents. A tray that calls a deleted paragraph
*resolved*. A README promising *nothing leaves the machine* beside a mode-0644
copy of every prompt from twenty projects. Four `[x]` lines above describing
features that were never built.

**35 of the 44 are S and 9 are M. None is longer.** That is the finding, not a
rounding. The programme that survived verification is small; what did not
survive is most of the ambition — no diff review, no MCP server, no transcript
archive, no code-knowledge map. All of it is in [Killed](#killed), which is the
more valuable half of this register: it is what stops the ideas coming back.

The reasoning is in five documents, one per phase except O and P, which share
one argument and one document: [`install-plan.md`](install-plan.md) (K),
[`signals-plan.md`](signals-plan.md) (L), [`anchoring-plan.md`](anchoring-plan.md)
(M), [`retention-plan.md`](retention-plan.md) (N) and
[`scope-plan.md`](scope-plan.md) (O, P, the standing rules, the kills). Each
opens with a table of what was measured rather than assumed. Q has no document
of its own: every one of its items reads from a subsystem an earlier phase
corrects, and is planned there.

---

## Phase K — the documented install has to work

100% of non-maintainer installs are broken at minute one, and the failure is
silent: `md: wrote out.html`, exit 0, blank page. Nothing downstream can be
dogfooded, measured or recommended until this works. Build order is K1, K3, K2,
K4, K5 — K3 before K2 because the installer's self-check and CI's assertion are
the same assertion, and getting it wrong in one place is getting it wrong in
both. K5 waits on one hook fire against the installed build, which standing rule
12 wants before the code is written; that same fire settles open question 5, so
take the two together. See [`install-plan.md`](install-plan.md).

- [x] **K1 · Install by glob, not by list.** `install.sh:59` names seven files
      plus `hook.py`; `share/` holds eighteen. `render.js` is not among them, so
      `template.html:322`'s `<!--@include render.js-->` expands to nothing,
      `template.html:364`'s `MD.render()` throws with no try/catch, and
      `bin/md:380`'s `emit()` prints nothing because awk's `getline` returned
      −1. `workspace.py` is missing too, so bare `md` — the first example on the
      front page — dies with a raw `[Errno 2]`. Install from `git ls-files
      share/`, which carries no list at all.
      *Done when:* `diff -rq --exclude=vendor --exclude=__pycache__ share/
      "$PREFIX/share/rubricator/"` exits 0 after a copy install of the same
      commit, `md -o out.html sample.md` in a fresh `HOME` yields a page whose
      rendered DOM contains the fixture's `<h1>`, and bare `md` in a git repo
      exits 0. **S**

- [x] **K2 · The installer proves itself before it says ready.** Three silences
      in one script. It prints `Done.` without ever running the thing it
      installed. On a **zero-byte** `~/.zshrc`, `install.sh:79`'s `grep -v` emits
      no lines, exits 1, and `set -euo pipefail` aborts before the banner and
      before `--with-hook` — no message, exit 1. And `bin/md:109` wraps the
      checksum check in `if command -v shasum`, so with no hasher the five
      render libraries install unverified, while `bin/md:111`'s `[ -n "$sha" ]`
      skips any manifest entry with an empty third field. End with a real
      self-check — `md --version` plus one render of a temp file — guard the rc
      edit, and make both checksum branches hard failures, accepting `shasum`
      **or** `sha256sum`.
      *Done when:* `: > ~/.zshrc && ./install.sh` exits 0 and prints the banner;
      an install with both hashers masked out fails loudly; and a deliberately
      broken `share/` makes the self-check name what is missing and exit
      non-zero. **S**

- [x] **K3 · CI that fails on the bug it was written for.** One job on a macOS
      runner, three layers: the inventory diff from K1, a grep for a
      `render.js`-unique string on the built page, and — on whatever cadence it
      proves reliable on — a headless render. **The assertion must not be
      `window.MD`**: it returns 1 on the broken artefact, because
      `review.js:570` defines `window.MDReview` and `review.js` is one of the
      eight copied files (X1). Note that `install.sh:68` runs `md --vendor`,
      which bypasses the cache and re-downloads 3,737,839 bytes on every run.
      *Done when:* reverting K1 turns the job red, and layer 2's string is
      demonstrably absent from a copy-install artefact built without
      `render.js`. **S**

- [x] **K4 · Six smoke tests on the seams that already exist.**
      `RUBRICATOR_NO_WINDOW` (`hook.py:108`) was exercised live under both
      install modes; `RUBRICATOR_DRY_LAUNCH` (`actions.py:230`) is in the code
      and has been read, not run. Assert: bare `md` in a repo exits 0; `md -o`
      produces a page with a rendered heading; `md --review` on a fixture
      returns the export text; `RUBRICATOR_NO_WINDOW=1 md --review` with no
      feedback exits 1 with `md: no feedback given`; the hook returns valid JSON
      for close and for timeout; `md --vendor` verifies all five checksums.
      Exit codes are almost all green on the broken install, so test 2 must
      assert on content.
      *Done when:* tests 1 and 3–6 run in CI in under a minute, test 2 runs on
      K3's browser cadence, and one deliberate regression per test turns the job
      red. **S**

- [ ] **K5 · The hook reads the plan Claude Code hands it.** `hook.py:30-55`
      reads the last 4 MB of `transcript_path` and regex-scans for a path under
      `~/.claude/plans`, falling back to the newest `*.md` there modified within
      the hour. Claude Code injects `plan` and `planFilePath` into the hook
      payload; `grep -rn "planFilePath\|payload\[" share/ bin/` returns nothing.
      Anyone who set `plansDirectory` — documented example `./plans` — gets
      `no plan file found — skipping review`, exit 0, silently, and the mtime
      fallback can pick up a concurrent session's plan. Delete `find_plan`.
      Standing rule 12 gates it: fire the hook once against the installed build
      and confirm the fields arrive before writing the code.
      *Done when:* `find_plan` is gone, the hook takes the plan from the
      payload, and a hook run under a custom `plansDirectory` opens the right
      plan. **S**

---

## Phase L — stop reporting confidence you have not earned

The places a stranger meets the defect in minute two. Seven of the eight are a
subtraction or a correction; only L1 adds behaviour. They come before the
anchoring work because they are what makes the tool's own output trustworthy
enough to judge that work by. Phase N now comes before them — the build-order
paragraph above says why, and nothing here is made harder by the week's wait.
See [`signals-plan.md`](signals-plan.md).

- [ ] **L1 · Search requires every term.** `count()` at `workspace.js:157-162`
      is one case-insensitive `indexOf` of the whole query. On repo B's 330
      documents: `auth`→132, `auth flow`→2, `flow auth`→0, `authentication
      flow`→0, `rate limit`→17, `limit rate`→0. Against 37 two-word queries each
      built from two words of a real document's own title, the shipped matcher
      returns **zero for 25 of 37**; AND-of-terms returns zero for none. Split on
      whitespace, require every term, score as `Σ per-term count + 3 × count(full
      phrase)`. AND alone is not enough — `business match` goes from 0 hits to
      111 — which is why the ranking half is not optional and why this is the
      one **M** in the phase. No stemming, no fuzzy matching, no index.
      *Done when:* `flow auth` and `auth flow` return the same document set,
      `business match` does not return the whole corpus, and all eight sites —
      three ranking callers, two inline matchers, the navigator filter and the
      two displayed counts — go through one parser. **M**

- [ ] **L2 · `⌘K` says what it is matching.** `workspace.py:459` strips `text`
      from every doc in serve mode; `palSearch` then tests `hit(d.text)` on
      `undefined` and reports `total + ' hits'` unhedged. On repo B, `auth`
      gives **0 palette rows against 132 from the Search surface**. It silently
      becomes full-text for the rest of the run if you visit either the Search
      surface or the All navigator first — two ways to get two different answers
      to one keystroke. Call `ensureAllText` when the palette opens with a
      non-empty query, and until it resolves reuse the sentence `searching()`
      already ships at `workspace.js:207`. Ships in one commit with L1.
      *Done when:* a fresh window's first `⌘K` for a body-only term returns the
      same count as the Search surface, and the count is labelled while the
      fetch is in flight. **S**

- [ ] **L3 · The views that count notes read the notes.** `.rubricator/notes.json`
      is written correctly and shipped to the page, and `workspace.js:74-98`
      installs a disk-aware storage adapter with exactly one caller,
      `review.js:47`. Every corpus-wide view goes through `annosFor()` at
      `:116-123`, which reads `localStorage` only and never consults `DISK`,
      though `DISK` is in scope on line 118. Seven consumers: `:259`, `:299`,
      `:387`, **`:774` — the dossier builder, which ships the wrong data into an
      agent prompt** — `:1233`, `:1303`, `:1380`. Every `md <dir>` gets an
      ephemeral port, therefore a new origin, therefore an empty `localStorage`:
      not empty on the first run, empty on every run. Make `annosFor` prefer
      `DISK[doc.abs]`, and seed `data['notes']` into the static payload in the
      same commit.
      *Done when:* a note taken in one run appears in the Notes surface, the tab
      badge, `⌘K` and the dossier after the server is restarted on a new
      ephemeral port. **S**

- [ ] **L4 · The staleness signal stops calling itself a quality signal.** Four
      false statements in one subsystem. `workspace.js:370` renders *"Nothing
      looks stale…"* where the detector resolved **zero targets for 87 of 99**
      repo A documents, and again on repo D while the navigator paints
      **61 ⚠** in the same window. The navigator glyph and the Stale surface use
      different predicates — 231 triangles against 129 rows on repo C.
      `viewStale` then slices to 40 and says nothing: 40 of 129, 40 of 154. And
      `repo_churn` at `workspace.py:175` costs 26% of the git pass and is read
      by no JavaScript. Delete `isStale` and the `⚠` glyph; the navigator's
      `stale` facet shares that predicate, so it goes with it or is repointed at
      `viewStale`'s so that facet and surface finally agree. Delete `repo_churn`
      and the dead `stem` at `:167`; distinguish the two empties with counts;
      print `showing 40 of 154`; relabel the surface as *documents whose named
      files kept changing* and stop calling it staleness in the README. **Do not
      widen the extension list** (X14).
      *Done when:* repo A' Stale surface says how many documents could not
      be judged, the `⚠` glyph is gone, `grep -rn repoChurn share/` returns
      nothing, and the row count and the displayed count agree. **S**

- [ ] **L5 · The index sees the file the agent just wrote.**
      `workspace.py:32-40` builds the document set from `git ls-files` and
      returns early whenever any file is tracked, so the `os.walk` fallback is
      unreachable in a real repo and a markdown file the agent wrote is
      invisible until `git add`. Reproduced on a scratch repo. Union in
      `git ls-files --others --exclude-standard` — 23 ms on repo C
      against 19 ms for the existing call — and mark untracked rows visually.
      Add `.mdc` to `MD_EXT` in the same commit: one set entry, no finding
      attached, and nothing is built on it (X30).
      *Done when:* a file created and not staged appears in the tree, marked
      untracked, after one reindex — which is also what makes the `untracked`
      facet claimed at [`tasks.md:77`](tasks.md) buildable. **S**

- [ ] **L6 · The prompt index stops discarding 13.6% of what you typed.**
      `workspace.py:237` does `scrub(txt)[:600]`. Over the indexed prompts, 127
      (3.2%) exceed 600 characters and **86,020 characters — 13.6% of all prompt
      text — are dropped**. The adjacent slash-command filter at `:233` drops
      756 of 4,750 records (15.9%), but 82% of those are `/model`, `/compact`
      and `/clear`; the genuinely lost material is 71 prompts, 1.5%. So the cap
      is the nine-times-larger loss. Raise it — 2,000 is one constant — and
      replace the blanket `startswith("/")` with a short skiplist, which also
      keeps prose that happens to begin with a path.
      *Done when:* a 900-character prompt is findable by a phrase in its second
      half, and `/api/orders returns 500 after the migration…` is in the index.
      **S**

- [ ] **L7 · Silent data loss stops being a 1.9-second toast.**
      `workspace.js:96` reports a failed disk write with `toast('note not saved
      to disk')`, cleared after 1,900 ms and logged nowhere — the sole report of
      losing the one thing the tool exists to keep. Route it to a line in the
      status strip that survives until the next successful save, and give
      `#toast` `role="status"` while you are there.
      *Done when:* a `/notes` POST forced to fail leaves a visible, persistent
      line in the status strip, and it clears on the next successful save. **S**

- [ ] **L8 · The hook names what you are about to lose.** On expiry,
      `review.js:664-676` disables Send while still rendering the live item
      count. The hook window writes nothing to disk by construction — it serves
      the static tier from a temp file it unlinks at `hook.py:221-223` — so the
      marks go. On the ordinary Chrome path `hook.py:231-232` closes the window
      0.35 s later, so it is a flash; where `close_window` cannot match, it
      persists. If `askItems().length`, say the number in the expiry banner and
      make the existing copy-to-clipboard link the primary control.
      *Done when:* an expired hook window with three marks says three, and the
      copy link is the visually primary action. **S**

---

## Phase M — a mark survives the rewrite

The tool's central promise and its central lie. The README says annotations are
re-anchored by content; the code is `raw.indexOf(it.anchor)` at
`review.js:119`, exact substring, first occurrence, and a miss sets
`state = 'stale'`, which seven aggregate views filter out and the tray counts as
*resolved*. Two of the eight items are the whole mechanical fix and come to
about fifteen lines. Build order is M1, M3, M2, M6, then the rest in number
order: M3 is one line and must land before M2 starts moving items, and M6 is
independent of all of them, is the phase's only **M**, and is the only item here
another phase waits on — N6's plan-text half. See
[`anchoring-plan.md`](anchoring-plan.md).

- [ ] **M1 · Re-anchor to the nearest occurrence, not the first.** Collect all
      `indexOf` occurrences and pick the one nearest the stored `lineStart`.
      Corpus-wide, first-occurrence ambiguity is a rounding error — **8 bad
      anchors in 25,094 realistic ones (0.03%)** across five repos — so this is
      worth five lines because it is five lines, and because the fuzzy step
      needs the position hint. It also fixes the one dramatic case: **1,636 of
      1,851 `hr` anchors (88.4%)** resolve to the wrong offset, 127 of them to
      byte 0 because the file opens with front matter.
      *Done when:* a document with `---` at three positions anchors each mark to
      its own rule, and a repeated heading anchors to the section it was made
      in. **S**

- [ ] **M2 · Fall back to the longest surviving line.** On a miss, try the
      anchor's own lines, longest first, by plain `indexOf`; on a hit set the
      anchor status to `moved` and keep both texts. Measured over 2,985 commit
      pairs in five repos, 6.6% of substantive anchors vanish per revision, and
      this ten-line step **recovers 62.6% / 40.2% of them at 98.6% / 96.5%
      precision** — beating the 525-line match-quote port at the 0.90 threshold
      (62.6% against 42.1%) with better precision. Whitespace normalisation
      recovers 0.2% / 0.0% and is not worth writing.
      *Done when:* a mark on a paragraph whose first sentence was rewritten but
      whose longest line survived comes back as `moved`, with the original text
      still readable in the tray. **S**

- [ ] **M3 · Never overwrite the recorded quote.** `review.js:125` does
      `if (!it.partial) it.quote = srcSlice(...)` on every successful re-anchor,
      and `reanchor()` calls `save()`, so it persists. A no-op for whole-block
      and partial marks — but for a **section** mark, where `anchor` is the
      heading line and `quote` is the whole section, `sectionEnd()` recomputes
      the span and the recorded text is silently replaced by a different
      section's. That is irreversible local data loss. Stop writing `quote`; the
      current section text is `srcSlice()` on every open (rule 4).
      *Done when:* a heading mark whose section was rewritten still shows the
      text it was made against, and `notes.json` never loses a `quote` it once
      held. **S**

- [ ] **M4 · Three anchor states, and stop calling deleted text resolved.**
      One bit does two jobs: `review.js:347` prints `N · M resolved`, `:370`
      tags the item `gone`, `:414` drops it from the export, and seven
      `workspace.js` sites filter it out — so a deleted section and a
      typo-corrected sentence are the same state, and both are reported as an
      accomplishment. The maintainer asked this question himself at
      [`review-design.md:244`](review-design.md). Split it: `attached` ·
      `moved` · `orphaned`. Read a legacy `state: "stale"` as
      `{anchor: 'orphaned'}` and never write it again. **An `approve` that has
      moved or been orphaned is the one case that must be surfaced** — one
      string in the tray header: *three of your seven approvals were altered*.
      Defer any human done/dropped state until someone has run a second round.
      *Done when:* the tray distinguishes the three, an orphaned approve is
      counted in a header line rather than filed under *resolved*, and an old
      `notes.json` loads without migration. **S**

- [ ] **M5 · Say what moved.** `reanchor()` already knows which items moved and
      which lost their text. Print it in the status strip on open — *7 of your
      marks moved, 2 lost their text*. No LCS, no gutter, no stored snapshots
      (X16: wholesale rewrites are 0.0–3.2% of 2,982 markdown revisions and the
      median revision changes 6–20 lines, so `git diff` already covers it).
      *Done when:* reopening a document an agent rewrote states the two counts
      before you scroll. **S**

- [ ] **M6 · `notes.json` becomes a directory, with relative keys, `at`, `by` and
      a version.** `write_notes` (`workspace.py:526`) documents itself as *"one
      file per repo, keyed by absolute document path"* and does exactly that; the
      one key on this machine is an absolute README path, so the file cannot
      survive a second checkout while `README.md:459` says notes sync *"if you
      commit it"*. Standing rule 3 now makes committing them the supported path,
      which makes this one commit rather than four. **Relative keys**, migrated
      from absolute on read, relative to the **enclosing git repository** rather
      than to the directory the human typed — otherwise `md .` and `md docs/` in
      one repository keep two disjoint stores, and two people who invoke the tool
      differently never see each other's marks. **One file per document**, at
      `.rubricator/notes/<relative path>.json`: `git status` then names the
      document whose marks changed, `git log` on that path is that document's
      mark history, two people marking different documents never touch the same
      file, and a conflict, when it comes, is in the one document they both
      marked. The wire format does not move — `data["notes"]`
      (`workspace.py:576`) stays one object and `/notes` still takes
      `{path, store}`; only the disk layout and the `DISK` key
      (`workspace.js:74`, which L3 has just touched) change. **A per-item `at`
      and `by`** — eleven fields are stored and none of them is a clock. `at` is
      epoch milliseconds, like the `store.saved` already written by `save()`;
      `by` is `git config user.name`, omitted when git does not know one and
      never guessed from the OS account. Both are written at creation and never
      rewritten, for M3's reason. The name is already in every commit in the same
      repository, so the notes file adds no exposure the history does not already
      carry. And **`"v": 1`**, with the right to break it, said in the docstring.
      Two behaviours reverse. `write_notes:540-546` stops appending
      `.rubricator/` to `.git/info/exclude`, and removes the line it wrote on the
      first run after the upgrade, saying so once — the tool wrote that line, so
      the tool takes it back, and nothing else in the file is touched. And
      rubricator's own `.gitignore` does **not** gain the line the previous
      version of this item asked for: it would hide the file its own maintainers
      are now meant to commit. `md docs/` therefore leaves `.rubricator/` in
      `git status`, which is no longer noise but the point. The walk-up for `.git`
      survives with a new job — it locates the notes root, falling back to the
      directory itself outside a repository. `review.js`'s localStorage key is not
      touched, so the `file://` reader is unaffected.
      *Done when:* a notes file written in one clone loads in a second clone of
      the same repository at a different path; `md .` and `md docs/` read and
      write the same marks; every new item carries `at`, and `by` wherever git
      knows a name; two people marking different documents in one repository can
      both commit without a conflict; `.git/info/exclude` gains no `.rubricator/`
      line and loses the one this tool wrote; and `git status` after a live run
      shows `.rubricator/`. **M**

- [ ] **M7 · A verb cannot land on a document you are not looking at.**
      `shell.js:390-397` focuses a pane on mousedown, so select-and-mark is
      safe — but click in pane A, hover a block there, move to pane B without
      clicking and press a verb, and the mark is written to the wrong document.
      `x` and `a` are silent (`review.js:20`); the others open a composer
      showing the wrong excerpt. Extend the focus treatment at `shell.css:101`
      from the active tab to the pane itself, and in `review.js`'s keydown
      refuse a verb when `blocks[focusIdx]` is not inside the focused pane.
      **Do not rebind on hover** — that routes through `openDoc`, which calls
      `hidePop(); closeComposer();`, so mouse drift would eat in-progress
      composer text.
      *Done when:* pressing `a` while hovering an unfocused pane writes nothing
      and says why, and the focused pane is identifiable without reading the tab
      strip. **S**

- [ ] **M8 · One quiet coverage line in the tray.** `review.js` already builds
      `blocks` on every `openDoc` and `paint()` already marks the ones carrying
      a mark. Print `3 of 41 blocks marked`. No percentage bar, no colour, no
      gate, no nag, no persistence, nowhere else in the interface — this is the
      deterministic version of a number dwell telemetry wanted to infer (X18).
      *Done when:* the line is present, updates on every mark, and appears
      nowhere else. **S**

---

## Phase N — what the tool keeps

The README says *nothing leaves the machine* and `bin/md:149` enforces it by
refusing `--out` with `--sessions` — while `index/sessions.json` under the cache
root holds 3,998 prompts across 419 sessions and 20 project paths at mode 0644,
is never pruned, and sits in the one cache directory macOS does not exclude from
Time Machine. The victim count was one, and that one was the maintainer, who
owns every prompt in the index — which is why this sat fourth. Open question 3
was answered on 2026-08-24: `md --sessions` already runs on a machine with client
work on it. The population changed, not a measurement; nothing below moved. The
phase now runs second, after K, and the build-order paragraph above says why it
also goes ahead of L. Build order inside the phase is unchanged: N5 first — it
is small and it unblocks Q1 — then N1, N2, N4, N3, one commit each, and N6 last
because it is the only item here that adds a file rather than removing an
exposure. See [`retention-plan.md`](retention-plan.md).

- [ ] **N1 · The prompt cache stops being world-readable and immortal.** Three
      fixes. Mode 0600 on files and 0700 on the directory — `actions.py:113` and
      `:222` already do exactly this elsewhere, and 33 of 33 files under the
      cache root are world-readable today, including the extraction cache
      holding the plaintext of every indexed PDF. Get the root excluded from
      Time Machine: `tmutil isexcluded ~/Library/Caches` → Excluded,
      `tmutil isexcluded ~/.cache/rubricator` → **Included**. Assert the
      property, not the mechanism — moving to `~/Library/Caches/rubricator` and
      `tmutil addexclusion` both reach it. Open question 4 was answered on
      2026-08-24 and does not pick between them: it removes the portability
      argument for the second, and leaves the choice to this item's own commit.
      Prune `index/sessions*.json` on the seven-day schedule
      `bin/md:413` already applies to rendered HTML, which `-maxdepth 1` and
      `-name '*.html'` currently miss.
      *Done when:* `find ~/.cache/rubricator -type f ! -perm 600 | wc -l` is 0,
      `tmutil isexcluded` on the cache root says Excluded, and a session index
      older than seven days is gone on the next run. **S**

- [ ] **N2 · The prompt corpus is never baked into a file.**
      `~/.cache/rubricator/workspace-*.html` is 8 MB at mode 0644 and contains
      7,792 occurrences of `sid` — the same corpus `--sessions` refuses to write
      with `--out`, by another route, reached without a flag when the local
      server does not come up. Serve prompts only; drop them from any static
      build. The user-visible cost is real and correct: a static workspace loses
      prompt search.
      *Done when:* no `.html` on disk contains prompt text, and the
      `--sessions` refusal at `bin/md:149` is true of every write path rather
      than one. **S**

- [ ] **N3 · The scrubber comment tells the truth.** `transcript.py:29` says
      *"the same scrubbing the prompt index uses, so a conversation cannot leak
      a key"*. It is one pattern against `workspace.SECRET`'s ten, and it is
      applied to your turns only — the assistant branch at `transcript.py:200`
      assigns `chunk` raw. Measured: **118 of 7,830 assistant text blocks
      (1.5%)** match `workspace.SECRET` — 51 emails, 30 opaque blobs, 25
      credential assignments, 8 authorization headers, 3 env lines, 1
      connection string — and the shipped scrubber catches none. Either apply
      `workspace.SECRET` to Claude's turns, or delete the comment and say in the
      README that the transcript reader shows what is on disk, unmodified.
      *Done when:* the comment and the code agree, and the README says which
      choice was made. **S**

- [ ] **N4 · `⌘K` sessions default to this repo.** `sessionList()` defaults to
      `here` and filters on `inRepo` — a deliberate, good default, with an
      escape hatch at `workspace.js:1709` for a repo with no history of its own.
      `palSearch` at `:1363` iterates every session on the machine with no scope
      filter and no indication, so the palette returns prompt text from all
      twenty directories. Give it the same default, the same *everywhere*
      toggle and the same escape hatch.
      *Done when:* `⌘K` in one repo does not surface another repo's prompts
      until the toggle is used, and the toggle is visible. **S**

- [ ] **N5 · Say how much history has already been lost.**
      `~/.claude/history.jsonl` remembers **452 sessions back to 2026-04-17**;
      `~/.claude/projects` holds 71 main transcripts, of which 68 correspond —
      **384 sessions can be found but not read.** Anthropic's documentation:
      *"Claude Code clients store session transcripts locally in plaintext under
      `~/.claude/projects/` for 30 days by default to enable session resumption.
      Adjust the period with `cleanupPeriodDays`."* Put the ratio in the status
      strip and print one sentence once, naming the setting. **Print the line;
      do not write the file** — a markdown reader that edits another tool's
      51-line config with a hooks block is one malformed write from bricking the
      user's agent (rule 1).
      *Done when:* the strip shows a labelled ratio from a single named source —
      **452/68, the session ids counted from `history.jsonl` directly**, which
      the reorder decides: L6 now lands after this item, so the index's own
      419/78 would move under an unrelated phase after the strip had already
      printed it. Not a mix, either way. The sentence appears once per install,
      and nothing under `~/.claude` is written. **S**

- [ ] **N6 · The hook leaves a record.** A plan review produces a decision, a
      `systemMessage` and nothing on disk, and because every invocation is a
      fresh ephemeral origin it cannot leave a mark that survives to the next
      one. The hook has fired zero recorded reviews on this machine, and there
      is no way to tell that from two hundred. Two writes: one appended line per
      fire to `~/.local/state/rubricator/reviews.jsonl` — decision, plan path,
      item count, session id, repo, all derived from what the hook already reads
      — and, on approval only and second, the approved plan text plus the
      session id into `.rubricator/`. Grep-readable, `rm`-deletable, no new UI
      surface, no migration. This is a named design change: the hook stops being
      fire-and-forget. Add a navigator group only if the file accumulates
      anything. **The two halves ship apart, under the one number.** The
      `reviews.jsonl` line lands here, in phase N. The approved-plan-text half
      lands with M6 in phase M, because M6 decides what `.rubricator/` is on
      disk — and the escape hatch this item used to carry, *the hook writes the
      exclude line itself*, is retired by M6, which stops writing that line at
      all. Writing it here for phase M to delete is the same work done twice in
      opposite directions.
      *Done when:* three hook fires leave three lines and `md` never reads the
      file; the approved plan text follows with M6. **S**

---

## Phase O — the written record matches the code

The maintainer is the primary victim of a register that lies. Four `[x]` lines
above describe features that do not exist, and one of them has a data-loss
shape behind it. An hour of bookkeeping restores a planning instrument the rest
of this programme depends on. See [`scope-plan.md`](scope-plan.md).

- [ ] **O1 · Four false register lines.** `C7` claims a document index cache at
      `~/.cache/rubricator/index/<roothash>.json`; `grep -rn roothash` finds
      only prose, `_cache_read`/`_cache_write` serve sessions alone, and
      `workspace.py:6-7` argues in a comment that document caching is not worth
      it — a feature that was reasoned against, not one that drifted. `B1`
      claims `untracked` and `front-matter tag` facets; `workspace.js:1149`
      ships `notes · stale · 14 days`, so the line is wrong in both directions.
      `C6` claims a one-time localStorage migration; a lazy per-document one
      exists at `workspace.js:76-90` and cannot cross the `file://` → `http://`
      origin boundary. `E3` claims a node budget; there is a manual *Draw it*
      gate and an advisory string above 120 nodes, and no cap at all.
      *Done when:* each of the four lines states what is in the code, and C7's
      claim is either deleted or built. **S**

- [ ] **O2 · Multi-root becomes read-only, and says so.** Reproduced:
      `build([rubricator, repo A])` gives 110 documents, 99 of them with a
      stale key of the form `repo A/repo A/…` matching nothing and
      `commits: 0`, because `workspace.py:399-400` prefixes inside the
      `find_docs` loop and `:404-405` prefixes again. Notes for every root go to
      `roots[0]/.rubricator/notes.json` — a note taken on the second repo lands
      in the first — `asset()` resolves against `roots[0]`, and
      `remember_project` stores single paths, so a multi-root workspace can
      never be reopened. Measured usage: four recents, all single paths; all
      three cached pages single-root. **Do not finish the feature** (X22).
      Refuse `/notes` writes for non-first roots server-side, badge the row with
      its repo, drop `E8` to `[~]`, say it in `md --help`. Ride along the
      first-contact fix: `md ~/Repositories` silently builds a 1,982-document,
      git-less workspace in 0.65 s and emits a 41.1 MB page.
      *Done when:* a note attempted on a second-root document is refused with a
      reason rather than written into the first repo, `E8` reads `[~]`, and
      `md ~/Repositories` says what it is about to do. **S**

- [ ] **O3 · `continue-plan.md`'s measurement was confounded.** Rows 3 and 4 of
      its §1 table — *a shell tool call in `-p`: ran, with no prompt and no
      approval event* and *the same, with `--permission-mode manual`: ran
      anyway* — measured the author's own `~/.claude/settings.json`
      `"defaultMode": "auto"`, not headless Claude. With default or manual mode
      in an untrusted directory the identical call is **denied**, visibly, in
      `result.permission_denials`. Separately, a `PermissionRequest` hook event
      is documented and exists; run on 2.1.241 it **did not fire once** under
      `claude -p` in any configuration, while `PreToolUse` from the identical
      config fired every time. J1–J4's read-only scope is still sound, for a
      different reason than the document states. A shipped plan is not
      rewritten, so this lands as a `> **Since then.**` note under the table
      rather than as an edit to the rows. The same confounded sentence is in
      this file, under *Planned — continuing a session*: *"Headless Claude does
      not ask — verified, including under `--permission-mode manual`"*. That one
      is a register line and is edited in place.
      *Done when:* the note states the auto-denial and the
      `PermissionRequest` result, carries *measured 2026-08-23 against claude
      2.1.241*, and sits where a reader of rows 3 and 4 cannot miss it; and the
      *Not planned: a permission UI* paragraph above no longer claims a manual
      permission mode was tested. **S**

- [ ] **O4 · The platform matrix, and the Chrome path fixed at every site.**
      `/Applications/Google Chrome.app` is a literal at `bin/md:175, 176, 188,
      189, 417` and `hook.py:20` — six occurrences, **four guard sites**: three
      in `bin/md` (`:175`, `:188`, `:423`) and one in `hook.py` (`:110`). Only
      two go through a `CHROME` variable, so a fix scoped to `bin/md` leaves the
      hook broken. The degradation is cosmetic — every guard falls back to plain
      `open` — so fix it as a one-time chore with one rule: **all four sites or
      none**, searching `/Applications`, `~/Applications` and `mdfind`.
      Separately, write the capability matrix into `docs/` as a decision record,
      and write it as a **closed** question: open question 4 was answered on
      2026-08-24 — macOS-only is a decision, not a *not yet*. The six macOS-bound
      capabilities — app window, AppleScript window close, native folder chooser,
      `.command`/LaunchServices dispatch, `textutil` + JXA/PDFKit, `shasum` —
      each with its honest Linux answer, and nothing promised beyond them. **Do
      not extract `share/platform.py`**: a seam built before the port it must
      accommodate is the wrong seam, and the port is not coming.
      *Done when:* all four guard sites resolve Chrome the same way, and the
      matrix answers the first question a Linux visitor asks without promising
      anything. **M**

- [ ] **O5 · The standing rules, written down once.** Twelve decisions this
      investigation settled that will otherwise be re-litigated — the register
      line said six; twelve is what was settled. Each carries the measurement or
      the enumeration that justifies it, because a rule with no evidence under
      it is a preference, and a preference loses to whoever argues best on the
      day. The numbers are load-bearing: four plan documents cite rules by
      number, so a rule may gain a clause but the list may not be renumbered.
      Record with them the honest amendment to the README's *nothing is written
      into your files*. M6 now lands before this phase and withdraws the append
      at `workspace.py:540-546`, so what O5 records is the post-M6 state: the
      notes file is not hidden, it appears in `git status` by design, and
      committing it is the supported path (rule 3). Do not describe a behaviour
      that will already be gone.
      *Done when:* the twelve are in [`scope-plan.md`](scope-plan.md) §5, each
      with its justification, and the README's sentence is amended to the post-M6
      truth. **M**

- [ ] **O6 · The shipped plans name four private repositories.**
      `workspace-plan.md:183-185` tabulates `<repo>/requirements.md`,
      `<repo>/ROADMAP.md` and a `public-docs/features/*` path by name;
      `architecture-plan.md:182-186` and `conversations-plan.md:192` reproduce
      mock UI carrying repository names and a prompt fragment; `README.md:400`
      names two. The five plans added in this programme use `repo A`–`repo D`
      instead, and `measurements.md` states the rule — so the repository now
      contradicts itself, and the older half is the more revealing one. This is
      not a code change and not a correction of fact, so the *plans are not
      rewritten* convention does not obviously cover it: a `> **Since then.**`
      note cannot un-publish a filename. Decide whether the names stay,
      then make the whole repository agree either way.
      *Done when:* `grep -rE '<the four names>' --include='*.md' .` returns
      either nothing or only lines the owner has explicitly kept, and
      `measurements.md`'s parenthetical is updated to match.

---

## Phase P — what the tool is for

Every claim on the front page has to be true before it is worth making louder,
and three of the claims a rewrite would naturally reach for were measured false.
This is also where the tool gets a version tag and a distribution channel, which
only make sense once K–O hold. See [`scope-plan.md`](scope-plan.md).

- [ ] **P1 · The front page stops understating the tool.** `README.md:26` says
      *"One bash script and a page."* Measured: **7,372 lines across 18 files**
      of own code (7,379 with `vendor.txt`; 12,314 with the five vendored
      libraries, which the next sentence already discloses). *One bash script
      and a page* describes `bin/md` (429) plus `template.html` (422) — 11.5% —
      while omitting an HTTP server, a subprocess launcher with a hardcoded
      terminal table, and an extractor that shells to `osascript`. Understating
      your own surface is worse for trust than stating it, and the best trust
      paragraph in the document is at line 465 of 473. Fix three more sentences
      while there: `README.md:287-289` promises cross-origin note sharing that
      the same-origin policy makes impossible — the sidecar is a **decision**,
      not a compromise; `README.md:185` says *17 MB parses in 0.05 s* when the
      largest transcript here is 105.0 MB and parses in 0.28 s; and
      `README.md:124` calls a lost anchor *resolved*. **One sentence in here
      waits, and only that one:** whether the page may say the hook's Approve
      approves turns on open question 5, which is awaiting a measurement rather
      than an answer. Write the rest and leave that sentence out until the
      keypress has been taken; do not stall the item on it.
      *Done when:* line 26 states the real surface, the trust material is above
      the fold, no sentence promises cross-origin note sharing, `README.md:185`
      carries the measured 105 MB / 0.28 s, and `README.md:124` no longer calls
      a lost anchor resolved. **M**

- [ ] **P2 · Cut four sections; backfill with what ships.** Themes, *Extending
      it*, the graph paragraph and the power-flag block come out of a
      4,074-word, twenty-heading README — advertising an extension API before
      you have a user invites the reader to ask who else is building on it.
      Backfill with three things, in this order. (a) **The review layer over
      documents that keep changing** — open question 1, answered on 2026-08-24:
      *living documents*. The page opens with the owner's own wording, which is
      the plainest statement of the thesis this project has produced: *"Mark up a
      document an agent is going to rewrite, and still have your marks
      afterwards. Read it, mark the parts that matter, send the marks to your
      agent. When it rewrites the file, your notes follow their text to the new
      lines — and the ones whose text is gone say so."* `scope-plan.md` §7
      carries it verbatim, and the two paragraphs of its argument follow it here.
      It is the only candidate whose mechanism works today on the first file a
      stranger opens; the document↔session↔git join is **88% empty** (49 of 419
      sessions carry a file list) and has a thirty-day half-life by construction.
      (b) **PDF and Word**, which already carry the full review layer with the
      page number surviving into the export, and are unmentioned until line 377
      of 473. (c) The **durable** half of the history index: every prompt typed
      in 18 project directories over 128 days, in one field, in a second. Do not attach the file-join to that sentence. Add the
      two missing screenshots, move `--sessions` into the first code block, and
      rewrite the GitHub description. Editorial rule throughout: *does this help
      a stranger decide, or an existing user operate?*
      *Done when:* the four sections are gone, the first three paragraphs are
      the three above, the page opens with the owner's wording as quoted, and
      both screenshots are in the repo. **M**

- [ ] **P3 · Delete the graph.** Not for the reason first given — the spring
      loop was ported verbatim to V8 and runs in **19.5 ms** at 299 nodes,
      234 ms at a thousand, so there is no freeze and that claim is struck (X2).
      Delete it because it is structurally illegible: it draws only connected
      nodes, which is **11 on a 99-document repo** and **300 on a 502-document
      one**, into a fixed 900×560 viewBox with no zoom or pan — 1,680 px² per
      labelled node. There is no corpus size at which it is both legible and
      informative. Its edges also come from the target extraction L just
      relabelled, so keeping it means re-tuning `g.length > 12` and
      `hit.length <= 15` every time that subsystem moves.
      *Done when:* `viewGraph`, `graphEdges` and their CSS are gone, `E3` reads
      *removed*, and the register says why in one paragraph. **S**

- [ ] **P4 · Prior art, named and numbered correctly.** The README does have a
      prior-art section, at line 442, since the first commit — the finding that
      said otherwise was wrong. What it lacks is numbers, scale and the native
      alternatives. Name, with figures dated to the day they were fetched:
      **plannotator**, 7,971 stars on 2026-08-23 (not *8,000+*, which is
      literally false), 1,072 commits, created **2025-12-28** — 7 months 21 days
      ahead — 147 releases, PR/MR diff review, a `PermissionRequest` hook where
      rubricator registers `PreToolUse`, and a Version Browser that saves each
      plan submission and shows a change badge on resubmit, which is **the one
      competitive gap that is real**. **PlanBridge**, MIT and localhost, 27
      stars. **Moat**, hosted. **Imark**, 46 stars in eighteen days, storing
      notes in the `.md` as HTML comments. And the native alternatives: Claude
      Code's `Ctrl+G` opens the plan in `$EDITOR`, and **the vendor's own VS
      Code extension automatically opens the plan as a full Markdown document
      with inline comments.** Three phrases must not be printed: *no Bun
      needed*, *nobody has a verb grammar*, and *Anthropic tried browser plan
      review and local won*. The Claude-session-viewer star total does not
      reconcile — print the repositories and their own numbers.
      *Done when:* the section exists, every number in it matches a live API
      call and carries its date, and none of the three struck phrases appears
      anywhere in the repo. **S**

- [ ] **P5 · The keyboard tool gets a keyboard.** Three small repairs, none of
      them an accessibility project. `all:unset` appears **23 times** across the
      three stylesheets and resets `outline-style`, so the platform's focus ring
      is gone by construction — one global
      `:focus-visible{outline:2px solid var(--accent);outline-offset:2px}`
      restores it. `shell.js:437` handles `Tab` with no shift check, so `⇧Tab`
      advances the palette's kind filter instead of stepping back through it.
      And the whole workspace keymap (`⌘\`, `⌘E`, `⌘B`, `⌘1-9`, `⌘⌥[`, `⌘⌥]`,
      `⌘W`) exists only in the README, which is a tool whose interface *is* a
      keymap failing at its own premise — port the reader's existing `⌘/` sheet
      (`ui.js:288`) rather than inventing a second one, and hang it off `#more`.
      Drop the `if (navMode === 'notes') setNavMode('docs')` side effect at
      `workspace.js:1683-1689`. **Do not bind `⌘F` in the workspace** — the
      reader binds it and the workspace deliberately does not, so it falls
      through to the browser's find bar, which already has a hit count,
      next/prev and wrap-around. Say that in the sheet.
      *Done when:* every focusable control shows a focus ring, `⇧Tab` reverses,
      `?` lists the keymap, and `/` in Notes mode filters notes. **S**

- [ ] **P6 · A tag, topics, a badge.** Zero tags, zero releases, zero topics,
      empty homepage, no CI badge. Cut `v2.0.0`, set six topics, point the
      homepage somewhere, add the CI badge from K3 — each answers a specific
      reader, and the badge is the only place K3's assertion becomes visible to
      someone who has not read `.github/`. **Do not confess the project's age in
      the README**: a stranger already suspicious of a five-day-old repo is
      confirmed, not reassured, and the commit dates say it anyway. **Do not
      turn on Discussions** until someone files an issue.
      *Done when:* `gh api repos/TheRealVale/rubricator` returns a non-empty
      `topics`, one release, and the README's first line carries a green badge.
      **S**

- [ ] **P7 · The plugin manifest, in the repo.** Ship
      `.claude-plugin/marketplace.json`, `plugin.json` and `hooks/hooks.json`,
      so a Claude Code user can run `/plugin marketplace add
      TheRealVale/rubricator` and get the hook without `install-hook.sh`
      performing surgery on `settings.json`. A few dozen lines of JSON that
      **deletes a script**. Note the limit honestly: a plugin's `bin/` is added
      to *the Bash tool's* PATH, not the human's interactive shell, so the
      channel delivers the hook and only the hook. **Skip the
      community-directory submission** — `anthropics/claude-plugins-community`
      lists 2,282 plugins; entry 2,283 is not distribution. No longer blocked:
      open question 2 was answered on 2026-08-24, and several people using the
      tool without effort or blockers is a goal, so the channel has someone to
      deliver to. Both limits above stand unchanged.
      *Done when:* a clean machine can install the hook through
      `/plugin install` with no shell script, and `install-hook.sh` is deleted
      or reduced to a wrapper. **S**

---

## Phase Q — the additions that survived

Five additions — four features and a flag — that are both wanted and buildable
on a corpus that now tells the truth. Each reads from a subsystem K–O corrects;
built earlier, every one would present a confident answer computed from a signal
this register does not trust. Q has no plan document of its own.

- [ ] **Q1 · Document → sessions, designed for the empty case.** `D.touches`
      maps 1,312 files back to session ids at the 2026-08-23 count, and has
      exactly two consumers: a search-ranking denominator and 9×9 px dots. `G4` has been `[ ]` since it
      was written. Build it — but design the empty state first, because it *is*
      the common state: 264 of 330 repo B documents and 440 of 502
      repo C documents have zero sessions, and the mean over covered
      documents is **1.09**. When `D.touches[d.abs]` is empty, say *no session
      on record touched this*, with N5's `cleanupPeriodDays` sentence. Label the
      commit dots at `workspace.js:814`, which carry no title and no data
      attribute, in the same commit. Make `--deep` the default while you are
      here: 1.01 s against 1.02 s warm, and it adds 299 `touches` entries (+23%).
      *Done when:* a document with no sessions explains why in a sentence that
      names the setting, commit dots have hover titles, and `--deep` is no
      longer a flag. **M** — depends on N5.

- [ ] **Q2 · `status:` from front matter, as a facet.** A document that still
      says *planned* while the code shipped is a falsifiable claim, unlike a
      churn count. Parse `status:` from **YAML front matter only** — no
      first-line prose matching, no state machine, no classifier: ~20 distinct
      freeform status shapes across 80 files in one repo, of which exactly one
      repeats, so a prose parser is a week of whack-a-mole. Show it in the row
      and add it to the facet list beside `has notes` and `14 days` — L4 either
      removes or repoints `stale`, so land Q2 after it or the facet row is
      written twice. A user who can filter to *everything that still says
      planned* and sort by age finds the lies themselves, and rubricator has
      asserted nothing it has to defend.
      *Done when:* filtering to a status value lists exactly the documents whose
      front matter carries it, and documents without front matter are absent
      rather than guessed at. **S**

- [ ] **Q3 · The dossier is rendered, and what persists is the query.**
      `buildDossier()` (`workspace.js:757-794`) is assembled on every keystroke
      and thrown away — it is only ever copied to the clipboard, and it drops
      the excerpts `exportQuote` already knows how to produce. Render it on
      screen so it can be read and reopened, and include the excerpts. Then add
      a named saved search — `{name, query}` — that **re-runs** `buildDossier()`
      on open. Persist the selection, never the assembly (rule 4).
      *Done when:* a saved pack opened a week later reflects the corpus as it is
      today, and no assembled dossier is ever written to disk. **M** — depends
      on L3.

- [ ] **Q4 · The Notes surface copies what it renders.** Give it a Copy that
      emits exactly what is on screen — `rel:line [verb] note`, grouped by
      document — with a header saying *line numbers as of when each document was
      last opened*. That header is not decoration: `reanchor()` has exactly one
      caller, `openDoc()` at `review.js:564`, so every item for a document not
      opened this run carries a `lineStart` from whenever it was last opened,
      possibly several agent rewrites ago. Keep the numbered, excerpt-carrying,
      line-anchored export **single-document**, because single-document is the
      only scope in which its anchors have been re-verified, and say that is a
      feature.
      *Done when:* the Notes surface has a Copy, its output is byte-comparable
      to what is rendered, and the cross-document path carries the header. **S**
      — depends on L3, M1.

- [ ] **Q5 · `md --json` — facts, not judgements.** The machine-readable door
      for a local CLI is a flag, not a protocol: `workspace.py:751` already
      returns documents, stale, sessions, prompts and touches as one JSON
      structure. Emit it to stdout. It works from Bash, from a script, from cron
      and from an agent that has never heard of MCP, and it adds no process, no
      lifetime and no spec dependency. **Emit facts** — documents, headings,
      notes, last-commit dates, session ids — and not the staleness verdict
      until that signal is validated or deleted, and not prompt text, which is
      N2's rule applied to a second write path.
      *Done when:* `md --json .` prints a parseable index to stdout, exits 0,
      starts no server, and contains neither a `stale` verdict field nor prompt
      text. **M** — depends on L4 and M6. It stays in Q even though *readable by
      agents* is now part of what the tool is for: `.rubricator/` is already
      clean JSON an agent can `cat`, which is the sentence X9 was killed on, so
      nothing about the purpose is blocked on this. What Q5 adds is an interface,
      and an interface ships last — before L4 it would carry the staleness
      verdict through a door built for automation, where nobody reads the caveat
      under the table, and before M6 its note keys are absolute paths from one
      machine.

---

## Killed

Written out because this is what stops it coming back. Thirty-one proposals,
each with the measurement that killed it. This list is as valuable as the work
list above; the rationale behind the larger entries is in
[`scope-plan.md`](scope-plan.md) §12, [`signals-plan.md`](signals-plan.md) §6.5,
[`anchoring-plan.md`](anchoring-plan.md) §6 and
[`retention-plan.md`](retention-plan.md) §7.

### Killed on evidence

| | what | why |
|---|---|---|
| **X1** | The `window.MD` CI assertion | Returns **1 on the broken artefact** — `review.js:570` defines `window.MDReview` and `review.js` is one of the eight copied files. The proposed green tick passes on the exact bug it was written to catch. K3 replaces it. |
| **X2** | The performance case for deleting the graph | Ported verbatim to V8: **19.5 ms** at 299 nodes, 234 ms at a thousand; `graphEdges`' 919,500 comparisons cost 3.0 ms. There is no freeze. The graph still goes (P3), for a reason that was measured. |
| **X3** | `md --standing` — inferring standing rules from the annotation corpus | Its own text concedes it says nothing useful under ~50 annotations; three exist. It also writes into `CLAUDE.md`, which is normally tracked — forbidden by rule 1. |
| **X4** | "Index all slash commands" as a 15.9% recovery | 82% of the 756 dropped prompts are `/model`, `/compact` and `/clear`; the real loss is 71 prompts, 1.5%. The finding also named two commands that occur zero times on this machine — confabulated inside a finding marked verified. A skiplist rides along in L6. |
| **X5** | `SPEC-3` — that Approve does not actually approve, and `updatedInput` as a third outcome | The quoted sentence is scoped to non-interactive `-p`, and the two vendor pages disagree exactly about the interactive case rubricator runs in. Unresolved, not broken — open question 5, one plan and one keypress. The edited-plan half duplicates `Ctrl+G`, which ships natively. |
| **X6** | A `defer` button in the hook | The docs say Claude Code honours `defer` **only** under `-p`; an interactive session logs a warning and ignores the hook result. A defer button would silently discard the deny/ask fallback — a regression shaped like a feature. |
| **X7** | The `docs.claude.com` → `code.claude.com` URL sweep | `grep -rn "claude\.com"` across the repo excluding vendor returns **zero hits**. A chore invented for a problem the repo does not have. |

### Killed on scope — the tool would become something else

| | what | why |
|---|---|---|
| **X8** | Diff and PR/MR review | The entire justification was market size, and the vendor telemetry behind it does not support the claim made of it: neither vendor defines an *AI PR* or an *acceptance rate*, the two measure different contrasts, and the headline ratio is arithmetically wrong. The target is meanwhile occupied by 1,072 commits of TypeScript with Perforce and Jujutsu support, and the work is a diff parser, hunk anchoring, a side-by-side render and forge integrations. |
| **X9** | An MCP server | For a local tool that already has a CLI, **the agent's Bash tool is the MCP server** — `open_notes` is `cat .rubricator/notes.json`, `search_documents` is Grep and Glob. It buys a calling convention and charges a long-lived process, a second security surface the `actions.py` allowlist reasoning does not cover, and a spec dependency. Q5 is the answer. |
| **X10** | `md sessions --archive` / a durable transcript copy | ~960 MB per 30 days, unscrubbed. It permanently defeats the vendor's own privacy control, whose first documented mitigation for plaintext credentials is to *lower* `cleanupPeriodDays`; it survives `claude project purge`; and it does not restore resumability, because `claude --resume` needs the file where the sweep found it. One integer dominates it on every axis. N5 is the ten-line answer. |
| **X11** | The document map / PageRank over the corpus | The document graph is nearly edgeless — **0 doc→doc links across 330 repo B documents**, 1 across 84 in repo D. PageRank on an edgeless graph returns the uniform distribution, so it would ship an arbitrary ordering with an algorithm's authority behind it, in the two repos where a newcomer needs it most. |
| **X12** | Coverage — the inverse map of code files no document names | 916 of 1,702 tracked repo B files (54%), 1,223 of 2,169 on repo C (56%). A to-do list with 1,223 rows is wallpaper, grouping by directory makes it *every directory*, and the unit is wrong: nobody documents individual files. |
| **X13** | Staleness as the product's thesis | `targetChurn` correlates **0.84** with the number of paths a document quotes and **0.12** with its age; 9–11% of resolved tokens are arbitrary first-wins picks; 71.5–92.4% of judgeable documents are flagged. Positioning is the one decision a later commit cannot undo, and this one obliges a solo maintainer to defend an accuracy table against ground truth that does not exist. |
| **X14** | Widening the target-extraction whitelist | As specified it costs **5.03 s on repo C — 11× the entire current index**; `all_paths` comes from the git *log*, so 30% of it is deleted files and it misses 24 tracked ones; and it makes the other half worse, taking nav flags from 46% to **62%** of the corpus. The two complaints have remedies that pull against each other. |
| **X15** | The Stale × sessions × notes join, and the five-section Brief surface | Polish over a signal that fires on 71.5–92.4% of what it can judge and truncates at 40 rows. A more attractive way to be told the same unhelpful thing 231 times. |
| **X16** | Second-read mode with shadow copies of previous document versions | Refuted by the author's own history: wholesale rewrites are **0.0–3.2%** of 2,982 markdown revisions and the median revision changes 6–20 lines. It also cannot reach the flagship path — three consecutive hook runs gave three different origins and the page it serves has no disk store. |
| **X17** | Agent-proposed marks | Self-labelled speculative, false-positive rate explicitly unmeasured, and its failure mode is the failure it claims to fix: a plan with six agent-proposed marks reads as reviewed, so a miss becomes invisible *and* endorsed. The only proposal that adds a model call to a deterministic offline tool. |
| **X18** | Dwell/scroll telemetry as an attention mirror | Its own evidence concedes the load-bearing joint is untested. The honest number is available for free without any telemetry — M8. |
| **X19** | `md --audit` — a self-reported security inventory | A **hand-maintained** inventory in a repo that has already shipped a broken hand-maintained inventory (rule 9). When `install.sh`'s list drifts you get a blank page; when this one drifts the tool lies about its security surface. The property already exists, better: 7,379 readable lines. |
| **X20** | Contradiction marks, marks-as-threads, a Suggest verb, unanchored notes, promote-to-document | Machinery for a corpus of **three real annotations on two documents**. The Suggest verb's one-key apply is separately forbidden by rule 1; promote-to-document competes with the filesystem and loses. |

### Killed on sequencing — right idea, wrong month

| | what | why |
|---|---|---|
| **X21** | The thirty-day instrumentation freeze | The data already existed and was read without instrumenting: 3 real marks, ~30 document-opens, 31 storage records, and ten real documents opened and closed with **zero verbs pressed**. n=1 and the n is the author, so it is a diary — and it profiles the wrong population, because a stranger cannot install the tool. The two lines that survive are the `at` stamp (M6) and one line per hook fire (N6). |
| **X22** | Finishing the multi-root workspace | A day to a week on the live tier for a feature with a **measured user count of zero** — four recents, all single paths; all cached workspaces single-root. Scoped down in O2; the named-workspace-file design remains right the day someone needs it. |
| **X23** | Porting match-quote + approx-string-match (525 lines) | The ten-line longest-line step **beats it at the 0.90 threshold** (62.6% against 42.1%) with better precision. The port buys the last 15–19 recovery points for 525 vendored lines the maintainer owns forever, a BSD-2-Clause entry, a hand de-typing with no upstream path and a threshold policy. Revisit when a real user reports a miss M2 could not catch — at which point there is also a test corpus. |
| **X24** | Annotation-scoped staleness (*you marked this paragraph and the code under it moved*) | The best idea in its cluster on merit and unbuildable today: its input is annotations, and there are three. Its second half — say *cannot assess* when a document yields zero targets — is already in L4. |
| **X25** | Annotating a conversation turn | A second binding model in `review.js`, whose single-document invariant is load-bearing — M7 is a bug in exactly that invariant with two documents in play — keyed to a transcript that expires in 30 days, so marks would silently orphan themselves. A worse version of the problem phase M just fixed, in a place where no ladder can help. |
| **X26** | Exporting a mark as a candidate `CLAUDE.md` line | A write path into a tracked file, from a tool with no tests, for a user who has not yet used the read path. Forbidden by rule 1 and by sequencing. |
| **X27** | The decision queue as the workspace's default landing state, and a ranked read-queue | All three ranking inputs are unavailable: churn-in-mentioned-files is null for 87 of 99 repo A documents, open-annotation count is 3 machine-wide, and read-state does not exist. A front door computed from three empty inputs renders *nothing to decide* on a repo where 24 documents changed today. |
| **X28** | Grouping subagent transcripts by workflow run | Twelve `wf_*` runs across three repos over eleven weeks is real activity, but the largest are read-only analysis panels whose output the user reads immediately — **evidence of activity mistaken for evidence of pain**. Its own reshape gated it on the usage log, which is X21. The free part (`--deep` by default) rides along in Q1. |
| **X29** | A Memory navigator mode | Already shipped and nobody noticed: `md ~/.claude/projects/<slug>/memory` routes to the workspace, the non-git walk picks up all 102 files, and every verb works today. What is left is a README paragraph, which belongs in P2, plus three lines of bash for an alias. |
| **X30** | Pinning `AGENTS.md`/`CLAUDE.md` in the navigator | Zero `.mdc` files and zero `.cursor*` directories exist under `~/Repositories`; one `AGENTS.md`, eight `CLAUDE.md`. A permanent special case in the sort order, plus a nested-closest-wins policy, bought with one file of local evidence. The `.mdc` extension rides along in L5 as a chore. |
| **X31** | Thirteen research and competitor claims the investigation produced and verification destroyed | The ten research claims are enumerated in `docs/citations.md`'s *Do not cite*, which is the only page a claim may be quoted from at all (rule 11); the three competitor claims — a star count rounded past the truth, a lead of 7 months 21 days written as *seven months*, and a launch date placed four months late — are corrected in `scope-plan.md` §10. None of the thirteen may reach a README, a plan document or a commit message. The recurring shapes: a star count rounded up past the truth, a lead of 7 months 21 days written as *seven months*, a competitor's launch date placed four months later than it was, a vendor percentage restated as a multiple in the wrong direction, one quantity measured two ways and reported as before-and-after, a retraction that never happened, a competitor's build-time dependency sold as an end-user cost, and *nobody serves X* — never write that; write *we serve X*, which is unfalsifiable in the harmless direction. |

---

## Standing rules

Twelve, adopted by this register. Each is stated here in one line; the
measurement or enumeration under each is in
[`scope-plan.md`](scope-plan.md) §5, which O5 writes. Four plan documents cite
these by number, so a rule may gain a clause and the list may not be renumbered.
Rule 3 was withdrawn and replaced on 2026-08-24, when the owner answered open
question 2; it keeps its number for that reason, its text here is §5's word for
word rather than a shorter restatement of it, and rule 1 gained a clause in the
same round.

1. **The write rule.** Rubricator may write only inside `.rubricator/` in a root
   it was pointed at — whose enclosing git repository reads as that root for
   `.rubricator/` itself, and for nothing else — inside `~/.config/rubricator/`,
   `~/.cache/rubricator/` and `~/.local/state/rubricator/`, and to a path the
   human typed in the same gesture. Never a file git tracks, never a file it
   found by indexing. Proposing a change the human applies is an export; applying it is not — at
   any confidence, behind any flag.
2. **Nothing that must survive a restart may live in `localStorage`.** Per-root
   state in `.rubricator/`, per-user state in `config.json` behind the
   whitelist; `localStorage` is within-run convenience only.
3. **More than one reader, and git is the transport.** Committing the notes is
   the supported path: one file per document, so two people's marks merge rather
   than collide, and each mark carries a `by` and an `at`. No server, no account,
   no sync, no locking — two people who mark the same document get a git conflict
   in a small JSON file, and rubricator's only help is that the file is small
   enough to resolve by hand in a minute.
4. **Persist the selection, never the assembly.** Rebuild on every open.
5. **No MCP server.** The machine-readable door for a local CLI is a flag.
6. **No database.** The Logseq DB split is the standing argument.
7. **Do not generate the artefact.** No spec, no plan, no task list, no
   template. The tool reviews documents; it does not write them.
8. **An empty result must say which empty it is** — *nothing matched* or
   *nothing could be judged* — with counts.
9. **No hand-maintained inventory of files in shipped code.** Generate it, or
   assert it in CI. This is what `install.sh:59` cost.
10. **Claim coverage and time-to-first-mark; never code quality.** The
    maintainability literature is contested from both directions.
11. **No research sentence is copied.** A claim is quoted from a `citations.md`
    card in that card's wording with its qualifier attached, and vendor
    telemetry names the vendor in the same sentence as the number.
12. **Never scope a design on a documented-but-unfired platform feature**
    without re-running the measurement against the then-current build.
    `PermissionRequest` is documented and fired zero times on 2.1.241.

---

## Open questions — the owner's, not the register's

Everything else in phases K–Q was measured. These six could not be, and each
blocked something. The owner answered all six on **2026-08-24**. Five are
decisions and are recorded here rather than deleted — a register that quietly
drops its own questions is the defect this programme is about — and the sixth is
not an answer but a measurement the owner will take, so it stays open.

| # | question | the answer, and its date | blocks |
|---|---|---|---|
| 1 | **What is `md` for, in one sentence?** The register's answer was *the review layer for documents that keep being rewritten*, chosen because it is the only candidate whose mechanism works today. The alternative was the document↔session join, which is 88% empty and has a thirty-day half-life. | **Living documents** — 2026-08-24. The owner's own wording is in [`scope-plan.md`](scope-plan.md) §7 and opens the front page; P2 quotes it. The join is not the thesis. | P1, P2 — both released |
| 2 | **Is there a second reader, actual or intended, within six months?** Almost everything deferred — multi-root, per-document note files, authorship, threads, the plugin channel — turned on this, and the measured answer was no. | **Yes, and multi-person use is a goal** — 2026-08-24. Readable by agents; several people able to use it without effort or blockers; seeing who did what is wanted. Standing rule 3 is withdrawn and replaced, and M6 carries relative keys, one file per document, `by` and `at`. It revives nothing: X20, X9 and X17 stay dead, and it is not X22 — several people reading one repository is not one person reading several. *git blame for annotations* was the owner's own idea, floated with a question mark: cheap once `by` and `at` exist, no evidence behind it, no item, and nothing planned on it. | O2, O5, P7 — all released; O2's scope is unchanged, because the answer is about readers, not roots |
| 3 | **Will `md --sessions` run on a machine with client work on it?** If yes, N moves ahead of M and probably ahead of L. Nothing in phase N's content changes either way — only its place in the queue. | **Yes, already** — 2026-08-24. Phase N runs second, after K, and ahead of L as well; the population changed, not a measurement, and no figure in [`retention-plan.md`](retention-plan.md) moved. The build order is in the phases preamble above. | N1–N4's position |
| 4 | **Is macOS-only a decision or a "not yet"?** O4's matrix cannot be written honestly without an answer, and the answer decides whether N1 moves the cache or excludes it in place. | **A decision, not a *not yet*** — 2026-08-24. O4 writes the matrix as a closed question and promises no port, and the refusal to extract `share/platform.py` now has a reason rather than a deferral behind it. N1 keeps its *assert the property, not the mechanism* rule; neither mechanism is ruled out by a port that is not coming. | O4, N1's mechanism |
| 5 | **Does Approve actually skip Claude Code's approval menu?** Two vendor pages disagree, and the disagreement is exactly about the interactive case rubricator runs in. It cannot be settled by an agent — it needs one human pressing Approve once and watching. | **Still open, and the only one.** Not an answer but a measurement, and the owner will take it: one plan, one keypress. The procedure is under this table. | P1, in part — one sentence of it, and K5 shares the hook fire |
| 6 | **Is the diff lane off the table permanently, or a 2027 bet?** This register cedes it (X8). If the owner disagrees, P4 says something different about the incumbent and phase Q's value changes. | **Ceded permanently** — 2026-08-24, not deferred to a 2027 bet. X8 stands, [`scope-plan.md`](scope-plan.md) §12 records it as settled rather than hedged, and P4 names the lane as the incumbent's and says why rubricator will not follow. | P4 — released |

> **The measurement open question 5 is waiting on.** In an interactive Claude Code
> session — not `-p` — in a repository with the hook installed, ask for something
> large enough that Claude proposes a plan, and let it call ExitPlanMode. Note
> `claude --version` first. When the rubricator window opens, press Approve and
> send. Then watch the terminal. Either the session starts executing the plan with
> no further prompt, in which case `permissionDecision: "allow"`
> (`hook.py:164-166`) is sufficient in the interactive case, **X5** stays dead and
> P1 may say the hook approves; or Claude Code's own approval menu appears anyway,
> in which case Approve is a suggestion, P1 must say so, and this register gains an
> item. Write down which happened and the version. Thirty seconds, once.

A rider, and not part of the thirty seconds: the same hook fire also answers
standing rule 12's gate on **K5**, if one temporary line is added after
`payload = json.loads(...)` (`hook.py:193`) to print the payload's keys. That is
a code edit, so it is a separate decision from pressing Approve once — but it is
the same fire, and taking both at one sitting saves the second one.

---

## Done

All five phases are in, plus the shell they were leading to. What the plan called
*room deliberately left* is now reachable rather than hypothetical: a provider is
a file in `~/.config/rubricator/providers/`, a view is a file in
`~/.config/rubricator/views/`, and a workspace can hold more than one repo.

What is deliberately still missing, and why:

- **No daemon by default.** `md serve` exists for when you want one, but the
  ordinary path still starts a server that dies with its window.
- **No cloud, no sync, no account.** Nothing is uploaded, and `--sessions`
  refuses `--out` (`bin/md:149`). That refusal guards one write path, not all of
  them: the default static build still bakes the prompt corpus into
  `~/.cache/rubricator/workspace-<hash>.html` — 8.0 MB at mode 0644 — which is
  the same corpus by another route. N1 and N2 make the sentence true of every
  path.
- **No agent loop in the window.** A session can be read here and continued
  here (J1–J4), but only for thinking — the tools that change your repo stay in
  the terminal. See [`continue-plan.md`](continue-plan.md) for why that is a
  decision rather than a gap.
- **A conversation is not annotatable.** The review layer binds to a document
  and a chat bubble is not one; §7b of the conversations plan says what it would
  take.
- **macOS only**, in six places rather than three. The counted bindings are: the
  app-window launch through `open -na "Google Chrome"`, the AppleScript window
  close, the native folder chooser, `.command`/LaunchServices dispatch for
  *open in terminal*, document extraction via `textutil` and the JXA/PDFKit
  bridge, and `shasum` where Linux has `sha256sum`. The first four degrade
  gracefully; the fifth is the whole of PDF and Word, and the sixth is silent.
  O4 writes the matrix, with the honest Linux answer beside each — and
  deliberately does not extract a `platform.py` for a port that is not coming.
  Since 2026-08-24 that is a decision rather than an admission: macOS-only is the
  answer, not a *not yet*.
