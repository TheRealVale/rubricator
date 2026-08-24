---
title: What this is for, and what it will never be
subtitle: The register corrections, the front page, and the twelve rules that keep both honest
status: plan — 2026-08-23
---

# What this is for, and what it will never be

This plan covers register items **O1–O5** and **P1–P7**. It is the phase where the
project stops describing itself inaccurately — to itself, in `docs/tasks.md`, and to
strangers, on the front page — and writes down the rules that make every future claim
checkable.

It is one document rather than two because it is one defect. A register that marks a
feature done when it was never built and a README that describes 7,372 lines as *one bash
script and a page* are the same failure pointed in two directions. Split, they produce a
page of bookkeeping nobody reads and a page of positioning nobody trusts.

---

## 1. Measured on this machine, not assumed

Two rows come from the GitHub API rather than from this disk. They are marked, and they
move. The ids in the source column are entries in `measurements.md`, which carries the
command behind each figure.

| | measured | source |
|---|---|---|
| `README.md:26` — *one bash script and a page* | **7,372 lines across 18 files** of own code (7,379 with `vendor.txt`; 12,314 with the five vendored files) | `M-POS-1` |
| what that phrase actually describes | `bin/md` 429 + `template.html` 422 — **11.5%** of it | same |
| where the trust material sits | the admitted-and-fixed `<img onerror>` paragraph at line **465 of 473**; `## How it works` at **264** | `grep -n`, today |
| register lines that misdescribe the code | **4** in `docs/tasks.md` — one feature that does not exist, one wrong in both directions, two overstated — plus a fifth (`E8`) marked done over a data-loss shape | `M-POS-4` |
| two-root build, rubricator + repo A | 110 documents, **99 orphan stale keys** of the form `repo/repo/path`, every root-2 document reporting `commits: 0` | `M-POS-5` |
| multi-root users | recents: **four entries, all single paths**; all three cached workspace pages single-root | `M-POS-6` |
| plannotator | ★**7,971** · 1,072 commits · created **2025-12-28** · **147 releases** in eight months | `gh api`, 2026-08-23 — not this machine |
| that lead, over rubricator's first commit (2026-08-18) | **7 months 21 days** | `M-POS-15` |
| rubricator | ★0 · 0 tags · 0 releases · `topics: []` · homepage `null` | `gh api`, 2026-08-23 — not this machine |
| the document↔session join | **49 of 419** sessions carry a file list | `M-POS-11` |
| the graph, on a 99-document repo | **11** connected nodes; **300** on a 502-document one, into a fixed 900×560 viewBox | `M-POS-12` |
| the graph's spring loop, ported verbatim to V8 | **19.5 ms** at 299 nodes — there is no freeze | `M-POS-13` |

Every figure in this document is either recorded in `measurements.md` under the id given
or comes from a command re-run while writing it. Where a figure in the task register did not survive re-measurement, this
document uses the corrected one and says so.

---

## 2. The written record — four false register lines, and one confounded table

`docs/tasks.md` is the planning instrument the rest of this programme runs on. Four of its
`[x]` lines misdescribe the code — one feature that does not exist, one wrong in both
directions, two overstated. That is **O1**. A fifth — `E8 · Multi-root workspace` — is an
overclaim with a data-loss shape behind it, and it gets §3 to itself.

**C7 · Index cache** claims `~/.cache/rubricator/index/<roothash>.json`, invalidated by
mtime and git HEAD. `grep -rn roothash` over `bin`, `share`, `docs` and `README.md` returns
two hits, both in prose: `docs/tasks.md:108` and `docs/architecture-plan.md:308`. There is
no such code. `_cache_read` and `_cache_write` (`workspace.py:300-317`) serve
`sessions.json` and `sessions-deep.json` and nothing else, and `workspace.py:6-7` argues in
a comment that document caching is not worth having. The line does not describe a feature
that drifted; it describes a feature that was reasoned against.

**B1 · Library view** claims facets for `has-notes · stale · untracked · front-matter tag`.
`workspace.js:1149` is one line:

```js
var facets = [['notes','has notes'],['stale','stale'],['recent','14 days']];
```

Two of the four claimed facets are absent, and a shipped facet — `14 days` — is not in the
register. The line is wrong in both directions. `untracked` is also not merely unbuilt: it
is unbuildable until L5 lands, because `find_docs` returns early on `git ls-files` and an
uncommitted markdown file is invisible to the index.

**C6 · Notes on disk** claims *a one-time migration*. A migration exists at
`workspace.js:76-90`; it is lazy and per-document, comparing the localStorage copy against
the disk copy on every read and pushing the newer one up. It cannot cross the
`file://` → `http://127.0.0.1:PORT` boundary, because nothing can. The honest line says
*lazy, per-document, and same-origin only* — which is more useful than either *one-time* or
*none*.

**E3 · Correlation graph** claims it is *gated behind a node budget*. `workspace.js:603-609`
renders an empty state with a **Draw it** button and an advisory string when `n > 120`.
`graphEdges` caps groups (`g.length > 12`, `files.length > 400`, `hit.length <= 15`) and
nothing caps node count. There is a gate. There is no budget. E3 is separately overtaken by
§9, which deletes the feature.

The fix is an hour: each line states what is in the code, and C7's claim is either deleted
or built. It is worth the hour because the alternative is a register a future self cannot
use, and because the same drift in a machine-read list — `install.sh:59` — is why the copy
install on the front page has never produced a working `md` for anyone who took it.

### The confounded table in `continue-plan.md`

**O3.** `docs/continue-plan.md` opens with a table headed *What was measured, not assumed*.
Rows 3 and 4 read *a shell tool call in `-p`: ran, with no prompt and no approval event* and
*the same, with `--permission-mode manual`: ran anyway*. What they measured was the author's
own `~/.claude/settings.json`, which carries `"defaultMode": "auto"`. With default or manual
mode in an untrusted directory the identical call is **denied**, visibly, and the denial is
reported in `result.permission_denials`.

