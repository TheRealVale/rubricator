---
title: What the surfaces claim, and what they can support
subtitle: Phase L — search, ⌘K, the note counts, the staleness signal, the index, and two silences
status: plan — 2026-08-23
---

# What the surfaces claim, and what they can support

Every surface in this workspace that reports a **judgement** — a hit count, a note
count, an all-clear — reports one it cannot support. Search says *nothing matched*
when it means *I looked for your two words glued together*. `⌘K` prints a
confident hit count for a corpus it was never given. The note counts read an empty
store. The Stale surface says *nothing looks stale* about a repository where it
could not judge 87 of its 99 documents, and says it again on a repository where
the same window is painting 61 warning triangles in the navigator beside it.

None of this is a missing feature. Every item in this phase is a subtraction or a
correction, with one exception — L1, which is the only one that adds behaviour.
Seven of the eight are an evening or less and the eighth is a day or two. None of
them adds a surface; the four proposals that would have sat on top of them are in
§6.5.

The harder half of this document is a refusal. The obvious repair to the staleness
detector — widen what counts as a code path — was written, measured and rejected:
it costs eleven times the entire index and it pushes the flag from 46% to 62% of
the corpus. The two complaints in that subsystem have remedies that pull against
each other. So the plan is to demote the signal to what it actually measures,
delete the unranked glyph outright, and make every empty result say which kind of
empty it is.

---

## 1. What was measured, not assumed

| | measured |
|---|---|
| `auth` on repo B's 330 documents | **132** documents |
| `auth flow` · `flow auth` · `authentication flow` | **2** · **0** · **0** |
| `rate limit` · `limit rate` | **17** · **0** |
| 37 two-word queries, each built from two words of a real document's own title | the shipped matcher returns **zero for 25 of 37**; AND-of-terms returns zero for **none** |
| `⌘K auth`, fresh window, same corpus | **0 palette rows** against **132** from the Search surface, under an unhedged `N hits` |
| Stale on repo A: *"Nothing looks stale…"* | the detector resolved **zero targets for 87 of 99** documents |
| the same sentence on repo D | shown while the navigator in the same window paints **61 ⚠** |
| Stale, of the documents it *can* judge | **71.5%** repo C · **86.3%** repo B · **92.4%** repo D |
| Stale on repo C, three counts of one thing | **231** navigator triangles · **129** surface rows · **40** displayed |
| what `targetChurn` correlates with | **r = 0.84** with the number of paths a document quotes · **r = 0.12** with its age |
| widening the target whitelist, as specified | **5.03 s** on repo C against a **0.44 s** whole index; nav flags **231 → 309** |
| `repo_churn` | **26%** of the git pass, read by **no** JavaScript |
| the prompt index | `workspace.py:237`'s `[:600]` drops **86,020 characters — 13.6%** of all indexed prompt text |
| the only report of a note failing to reach disk | a **1.9-second** toast (`review.js:195`, `workspace.js:140`) |

Re-measured on 2026-08-23 by importing `share/workspace.py` directly against five
real repositories — rubricator 11 documents, repo A 99, repo D 84,
repo B 330, repo C 502. Nothing was written into any of them. Every row
above has an entry in `measurements.md`, under `M-SIG-*`, with the command or the
method behind it.

---

## 2. One defect, eight surfaces

The install bug in `install-plan.md` — eight of eighteen files copied, blank page,
exit 0 — is the same defect as everything below, in its purest form: **the tool
reports confidence it has not earned.** It is worth being explicit about why that
is the expensive category rather than a cosmetic one.

A missing feature is visible. The user looks for it, does not find it, and knows
where they stand. A false all-clear is invisible by construction: it costs the
user the search they would otherwise have run. *Nothing matched* ends the enquiry.
*Nothing looks stale* ends the enquiry. `0 hits` ends the enquiry. Each of those
three sentences is currently produced by a code path that never looked.

The audience makes it worse. This is a tool for people checking what an agent
produced, and one external number is worth attaching here — the only one in this
document:

> In Stack Overflow's 2025 Developer Survey (over 49,000 respondents in 177
> countries; **33,244** answered the trust question), "More developers actively
> distrust the accuracy of AI tools (**46%**) than trust it (**33%**), and only a
> fraction (**3%**) report 'highly trusting' the output."
>
> — survey.stackoverflow.co/2025/ai. Must accompany: quote the per-question n
> (25k–33k), not the 49,000 total, next to a percentage. Do not write "29% trust"
> — that figure is on neither source.

The survey measures distrust of AI tools' output, and rubricator is not one, so
the inference has to be named rather than assumed: the artefact under review
arrives already distrusted. A reviewer that misreports its own coverage joins the
thing it was meant to check. A tool a suspicious reader installs to check an
agent's output has one thing to trade on, and it is not features.

