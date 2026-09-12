---
title: Reading your own history
subtitle: Phase A — the two corpora, the four metrics that discriminate, and the model pass that is a second consent
status: plan — 2026-08-30. §6 is a decision only the owner can take; the `/insights` citation in §11 is unverified and load-bearing
---

# Reading your own history

> Point rubricator at the record it already indexes — every prompt ever typed and
> every transcript still on disk — and answer the question the session surface
> cannot: **what does this corpus say about how the work actually goes.**

Four research streams looked at what analytics this project could honestly offer —
product framing, the metric catalogue, the model layer, and the visual design. They
came back disagreeing, and the disagreement is the finding. The corpus looks like
one thing and behaves like two, and the feature has to be built along that seam.

Every figure below is measured directly against `~/.claude` on 2026-08-30, against
`claude` **2.1.251**. The commands behind them belong in `measurements.md` before
anything here is built.

---

## 1. The seam

`history.jsonl` keeps every prompt forever. `~/.claude/projects/` keeps transcripts
for thirty days and then a sweep takes them. So one half of the record is
**complete but thin** — text only, no structure — and the other is **structurally
rich but covers a sixth of the work**.

| | prompts | transcripts |
|---|---|---|
| coverage | **466 of 466 sessions**, 135 days | **74 of 466** — 392 already swept |
| size | 4,423 prompts ≈ **218K tokens** | 85 files, **1.2 GB** |
| content | text only, no structure | `gitOperation`, `turn_duration`, per-message `usage`, compaction |

That asymmetry assigns the work, and the assignment is the architecture:

**The deterministic charts belong to the transcripts.** They carry exact structure,
and nothing computed from them is ever a trend — it is a rate inside the retention
window, and must be labelled as one.

**The model belongs to the prompts.** They are the only complete record, and at
218K tokens the whole corpus fits in a single request with room to spare.

That last number kills a lot of architecture. There is no map-reduce, no
per-session summarisation, no chunking — and crucially nothing that destroys
*sequence*, which is where the non-obvious findings live. *You asked the same thing
three ways in eleven minutes* is invisible in a summary and obvious in the raw
stream.

---

## 2. Measured on this machine, not assumed

| | measured |
|---|---|
| prompt records | **4,974** raw → **4,423** after slash-noise filtering |
| prompt corpus | **≈ 218,000 tokens**, at a measured 2.98 chars/token on English technical prose |
| sessions | **466**, across **135 days** |
| transcripts on disk | **85 files, 1.2 GB** — covering **74** of those sessions |
| token inflation if records are not deduped on `message.id` | **2.02×** |
| files in the session→file edge | **1,885**, excluding scratchpads and worktrees |
| tool calls, deduped | Bash **18,119** · Edit **7,995** · Read **3,602** · Write **1,532** · Grep **4** · Glob **3** |
| write-shaped Bash command lines | **4,753** — heredoc, `sed -i`, `tee`, redirect |
| input tokens served from cache | **98.4%** |
| harness-measured turn durations | **n = 1,289**, median **203 s**, max **1,534 minutes** |
| tool error rate | **1.96%**, and **no run of consecutive errors exceeds three** |
| `userModified` | **`false` on all 9,429 records** |
| `cost-state` | present in **4 of 85** sessions |

Two honesties about the table. The 4,974 → 4,423 filter is a judgement about what
counts as a prompt, not a fact — `/model`, `/compact` and their kin are dropped, and
the rule that drops them is part of the feature and belongs beside the number. And
the max turn duration is 1,534 minutes because a turn spans lunch: the figure is
real and the median is the only honest summary of it.

---

## 3. What actually discriminates

A metric earns its place by naming a few things out of many, not by ranking
everything. The rework metric is the clearest case. Join files to the sessions that
edited them and the distribution is violently skewed:

| sessions that touched the file | 1 | 2 | 3 | 4 | 5 | 6+ |
|---|---|---|---|---|---|---|
| files | **1,508** | 208 | 86 | 41 | 22 | 20 |