The document's conclusion is unharmed. J1–J4's read-only scope is still right — for a
different reason, which the table should now state. A `PermissionRequest` hook event is
documented and exists; run against `claude` 2.1.241 it **did not fire once** under
`claude -p` in any configuration tried — not at top level, not for a subagent, not from
`--settings`, not from project settings — while `PreToolUse` from the identical config fired
every time. The interactive case was not tested and no claim is made about it.

Rows 3 and 4 become *auto-denied, and visible in `result.permission_denials`*; the table
header gains *measured 2026-08-23 against claude 2.1.241*; a `PermissionRequest` row is
added. A plan document is allowed to be wrong. It is not allowed to stay wrong quietly —
`continue-plan.md` is the sibling that already got this right, and it is the one this
correction lands on.

---

## 3. Multi-root: zero users, one hour, and the right design left on the shelf

**O2** is the item where it would be easiest to write *we fixed it*. That is not what
happened, and the honest version is more useful.

`workspace.build(['~/Repositories/rubricator','~/Repositories/repo A'])` produces 110
documents and 99 stale keys that match no document, of the form
`repo A/repo A/…`. Every second-root document reports `commits: 0`. The mechanism
is two prefixes where there should be one: `workspace.py:399-400` prefixes `d["rel"]` inside
the `find_docs` loop, `git_activity` is then handed rels that are already prefixed, and
`:404-405` prefixes again.

Three more shortcuts sit behind it. Notes for every root are written to
`roots[0]/.rubricator/notes.json` — reproduced on two scratch repos: a note taken on
`repoB/b.md` lands in `repoA`, and opening `repoB` alone reads back nothing. `asset()`
resolves against `roots[0]`. `remember_project` stores a flat list of single path strings,
so there is no representation for a set of roots and a multi-root workspace can never be
reopened as one.

Then the measurement that decides it. `~/.config/rubricator/config.json` holds four recents,
all single paths. All three cached workspace pages are single-root. Nobody has run this
feature, including the person who wrote it and documented it in the code block under
`Watching, and the rest` — `md . ../other-repo`, `README.md:311`.

The correct engineering is known and was priced honestly by the panel that proposed it: a
root becomes `{id, name, path}`, a rel becomes a `(rootId, relPath)` pair, one notes file per
root, asset resolution per owning root, membership tests instead of `D.root` prefix tests —
*a day's careful work rather than an afternoon's*, on the live tier, unwinding a `roots[0]`
shortcut that the notes file, the asset route, `relatedDocs`, the search *here* flag,
`remember_project` and the reindex handler all depend on. For zero users. That is **X22**,
and it stays killed.

So the shape that ships is smaller and states its own limit:

- non-first roots become explicitly read-only — `/notes` writes are refused server-side for
  documents whose root is not `roots[0]`, with a reason;
- the row is badged with its repo;
- `E8` drops from `[x]` to `[~]`;
- `md --help` says the second root is searchable and read-only.

A note written into the wrong repository is data loss, and a feature with no users is still
not allowed to ship one. What is bought here is the removal of that shape, in an hour, with
the good design left on the shelf and reachable the day a real multi-repo user appears.

One adjacent first-contact fix rides along, because it is the gesture a newcomer actually
makes rather than the one the README documents. `md ~/Repositories` builds a
**1,982-document, git-less workspace in 0.65 s** and emits a **41.1 MB** static page,
silently. There is an empty `~/Repositories/.rubricator/notes.json` on this disk,
containing `{}` — somebody already tried it. Warn, or refuse, and say what is about to
happen.

---

## 4. macOS, in six places — the matrix, and the Chrome path fixed at all four sites

**O4.** The string `/Applications/Google Chrome.app` appears five times in `bin/md`
(lines 175, 176, 188, 189, 417) and once in `hook.py` (line 20). Six occurrences, **four
guard sites**: three in `bin/md` (`:175`, `:188`, `:423`) and one in `hook.py` (`:110`,
`os.path.isdir(CHROME)`, fed by the literal at `:20`). Only `bin/md:423` and `hook.py:110`
go through a `CHROME` variable at all; the workspace launchers at `:175` and `:188` test the
literal inline. The register's own line says three, counting `bin/md` only — a fix scoped to
those three leaves the hook broken, and the hook is the one component §10 calls the only one
that opens a window without being asked.

The degradation is cosmetic: every guard falls back to plain `open`, which gives a browser
tab instead of an app window, silently, exit 0. So this is a chore, not a defect, and it
carries exactly one rule — **all four sites or none**, searching `/Applications`,
`~/Applications` and `mdfind`. A partial fix here is worse than no fix, because it makes the
remaining failure look like a different bug.

The second half of O4 is a document, not code. Six capabilities in this tool are bound to
macOS, spread across four files of own code plus `install.sh` and `share/md.zsh`:

1. opening a URL as an app window (`open -na`) — `bin/md`, `hook.py:112`;
2. closing that window by AppleScript (`tell application "Google Chrome"`) —
   `hook.py:126`, `:136`;
3. the native folder chooser (Standard Additions `choose folder`) — `actions.py:151`;
4. `.command` + LaunchServices terminal dispatch, against a hardcoded app table —
   `actions.py:37-42`, `:201-240`;
5. `textutil` and JXA/PDFKit extraction — `extract.py:87`, `:116`;
6. `shasum`, which macOS ships and Linux does not — `bin/md:110` (`-a 256`, the vendor
   checksum) and `:183`, `:357` (`-a 1`, a cache filename). The Linux answers are
   `sha256sum` and `sha1sum`, or one line of Python.

Everything else is portable: `workspace.py`, `serve.py`, `transcript.py`, `workspace.js`,
`shell.js`, `render.js`, `review.js`, `ui.js`, every stylesheet and every template contain
zero platform markers, and `workspace.py:25` shells out only to `git`.