Standing rule 8 exists for this reason: **an empty result must say which empty it
is** — *nothing matched* or *nothing could be judged* — with counts. Four of the
eight items below are that rule, applied: L1, L2, L4 and L8.

---

## 3. Search returns nothing, and nothing is what an empty corpus returns · L1

`count()` at `workspace.js:157-162` is a case-insensitive `indexOf` of the whole
query string, looped for occurrences:

```js
function count(text, q){
  if (!q || !text) return 0;
  var n = 0, i = 0, t = text.toLowerCase(), s = q.toLowerCase();
  while ((i = t.indexOf(s, i)) >= 0){ n++; i += s.length; }
  return n;
}
```

Three ranking callers hand it the raw string — `promptHits` :167, `docScore`
:198-202, `sessionScore` :425/:427 — and two more surfaces reimplement the same
phrase test inline rather than calling it: `navAll.hit` :1263 and `palSearch.hit`
:1341 are their own bare `indexOf`, as is the Documents navigator filter at
:1144-1146. Four further uses of `count()` are not ranking at all: :204
(`nameHit`, the *name* pill) and :558 (whether a prompt row is highlighted) are
boolean phrase tests, and :265 (*N in the text*) and :769 (the dossier's
*(N mentions)*) put a phrase count on screen. So the whole workspace searches for
a *phrase*, and a phrase is not what the tool's own empty state invites.

The consequence, reproduced against the real repo B index: `auth` finds 132
documents, `auth flow` finds 2, `flow auth` finds 0, `authentication flow` finds
0. Word order is load-bearing and there is nothing on screen that says so.

The measurement that settles it is not the anecdote but the sample. Thirty-seven
two-word queries were generated by taking two words out of a real document's own
title — queries that are guaranteed to have an answer in the corpus:

```
phrase (indexOf, what ships today) returns ZERO hits: 25/37  (68%)
AND-of-terms                       returns ZERO hits:  0/37  ( 0%)
```

Sixty-eight per cent of queries that name a document in the index return nothing,
and return it in the same words the tool uses when it genuinely has nothing. One
caveat travels with that figure: the generated query list was not kept, so a
re-run draws a different thirty-seven and the exact 68% will not come back
(`measurements.md` `M-GAP-1`). What L1 turns on is the shape — two-word queries
that are guaranteed an answer, scored twice.

The obvious objection — *nobody types two-word queries in their own repo* — is
answered by the tool itself. The empty state at `workspace.js:235` invites a
topic: *"A topic resolves to documents, the sessions that discussed it, and the
files those sessions changed."* The product asks for the query shape it cannot
serve.

**The fix, and the half of it that is real work.** Split the query on whitespace,
require every term, and score as `Σ per-term count + 3 × count(full phrase)` so an
exact phrase still outranks a scatter. `docScore`'s field weights stay as they are
(name ×14, title ×8, path ×6, headings ×4, body ×1). No stemming, no fuzzy
matching, no index — the rebuild-everything guarantee at
`docs/workspace-plan.md:42` (*"no index to maintain, no watcher"*) stays intact.

AND alone is not enough, and this is the attack that partly landed: it converts
*no results* into *all results*. `business match` goes from 0 hits to 111;
`reads that` goes from 1 to 132. That is why the ranking half is not optional and
why this is the one **M** in the phase rather than an **S**.

The scope of *one parser* is the thing to get right, and it is wider than the
ranking. The three ranking callers and the two inline matchers have to end up
behind it or the ranking gets tuned five times. So do the two display counts:
if :265 and :769 keep counting whole phrases while the ranking counts terms, the
number on screen stops matching the order it is printed in — the same defect as
§4, moved one surface along.

*Done when:* `flow auth` and `auth flow` return the same document set,
`business match` does not return the whole corpus, and every site named above —
the three ranking callers, the two inline matchers, the navigator filter and the
two displayed counts — goes through one parser.

---

## 4. `⌘K` counts a corpus it was not given · L2

In serve mode `workspace.py:459` strips `text` from every document in the initial
payload:

```python
data = dict(data, docs=[{k: x for k, x in d.items() if k != "text"} for d in data["docs"]])
```

That is correct — a 502-document index is 10.2 MB of JSON with the bodies in it,
which is why the live tier strips them and fetches on demand. What is not correct
is that `palSearch` (`workspace.js:1341-1344`) tests `hit(d.text)` against
`undefined` and then reports the result as fact: `total + ' hits'`, unhedged
(`:1419`), rendered into `#pal-count` at `shell.js:290`.

On repo B, a fresh window's first `⌘K auth` returns **0 rows**. The Search
surface, on the same corpus in the same window, returns 132. On repo C it
is 3 against 153.

