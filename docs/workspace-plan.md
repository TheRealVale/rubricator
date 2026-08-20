---
title: markside — workspace mode
status: proposal
date: 2026-08-18
---

# Workspace mode

> Point markside at a repo root. Index every markdown file in it, search across all of
> them, see which are alive, and find the ones that talk about the same thing.

The driving need is one sentence from the brief: **"often I ask myself where I noted
something, so I can search."** That is the real problem. Everything else in this plan is
in service of it or should be cut.

## The take

**Search across files: yes, unreservedly.** It is the strongest idea here, it has an
obvious daily use, and markside is already the thing you read those files in. Today's
search is per-document; making it per-repo is a natural extension rather than a new
product.

**Usage statistics: yes, but not as described.** "Which files are used most" isn't
observable — markside can't see you reading a file in your editor, and neither can
anything else. What *is* observable, precisely and for free:

- `git log` per file — commits, recency, churn, who touched it
- file mtime
- markside's own open counts (it can record what you opened in it)
- annotation counts — which documents you argued with most

That's a genuinely useful "what's alive in this repo" view. Framed as *traffic* it would be
a vanity dashboard measuring nothing; framed as **activity**, backed by git, it's real. Be
honest about the source and it earns its place.

**Correlation and mindmaps: yes to the correlation, careful with the map.** A graph view is
the classic feature that looks superb in a screenshot and gets opened twice. Obsidian's
graph is the cautionary tale. The useful 90% is a *list*: "these six files mention
`Migrationswächter`", "these four link to this one". Build that first; it's cheap, exact and
immediately useful. Render it as a graph afterwards, once you know which edges you actually
care about.

Crucially, edges must **mean something concrete**. Three honest edge types, no model needed:

| Edge | Signal | Cost |
|---|---|---|
| A links to B | markdown links between files | trivial, exact |
| A and B share a heading | normalised heading text | trivial, exact |
| A and B share rare terms | TF-IDF cosine over the corpus | ~80 lines, deterministic, offline |