That matrix goes into `docs/` as a decision record, with each row's honest Linux answer next
to it. What does **not** happen is extracting `share/platform.py`. A seam built before the
port it is meant to accommodate is the wrong seam, and it would touch four of the files most
likely to change this month. The matrix answers the first question a Linux visitor asks; it
promises nothing. Whether that answer is *no* or *not yet* is not this document's to give —
see §13.

---

## 5. The twelve standing rules

**O5.** These are the decisions this investigation settled, in full, in one place — because
each will otherwise be re-litigated by a future self who has forgotten the measurement, and
because several of them are the only thing standing between this project and a feature that
would be pleasant to build. Each carries the measurement or the enumeration that justifies
it. A rule with no evidence under it is a preference, and a preference loses to whoever
argues best on the day.

O5's register line says *six decisions*. The register's own standing-rules section lists
twelve, and twelve is what the investigation settled; O5's count is superseded here. The
numbers are load-bearing — `install-plan.md`, `signals-plan.md`, `anchoring-plan.md` and
`retention-plan.md` all cite rules by number, so a rule may gain a clause but the list may
not be renumbered.

1. **The write rule.** Rubricator may write only (a) inside `.rubricator/` in a root it was
   pointed at, (b) inside `~/.config/rubricator/`, `~/.cache/rubricator/` and
   `~/.local/state/rubricator/`, and (c) to a path the human typed in the same gesture —
   `--out`, or a native save dialog. It may never create, modify or delete a file that
   **git tracks**, and never a file it discovered by **indexing**. Proposing a change the
   human applies is an export; applying it is not — at any confidence, behind any flag.
   *Justification:* this rule alone kills four proposals that were separately attractive —
   writing standing rules into `CLAUDE.md` (**X3**), a Suggest verb with one-key apply
   (**X20**), exporting a mark as a candidate `CLAUDE.md` line (**X26**), and writing
   `cleanupPeriodDays` into `~/.claude/settings.json` on the user's behalf. That last one is
   the clearest: a markdown reader that edits another tool's config file is one malformed
   write away from bricking the user's agent.
   The state directory was added for N6's review log — the cache is wrong for it twice over,
   since N1 makes the cache prunable at seven days and a review log that expires in a week
   answers no question. The rule's substance is untouched; the enumeration is amended
   explicitly rather than assumed, because this programme's opening lesson is that
   enumerations drift. `retention-plan.md` §8 asks O5 one further question, and the answer is
   yes: the working directory a hook fires in **does** read as *a root it was pointed at*,
   because the human started the session there and the write lands in the same
   `.rubricator/` a note taken in that repo would land in. So N6's approved-plan-text half is
   permitted.
   `anchoring-plan.md` §10 asks the mirror question and gets the same answer: M6 makes
   `write_notes` walk up for a `.git` directory, so `md docs/deep/nested/` appends
   `.rubricator/` to the `.git/info/exclude` of a repository the human named only the inside
   of. That is permitted — the enclosing repository of a root the human typed reads as that
   root — but only for that one untracked file and that one appended line. It is not a
   general licence to walk up, and no other write may use it.

2. **Nothing that must survive a restart may live in `localStorage`.** Per-root state goes in
   `.rubricator/`, per-user state in `config.json` behind the whitelist; `localStorage` is
   within-run convenience only.
   *Justification:* `serve.py:38` binds `("127.0.0.1", 0)`, and `bin/md:165` launches without
   `--port`, so the default invocation gets a **new origin on every run**. localStorage is
   keyed by origin including port. Everything the page keeps there starts empty every time.
   This is not a first-run problem; it is an every-run problem.

3. **Single reader.** Committing `notes.json` is permitted (`git add -f`) and unsupported.
   Two people editing one JSON blob will conflict and rubricator will not help.
   *Justification:* the measured number of second readers is zero. Everything deferred on
   this basis — per-document note files, authorship, threads — is cheap to build the day the
   answer changes and expensive to carry until then.

4. **Persist the selection, never the assembly.** Rebuild on every open.
   *Justification:* GitHub's own replacement for Copilot knowledge bases is human-*selected*
   and machine-*refreshed*: a Space holds repositories, code, pull requests, issues and
   free-text content, and *"GitHub files and other GitHub-based sources added to a space are
   automatically updated as they change"* (`citations.md` G9, quoting
   `docs.github.com/en/copilot/concepts/spaces`). A saved assembly starts rotting the day
   after it is written.

5. **No MCP server.** The machine-readable door for a local CLI is a flag.
   *Justification:* **X9.** For a tool that already has a CLI, the agent's Bash tool is the
   MCP server — `open_notes` is `cat .rubricator/notes.json`, `search_documents` is Grep and
   Glob. A server buys a calling convention and charges a long-lived process, a second
   security surface the `actions.py` allowlist reasoning does not cover, and a spec
   dependency. Q5's `md --json` is the answer.

6. **No database.** The Logseq DB split is the standing argument: the file-based product is
   now *Logseq OG*, with the vendor's own commitment being *"Security fixes and patches"* and
   *"Electron and dependency upgrades"*, and *"Our focus will be on maintenance and
   reliability rather than new feature development"* (`citations.md` G10, quoting
   `logseq.io/p/e3YDyX5AYr`, linked from the 2.0 beta release of 2026-07-13). The analogy
   lands because the file-based product is
   the one rubricator is: the split is what happens to a file-based tool that adds a
   database, and the file-based half is the half that gets maintenance-only.

7. **Do not generate the artefact.** No spec, no plan, no task list, no template. The tool
   reviews documents; it does not write them.
   *Justification:* the tool has exactly one distinctive computation — a mark that survives a
   rewrite — and it is not built yet (phase M). Every generator proposed during this
   investigation competed for the same evening as that. And a reviewer that wrote the
   artefact is reviewing itself.