The second half is worse than a wrong count, because it is a wrong count that
changes. Two other surfaces call `ensureAllText` — the Search surface via
`needText()` (`workspace.js:883` → `:1484`) and the All navigator via
`navAll` (`:1264`) — and once either has run, `textAll` is true for the rest of the
page's life, until a reindex resets it (`:1505`), and `⌘K` silently becomes a
full-text search. The default navigator mode is `docs` (`shell.js:19`), so a fresh
window is filename-only. One keystroke, two different answers, no explanation
either time.

**The fix.** Call `ensureAllText` when the palette opens with a non-empty query.
The round trip that fetch makes has not been timed, and this document will not
pretend otherwise. What is measured is the work behind it: the whole repo B
index — find, read, git, build — rebuilds in 0.23–0.25 s warm and its JSON payload
is 6.6 MB (`M-SIG-15`), so warming the corpus when the palette opens is
affordable. The honest interim wording already ships — `searching()` at `:207`
gates the banner rendered at `:250`:

```js
if (searching()) out.push('<div class="qnote">Searching titles and headings — ' +
  'fetching the full text…</div>');
```

Use that same sentence in the palette while the fetch is in flight, and label the
count as by-name until it resolves. Nothing new is designed here; a sentence that
already exists is moved to the surface that lies without it. One note for whoever
implements it: the register's L2 quotes the shipped wording as `N by name —
loading full text…`. That string is not in the code. The sentence above is.

*Done when:* a fresh window's first `⌘K` for a body-only term returns the same
count as the Search surface, and the count is labelled while the fetch is in
flight.

L1 and L2 ship in one commit. `palSearch.hit` is one of the two inline phrase
matchers L1 has to fold into the parser, and splitting the work means tuning the
ranking twice.

---

## 5. The views that count notes do not read the notes · L3

The server side of this is right. `workspace.py:513-548` writes
`.rubricator/notes.json` through a temp file and a rename, ships it in the initial
payload at `:576` and again on reindex at `:647`, and answers a `notes` route at
`:650-657`. The client installs a disk-aware storage adapter at
`workspace.js:74-98` that merges the disk copy with the local one by `saved`
timestamp and pushes the newer one up.

The disk-aware **read** has exactly one caller in the whole codebase:
`review.js:47`, inside `loadStore()`. (The write side is used more widely —
`review.js:53`, wrapped again at `workspace.js:103-111` — which is why notes reach
disk at all.) The tray is the only disk-aware reader in the tool.

Every corpus-wide view goes through a second, parallel, disk-blind reader:

```js
114  /* annotations live in the reader's local storage, keyed by a hash of the abs path */
115  function hash(s){ var h=5381,i=s.length; while(i) h=(h*33^s.charCodeAt(--i))>>>0; return h.toString(36); }
116  function annosFor(doc){
117    try {
118      var raw = localStorage.getItem('md-review:' + hash(doc.abs));
```

`DISK` is in scope on line 118 and is not consulted. The keys already agree —
`review.js` builds its key from `META.path`, `workspace.js:1013` sets `META.path`
to `d.abs`, and `annosFor` hashes `doc.abs`. This is a missing read, not a key
mismatch, which is why it is one line.

Seven read sites, all in `share/workspace.js`:

| line | what it feeds |
|---|---|
| 259 | the `⌘K`/query view's per-document annotation count |
| 299 | `noteCount()` — the card badge, the notes **sort** (:309), the has-notes **filter** (:315), the document header (:321), the tab badge (:972), the navigator row (:1354) |
| 387 | the Notes surface — the entire cross-document annotation view |
| **774** | **the dossier builder — the notes pasted into an agent prompt** |
| 1233 | the navigator's Notes mode |
| 1303 | the notes group in the navigator |
| 1380 | the Notes group in `⌘K` |

Line 774 is the one that matters most: FEAT-10's enumeration of the read sites
missed it entirely, and FEAT-1 listed it without singling it out. It is the only
site that ships wrong data *out of the tool* into somebody's agent context.

The reason this is not a first-run edge case: `serve.py:38` binds `("127.0.0.1", 0)`,
an ephemeral port, and `bin/md:165` launches the workspace with no `--port`. Every
`md <dir>` gets a new port, therefore a new origin, therefore an empty
`localStorage` — `md serve --port N` (`bin/md:80`, `:235`) is the one path with a
stable origin, and no example on the front page uses it. Not empty on the first
run — empty on **every** run. Chrome's store on this machine holds 31
`md-review:*` records across 21 distinct origins.

And there is a real casualty rather than a hypothetical one. Of the three genuine
annotations on this machine, one — a note on a repo A requirements document,
written in the static `file://` tier — exists in Chrome's localStorage, in no
`notes.json`, and there is no `.rubricator` directory in that repository at all.
The author wrote a real note on a real document and the tool has already lost it.

**The fix.** Make `annosFor` prefer `DISK[doc.abs]` and fall back to localStorage,
mirroring the recency rule already written at `:77-82`. `reindex()` refreshes
`DISK` at `:1506`, so nothing else changes. Seed `data['notes']` into the static
workspace payload in the same commit.

This is standing rule 2 in one function: **nothing that must survive a restart may
live in `localStorage`.** Per-root state belongs in `.rubricator/`.

*Done when:* a note taken in one run appears in the Notes surface, the tab badge,
`⌘K` and the dossier after the server has been restarted on a new ephemeral port.

---

## 6. The refusal: staleness · L4

`docs/workspace-plan.md:174` calls the stale-doc detector *"the one that pays
immediately"*. It was the right thing to build first — pure git, no session data,
half a session of work. Measured against five real repositories, it is the least
trustworthy signal in the tool. This section is the record of measuring the
obvious repair and declining it.

### 6.1 Four false statements in one subsystem

**(a) The empty state is false where it fires.** `workspace.js:370`, verbatim:

```js
if (!rows.length) return '<div class="empty">Nothing looks stale — every document that names code has been touched since that code last changed.</div>';
```

On repo A, 87 of 99 documents resolved **zero** targets — the detector did
not judge them, it declined to. On repo D the same sentence appears while the
navigator in the same window paints **61** warning triangles, because the two code
paths disagree (below). The sentence is not a rounding error; it is the opposite
of what happened.

**(b) Two predicates for one concept.** `isStale` (`:301-305`) filters on
`kind === 'md'` and fires on any positive churn. `viewStale` (`:365-369`) has no
`kind` filter and adds a 30-day condition. The disagreement is one-directional on
every corpus tested — the navigator is always a superset — and it is large:

| repo | nav ⚠ (`isStale`) | Stale surface (`viewStale`) |
|---|---|---|
| repo C | 231 | 129 |
| repo B | 177 | 154 |
| repo D | 61 | 0 |
| repo A | 6 | 0 |

**(c) A silent truncation.** `viewStale` ends with `rows.slice(0, 40)` at `:375`
and says nothing about it. repo C hides 89 of 129 rows (69%); repo B
hides 114 of 154 (74%).

**(d) A value nothing reads.** `repo_churn` at `workspace.py:175` is computed for
every document and consumed by no JavaScript — `grep -rn repoChurn share/*.js`
returns nothing today. It costs 26% of the git pass on repo C
(`git_activity` 0.323 s with it, 0.238 s without), inside a whole build of 0.44 s.
`stem` at `:167` is a second dead local in the same loop.

### 6.2 The obvious repair, measured and refused · X14

Five lenses converged on the same diagnosis: the input aperture is too narrow —
the extractor only matches backticked paths ending in one of twelve extensions.
Two of them (FEAT-3, CODEKB-1) proposed the same repair: widen the regex, and
match the tokens against the file list git already has. Every one of the five
assumed the *output* was worth widening the input for.

It was costed three ways.

*As literally specified*, keeping the existing `for p in all_paths: if
p.endswith(t)` loop, the widened regex runs 40,204 tokens against 4,789 paths:
**5.03 s on repo C**, 1.12 s on repo B. The entire current index —
find, read, git, build — is **0.44 s**. That is roughly eleven times the whole
thing, for one signal. With a suffix dictionary built once it is 0.009 s + 0.028 s
and effectively free, but no version of the proposal says to build one, and the
proposal is what was priced.

*Its foundation is wrong.* `all_paths` is `list(commits.keys())`, derived from
`git log --since=2 years ago --name-only` — not from `git ls-files`. On
repo C that is 4,789 log paths against 3,363 tracked files: 1,450 of them
no longer exist, and 24 tracked files never appear. Any fix built on it inherits
both errors.

*It makes the other half worse.* This is the finding that killed it:

| repo | zero-target docs | nav ⚠ |
|---|---|---|
| repo A | 87 → 58 | 6 → 29 |
| repo B | 125 → 93 | 177 → 212 |
| repo C | 179 → 130 | 231 → **309** |

Widening cures about a third of the blindness and takes repo C from 46% of
the corpus flagged to **62%**. The two complaints — *it cannot see enough* and
*it warns about everything* — are the same complaint measured from two ends, and
the proposed fix trades one for the other at a bad rate. **X14 is dead.** If a
future reader wants it back, the number to beat is not 5.03 s; it is 62%.

### 6.3 What the number actually measures

Ranking is what saved the Stale *surface* from the same verdict as the glyph — a
ranked top-40 is a usable triage list even at a high base rate, *if the ranking
means anything*. It does not.

```
pearson(targetChurn, number of targets the doc resolved) = 0.84
pearson(targetChurn, age of the document)                = 0.12
```

`targetChurn` is a sum over the files a document names. A document that quotes
forty paths outranks one that quotes three, whatever either of them says. The top
of the list is saturated by the cap at `workspace.py:178` — `sorted(targets)[:40]`
— and on repo B the top three documents all sit at exactly 40 targets. Rank the
same corpus by churn-per-target instead, an equally defensible metric and three
characters of code, and the top ten is disjoint.

The input is partly arbitrary too. The resolver takes the first path whose suffix
matches and breaks:

```python
for p in all_paths:
    if p.endswith(t):
        targets.add(p)
        break
```

Measured over every token the regex matches: on repo B, 247 of 2,869 tokens
(9%) match two or more tracked paths and get an arbitrary winner, and 142 (5%)
match none; on repo C, 359 of 3,153 (11%) and 136 (4%).

And the flag rate, on the documents the detector can actually judge, is 71.5%
(repo C), 86.3% (repo B), 92.4% (repo D).

An almost-constant output, ordered by verbosity, computed from an input that is
arbitrary one time in ten. That is not a signal with a bug in it.

Which raises the obvious objection to what follows: if the ranking means nothing,
why does the glyph die and the surface live? Because the surface can be renamed
and the glyph cannot. Renamed, the surface stops presenting a ranking of quality
and becomes an ordering of a fact — how much churn accumulated in the files this
document names, descending. That ordering is defensible on its own terms in a way
that *stale, yes/no* never was, because nothing about it claims the document at
the top is wrong. What it may not do is present that order as a judgement, which
is why point 5 below is not cosmetic. A per-row boolean has no equivalent move
available: `⚠` is a verdict or it is nothing.

### 6.4 What ships instead

Five changes, all subtraction or wording, all an evening.

1. **Delete `isStale` and the `⚠` glyph.** An unranked per-row boolean that fires
   on 46% of a corpus, with no aggregate count anywhere on screen, cannot inform a
   decision. Deleting it is the fix, and it also resolves the two-predicates
   problem for free. But `isStale` has a second consumer, and the glyph at `:328`
   is not it: `workspace.js:316` backs the navigator's `stale` facet, one of the
   three shipped at `:1149` (`has notes` · `stale` · `14 days`). It goes too, or
   it is repointed at `viewStale`'s predicate so the facet and the surface finally
   agree. Deleting the function and leaving `libFacet.stale` behind gives a page
   that throws while the done-when below still passes. Register **Q2** adds
   `status:` beside the other two facets; if this one is deleted, Q2's line
   changes with it.
2. **Delete `repo_churn`** — and `stem` with it. 26% of the git pass, zero readers.
3. **Make the empty state distinguish the two empties**, with counts: *nothing is
   stale* versus *N of M documents named no code we could match, so they were not
   judged*. This is standing rule 8, and it is the only change here that removes a
   false claim rather than a useless one.
4. **Print `showing 40 of 154`.**
5. **Relabel the surface as what it measures**, and stop calling it staleness.
   The honest sentence already ships, in the surface's own subhead
   (`workspace.js:371`): *"Documents whose named files kept changing after the
   document stopped."* What has to change is the name above it — `TITLES` at
   `:848` (`stale:'Stale'`) and the sort and facet labels at `:1148-1149` — and
   `README.md:215`, which currently says *"Stale lists documents whose code moved
   on without them"* and asserts a causal judgement the code does not make.

Point 5 is the one that will be argued with, so: this is standing rule 10.
**Claim coverage and time-to-first-mark; never code quality.** *These files kept
changing after this document stopped* is a fact about git. *This document is out
of date* is a claim about correctness that nothing in this tool can support, and
`targetChurn`'s r = 0.84 with verbosity says what it would be supported by
instead.

*Done when:* repo A' Stale surface says how many documents could not be
judged, the `⚠` glyph is gone, `grep -rn repoChurn share/` returns nothing, and
the row count and the displayed count agree.

One correction to the register's own acceptance line for this item: it asks for
`grep -c repoChurn share/*.js` to be 0, and that is already true — the JavaScript
never read it. The deletion is `workspace.py:175`, where `repo_churn` is computed,
and the `"repoChurn"` key at `:179`; the dead local `stem` at `:167` goes with
them. Not `:178` — that is `"targets": sorted(targets)[:40]`, the list the entire
surface is computed from.

### 6.5 What stays out, and why

Four proposals sat downstream of this signal. They are out, and they are named
here so the reasoning survives the phase note.

- **X13 — staleness as the product's thesis.** Positioning is the one decision a
  later commit cannot undo. This one would oblige a solo maintainer to defend an
  accuracy table against a ground truth that does not exist, for a signal whose
  ordering correlates r = 0.84 with how many paths a document quotes.
  `scope-plan.md` carries the alternative.
- **X12 — a Coverage surface**, the inverse map of code files no document names.
  916 of 1,702 tracked repo B files (54%), 1,223 of 2,169 on repo C
  (56%). A to-do list with 1,223 rows is wallpaper, grouping by directory makes it
  every directory, and the unit is wrong: nobody documents individual files.
- **X15 — the Stale × sessions × notes join and the five-section Brief surface.**
  Polish over a signal that fires on 71.5–92.4% of what it can judge and truncates
  at 40 rows. A more attractive way to be told the same unhelpful thing 231 times.
- **X24 — annotation-scoped staleness** (*you marked this paragraph and the code
  under it moved*). The best idea in the cluster on merit, and unbuildable today:
  its input is annotations, and three exist on this machine. Its second half — say
  *cannot assess* when a document yields zero targets — is item 3 above. Revisit
  when there is a corpus of marks to compute it from.

---

## 7. The index cannot see the file the agent just wrote · L5

`find_docs` (`workspace.py:32-40`) builds the document set from `git ls-files` and
returns as soon as any tracked file exists, which makes the `os.walk` fallback
below it unreachable in a real repository. A markdown file an agent wrote thirty
seconds ago is invisible to the workspace until someone runs `git add`.

Reproduced in a scratch repository: one committed `a.md`, one untracked `b.md`,
`find_docs` yields `['a.md']`. After `git add b.md` with no commit, both.

Two things keep this an **S** rather than an emergency, and both are worth
recording because they change the priority rather than the ruling. First, the
snapshot is small: across four active repositories there are 0, 0, 2 and 3
untracked markdown files right now. Second, the flagship paths already work —
`md b.md` renders an untracked file perfectly, `md --review b.md` is the documented
agent path, and the hook renders the plan file straight from `~/.claude/plans`
(`hook.py:29-55`, `:197`, `:217`), never through the index. After K5
(`install-plan.md`) the hook will not need a file at all; today it does. The harm
is confined to the workspace navigator, where it reads as *I pressed `r` and it is
still not there*.

**The fix.** Union in `git ls-files --others --exclude-standard`, measured at
23 ms on repo C against 19 ms for the call already being made, and mark
untracked rows visually. That also makes the `untracked` facet `docs/tasks.md:77`
has been claiming since B1 actually buildable.

Add `.mdc` to `MD_EXT` in the same commit — currently
`{".md", ".markdown", ".mdown", ".mdx"}`. It cannot fire today: zero `.mdc` files
exist anywhere under `~/Repositories` (X30). It is one set entry, and that is the
whole argument for it; if that is not enough, drop it. Nothing is built on it —
pinning agent files in the navigator is X30 and stays dead.

The other half of that finding — rewriting `snapshot()` to walk the tree every
second — is not done. Its only action is `return reindex()` on a page that just
reindexed, so it would buy a per-second directory walk forever to enable a
redundant re-fetch.

*Done when:* a file created and not staged appears in the tree, marked untracked,
after one reindex.

---

## 8. The prompt cap, and the recovery figure that was not real · L6

Two lines of `workspace.py` decide what of your own typing is searchable. Both
were reported as problems; the sizes were the wrong way round.

```python
233  if not txt or txt.startswith("/"):        # slash commands aren't topics
237  text = scrub(txt)[:600]
```

**The slash filter.** It drops 756 of 4,750 records (15.9%), and that number was
carried into a recommendation to index all slash commands. Broken down:

```
known-noise commands (/model, /compact, /clear, /effort, /context, /resume, ...): 623
non-noise, bare, no arguments:                                                     62
non-noise, WITH arguments (actual lost content):                                   71
distinct slash commands: 46
top: /model 195, /compact 159, /clear 142, /effort 28, /goal 24, /resume 23
```

82% of the loss is session plumbing with no recall value. The genuinely lost
material is **71 prompts, 1.5%** — a tenth of the advertised prize. This is X4,
and it carries a second warning: the finding that proposed it named
`/reconcile` and `/atlas-sync` as this user's commands, and both occur **zero**
times in this machine's entire history. A confabulated detail inside a finding
marked *verified*. Every number in this document was re-measured because of that
one.

There is still a real false positive worth fixing, and it is not a slash command
at all — it is prose that begins with a path (the example is synthetic; the real
one is a prompt from this machine's history and does not belong in a public file):

```
/api/orders returns 500 after the migration; also the retry banner never clears
```

**The truncation.** Nobody proposed this one, and it is nine times larger:

```
indexed prompts: 3995, 634,579 chars total
prompts > 600 chars: 127 (3.2%)
chars dropped by [:600]: 86,020 = 13.6% of all prompt text
```

Only 3.2% of prompts are affected, but they are the long ones — the ones where
somebody explained something — and they lose everything after the first 600
characters. The searchable prompt corpus is missing an eighth of itself, silently.

That denominator is the index as it stood at 20:10 on 2026-08-23
(`M-SIG-25`). `retention-plan.md` §1.2 re-counts the same file at
21:20 and gets 3,998 prompts across 419 sessions — eighty minutes of the
author's own typing. Two right answers to one question, which is why both are
dated. The share is what this item turns on, and the share does not move.

**The fix.** Raise the cap; 2,000 is one constant. Replace the blanket
`startswith("/")` with a short skiplist of known session-plumbing commands, which
keeps the prose above as a side effect.

That skiplist is a hand-maintained list in shipped code, and standing rule 9 bans
those, so the distinction has to be stated rather than hoped for. Rule 9 is about
an inventory of the tool's *own files* — `install.sh:59`, and the `md --audit`
proposal it killed (X19) — because when that list drifts the tool makes a false
statement about itself. A skiplist of slash commands drifts the other way. A
command nobody listed gets indexed, not hidden; the failure mode of a stale list
is a `/model` line in the prompt index, which is a smaller wrong than the 71
prompts currently dropped. It also cannot be generated: `/model` is noise and
`/goal` is not, and no property of the string separates them.

*Done when:* a 900-character prompt is findable by a phrase in its second half,
and the synthetic prompt above is in the index.

---

## 9. Two silences · L7, L8

Both of these are the same bug as the empty states, in the moment the user is
about to lose something.

**L7 — a data loss report that fades.** `workspace.js:96`:

```js
api('notes', { path: path, store: val }, null, function(){ toast('note not saved to disk'); });
```

`toast()` clears itself after 1,900 ms (`workspace.js:140`) and is written
nowhere else. That is the sole report that a mark never reached
`.rubricator/notes.json`, in a tool whose entire value proposition is that the
marks persist. The most important message the workspace can emit is also its most
ephemeral.

How often has this hurt? The failure has not been observed — nothing on this
machine records a `/notes` POST ever having failed. §7 applied that test against
its own item and this one gets it too. What L7 has instead of a frequency is a
blast radius: the failure loses the only thing the tool exists to keep.

Route it to a line in the status strip (`shell.js:244-256` — `status()`, writing
into `#stat-l`) that survives until the next successful save, and give `#toast`
`role="status"` while the file is open. The ARIA attribute is one word and it is
filed under durability, not accessibility — the larger keyboard-semantics
proposal that came with it was priced at **M** and is nearer a week plus a
permanent invariant, because the workspace repaints by string
(`innerHTML =` appears 34 times across `workspace.js`, `shell.js` and `review.js`)
and a roving tabindex would need focus save/restore at every one of those sites.

*Done when:* a `/notes` POST forced to fail leaves a visible, persistent line in
the status strip, and it clears on the next successful save.

**L8 — the hook window that counts what it is discarding.** On expiry,
`review.js:664-676` sets `expired`, rewrites the banner to *"Timed out — Claude
fell back to the terminal prompt"*, and re-runs `__mdHookSync()`, which disables
Send at `:611` while still rendering the live count at `:615`. The window knows
exactly how many marks are about to evaporate and does not say so.

How often has this hurt? Not yet: no hook review has ever been recorded on this
machine (`M-SIG-27`) — an absence rather than a zero, since nothing instruments
it, which is exactly what register item **N6** in `docs/tasks.md` fixes. This is
an evening spent so the first one does not lose its marks — which is the whole
argument, and it is either enough or it is not.

They do evaporate. The hook window writes nothing to disk by construction:
`hook.py:143-150` renders the plan through the **static** tier into a temp file
and `:221-223` unlinks it, there is no `notes` route on the hook server
(`hook.py:70-96` serves exactly two paths), and the page's marks live in the
localStorage of an origin that dies with the process.

How long the expired state stays on screen depends on the browser.
`hook.py:231-232` sleeps 0.35 s past the deadline and AppleScripts the window
shut, so on the ordinary Chrome path it is a flash. Where `close_window` cannot
match — a non-Chrome default browser (`hook.py:118`), or a Chrome window with more
than one tab (`hook.py:129`) — it persists.

If `askItems().length` is non-zero, say the number in the expiry banner and
promote the existing `copy to clipboard instead` link (`review.js:596-600`, class
`lnk hk-copy`) to the visually primary control. It is the only action left that
saves anything, and it currently looks like a footnote.

*Done when:* an expired hook window with three marks says three, and the copy link
is the visually primary action.

Two things this deliberately does not do. It does not add a `defer` button:
Claude Code's own hooks documentation says `defer` is honoured only under `-p`,
and that an interactive session logs a warning and ignores the hook result
(`citations.md` G2, quoting code.claude.com/docs/en/hooks). Rubricator's hook is
interactive, so the button would silently discard the deny/ask fallback (X6).
That documentation was read, not re-run — standing rule 12 applies to anyone who
wants to reopen it, and rule 12 exists because `PermissionRequest` is documented
and fired zero times on 2.1.241. And it does not make the hook window write to
disk: that is a change to the tier boundary — the hook serves the static tier
from a temp file it unlinks — not a change to a banner.

---

## 10. Two numbers that will otherwise be re-derived wrongly

Both of these were got wrong once already, in the investigation's own output.

**The staleness flag rate is on judgeable documents, not on the corpus.** The
figure 47–54% is the share of *all* documents flagged — repo B 177/330 = 53.6%,
repo C 231/502 = 46.0%. That number quietly counts every document the
detector could not judge as a document it cleared. The honest denominator is the
documents that resolved at least one target, and on that denominator the flag rate
is **71.5% (repo C) · 86.3% (repo B) · 92.4% (repo D)**. Worse, not
better. If someone re-derives 46% and concludes the signal is merely noisy, they
will reopen X14.

**The duplicate-heading hazard is 0.03%, not 2.7%.** The 2.7% is a real
measurement of a different thing — the share of heading lines in repo B plan
files that are duplicated within their own file — and it is not the mis-anchor
rate. Measured as the code behaves, over anchors a human would plausibly mark, it
is **8 in 25,094 across five repositories, 0.03%**. The derivation is in
`anchoring-plan.md` §7 and is not repeated here, because two copies of one
measurement in two published documents will drift. What matters at this distance:
`anchoring-plan.md` builds nearest-occurrence anchoring because it is five lines
and because the fuzzy step needs the position hint, not because it fixes a 2.7%
hazard, and the anchoring budget belongs to fuzziness instead.

---

## 11. The phase

| | item | effort |
|---|---|---|
| **L1** | Search requires every term — one parser behind every phrase test | **M** |
| **L2** | `⌘K` says what it is matching; no silent flip to full text | S |
| **L3** | `annosFor` prefers `DISK`; seed notes into the static payload | S |
| **L4** | Demote the staleness signal; delete `isStale`, `⚠`, `repo_churn`; two empties with counts; `showing 40 of 154` | S |
| **L5** | Union untracked files into the index; `.mdc` rides along | S |
| **L6** | Raise the 600-char cap; skiplist instead of `startswith("/")` | S |
| **L7** | Failed disk write becomes a persistent status line | S |
| **L8** | The expiry banner names what is about to be lost | S |

L1 and L2 are one commit. Everything else is independent and can ship in any
order.

Phase L comes before `anchoring-plan.md`, for one reason: these are the surfaces
that make the tool's own output trustworthy enough to judge the anchoring work
by. It is difficult to evaluate whether a mark survived a rewrite in a window
whose note counts read an empty store. It no longer comes directly after
`install-plan.md`: the owner's answer to open question 3 on 2026-08-24 put
`retention-plan.md`'s phase N second, so the order is K, N, L, M, O, P, Q. The
register's *Phases K–Q* preamble says why. Nothing in this document moves — L3
still lands before M6, and the week's wait makes nothing here harder.

---

## 12. What this phase does not buy

It buys no features. Seven of the eight items delete something, correct a
sentence, or add a count to an existing one; the eighth (L1) makes a search box
work the way its own empty state promises. Nothing here will look like progress in
a changelog.

That is the trade, and it is deliberate. The alternative programme — a Coverage
surface, a Brief surface, the stale × sessions × notes join, the staleness thesis
in the README — is four items of real work sitting on a signal that fires on
seven to nine of every ten documents it can judge, ordered by how many file paths
each document happens to quote. Building any of it first would have meant
defending those numbers later, in public, against a ground truth nobody has.

The last thing to record is the shape of the mistake, because it will recur. Every
false statement in this document was produced by a code path that returned early:
`palSearch` matching `undefined`, `annosFor` reading one of two stores, `find_docs`
returning on the first branch, the resolver's `break`, `viewStale`'s
`slice(0, 40)`, `[:600]`. In each case the surface above it reported the truncated
result in the same words it would have used for the complete one. **A surface must
report which of the two it has.** That is standing rule 8, and it is the spine of
phase L.
