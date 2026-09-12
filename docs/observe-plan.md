---
title: What the agent did to the code
subtitle: Phase R — the settled change set, prompt-to-code provenance at two grains, and the two rules this cannot have without an amendment
status: plan — 2026-08-30, hook measurement 2026-09-12. §1 is a collision with X8 and rule 1; §6 and §9 are decisions only the owner can take
---

# What the agent did to the code

> Watch an agent work on a repository, and afterwards see exactly what it
> changed, why each line is there, and which prompt to blame — then act on it.

This is the most-requested shape in the category and the one this project has
already refused once. The refusal was correct on the evidence it had. This
document establishes which parts of today's proposal that evidence actually
covers, measures the rest against the current build, and separates what can be
built under the standing rules from what needs one of them changed.

Two things here are decisions rather than designs, and they are marked as such.
Nothing in §6 or §9 should be built before they are answered.

---

## 1. The collision, stated first

Three parts of this proposal are already adjudicated, and a plan that did not say
so on its first page would be the exact failure `scope-plan.md` was written to
stop — a feature re-argued each quarter by a self who has forgotten the
measurement.

**X8 — no diff or pull-request review.** *"Ceded permanently on 2026-08-24 — the
owner's decision, not a deferral to a 2027 bet, and it is recorded here so that it
is not re-argued each quarter."* The work it names is the work this proposal
names: *"a diff parser, hunk-level anchoring across two file versions, a
side-by-side render path, and forge integrations to matter at all."*

**Rule 1, the write rule.** *"It may never create, modify or delete a file that
git tracks … Proposing a change the human applies is an export; applying it is
not — at any confidence, behind any flag."* Revert-this-file, revert-this-hunk and
discard are working-tree writes to tracked files. They are not a hard case under
rule 1; they are the central case it was written to forbid.

**The all-day ambition.** *"A tool you keep open all day is not achievable here,
and the reason is structural rather than a missing feature … The right target is
frequency times summonability: a window you open five times a day, in under a
second, at moments something else created."* A realtime monitor is the all-day
tool by construction, and needs the daemon that paragraph refuses.

So the naive reading of the request — a live monitor you keep open, with a diff
lane and git buttons — is refused three times over by this project's own record,
and this document does not argue with any of the three.

What follows is the part that is genuinely not covered.

---

## 2. Measured on this machine, not assumed

Against `claude` **2.1.251**, 2026-08-30. Rule 12 obliges a re-measurement rather
than a citation of the 2.1.241 figures, and the numbers below are the ones this
plan is scoped on. The command behind each belongs in `measurements.md` before
anything here is built.

| | measured |
|---|---|
| transcripts on disk | **84**, totalling **954 MB** — the 960 MB/30 days of X10 reproduces exactly |
| carrying at least one structured file edit | **52 of 84 (62%)** |
| median edits per file touched, per session | **2.59** |
| sessions that rewrite at least one file they already wrote | **45 of 52** |
| the largest run on this disk | **1,966 edits across 260 files** — 7.6 edits per file |
| the most-rewritten single file in it | `main.ts`, **154 times** |
| gross lines changed vs. net effect, four sessions | **62% · 78% · 75% · 65%** — so **22–38% of what a live feed shows is superseded before the run ends** |
| files touched and left net-unchanged | **0 of 362** across those four sessions |
| per-edit structured diff | present on Edit and Write: `toolUseResult.structuredPatch`, real hunks (`oldStart`/`newStart`/`lines[]` with `+`/`-`) |
| file work through Bash | **18,119 Bash calls against 7,995 Edits**, of which **4,753 command lines are write-shaped** — and a Bash write carries **no `structuredPatch`** |
| human-vs-agent attribution | **absent.** `toolUseResult.userModified` is `false` on all **9,429** records that carry it |
| subagent attribution | present: `isSidechain` on the record |
| prompt causality | present: `promptId` → `parentUuid` chain → `requestId` → `tool_use` → patch |

Two honesties about the table. The gross-vs-net row is computed only over files
whose baseline is recoverable from the transcript — **245 of 260, 69 of 103, 27 of
53, 21 of 110** — because `originalFile` is absent on some update records, so the
ratio is measured on the recoverable majority and not on every file. And the first
attempt at that row produced *net exceeding gross*, which is arithmetically
impossible: file creations carry an empty `structuredPatch`, so a create-blind
gross undercounted. The corrected figures are above. The wrong ones are recorded
here rather than deleted, because this is the second time in this project's
history that a plausible-looking formula reproduced a wrong number
(`signals-plan.md` §3), and the lesson is the same one.