8. **An empty result must say which empty it is** — *nothing matched* or *nothing could be
   judged* — with counts.
   *Justification:* `workspace.js:370` renders *"Nothing looks stale — every document that
   names code has been touched since that code last changed"* on a repo where the detector
   resolved **zero targets for 87 of 99 documents**, and on repo D while the same window
   paints 61 warning triangles in the navigator.

9. **No hand-maintained inventory of files in shipped code.** Generate it, or assert it in
   CI.
   *Justification:* `install.sh:59` names seven files plus `hook.py`; `share/` holds eighteen.
   Every developer who ran the copy install got either a blank page and exit 0 or a raw
   Python `[Errno 2]` and exit 1, depending on which of the README's two first examples they
   tried. This rule is also what kills `md --audit` (**X19**): when a hand-maintained file
   list drifts you get a blank page, and when a hand-maintained *security* inventory drifts
   the tool lies about its own attack surface. That is strictly worse than having no such
   command.

10. **Claim coverage and time-to-first-mark; never code quality.** The maintainability
    literature is contested from both directions.

11. **No research sentence is copied.** If a claim is needed it is quoted from a
    `citations.md` card in that card's wording, with its qualifier attached, and vendor
    telemetry names the vendor in the same sentence as the number.
    *Worked example, because a rule about wording has to show its wording.* The correct form
    of the strongest available claim about where review time goes is: *In a CHI 2024 study of
    21 programmers using GitHub Copilot, "verifying suggestion" was the single largest
    activity at 22.4% of session time, ahead of "writing new functionality" at 14.05%; all
    Copilot-related states together accounted for 51.5% of average session duration*
    (`citations.md` A1, quoting Mozannar, Bansal, Fourney & Horvitz, arXiv:2210.14306,
    §6) — **and it travels with its
    qualifier: 21 participants inside one large technology company, on eight assigned lab
    tasks of at most 20 minutes (mean 12.2 min), 19 of 21 in Python, labels applied by
    participants retrospectively, and this is autocomplete-era Copilot, not agents.** A
    sentence that cannot carry that qualifier does not go on the front page, which is why
    rule 10 exists and why none of this appears in §8.

12. **Never scope a design on a documented-but-unfired platform feature** without re-running
    the measurement against the then-current build.
    *Justification:* `PermissionRequest` is documented, and fired zero times under `claude -p`
    on 2.1.241 (§2). It is also the hook event the incumbent registers (§10), which is exactly
    the situation where borrowing a design without re-measuring is most tempting.

One honest amendment goes with them. The README says *nothing is written into your files*.
That is not quite true: `workspace.py:540-546` appends `.rubricator/` to
`.git/info/exclude` when the first note is saved. The intent is good — nothing git tracks is
touched and committing the notes file stays a choice — but the sentence as written is
absolute and the behaviour is not. Amend the sentence; keep the behaviour.

---

## 6. The front page understates the tool

**P1.** `README.md:26`:

> One bash script and a page. No build step, no runtime dependency beyond what macOS ships.

Counted: **7,372 lines across 18 files** of own code — 7,379 including the seven-line
`vendor.txt` manifest, 12,314 including the five vendored files, which the very next
sentence already discloses separately as *the three render libraries* (`README.md:46`) —
three is right, because highlight.js contributes two theme stylesheets. The charitable
number is the right one to judge the sentence against, and the sentence still fails against
it. *One bash script and a page*
describes `bin/md` (429 lines) and `template.html` (422) — **11.5%** — while omitting
`workspace.js` (1,728), `workspace.py` (835), `review.js` (684), `shell.js` (558), an HTTP
server, a subprocess launcher with a hardcoded terminal-app table, and an extractor that
shells out to `osascript`.

The instinct behind that sentence is good and the execution inverts it. The claim being
reached for is *you can read all of this*, and 7,372 readable lines supports it far better
than a figure of speech that a careful reader will check in one `wc -l` and disbelieve.
Understating your own surface is worse for trust than stating it, because the reader who
catches it now doubts the sentences they cannot check.

Two structural problems compound it.

**The trust material is at the bottom.** The best paragraph in the document — the admitted,
fixed `<img onerror>` that used to be a Limitation — sits at line **465 of 473**.
`## How it works`, which lists every file and what it does, is at **264**. A reader deciding
whether to run a script that opens a local server and can spawn a terminal decides on the
first screen — and the first screen currently holds the understated sentence and nothing that
answers the question. Move the file inventory and the trust paragraph above the fold. That
inventory is also, and deliberately, the *replacement* for `md --audit` (**X19**) — but it
does not get an exemption from rule 9 by being prose. This document is itself a catalogue of
prose drift that review did not catch. So the inventory becomes the generated side of the
rule: one more CI step in K3, asserting that every non-vendor file in `share/` is matched by
a line in the `## How it works` block, failing the job when one is not. It would fail today —
the block lists `share/review.*`, `share/ui.*`, `share/shell.*` and `share/workspace.*` as
globs and never mentions `share/md.zsh` at all. Prose that a program checks is not a
hand-maintained inventory.

**One promise is impossible.** `README.md:287-289` says annotations are keyed by the
document's absolute path — *"the same key from either page, so a note written in the
workspace is there when you open the file on its own"*. The static tier is `file://` and the
live tier is `http://127.0.0.1:PORT`. The same-origin policy makes that sharing impossible,
and rule 2's every-run-new-port measurement makes it doubly so. The honest sentence is not an
apology, it is the design: the sidecar is a **decision**. The reviewed artefact stays
byte-identical, review stays out of `git diff`, and an agent told to rewrite the plan cannot
drop or duplicate your marks. Say that, and delete the sharing claim.

Two further sentences on the front page are checkably false and P1's register line does not
cover either. `README.md:185` says *17 MB parses in 0.05 s*; the largest transcript on this
machine is **105.0 MB** and `transcript.read()` parses it in **0.28 s** (`M-POS-10`,
which names README:185 as one of five stale copies of the old figure). And `README.md:124`
says notes whose text is gone are *marked resolved* — the lie §7 takes apart. A section
titled *the front page understates the tool* that leaves two false numbers on the page has
not finished.