**80.0% of files are touched exactly once.** The metric does not produce a
leaderboard; it produces a shortlist of **42**, which is short enough to read.

Four metrics clear that bar, and each needs a join rather than a count:

| Metric | The question it answers | Verified |
|---|---|---|
| **Rework loops** | Which files do you keep returning to — and is that iteration or thrash? Separated by joining to commit count and calendar span. | 42 files |
| **Cache structure** | Where do the tokens actually go? Nearly all input is cache read, and the main thread runs a 1-hour cache while subagents run 5-minute. | 98.4% |
| **Turn latency** | How long does one instruction take to come back? Harness-measured, not inferred from timestamp gaps. | n = 1,289 |
| **Subagent leverage** | Did delegation relieve the parent context, or just add runs? The ratio is the metric; the run count is vanity. | 21 of 85 |

Turn latency needs one guard: winsorize at two hours and say so on the chart, or
the number is a lie. Rework needs the other: it is computed over the session→file
edge, which understates until §5 is fixed.

---

## 4. Where the research collided

Three genuine conflicts. Each resolves against evidence rather than preference, and
each is recorded here so it is not re-argued by a future self who has forgotten the
measurement.

**The time-of-day heatmap · cut.** The visual stream proposed an hour × weekday heat
grid as the flagship chart — 168 cells fold a sparse corpus into something dense and
readable. `workspace-plan.md` §5.10 bans it by name: *"Rhythm and usage dashboards —
sessions per week, time of day, streaks. Measures something real, tells you nothing
you would act on."* The metric stream independently downgraded rhythm and refused to
ship *you make more mistakes at 9 a.m.* — the 0.63% → 3.00% error spread across hours
is well within reach of project mix. Two streams and the written rule land the same
way.

**Reporting money · split.** The metric stream produced a headline of **$13,878**
across the retained window, priced from published rates with cache multipliers
applied. Rule 9 forbids a hand-maintained inventory in shipped code, and a price
table is the worst kind: it drifts silently and then lies about money — which on a
subscription was never a bill in the first place. **Ship tokens, never currency.**
The genuinely interesting finding needs no price table at all: 98.4% of all input is
cache read, and the main thread and its subagents sit on different cache tiers. That
is a structural fact about how the work runs, and it survives every price change.

**Whether to call a model at all · both, sequenced.** The usability stream says ship
with no model call: every surviving job is arithmetic over local files, and a network
call re-runs the trade that killed agent-proposed marks. The model stream verified a
hermetic recipe and designed the grounding that makes fabrication mechanically
detectable. Both are right in order. **The deterministic half ships first and must
stand alone** — if it needs the narrative to be worth opening, it is not finished.
The model half is a second, separately consented step, and the README sentence
*"Nothing leaves the machine"* gets rewritten in the same commit that makes it false,
not later.

---

## 5. The blind spot, which is not a feature

rubricator builds its session→file edge by grepping transcripts for `"file_path"`.
That worked when file work went through the file tools. It no longer does: Bash
carries **18,119** calls against Edit's 7,995, while Grep and Glob are effectively
absent at 4 and 3. Every heredoc, `sed -i` and `>` redirect — **4,753** command lines
— is invisible to a `"file_path"` regex.

So *sessions that touched this document* already understates, and does so more every
month. Parsing write-shaped Bash is a fix to something shipping, not a new feature,
and it is a precondition for the rework metric being true rather than merely
plausible. **Nothing else goes first.**

Three smaller hazards turned up in the same sweep, all confirmed in source:

- `prune_cache()` globs only `index/sessions*.json`, so a new `analysis/` cache
  directory would never expire — reintroducing exactly the bug its own comment says
  was just fixed.
- `session_stamp()` carries no scrubber version, so tightening a `SECRET` rule keeps
  serving the old under-scrubbed text.
- `workspace.js:1396` reads `stale:'Stale'` while `:589` calls the same thing *behind
  its code* — two names for one idea.

---

## 6. Keeping the model honest · **DECISION**