### The two hook events this depends on

Re-measured on **2.1.269**; the figures above were taken on 2.1.251, and rule 12
asks for the re-run rather than the citation. These come from hook fires recorded
in real sessions on this machine, not from a synthetic harness — two projects here
already configure both events, so the question is answered by what happened rather
than by what a test rig can be made to do.

| | measured |
|---|---|
| `Stop` fires | **865** recorded, `hookErrors: []` on **847** — the error channel works, and the nine failures are a project's own parity hook reporting |
| `SessionStart` fires | **69**, across only **20** startups: `compact` **34**, `startup` 20, `resume` 7, `clear` 7, `fork` 1 |
| `SessionStart` arrives ahead of the first prompt | by **2m49s** in the session measured |
| a session that never settles | one carries `SessionStart:startup` and **zero** `Stop` fires across seven assistant turns |
| recorded outcomes | 212 `hook_success`, 368 `hook_additional_context`, **1** `hook_cancelled`, no failures |

Both events fire, so R6 is no longer scoped on an unmeasured platform feature. Two
consequences, and each one changes a design.

**`SessionStart` is not once per session.** Sixty-nine fires against twenty
startups, and `compact` is its most common source — a long session that compacts
eight times fires it eight times. A hook that *opens* a window would put eight of
them on the screen. The hook must be *ensure running*, and idempotence is the
requirement rather than a nicety.

**`Stop` is not guaranteed.** One session on this disk has a startup fire and no
`Stop` at all across seven assistant turns. A run that settles only on `Stop` would
sit in *running* forever, so quiet has to settle it too: no write for a fixed
interval and no live turn in the transcript reads as **presumed settled**, marked
as such and never shown as though the agent had finished cleanly.

---

## 3. What is new since X8, and what is not

X8 was killed on **addressable market** — that is what its own paragraph says, and
the market figures are the part that did not survive. Every argument recorded
against it is an argument against *shipping a code-review product*: the incumbent's
1,072 commits, Perforce and Jujutsu support, forge integrations *"to matter at
all"*.

None of that bears on the question the owner actually asked, because the answer to
*who is the first user* was **you, right now**. A surface with one user needs no
addressable market, competes with no incumbent, and integrates with no forge. The
X8 refusal is intact as a refusal of the *product*; it never measured the *tool*.

That distinction is only worth anything if the tool does something a diff viewer
cannot, and it does — one thing, which is the whole of the case:

**Git knows what changed. Only the transcript knows why.** `promptId` →
`tool_use` → file is an unbroken causal chain from the sentence you typed to the
code that exists because of it. That is not diff review. It is the
document↔session join — this project's most original computation — pointed at code
instead of at markdown.

The chain resolves at two grains, and the difference is the `structuredPatch`. An
Edit or a Write carries one, so the chain ends on a *line*. A Bash write carries
none, so it ends on a *file* — this turn's command wrote this file. Both are the
same causal claim at different resolution, and the corpus is mostly the second:
18,119 Bash calls against 7,995 Edits. A surface that showed only the line grain
would be silent about most of the work.

And here the strongest objection reverses. §7 measured that join and found it
**fails**: 49 of 419 sessions carry a file list, a thirty-day half-life by
construction, median age 22 days with files against 95 without. That measurement is
correct and it is fatal — *retrospectively*. Every one of its failure modes is a
transcript that has been deleted or a session too old to carry one.

For a run that is happening now, or that ended this afternoon, the transcript is
**present by construction**, and coverage is 100%. The join does not fail
prospectively. It has never been tried prospectively, because every surface built on
it so far has pointed backwards.

That is the one genuinely new fact in this document, and it is the only ground on
which any of this should be built.

---

## 4. The thesis: do not watch, settle

The request is for a realtime view. The measurement in §2 says a realtime view is
the wrong surface, and the number is not marginal: **22–38% of the lines a live
feed would show you are superseded before the run ends**, the median file is
written **2.59 times**, and one file on this disk was rewritten **154 times** in a
single session.

Reading a live feed therefore means reading drafts. You form opinions about code
that will not exist in four minutes, and — worse — you spend the attention you
delegated the work to save. The naive feature is not merely low-value; it is
*negative*-value, because it converts an asynchronous agent back into a synchronous
one that you sit and watch.

What has value is the **settled set**: the net effect on each file, computed once
the run stops, deduplicated across the 2.59 writes, with the 154 rewrites collapsed
to one diff and recorded as a *churn* number beside it.