*Done when* — this is P1's acceptance condition from the register, with the two omissions
added, and it is the only section here that needs one, because every other section's
condition in the register is already right: line 26 states the real surface, the trust
material is above the fold, no sentence promises cross-origin note sharing,
`README.md:185` carries the measured 105 MB / 0.28 s, and `README.md:124` no longer calls a
lost anchor resolved.

---

## 7. The headline: six candidates, one test

**P2's first half is the only decision in this document that a later commit cannot undo.**
Positioning is chosen once and then defended, which is why it gets a test rather than a
preference.

The test: **does its mechanism work today, on the first file a new user opens, without
depending on a subsystem this investigation condemned?**

| candidate | prerequisite state | verdict |
|---|---|---|
| the document↔session↔git join | **49 of 419** sessions carry a file list; document coverage 12% / 20% / 9% on repo C / repo B / rubricator | fails |
| a triage or read-queue | all three ranking inputs are empty: churn-in-mentioned-files is null for 87 of 99 repo A documents, open-annotation count is 3 machine-wide, read-state does not exist | fails |
| rationale — *why was this decided* | needs the join | fails |
| a curated context pack | depends on three phases landing first | fails |
| the diff lane | ceded — see §12, **X8** | fails |
| **living documents** — the review layer over documents that keep being rewritten | reader, review layer and re-anchoring already ship; the defect is `raw.indexOf` and the fix is phase M, which is small | **wins** |

The join is the one that hurts to drop, because it is the tool's most original computation
and four separate findings wanted it as the headline. It does not work. Of 419 indexed
sessions, **49 carry a file list**. The other 370 are join-less, and 341 of those are older
than thirty days — because the file list comes from `~/.claude/projects/<slug>/<sid>.jsonl`,
and per Anthropic's documentation, *"Claude Code clients store session transcripts locally in
plaintext under `~/.claude/projects/` for 30 days by default to enable session resumption.
Adjust the period with `cleanupPeriodDays`."* (`citations.md` F1, quoting
`code.claude.com/docs/en/data-usage`.)
The join has a thirty-day half-life by construction. Median age of sessions that carry files:
**22 days**. Without: **95**.

The per-repo picture is worse than the ratio, and the best-looking number is the trap.
repo A shows **64 of 99 documents (65%)** joined to a session — and all 64 come from a
single session id, one that touched 80 files. The join's answer to *which conversation
produced this document* is the same answer for 65% of the corpus. That is not a join. It is a
constant.

None of that makes the join worthless; Q1 builds it, with the empty state designed first,
because the empty state is the common state. It makes it unfit to be the sentence a stranger
reads before deciding whether to run the installer.

Living documents wins on the only argument that matters here: it is the single candidate
whose prerequisite is not the index, and the index is where nearly every measured defect in
this investigation lives. A headline gated on a broken subsystem is a headline that cannot
ship this month.

Two narrowings, because the version that lost the argument overclaimed.

**Living *documents*, not living plans.** The plan case is served — the incumbent *"saves
each plan submission before opening the review"* and shows *"a change badge"* with added and
removed lines on resubmission (`citations.md` G11).
What is not served is the ADR from March, the requirements
document rewritten four times, the sixty-page vendor PDF. Write *we serve that*, never
*nobody serves that*: absence claims about a market are unfalsifiable in the dangerous
direction, and this one is checkable in ninety seconds by someone who wants you to be wrong.

**The mechanism has to be true before it is printed.** `README.md:122` says notes are
re-anchored by *content*, not line number — true of `raw.indexOf(it.anchor)` at
`review.js:119` as far as it goes. Two sentences later the same paragraph says notes whose
text is gone are *marked resolved and greyed out*, and that is the lie: exact substring,
first occurrence, and a miss sets a state the tray reports as an accomplishment.
`docs/review-design.md:141-142` specifies a per-item quote-hash that was never built. Phase M is
the whole prerequisite, and it is small. Nothing in §8 gets written until it lands.

**This section proposes; it does not decide.** The one-sentence answer to *what is `md` for*
is the owner's to write, and it is open question 1 in the register. What this document can
say is that five of the six candidates fail a test that was applied to all six, and that the
sixth is the one whose mechanism already ships.

One hazard worth naming before the owner writes it: Moat's own tagline is *"The review layer
for agent-written docs"* (`citations.md` G13, and §10). The proposal above is that sentence
with one noun changed. The distinguishing word has to be the one about rewriting, not the one
about review layers.

---

## 8. What comes out, and what goes back in

**P2's second half.** The README is 4,074 words under 20 headings. Two sections and two
paragraphs come out — the last two from inside `## Watching, and the rest`, which is why
naming them by heading would send the rewrite to the wrong place:

- **`## Themes`** (409) — a palette is not a reason to install anything;
- **`### Extending it`** (320) — advertising an extension API before you have a user invites
  the reader to wonder who else is building on it, and the answer is nobody;
- **the Graph paragraph** (301-303) — deleted in §9;
- **the power-flag code block** (309-313) — operator detail, not decision detail.

The editorial rule that decides every remaining paragraph: *does this help a stranger decide,
or an existing user operate?* Both are legitimate; they are not the same document, and today
they are interleaved.

Three things backfill the space, in this order.

**(a) The review layer over documents that keep changing.** §7's argument, in two paragraphs.

**(b) PDF and Word.** Already shipped, carrying the whole review layer, with a heading per
page and the page number surviving into the export — a marked-up PDF that can be handed to an
agent. It works today, and the front page does not mention it until line **377 of 473**,
under the ninth `##` heading. It is the second-strongest thing on the list.