TF-IDF is the right tool here: no API, no model download, no network, explainable ("these
files are linked because they both talk about *Migrationswächter*, a term that appears
almost nowhere else"). Embeddings would be better at synonyms and worse at everything
else — a dependency, a cost, and an unexplainable edge. Don't reach for them until the
cheap version demonstrably fails.

## What makes this markside's, and not a worse Obsidian

This space is crowded: Obsidian, Foam, Dendron, `rg` + `fzf`. The honest question is what
markside adds. Two things nothing else has:

1. **Search results feed the review loop.** Find the paragraph, annotate it on the spot,
   `⌘⏎`, paste into the agent. Search and act, not search and copy.
2. **Annotations are themselves searchable.** *"Where did I mark something as Cut?"*
   *"Which plans have open questions I never resolved?"* markside is the only tool that
   knows your notes, because it made them.

That second one is the feature I'd build the whole mode around. It's a genuinely new answer
to "where did I note that", because the thing you're looking for is often *your reaction*,
not the text.

## The architectural fork — worth naming

markside today is a hard rule: one file in, one self-contained page out, no server, no
state. Workspace mode breaks it. Indexing N files means a build step; keeping the index
fresh means watching; searching lazily means a server.

So it must be a **second mode, not a change to the first**. `md file.md` stays exactly what
it is. `md --workspace [dir]` is a different door into the same renderer. If workspace mode
ever forces a compromise on the single-file path, the answer is no.

Sizing: a repo with 200 markdown files at ~8 KB each is 1.6 MB of text. That inlines into a
single page without trouble. **The whole index can be a static page**, no server, if we
accept a rebuild on demand. That preserves the tool's character — and rebuilding takes
milliseconds.

## Phases

Each phase is independently useful. Stop after any of them.

### Phase 1 — the index and cross-file search

`md --workspace ~/repo` walks the tree (respecting `.gitignore`), reads every `.md`, and
emits one page: a file list with title, heading outline, word count and mtime, plus a
search box that searches **all files at once** and shows matches in context, grouped by
file. Click a result to open that file in the normal reader, at that line.

- reuse: the existing search machinery, the renderer, the whole design system
- new: a walker, an inlined index, a results view
- effort: **one session**. This is the 80%.

### Phase 2 — annotation search

The review store already knows every note you've made, keyed by absolute path. Surface it:
filter by verb, by file, by "unresolved". *"Show me every open Question across the repo."*

- reuse: the review store, unchanged
- new: a cross-document view of it
- effort: **half a session**, and it's the most distinctive feature in the plan

### Phase 3 — activity

Per file: last commit, commits in the last 90 days, churn, your open count, annotation
count. Sort by any of them. Sourced from `git log --numstat`, parsed once at index time.

- effort: **half a session**. Cheap because git already knows.

### Phase 4 — correlation, as a list

For a given file or a given term: which other files share links, headings or rare terms.
TF-IDF over the corpus built at index time.

- effort: **one session**, mostly the scoring and making the output trustworthy.

### Phase 5 — the graph, only if phase 4 gets used

Force-directed view of the phase-4 edges, filtered by edge type, clicking through to files.
Inline SVG, no library.

- effort: **one to two sessions**
- gate: build it only if you actually used phase 4 for a month. If you didn't, the graph
  won't save it.

## Open questions

- [ ] Where does the index live — rebuilt on demand, or cached in `~/.cache/markside`
      with an mtime check?
- [ ] Does `md` with no arguments in a repo root become workspace mode, or stay README?
- [ ] Should the index follow `docs/**` only, or the whole tree? (`.gitignore` plus a
      `--include` glob is probably enough.)
- [ ] Cross-repo: one workspace per repo, or a saved list of roots to search at once?

---

# Session archaeology

> Join the markdown corpus with your own Claude Code history: which topic touched which
> files, across which sessions.

This is the strongest idea in the plan, and measurement made it stronger — it is far
cheaper than it sounds. Numbers below are from a real machine, not estimates.

## What is actually on disk

| Store | Size | Contains |
|---|---|---|
| `~/.claude/projects/*/*.jsonl` | 640 MB, 56 sessions, 11 projects | full transcripts, incl. every `file_path` a tool touched |
| `~/.claude/history.jsonl` | 2.1 MB, **4,556 prompts** | every prompt you typed, with `sessionId`, `project`, `timestamp` |
| `~/.claude/plans/*.md` | 40 KB | the plan files |
| `~/.claude/file-history/` | 108 MB | Claude Code's before-edit backups |

`history.jsonl` is the find. Two megabytes holding every question you have asked, already
keyed by session and project — the cheapest possible index of *what you were thinking
about*, with no parsing of the 640 MB behind it.

## It is fast enough to need no daemon

Measured, single-threaded Python with a `"file_path"` string prefilter:

- extracting file-touches from **478 MB across 56 sessions: 0.6 s**
- a full *topic → sessions → files* join: **0.13 s**
- result: 1,588 distinct files, with their session counts

So: **no index to maintain, no watcher, no staleness.** Rebuild on demand, every time. That
keeps the property that makes markside markside.

The inverse index is immediately legible — `hypergol/index.html` was touched in 12 separate
sessions, `src/ui/shipyard.ts` in 9. "Which sessions worked on this file?" is a lookup.

## The finding that decides the design

The naive join is **useless noise**. Searching `migration` matched 22 sessions, and those
sessions touched **523 files** between them — nearly everything, because a session touches
whatever it touches.

The fix is the same trick as the correlation work: rank by **specificity**, not presence.
Score each file by how concentrated it is in the matching sessions versus everywhere:

```
score(file) = Σ over matching sessions ( 1 / sessions_that_ever_touched(file) )
```

A file touched in every session is background; a file touched only in the matching ones is
signal. Verified on real data: `pdf` then surfaces `pdfFormRenderer` and the PDF form
components; `migration` surfaces `supabase/migrations/…`. The routing is correct.

Two refinements the measurement also exposed:

- **Filter scratch paths.** Session temp directories (`/private/tmp/claude-*`) dominate the
  raw results and are never the answer.
- **The score saturates.** A file touched once in one matching session ties with one touched
  in all three. Tie-break by match count, or require ≥ 2 matches before ranking.
- **History outlives transcripts.** Many `sessionId`s in `history.jsonl` have no transcript
  left on disk. Degrade to "prompt only, files unknown" rather than dropping the hit.

## The rule this feature must not break

Transcripts contain **everything**: file contents, command output, pasted credentials,
client data. markside's whole architecture inlines its data into a self-contained page, and
`-o` makes that page shareable.

So, a hard constraint, not a preference:

1. Session data **never enters an exportable page**. `--workspace --sessions` refuses `-o`.
2. Index **metadata and prompt text only** — never tool output, never file contents.
3. Prompt text is itself sensitive (`pastedContents` exists in the history schema); treat
   the whole session index as local-only.

Getting this wrong turns a memory aid into a leak with a share button. It is the single
biggest risk in this document.

## Brittleness

The transcript JSONL schema is undocumented and moves with Claude Code versions. The
extractor leans on `"file_path":"…"` appearing in tool calls — stable in practice, not
guaranteed. It must degrade to fewer results, never to a crash or a wrong answer.

## Why it is worth it

The other half of "where did I note that" is: **you did not note it.** You discussed it. The
markdown corpus cannot answer that; the history can. Combined with cross-file search, one
query returns *these documents mention it, these sessions discussed it, and this is the code
that changed while they did.*

Nothing else can do this, because nothing else has both your notes and your sessions.

## Effort and sequencing

- session index (history + file-touch extraction + specificity ranking): **~150 lines,
  one session**
- joining it into workspace search results: **half a session**

Sequence it **after** workspace phase 1. On its own this is a session browser, which is
much less useful than the join it enables.
