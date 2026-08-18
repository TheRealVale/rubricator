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