**(c) The durable half of the history index.** Every prompt typed in **18 project directories
over 128 days** — 3,998 of them — searchable in one field in about a second, because
`history.jsonl` is documented as kept until you delete it. Eighteen is the count of distinct
projects in `history.jsonl` (`M-RET-14`); `retention-plan.md` publishes **20**,
which is the count of project paths in the session cache — two different files, two right
answers, and *projects* rather than *repositories* because some of them are not repos. This
one is true today and it is worth a sentence. **Do not attach the file-join to that
sentence.** The durable half and the thirty-day half are different claims and only one of
them survives contact with a new user's back catalogue.

Also in P2: add the two missing screenshots — a workspace with a split and the tray, and
`⌘K` mid-query — move `--sessions` into the first code block, and rewrite the GitHub
description, which is the first sentence most people will ever read and currently does no
work.

---

## 9. The graph goes, and not for the reason we first gave

**P3**, and the clearest single measurement error the investigation caught in its own
output.

The original case for deleting the correlation graph was that its spring layout *freezes the
window for millions of iterations*. Somebody counted iterations and inferred a stall without
timing one, and three further arguments were then built on the scary number. Ported verbatim
to V8 — the same engine Chrome runs — the loop takes **19.5 ms** at 299 nodes and 1,561
edges, **43.5 ms** at 301 nodes, and **234 ms** at a thousand nodes — more than three times
the largest graph ever drawn here. `graphEdges`' 919,500 string comparisons cost **3.0 ms**.
There is no freeze, there is not a perceptible hitch, and the proposed salvage — moving the
relaxation
into a `requestAnimationFrame` chunk loop — would be work spent chunking twenty milliseconds.
That argument is **X2** and it is struck. It must not reappear in a commit message.

Delete it anyway, for a reason that was measured.

The graph draws only nodes that have at least one edge. On repo A that is **11 nodes out
of 99 documents**, because 87 of the 99 resolve zero targets. On repo C it is **300
nodes of 502**, and on repo B 196 of 330 — drawn into a fixed 900×560 viewBox with no zoom
and no pan, which is **1,680 px² per labelled node** at 11 px type. Small repositories get a
stub. Large repositories get a hairball. **There is no corpus size at which this feature is
both legible and informative**, and that is a structural property, not a tuning problem.

The second reason is maintenance, and it is decisive for one maintainer. The graph's edges
come from the same target-extraction pass that phase L is about to relabel, and whose obvious
widening was measured and refused (**X14**). Keeping the graph means re-tuning `g.length > 12`
and `hit.length <= 15` every time that subsystem moves.

`viewGraph`, `graphEdges` and their CSS go. `E3` reads *removed*. The register records why in
one paragraph — including the struck performance claim — because the deletion, honestly
argued, is better material for the front page than the feature ever was.

---

## 10. Prior art, named and numbered correctly

**P4 begins with a correction to P4.** The register says the README has no prior-art section.
It has one, at line **442**, and it has had one since the first commit — `git log -S'## Prior
art'` returns `61550b2`. Two paragraphs, naming plannotator, md-annotator and Imark, and its
sentence about Imark is accurate today. Writing *the README has no such section* into a plan
document would have reproduced exactly the defect this document exists to fix, one paragraph
after describing it. It is recorded here rather than quietly fixed.

What the section lacks is numbers, the native alternatives, and scale. All three are
correctable, and every figure below was re-run with `gh api` on **2026-08-23**. Star counts
move; each one below is dated, and the register's own 7,970 for plannotator had already
drifted by one when this was written. That is the standard the section is held to — a
rounding error of thirty is what the *8,000+* objection was about.

**plannotator** — **7,971 stars on 2026-08-23** (not *8,000+*; that rounding is literally
false), 590 forks, **1,072 commits**, created **2025-12-28**, Apache-2.0, TypeScript. That is
**7 months 21 days** ahead of rubricator's first commit on 2026-08-18 — *nearly eight
months*, not *seven*. It has
shipped **147 releases** in eight months, one every 1.6 days. Nine agents, of which three
(Amp, Droid, Kiro CLI) are manual invocation rather than an integration. Full PR and MR diff
review, plus local diffs, Git, Jujutsu and Perforce. Its Claude Code integration registers a
**`PermissionRequest`** hook on `ExitPlanMode` (`citations.md` G12), where rubricator
registers `PreToolUse` on the same tool — a real distinction, and the reason rule 12 names
that event. And a **Version Browser** that *"saves each plan submission before opening the
review"* and shows *"a change badge"* with added and removed lines when the agent resubmits
(`citations.md` G11) — **the one competitive gap in this comparison that is real**, because
it is the feature closest to what §7 chose as the headline.

**PlanBridge** — MIT, localhost, no account, 27 stars and one fork, created 2026-04-29.
**Moat** — hosted, account-based, *"The review layer for agent-written docs"*
(`citations.md` G13).
**Imark** — 46 stars in **eighteen days** (created 2026-08-05), Swift, MIT, and it stores
notes in the `.md` itself as HTML comments, which is genuinely better than local storage if
you move between machines. **md-annotator** — 5 stars, 392 commits, created 2026-01-28.
Rubricator: **0 stars, 0 tags, 0 releases, no topics, no homepage.**

The **native alternatives** matter more than any of them, and the current section names none:

- Claude Code's `Ctrl+G` — *"Press `Ctrl+G` to open the proposed plan in your default text
  editor and edit it directly before Claude proceeds"* (`citations.md` G7).
  It is an edit affordance: no quoting, no line anchoring, no structured feedback channel.
  But it ships, in the terminal, to everyone.
- The vendor's own VS Code extension — *"VS Code automatically opens the plan as a full
  Markdown document where you can add inline comments to give feedback before Claude begins"*
  (`citations.md` G8). Automatic. Zero install. This is the best-sourced
  competitive fact available and it is not currently on the page.
- `/insights`, reported in February 2026, analyses local session history from `~/.claude/`
  (about 30 days, up to 50 sessions) and writes an HTML report to
  `~/.claude/usage-data/report.html` without sending data off the machine (`citations.md`
  F2). **That is secondary-sourced — no primary announcement page was located, so report it
  as reported behaviour, not as documented behaviour.** It matters because it is the
  first-party tool reading the same local corpus the session surface reads.