And churn is the second thing only this tool can offer. A file the agent rewrote
fourteen times is a file it was struggling with, which makes it the highest-prior
bug site in the change set. **Ranking a review queue by churn is a signal git cannot
produce**, because git sees only the final state. It costs one counter.

This also resolves the collision with the all-day ambition. §12's stated target is
*"frequency times summonability: a window you open five times a day, in under a
second, at moments something else created."* **A session beginning is exactly such
a moment**, and this project already has the machinery that acts on one: `md --hook
plan` opens a window when Claude finishes a plan. The observe surface is the same
gesture with a different trigger — `SessionStart` rather than `ExitPlanMode`.

The trigger is the beginning rather than the end for a mechanical reason. A
baseline cannot be taken retroactively: `git stash create` describes the tree as it
is now, not as it was when a prompt began an hour ago. A window summoned when the
agent stops arrives one moment too late to have captured anything, and would show a
reconstructed set where an exact one had been there for the asking.

So: not a monitor you keep open. A window that comes up when you start working,
watches quietly, and has an exact answer ready each time the agent stops. That is a
smaller feature than the one requested, it is the one the measurements support, and
it needs no daemon.

---

## 5. Tier A — what survives every standing rule unchanged

Read-only throughout — the one ref these write is rubricator's own, under a
namespace nothing else reads. No working-tree write, no rule amendment. This is the
whole of the recommended first build.

**What a run is.** Not a session. A session on this disk runs for a median of
**22.9 hours**, 45 of 95 span more than a day and the longest is **743**, so *what
this session changed* is a branch diff wearing a different hat. A run is **one
prompt and everything the agent did for it** — baselined at the prompt, settled
when the agent stops or goes quiet. That gives several runs per session, each small
enough to read, and it is what makes *undo what prompt 2 did* a coherent sentence.

**R1 · The baseline, and what holds it.** At each prompt, record `HEAD` and — only
if the tree is dirty — a tree object for it. `git stash create` writes that object
without touching the working tree and without touching the stash list, which stays
empty; on an unchanged tree it returns what it returned last time, so a repeat
costs nothing. A clean tree needs no object at all: the baseline *is* `HEAD`.

The object is anchored at `refs/rubricator/runs/<sid>/<n>` rather than left to
fend for itself. Unanchored it is a dangling commit — `git fsck` reports it as
noise and `git gc` decides when it dies, which may be in the middle of the run that
needs it. Anchored, every baseline the tool holds is one `git for-each-ref
refs/rubricator/` away and removing one is `git update-ref -d`. A ref is dropped
when its run's work is committed and when the run passes the thirty-day transcript
cliff, and the namespace is swept on window open. The cleanup ships in the same
commit as the thing that writes: this project has already shipped a prune that
globbed the wrong path.

The capture belongs to the open window, not to a hook. The `/events` loop already
ticks every second; it tails each watched transcript from a stored byte offset,
sees a new prompt within that tick, and takes the baseline then. A run that happened
with no window open has no baseline and falls back to the reconstructed set of R3 —
line grain where a `structuredPatch` exists, file grain for a Bash write — which is
coarser and says so.

Run state lives in `.rubricator/runs/<sid>.json` — rule 1 (a), rule 6 (a file, not
a database), rule 2 (not `localStorage`). *Done when:* a baseline survives a window
restart and a session resumed in another terminal, a repeat capture on an unchanged
tree adds no object, and `git stash list` is empty after a day of watching.

**R2 · The settled change set.** `git diff <baseline>` for what changed — not a
fold of the per-edit patches. This is the important architectural call and it is
what keeps R2 out of X8's cost estimate: **git is the diff engine, the transcript is
the attribution layer.** X8 priced *"a diff parser, hunk-level anchoring across two
file versions, a side-by-side render path"*; none of the three is built here, because
`git diff` already did all of it and the render is a one-column patch view, not a
side-by-side.

One working tree, several runs. Sessions here share a directory — **1 of 95** ran
in a worktree, and no project on this machine has more than one — so `git diff
<baseline>` shows the other run's writes beside this one's and cannot say which is
which. The division of labour survives, but its weight moves: **git supplies the
hunks, the transcript decides whose they are.** A file that no record in this run's
transcript names is not in this run's set, however dirty the tree is around it.
*Done when:* a run's set matches `git diff` from its baseline restricted to the
files its own transcript names, and a file only a concurrent session wrote is in
neither run's set by accident.