A model handed personal data produces flattery unless the structure forbids it — not
because it is sycophantic, but because unfalsifiable praise is the lowest-risk output
when ground truth is unknowable and the reader is the subject. Instructions alone do
not fix it: *be specific and honest* yields specifically-worded flattery. Four of the
five defences are structural rather than written.

| Mechanism | What it makes impossible |
|---|---|
| **Alias table** | Real paths and session ids never leave the machine; the model can only cite from a closed vocabulary. A hallucinated `s9999` fails set membership — a hallucinated UUID would have been indistinguishable from a real one. |
| **Curated, not generated numbers** | The model picks *which* precomputed fact to chart and captions it. The renderer draws Python's array. Bar heights cannot be invented. |
| **Required denominator** | *You iterate a lot* cannot be expressed in a `{numerator, denominator, unit}` field. *312 of 4,421 prompts* can. |
| **Required falsifier** | Every finding states what would have to be true for it to be wrong. A horoscope has no answer, and the model discovers that while writing it. |
| **A place to say nothing** | Without a first-class `insufficient_evidence` slot, a model says something instead. |

The invocation is hermetic and verified end to end. `--setting-sources ""` is not
optional: a `CLAUDE.md` in the analysed repo demonstrably hijacked a test run without
it. `--tools ""` drops overhead from 12,946 to about 270 tokens and removes the tool
surface entirely. `--no-session-persistence` writes nothing — the tool that reads your
history must not add to it.

One caveat carries forward under rule 12: `--system-prompt-file` works but is **not in
`--help`**. Nothing ships on an undocumented flag without a fallback.

**The decision.** This step is the one that makes the README sentence false. It is a
third setting, defaulting off, offered from the panel that needs it, with a preview
showing the literal payload — because a consent screen that *describes* the payload is
a promise, while one that *shows* it is a fact. Whether to take that step at all is
the owner's, and it should be decided on a day when he is not also deciding whether to
build steps 1–4.

---

## 7. The visual system

The five existing accent tokens **fail as a categorical palette**: `#8a7f9e` and
`#5f8f7a` sit at ΔE 5.1 under deuteranopia and read as two greys. The fix is to step
the slots out of the same hue families so they stay recognisably rubricator's, then
verify with the validator rather than by eye. These pass all six checks in both modes:

| slot | `rubric` (dark) | `bone` (light) |
|---|---|---|
| 1 · rust | `#cf4b26` | `#a8341c` |
| 2 · violet | `#8b67c3` | `#714ca6` |
| 3 · teal | `#249c74` | `#17895b` |
| 4 · blue | `#2b8cd5` | `#2c7ab6` |
| other | `#75706a` | `#877f72` |

One constraint has real teeth and is easy to miss: in `bone`, `--accent` and `--red`
are **the same hex**, both `#a8341c`. Hue therefore cannot carry *problem* in the light
theme. The rule that resolves it: **the attention accent is never an area fill.** It is
a threshold rule, a marker ring, or text — always paired with an icon and a word.

**No charting library.** Hand-rolled inline SVG, roughly 250 lines. The static tier
inlines every vendored library into every emitted page, so a chart lib is an
unconditional payload where mermaid is at least gated behind a content sniff. More
decisively, canvas throws away what the app already gives free: `workspace.js` delegates
clicks on `[data-ses]` and `[data-doc]` globally, with ⌘-click to split, so DOM marks
inherit navigation, focus, print and forced-colors for nothing. Canvas inherits none of
it and cannot read CSS custom properties, which would reintroduce the mermaid theme-latch
bug.

The technique that makes it cheap: **percentage on x, pixels on y, no `viewBox`.** Fully
fluid, no measurement pass, no resize observer, and text never scales.

---

## 8. Where this meets `observe-plan.md`

The two plans read the same edge and must not build it twice.

**Churn and rework are one computation at two grains.** Observe's flagship is churn —
a file rewritten many times inside one run. This plan's flagship is rework — a file
touched by many sessions over months. Both are the session→file write edge; only the
window differs. §5 is the shared precondition for both.