Three claims must not be printed. They are written out here, the way the killed list is
written out, because naming them is what stops them coming back — each is checkable in under
two minutes by a reader who would enjoy the catch:

1. ***no Bun needed.*** End users get a prebuilt per-platform binary from one `curl`; Bun is
   the development runtime. The honest differentiator is an opaque compiled binary behind a
   2,130-line installer versus 7,379 readable lines.
2. ***nobody has a verb grammar.*** The incumbent's plan review offers free text,
   mark-for-removal, quick labels, mark-as-looking-good, direct markdown edits, global
   comments and three verdicts. Rubricator's verb set is a subset.
3. ***Anthropic tried browser plan review and local won.*** Ultraplan's removal page points
   users at Claude Code on the web — another cloud product. It is a product consolidation,
   not a verdict on an axis.

A fourth number in the register does not reconcile and is therefore not used: *three
Claude-session viewers with 2,885 stars between them*. Re-queried 2026-08-23,
`jhlee0409/claude-code-history-viewer` has 2,089, `raine/claude-history` 457,
`eckardt/cchistory` 137 and `adewale/claude-history-explorer` 18 — **2,683** for the three
largest, 2,701 for all four. Print the repositories and their numbers, or print 2,683. Not
2,885.

Finally, the hook's placement. It stays visible in the Install section and out of the first
paragraph. Its job is not to beat a 147-release incumbent on the plan-review lane; its job is
that it is **the only component in this tool that opens a window without being asked**, at a
moment the user is already stopped and already has to read something. Every other surface
requires a decision to go and look. An on-ramp does not have to be best in class to be the
on-ramp — but it should not be sold as the thesis, and no further investment goes into it.

---

## 11. Three small ones: the keyboard, the tag, the manifest

**P5 — the keyboard tool gets a keyboard.** Three repairs, none of them an accessibility
project.

`all:unset` appears **23 times** across the three stylesheets — 9 in `review.css`, 11 in
`shell.css`, 3 in `ui.css` — and `all:unset` resets `outline-style`, so the platform's focus
ring is gone by construction. One global rule restores it:

```css
:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px }
```

`shell.js:437` handles `Tab` with no shift check, so `⇧Tab` advances the palette's kind
filter — the thing `README.md:162` documents as *`⇥` filters by kind* — instead of stepping
back through it. Selection is `ArrowDown`/`ArrowUp` at `:433-434` and is not involved. And
the entire workspace keymap — `⌘\`, `⌘E`, `⌘B`, `⌘1-9`, `⌘⌥[`, `⌘⌥]`, `⌘W` — exists only in
`README.md`. A tool whose interface *is* a keymap is failing at its own premise. The reader
tier already has a shortcuts sheet at `⌘/` (`ui.js:288`, `template.html:308`); the workspace
does not include `ui.js`, so port that sheet rather than inventing a second one, and hang it
off the existing `#more` menu. While there, drop the
`if (navMode === 'notes') setNavMode('docs')` side effect at `workspace.js:1683-1689`, so `/`
filters the mode you are actually in.

**Do not bind `⌘F` in the workspace.** The reader binds it (`ui.js:285`) and `README.md:62`
documents that. The workspace deliberately does not, so it falls through to the browser's own
find bar — which already has a hit count, next and previous, and wrap-around. Keep the split,
because the two tiers are searching different things, and say so in the `?` sheet rather than
leaving a reader to grep for the answer.

**P6 — a tag, topics, a badge.** Cut `v2.0.0`, set six topics, point the homepage somewhere,
add the CI badge from K3. Not because the fields are empty — the measured star count is 0 and
nobody is failing to find this repository — but because each answers a specific reader. A
stranger who wants to pin a version has nothing to pin. The badge is the only place K3's
assertion becomes visible to someone who has not read `.github/`. Topics and the homepage are
the two fields GitHub search reads. Two refusals go with it. **Do not put the project's age in
the README** — a stranger who is already suspicious of a five-day-old repository is confirmed
by that sentence, not reassured, and the commit dates say it anyway. **Do not turn on
Discussions** until someone files an issue; an empty discussion board is a louder signal than
no discussion board.

**P7 — the plugin manifest, in the repo.** P7 is drafted, not started: open question 2 blocks
it, because a distribution channel is only worth building for a second reader and today the
measured count is zero. What it buys when it unblocks: ship
`.claude-plugin/marketplace.json`, `plugin.json` and `hooks/hooks.json`, so a Claude Code user
can run `/plugin marketplace add TheRealVale/rubricator` and get the hook without
`install-hook.sh` performing surgery on `settings.json`. A few dozen lines of JSON that reduce
`install-hook.sh` to a wrapper, or delete it.

Two honest limits go in the README beside it. A plugin's `bin/` is documented as *"Executables
added to the Bash tool's `PATH`. Files here are invokable as bare commands in any Bash tool
call while the plugin is enabled"* (`citations.md` G3) — the
*agent's* PATH, not the human's interactive shell — so the plugin channel delivers the hook
and only the hook; a human who wants to type `md` still clones and runs `install.sh`. And the
community directory is not distribution:
`anthropics/claude-plugins-community` lists **2,282 plugins**, roughly 700 of which
keyword-match plan, review, markdown or doc. Entry 2,283 is not a channel. Skip the
submission.

---

## 12. What this will never be

Recording the refusals is the point of the document. Each of these was argued for, measured,
and killed; each will be proposed again.

**No diff or pull-request review (X8).** The entire case for it was addressable market, and
the market numbers did not survive: LinearB never defines what an *AI pull request* or an
*acceptance rate* is (`citations.md` B2), Faros AI measures a within-organisation comparison
of lowest- against highest-adoption periods rather than a time trend (`citations.md` B1), and
the headline ratio that was going to carry the argument is arithmetically wrong — it is in
*Do not cite*. Naming them is the point — a refusal a reader can
re-examine is worth more than one they have to re-argue. The target is meanwhile occupied by
1,072 commits of TypeScript with Perforce and Jujutsu support, and the work is not the effort
it was filed at — a diff parser, hunk-level
anchoring across two file versions, a side-by-side render path, and forge integrations to
matter at all.