**R3 · Attribution, at the grain the record supports.** Subagent work is marked
from `isSidechain`, which is on every record. A human-versus-agent split is not
available and no amount of design recovers it: `userModified` is `false` on all
9,429 records that carry it, so nothing in the transcript separates a line you
typed from one the agent wrote. What the record does support is *how* a line
arrived — `structuredPatch` overlap for Edit and Write, and the command itself for
a Bash write. *Done when:* a file rewritten by a heredoc is attributed at file
grain and says so, beside one rewritten by Edit that is attributed line by line.

**R4 · Provenance, both directions.** Click a line → the prompt that caused it and
the assistant's stated reason. Select a prompt → its work highlighted across every
file. This is §3's argument made concrete and it is the feature the whole plan
exists for. It highlights lines where a `structuredPatch` exists and the whole file
where the writer was Bash, and the surface says which of the two it is showing
rather than letting a file-grain answer pass for a line-grain one. *Done when:*
both directions resolve on a live session, and rule 8's empty states — *this line
predates the run*, *this file's writer named no lines*, and *this run's transcript
is gone* — read differently and are counted.

**R5 · Churn.** Writes-per-file, and the review queue ordered by it rather than
alphabetically. It counts both grains — a file the agent rewrote fourteen times
through a heredoc was fourteen times as hard to get right as the count would
otherwise suggest, which is why the classifier behind `touches` is this item's
precondition. *Done when:* the 154-rewrite file sorts first.

**R6 · The summons.** A `SessionStart` hook ensures the window is running for this
project, the way `--hook plan` opens it on a plan. *Ensure*, never *open*: §2
measured 69 fires across 20 startups with `compact` the most common source, so an
`open` would stack eight windows during one long session. Non-blocking, and a
failure must exit 0 and leave Claude Code untouched — `hook.py`'s existing guiding
rule. *Done when:* eight compactions in one session leave exactly one window, and a
session that starts with the window already up changes nothing on the screen.

**R7 · The live lane.** While the window is open: which session is running, the
file it is writing, a churn tick per write, and amber on a tripwire glob you
configured. That is the whole of it. Each of those is true at the instant it is
recorded and none of them is superseded four minutes later, which is exactly what
§4 says the content is not. It never steals scroll and never opens a file on its
own. This is the part of the original realtime request that survives, and it
survives because it carries state rather than drafts.

**R8 · Collisions.** Two runs whose write sets intersect get a marker, on both rows
and on the file they share. Live against live is the obvious case; live against
settled-but-uncommitted is the one that has actually cost time here, and it clears
itself when that work is committed rather than needing a gesture. This is the one
thing in this document that neither a diff viewer nor a per-run surface can offer,
and it is not hypothetical: **13.8% of all active ten-minute windows on this
machine have two or more sessions running in the same directory**, with a peak of
**seven**. It is drawn calm — a marker and a word, never a modal — because §8's
rule about what may interrupt applies to it exactly as it applies to tripwires.
*Done when:* two sessions writing `workspace.py` see each other, and one of them
committing clears it.

Nothing in R1–R8 writes anything git tracks, generates any artefact, needs a
database, a daemon, an MCP server or a forge.

---

## 6. Tier B — the git actions, and the rule they need · **DECISION**

The requested actions split cleanly in two, and the split is rule 1's own wording:
*"create, modify or delete a file that git tracks."*

**B-ref — stage, unstage, commit, branch, tag.** These write `.git/` refs and the
index. They do not create, modify or delete any tracked *file*. On the letter of
rule 1 they are already permitted, and I think that is the right reading rather than
a loophole: nothing you were looking at changes, and every one of them is
recoverable from the reflog. What they need is a clarifying clause, not an
amendment.

**B-tree — revert file, revert hunk, discard, and *revert everything this prompt
did*.** These modify tracked files in the working tree. They are forbidden, plainly,
and no reading of rule 1 admits them.

The last of them is the one worth wanting. Because R4 knows which lines a given
prompt caused, *undo that prompt and keep the rest* is a coherent operation, and it
is the single most useful thing in this entire document when an agent goes down a
wrong path three prompts back. It is also the one that most clearly requires the
amendment.

**The amendment, if the owner wants it**, stated so it can be judged:

> Rule 1 gains: *a working-tree restore is permitted when it is (i) initiated by
> an explicit human gesture in the same window, (ii) performed by git, to a state
> git already holds, and (iii) recoverable — a ref under `refs/rubricator/` is
> written before the operation and the window names it. Rubricator still authors
> no content: it moves between states git already has.*