**Two of observe's attribution mechanisms are falsified by §2.** `userModified` is
`false` on all 9,429 records, so a human-vs-agent split keyed on it cannot work. And
write-shaped Bash carries no `structuredPatch`, so line-level provenance exists only
for Edit and Write; for Bash-written files it degrades honestly to file level — *this
turn's command wrote this file*. Observe's settled change set is untouched by both,
because `git diff` does not care how a file was written, which is why *git is the diff
engine* was the right call.

**Analytics is not a navigator mode.** The navigator is a finder, and analytics is not
a list of things. One entry in `TITLES`, reachable from ⌘K, inheriting panes, tabs,
split and history. The session surface already carries the changed-file list, so observe
extends that surface rather than adding a fifth mode beside it.

**The palette in §7 is the shared one.** Any lane, mark or ramp in either surface comes
from those slots, and 3px lanes carry a word.

---

## 9. What to build, in order

Effort in the register's vocabulary: **S** an evening or less · **M** a day or two ·
**L** about a week. Each step is useful on its own, and none depends on the next being
built.

| | | |
|---|---|---|
| **1 · Parse write-shaped Bash** | Fixes a shipping surface that silently understates, and makes every file-level metric true instead of plausible. *Done when:* a session that wrote a file only by heredoc appears under that file. | **M** |
| **2 · Extend `prune_cache`, version the scrub in `session_stamp`** | Both must land before anything writes a new cache directory or sends scrubbed text anywhere. *Done when:* an `analysis/` directory expires on the same clock as the session index, and a tightened `SECRET` rule invalidates the old stamp. | **S** |
| **3 · One deterministic surface, reachable from ⌘K** | The four metrics of §3, drawn per §7, with every denominator stated and the retention window labelled on anything transcript-derived. *Done when:* it is worth opening with the model pass switched off. | **M** |
| **4 · The expiry panel, with its denominator stated** | The only recurring event in this data that has a date someone else set: 392 of 466 sessions are already gone, and the ones that remain have a deadline and one of three actions. *Done when:* rule 8's two empties — *nothing is expiring* vs. *no transcript survives to check* — read differently. | **S** |
| **5 · The model pass, separately consented** | §6, and only after §6's decision. | **M** |

Steps 1 and 2 are also `observe-plan.md`'s preconditions, which is the argument for
doing them first regardless of whether the rest of this is built.

---

## 10. What this will never be

- **Prompt, session and message counts.** 4,974 prompts says nothing about work done,
  and any per-period version is an artifact of retention rather than behaviour.
- **Lines added and removed.** Computable exactly from `structuredPatch` — and it
  rewards thrash. Two of the top three rework files are the ones with the most churn.
- **"Off the rails" error chains.** Empirically dead: the tool error rate is 1.96% and
  no run of consecutive errors exceeds three. Falsified, not merely weak.
- **Cross-project topic clustering from prompt text.** Bag-of-words over the corpus
  returns *lets*, *currently*, *text*, *like*; German–English code-switching defeats it.
  Skill attribution answers the same question from structure.
- **Session-level abandoned work.** Measured at 0 of 48. A metric whose value is always
  zero is not a metric — the file-level version survives.
- **Anything keyed on `cost-state` or `userModified`.** Present in 4 of 85 sessions, and
  `false` on all 9,429 records, respectively.
- **Currency.** §4. Tokens, always; money, never.
- **A transcript archive.** X10 stands. Whatever this writes under `.rubricator/` holds
  counters and aliases, not conversation text.

---

## 11. The one claim that could not be verified

The argument for ceding the thirty-day window rests on Claude Code shipping an
`/insights` command over this same corpus. `citations.md` flags that card as
secondary-sourced with no primary page found, and there is no `~/.claude/usage-data/`
on this machine. It is load-bearing — it is the difference between this surface
competing with a first-party incumbent and having the corpus to itself — so it gets
checked before it drives a decision, not after.