**No MCP server (X9), no database (rule 6), no transcript archive (X10).** The
archive is the one worth stating in full, because it is seductive: it is roughly 960 MB per
thirty days, unscrubbed — 118 of 7,830 assistant text blocks on this machine match the
project's own secret patterns and the shipped scrubber catches none of them — and it
permanently defeats the vendor's own privacy control, whose first documented mitigation for
plaintext credentials is to *lower* the retention period. It does not even restore
resumability. Ten lines of retention advice (N5) dominate it on every axis.

**Staleness is not the thesis (X13).** `targetChurn` correlates **0.84** with the number of
paths a document quotes and **0.12** with its age — it measures verbosity, not decay — and it
flags 71.5% to 92.4% of the documents it can judge. Positioning is the one decision a later
commit cannot undo, and this one would oblige a solo maintainer to defend an accuracy table
against ground truth that does not exist. The signal gets demoted and relabelled in phase L;
it does not get a front page.

**No `md --audit` (X19).** See rule 9. The property it advertises already exists, better and
for free: 7,379 readable lines.

**No document map or PageRank over the corpus (X11), no coverage inverse-map (X12).** The
document link graph is nearly edgeless — **0 doc→doc links across 330 repo B documents**, 1
across 84 in repo D — and PageRank on an edgeless graph returns the uniform distribution,
which would ship an arbitrary ordering with an algorithm's authority behind it. The coverage
map would produce a to-do list with 1,223 rows.

**No blocking review hook on markdown writes.** An agent touches **8.8 to 56 markdown files
per active day** in a single repository — 8.8 on repo D, 18.5 on repo B, 23.5 on
repo C, 56 on repo A — and the user works across 2.5 repositories a day on
average. A blocking `PreToolUse` on `.md` writes
would open a modal window dozens of times a day, each with a timeout. The user's response
would be to disable the hook, which is the tool's only occasion generator. The feature deletes
the on-ramp in about two days of use.

**And the ambition itself, honestly.** *A tool you keep open all day* is not achievable here,
and the reason is structural rather than a missing feature. A tool is open all day only if it
changes while you are not looking and tells you when it did. The second half requires a
background process watching several repositories with no window open — a daemon — plus
read-state, which means tracking what you have read rather than only what you marked, plus one
window spanning repositories. *Dies when you close the window* and *keep it open all day* are
the same sentence with opposite signs, and the first one is the more valuable asset. The right
target is frequency times summonability: a window you open five times a day, in under a
second, at moments something else created.

---

## 13. The questions this document cannot answer

Five of the register's six open questions bear on scope. They are the owner's, not this
document's, and nothing here decides them.

1. **What is `md` for, in one sentence?** §7 proposes *the review layer for documents that
   keep being rewritten*, and shows the test that selected it from six candidates. The
   sentence itself is the owner's to write, and it blocks P1 and P2. If the answer is the
   document↔session join instead, §7's table is the argument against, and §8 changes
   completely.
2. **Is there a second reader, actual or intended, within six months?** Today the measured
   answer is no, and rule 3 is written on that basis. The register blocks O2, O5 and P7 on
   it, which is why §11 states P7 and does not start it. Accepting rule 3 permanently
   unblocks all three and is much the cheaper answer.
3. **Is macOS-only a decision or a *not yet*?** §4's matrix can be written either way, but it
   cannot be written honestly without the answer, and the answer determines whether the
   platform seam is ever worth extracting. One line in the README settles it.
4. **Is the diff lane off the table permanently, or a 2027 bet?** §12 cedes it. If the owner
   disagrees, §10 says something different about the incumbent and phase Q's value changes.
   Record the decision here either way — an unrecorded cession is re-argued every quarter.
5. **Does Approve actually skip Claude Code's approval menu?** The register blocks P1 on it,
   and rightly: §6 cannot say what the hook does until someone has pressed Approve once and
   watched. It cannot be settled by reading documentation — two of the vendor's own pages
   disagree, and they disagree precisely about the interactive case rubricator runs in
   (**X5**). One plan, one keypress.

The remaining one — whether `md --sessions` will ever run on a machine with client work on
it — moves phase N's position rather than this document's argument.

---

## 14. What this phase trades away

It buys nothing a user can see. Not one line of O or P adds a capability: the graph is
deleted, four register lines are corrected, a feature with zero users is made read-only, and a
README is rewritten. Against a phase that could have shipped the join, or the diff lane, or
the archive, that is a poor-looking week.

It is the right week because every one of those alternatives would have shipped a confident
answer computed from a signal this investigation showed cannot support one — which is the
defect itself, not a symptom of it. The programme's own sentence applies to its own
documents: **stop reporting confidence you have not earned.** A register that lies has
stopped being a planning instrument, and a front page that offers 11.5% of its own code as
the whole of it is a trust claim that fails on the first `wc -l`.

What is given up, and should be recoverable later: the multi-root design that is correct and
costed (**X22**), on the shelf; and the join as a headline, which Q1 builds anyway and which
becomes honest the day N5's retention warning stops the transcripts expiring.

The graph is not on that list. §9's argument is structural — the stub half and the hairball
half are two ends of one corpus-size range, not two tuning targets — and the extractor work
that would change the stub half is **X14**, measured at 5.03 s on repo C and refused.
If the graph ever returns it returns as a different feature with a different argument, and
that argument has to be made from scratch.

See `install-plan.md` for phase K, `signals-plan.md` for L, `anchoring-plan.md` for M, and
`retention-plan.md` for N. The task lines, with their *done when* conditions, are O1–O5 and
P1–P7 in the register.