The distinction that makes it defensible is that rule 1's justification is about
**authored writes** — a reader that edits your files, a tool that writes another
tool's config. A git restore authors nothing. Clause (iii) is what makes it true
rather than merely arguable, and it costs one `git update-ref`.

The argument against is also real and should be recorded: rule 1's power comes from
being absolute, four separately attractive proposals died on it, and *"at any
confidence, behind any flag"* was written precisely to stop a reasonable-sounding
exception. An amendment weakens the rule for every future proposal, not just this one.

**My recommendation:** build B-ref under a clarifying clause; do not build B-tree
until the owner has decided the amendment on its own merits, on a day when he is not
also deciding whether to build the feature. Ship Tier A with **copy-the-command** for
every B-tree operation — which is an export, which rule 1 explicitly permits — and
find out over a month whether the copy step is actually annoying. If it is not, the
amendment was never needed.

---

## 7. Commit messages, and rule 7

A commit message drafted from the run bumps into rule 7 — *"Do not generate the
artefact."* The honest line: a message **assembled by quotation** from the prompts
the human typed, presented in an editable field and committed only on an explicit
click, is an export of his own words. A message the model *composes* is generation
and rule 7 forbids it. The field is pre-filled with quoted prompts and the file
list; it is never pre-filled with prose the human did not write.

---

## 8. The UX

The design problem is that the interesting moment (a run ending) is one the user is
not looking at, and the surface must be legible in the two seconds after it appears.

**Settle, don't stream.** The window opens already settled. Files are ordered by
churn, not by name, so the riskiest thing is first and the user's eye starts in the
right place without being told to.

**Recency as opacity, and it decays.** When the strip is live, a just-written hunk
carries a wash that fades over ~20 seconds. This is the honest form of *"highlight
what was added"*: everything cannot stay highlighted, or nothing is. Old changes stop
shouting on their own.

**Never steal scroll — the one detail that decides whether this is tolerable.**
Auto-follow only while pinned to the bottom. The moment the user scrolls up, the view
freezes and a pill reads *3 more edits below*. A surface that yanks the viewport while
someone is reading gets closed once and never reopened.

**Churn as a sparkline, not a number.** Per file, one tick per write across the run's
timeline. A file written 14 times in the last minute looks different at a glance from
one written 14 times spread evenly, and the first is the one that was going wrong.

**Provenance on hover, not on click.** Hovering a hunk dims the change set to just
the lines from the same prompt, and puts that prompt in the margin. Click pins it.
Making the tool's one distinctive computation cost a hover rather than a click is
what makes it feel like a property of the diff rather than a feature with a button.

**The tripwire is the only thing allowed to interrupt.** Globs you configure — a
migrations directory, `package.json`, anything under `.github/`. Amber on the strip,
and that is all: no modal, no focus steal. §12's measurement of blocking hooks — a
modal dozens of times a day, disabled within two days — is the standing evidence for
why this must never escalate further.

**Rule 8 everywhere.** *No changes yet* and *this run's transcript is gone* are
different empty states and must read differently, with counts.

**The Sessions surface grows; nothing is added beside it.** The navigator is a
finder, and a run is not a list of things to find. Sessions already lists every
session and the files it changed, so it gains the state rather than a neighbour: a
live dot, the file being written, the churn count, the collision marker. Opening a
session shows its runs, and a run's settled set opens in a tab, where panes, split
and history already work. There is no second place that lists sessions, and nothing
new has to be taught.

**Live first, then today, then the rest.** This project has 5 sessions on disk; one
on this machine has 254. Whatever is running now sorts to the top, then whatever
settled today, then a *show earlier* that opens the full history. Rule 8 applies to
both silences, which are different sentences: *nothing is running here*, and *no
transcript survives for this session*.

**Watching is a setting, and it is off.** Tailing transcripts and writing a git
object at every prompt, across as many as seven concurrent sessions, is not
something a markdown reader should start doing because you opened it. It switches
on once — the way indexing your history does — and until it does, Sessions looks
exactly as it looks today.

**Colour comes from the validated slots.** Lanes, marks and badges take the
categorical palette in `analytics-plan.md` §7 — rust, violet, teal, blue — because
the older accents do not survive a colourblind check: `#8a7f9e` and `#5f8f7a` sit
at ΔE 5.1 under deuteranopia and read as two greys. And in the `bone` theme
`--accent` and `--red` are the same hex, so hue alone cannot carry *problem* in the
light theme. A 3px lane always carries a word.

---

## 9. Launching a run from the window · **mostly already decided**

The owner asked for attach **and** launch. `continue-plan.md` measured this against
2.1.241 and landed read-only for J1–J4, and its reasoning is unaffected by anything
here: headless Claude does not ask for permission, it **refuses** — visibly, in
`result.permission_denials` — and `PermissionRequest`, the event that could speak for
it, *"fired zero times"* across five configurations while `PreToolUse` from the
identical config fired every time.

So a launch button on 2.1.241 gets a session that silently cannot use the tools that
make it worth launching. Rule 12 requires re-measuring that on 2.1.251 before either
building on it or citing it again — it is the exact case the rule names, since it is
documented, unfired, and belongs to the incumbent's design.

**Recommendation regardless of the re-measurement:** the valuable half is already
measured and it is not a client. `claude -p --resume <sid>` *"appends to the same
transcript, keeps the same session id"* — so the window does not need to run the
agent. It needs to **hand off**: a *Continue in terminal* action that puts
`claude --resume <sid>` on the clipboard, and an observe surface that picks the
session back up when it starts writing again. One session, one transcript, no
reconciliation, no local web page that can run arbitrary shell commands — which §2 of
`continue-plan.md` calls *"the exact thing the action bus and the opt-in gate were
built to prevent."*

---

## 10. Effort

Effort in the register's vocabulary: **S** an evening or less · **M** a day or two ·
**L** about a week.

| | | |
|---|---|---|
| R1 | baseline capture, the ref namespace, and its sweep | **M** — the sweep is the half that gets forgotten |
| R2 | settled change set over `git diff` | **S** |
| R3 | attribution: `isSidechain`, and line grain vs. file grain | **S** — smaller than it reads, because the human split is not available at any price |
| R4 | provenance, both directions | **M** — the differentiator, and the only M worth paying twice |
| R5 | churn + ordering | **S** |
| R6 | `SessionStart` summons, idempotent | **S** — the measurement it was gated on is in §2 |
| R7 | live lane over the existing SSE | **S** |
| R8 | collisions | **S** — a set intersection over what R5 already computes |
| B-ref | stage / commit / branch, allowlisted | **M** |
| B-tree | restores + safety refs | **M**, and blocked on §6 |

Tier A is **R1–R5**, plus R7 and R8 which ride on what R5 computes. R1+R2+R5 alone
— two evenings — is a usable surface: *what did this run actually change, riskiest
first.* Build that, use it for a week, and let it argue for R3 and R4 on evidence
rather than on this document. R8 is the cheapest thing here with the highest chance
of paying for itself, because the collision it names has already happened twice in
this repository.

The ordering that matters: **build it non-live first.** Everything that makes this
worth having works on a finished run, and every hard part — SSE, decay, follow
semantics, settle transitions — belongs to the half that §4 shows is worth the least.

---

## 11. What this will never be

- **Not a pull-request review product.** X8 stands, in full. No side-by-side, no
  forge integration, no review threads, no acceptance metrics.
- **Not an editor.** Read, attribute, and hand to git. Editing is the editor's job.
- **Not a merge tool.**
- **Not a daemon.** No background watch of repositories with no window open. §12's
  refusal of the all-day tool is upheld, and the summons in R6 is what replaces it.
- **Not a blocking gate.** The owner chose attach-and-launch over intervene, and §12's
  measured refusal of blocking hooks applies with more force to code than to markdown.
- **Not an audit product.** The owner chose *you, right now*. Provenance is built for
  review, not for auditors; no hash chain, no sign-off, no export. R4 happens to be the
  thing such a product would need, and noticing that later costs nothing extra now —
  which is the only reason it is mentioned.
- **Not a transcript archive.** X10 stands. `.rubricator/runs/` holds baselines and
  counters, not conversation text.

---

## 12. The two questions

1. **Does the X8 cede cover a single-user observe surface?** §3 argues it does not —
   X8 was killed on addressable market, and a tool with one user has none — but X8's
   wording is *permanently*, and only its author can say whether that was meant to
   cover the mechanism or the product.
2. **Does rule 1 get the working-tree clause in §6?** Recommended: not yet. Ship the
   copy-the-command export first and let a month of use say whether the amendment is
   needed.

Until both are answered, the buildable set is **R1–R5, R7 and R8** — read-only,
rule-clean, and about a week. Neither question blocks any of it.
