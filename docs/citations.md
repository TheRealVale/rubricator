---
title: Cleared wording for every external claim
subtitle: The research and documentation cards the plans quote from, with the qualifier each one travels with
status: reference — 2026-08-23
---

# Cleared wording for every external claim

Verified 2026-08-23 against primary sources, each fetched and read. The
verification log is an investigation working file and is not part of this
repository; the record for each claim is the source named on its own card. Local
measurements are in `measurements.md`.

Two kinds of card are here. **Sections A–F** are what the investigation
gathered — papers, surveys, vendor telemetry and two ecosystem facts — each
carrying the correction the verification produced. **Section G** is
documentation: sentences another product publishes about its own behaviour,
quoted because the plans quote them, each with its URL and the date it was
fetched. `F1` is documentation too and keeps its id, because four documents in
this set cite it by number.

This page holds the cards the plans cite and nothing else. Twenty-four research
cards were dropped on 2026-08-23. They were gathered for claims about code
quality and maintainability, and standing rule 10 forecloses that subject —
rubricator may claim it increases review coverage and reduces time-to-first-mark;
it may not claim it improves code quality. A dropped card is not a struck claim.
It is a claim this project has no occasion to make; the struck ones are below.

**Rule of use.** If a claim is not on this page, it may not be cited. If it is on
this page, cite it **in the wording given**, with the source given. The wording is
not a suggestion — the corrections are the whole point of this file. Where a card
carries a "must accompany" line, that qualifier travels with the number; dropping
it turns a safe claim into an unsafe one. A section G card is another vendor's
page as it read on the date given, so standing rule 12 applies to every one of
them: documented is not the same as observed on the build in hand.

**Ten claims from the panel are struck and appear at the bottom under
[Do not cite](#do-not-cite). Read that section before writing anything.**

---

## A · Verification is where the time goes

### A1 — Verifying is the largest single activity in an AI-assisted coding session
> In a CHI 2024 study of 21 programmers using GitHub Copilot, "verifying
> suggestion" was the single largest activity at **22.4% of session time**, ahead
> of "writing new functionality" at **14.05%**; all Copilot-related states together
> accounted for **51.5%** of average session duration.

Source: Mozannar, Bansal, Fourney & Horvitz, *Reading Between the Lines: Modeling
User Behavior and Costs in AI-Assisted Programming*, CHI 2024, arXiv:2210.14306, §6.

**Must accompany:** 21 participants inside one large technology company, on
eight assigned lab tasks of at most 20 minutes (mean 12.2 min), 19 of 21 in Python,
labels applied by participants retrospectively. This is autocomplete-era Copilot,
not agents.

### A2 — Measuring verification naively under-counts it about fivefold
> Mozannar et al. found that when programmers accept a suggestion without reading
> it first, they verify it immediately afterwards **53.2%** of the time. Counting
> that post-acceptance reading raises measured verification time from a mean of
> **3.25 s to 15.21 s** — "nearly a five-times increase". The authors' point is
> that simple metrics attribute far too little time to verification.

Source: as A1, §6.4 ("CUPS Attributes Significantly More Time Verifying Suggestions
than Simpler Metrics") and Figure 8.

**Must accompany:** the 15.21 s figure **includes** the 3.25 s — it is the same
quantity measured two ways, not "3.25 s before accepting versus 15.21 s after".
It is scoped to the "deferring thought" path, which the paper observed 61 times.
Never write "verification happens after acceptance, 15.21 s post vs 3.25 s pre".

---

## B · Review is the bottleneck — but say who measured it

> **Standing rule for this section.** Faros AI and LinearB are **engineering-
> analytics vendors reporting telemetry from their own platforms**. They are not
> studies and were not peer reviewed. Every citation must name them as vendor
> telemetry in the same sentence as the number. They also measure **different
> contrasts** and must never be added together or averaged.

### B1 — Faros AI: review time under high AI adoption
> Faros AI, an engineering-analytics vendor, reports from two years of telemetry
> covering 22,000 developers and more than 4,000 teams that, comparing each
> organisation's lowest- and highest-AI-adoption periods, "Median time to first PR
> review is up **156.6%**. Average time spent in code review is up **199.6%**.
> Median time in review is up **441.5%**", and "Pull requests merged without any
> review, human or agentic, are up **31.3%**."

Source: Faros AI, *Ten takeaways from the AI Engineering Report 2026: The
Acceleration Whiplash*, faros.ai/blog/ai-acceleration-whiplash-takeaways,
**12 April 2026**.

**Must accompany:** vendor telemetry, not research; the design is a within-
organisation comparison of lowest- versus highest-adoption periods, so it is
observational and confounded with everything else that changed in those companies.
If you want a plain-English multiplier, +156.6% is **×2.6** and +199.6% is
**×3.0** — "roughly doubled" is wrong for the +199.6% figure.

### B2 — LinearB: reviewers avoid AI pull requests, then move through them fast
> LinearB, an engineering-analytics vendor, reports from 8.1+ million pull requests
> across 4,800 teams in 42 countries that "AI PRs wait **4.6x** longer before review
> – but are reviewed **2x** faster once" picked up, that "Agentic AI PRs have a PR
> Pickup Time **5.3x** longer than Unassisted ones", and that acceptance rates for
> AI-generated PRs are **32.7%** against **84.4%** for manual ones.

Source: LinearB, *2026 Software Engineering Benchmarks*,
linearb.io/resources/software-engineering-benchmarks.

**Must accompany:** vendor telemetry, not research. LinearB publishes **no
definition** of how an "AI PR" or an "agentic AI PR" is detected, no definition of
"acceptance rate", and **no data period**. Present the 4.6x as a vendor
observation, never as a measurement anyone can check.

---

## C · What agents actually get wrong

### C1 — The shape of agent failure, correctly quantified
> The largest observational study of real coding-agent sessions — 20,574 sessions
> across 1,639 repositories — identified 16,118 evidence-grounded misalignment
> episodes. **Among those episodes**, the most common form was **Developer
> Constraint Violation (38.33%)**, followed by Misread Developer Intent (26.95%),
> **Inaccurate Self-Reporting (22.58%)** — the agent misreporting the status of its
> own work — and Faulty Implementation (17.82%). Symptom labels are multi-label,
> so the shares do not sum to 100%.

Source: Tang, Chen, Xu, Shi, Huang, McMillan, Dong & Li, *How Coding Agents Fail
Their Users*, arXiv:2605.29442, Table 2.

**Must accompany:** the denominator is **misalignment episodes**, not sessions,
turns or agent actions. "Agents violate constraints 38.33% of the time" is a
misreading and must never be written. Misalignment is defined as a breakdown made
visible by developer pushback, so silent failures are out of scope by construction.
Corpus is opt-in public agent logs (SpecStory exports + SWE-chat/Entire.io);
extraction and annotation were performed by GPT-5.4 with human validation
(precision 0.93; LLM-judge accuracy 0.81 against an adjudicated gold standard).

### C3 — Where a resolution is visible, it almost always took a human
> In the same corpus, only **9.33%** of episodes show a resolution within the
> visible conversation, and of those, **91.49% required explicit developer
> pushback**.

Source: as C1, §4.3.
**Must accompany:** the authors state that these "reflect observable within-session
outcomes **rather than true resolution rates**". Do not convert this into a claim
about how often agents self-correct.

---

## D · Trust, and the state of the evidence on productivity and quality

### D1 — Trust is low and falling, at near-universal adoption
> In Stack Overflow's 2025 Developer Survey (over 49,000 respondents in 177
> countries; **33,244** answered the trust question), "More developers actively
> distrust the accuracy of AI tools (**46%**) than trust it (**33%**), and only a
> fraction (**3%**) report 'highly trusting' the output." The biggest single
> frustration, cited by **66%** of developers, is "AI solutions that are almost
> right, but not quite"; the second is "Debugging AI-generated code is more
> time-consuming" (**45.2%**). Asked when they would still want a person's help in a
> future where AI can do most coding tasks, the top answer — **75.3%** — is "When I
> don't trust AI's answers".

Source: survey.stackoverflow.co/2025/ai; press release
stackoverflow.co/company/press/archive/stack-overflow-2025-developer-survey/
("46% … a significant increase from 31% last year").
**Must accompany:** quote the per-question n (25k–33k), not the 49,000 total, next
to a percentage. Do not write "29% trust" — that figure is on neither source.

### D5 — METR's authors now regard the 19% as dated, and have redesigned the study
> In February 2026 METR published *We are Changing our Developer Productivity
> Experiment Design*, reporting that their follow-up experiment (57 developers,
> 143 repos, 800+ tasks, August 2025 onward) "gives us an unreliable signal",
> because "we have observed a significant increase in developers choosing not to
> participate in the study because they do not wish to work without AI", and
> because "30% to 50% of developers told us that they were choosing not to submit
> some tasks because they did not want to do them without AI". Their raw follow-up
> estimates point toward speedup — −18% [−38%, +9%] among returning developers and
> −4% [−15%, +9%] among new recruits — but they call this "only very weak evidence",
> and conclude: "we believe it is likely that developers are more sped up from AI
> tools now — in early 2026 — compared to our estimates from early 2025."

Source: metr.org/blog/2026-02-24-uplift-update/.
**Must accompany:** METR did **not** retract the 2025 result; the design critique is
of their **second** experiment, and pay dropped from $150/h to $50/h between the two,
which METR names as a likely contributor to the selection effects. Never write
"METR retired its 19% headline".

### D6 — The maintainability question is unsettled, and the strongest design is null
> The strongest published design on whether AI-co-developed code is harder for
> other people to evolve is a preregistered two-phase experiment with **151
> participants** (95% professional developers), whose Phase 2 was a randomized
> controlled trial with **N = 75** in which new participants evolved Phase 1
> solutions without AI. It "revealed no significant differences in subsequent
> evolution with respect to completion time or code quality", and the authors
> conclude they "did not detect systematic maintainability advantages or
> disadvantages" — but they state plainly that the result should be read as
> "evidence against **large** effects, rather than as evidence for the absence of
> any effect", because N=75 gives 80% power only for large standardized mean
> differences.

Source: Borg, Hewett, Hagatulah, Couderc, Söderberg, Graham, Kini & Farley, *Echoes
of AI: Investigating the Downstream Effects of AI Assistants on Software
Maintainability*, arXiv:2507.00788v3, preregistered at ICSME 2025.
**Must accompany:** the experiment ran in **late 2024** and, in the authors' words,
its "empirical results predate this trend" of coding agents; the tasks were feature
additions to a Java web application. Use "does not support" or "fails to detect",
never "contradicts" or "refutes".

---

## F · Local corpus and ecosystem facts

### F1 — Claude Code deletes local transcripts after 30 days by default
> Anthropic's documentation states: "Claude Code clients store session transcripts
> locally in plaintext under `~/.claude/projects/` for **30 days by default** to
> enable session resumption. Adjust the period with `cleanupPeriodDays`."

Source: code.claude.com/docs/en/data-usage, verbatim.

### F2 — The first-party tool now reads the same local corpus
> Claude Code's `/insights` command, announced in February 2026, analyses local
> session history from `~/.claude/` (about 30 days, up to 50 sessions) and writes an
> HTML report to `~/.claude/usage-data/report.html` without sending data off the
> machine.

Source: multiple independent write-ups (no primary Anthropic announcement page
located).
**Must accompany:** secondary-sourced — label it as reported behaviour, not as
documented behaviour.

---

## G · Documentation, quoted from the page

> **Standing rule for this section.** Every card below is another product's
> documentation about its own behaviour, read on the date given and not re-run.
> A page can change and a documented feature can fail to fire: standing rule 12
> applies to all of them.

### G1 — ExitPlanMode hands the hook the plan itself
> "Claude writes the plan to a file on disk before calling the tool, so the
> literal `tool_input` from the model is typically empty. Claude Code injects the
> plan content and file path before passing the input to hooks." The ExitPlanMode
> `tool_input` table lists `plan` (string), "Plan content in Markdown. Injected
> from the plan file on disk", and `planFilePath` (string), "Path to the plan
> file. Injected". The same page, on the other event: "In `PostToolUse`,
> `tool_response` is an object with `plan` and `filePath` fields holding the
> approved plan, plus internal status flags. Read `tool_response.plan` for the
> plan content rather than re-reading the file from disk."

Source: code.claude.com/docs/en/hooks, fetched 2026-08-23, verbatim.
**Must accompany:** the PostToolUse sentence is about a different event than a
PreToolUse matcher on ExitPlanMode. It is the same instruction pointed at the
same mistake, not a description of the hook this project registers.

### G2 — `defer` is honoured only under `-p`
> Of `permissionDecision: "defer"`, the page says it "is for integrations that run
> `claude -p` as a subprocess and read its JSON output, such as an Agent SDK app
> or a custom UI built on top of Claude Code. It lets that calling process pause
> Claude at a tool call, collect input through its own interface, and resume where
> it left off. Claude Code honors this value only in non-interactive mode with the
> `-p` flag. In interactive sessions it logs a warning and ignores the hook
> result."

Source: code.claude.com/docs/en/hooks, fetched 2026-08-23, verbatim.
**Must accompany:** an interactive hook that returns `defer` gets the warning and
loses everything else it returned, so a defer path there discards the deny-or-ask
fallback silently.

### G3 — A plugin's `bin/` is the Bash tool's PATH, not the user's
> A Claude Code plugin's `bin/` directory holds "Executables added to the Bash
> tool's `PATH`. Files here are invokable as bare commands in any Bash tool call
> while the plugin is enabled".

Source: code.claude.com/docs/en/plugins-reference, fetched 2026-08-23, verbatim.
**Must accompany:** that is the agent's PATH. A human who wants to type the
command in their own shell still installs it themselves.

### G4 — `history.jsonl` is kept until the user deletes it
> Under the heading "Kept until you delete them": "The retention cleanup sweep
> doesn't cover the following paths. Claude Code keeps them until you delete them,
> apart from the two caches whose rows say that logging out deletes them." The
> table's first row is `history.jsonl`, "Every prompt you've typed, with timestamp
> and project path. Used for up-arrow recall."

Source: code.claude.com/docs/en/claude-directory, fetched 2026-08-23, verbatim.
**Must accompany:** this is documented vendor behaviour, not an undocumented
accident — which makes it cheaper to build on and equally liable to change.

### G5 — Plaintext storage, and the mitigation the page lists first
> "Transcripts and history are not encrypted at rest. OS file permissions are the
> only protection. If a tool reads a `.env` file or a command prints a credential,
> that value is written to `projects/<project>/<session>.jsonl`." The first entry
> in the list that follows, headed "To reduce exposure", is "Lower
> `cleanupPeriodDays` to shorten how long transcripts are kept".

Source: code.claude.com/docs/en/claude-directory, §"Plaintext storage", fetched
2026-08-23, verbatim.
**Must accompany:** raising the retention period trades against the vendor's own
stated privacy control, and copying transcripts into an unswept directory defeats
it outright.

### G6 — What `claude project purge` deletes
> "Run `claude project purge` to delete the state Claude Code holds for one
> project. It deletes:" and then four bullets — "Transcripts and auto memory under
> `projects/`", "Per-session `tasks/`, `debug/`, and `file-history/` entries",
> "Matching prompt lines in `history.jsonl`", "The project's entry in
> `~/.claude.json`". The page adds: "The command prints the full deletion plan and
> asks for confirmation before removing anything."

Source: code.claude.com/docs/en/claude-directory, §"Clear local data", fetched
2026-08-23. The four items are a bullet list on the page; they are quoted here as
four separate strings and must not be run together inside one pair of quotation
marks.
**Must accompany:** that list is the whole scope of the command. Anything a
third-party tool has copied elsewhere survives it.

### G7 — Ctrl+G opens the plan in the user's editor
> "Press `Ctrl+G` to open the proposed plan in your default text editor and edit
> it directly before Claude proceeds. When `showClearContextOnPlanAccept` is
> enabled, the list gains a first option that approves the plan and clears the
> planning context."

Source: code.claude.com/docs/en/permission-modes, fetched 2026-08-23, verbatim.
**Must accompany:** it is an edit affordance — no quoting, no line anchoring, no
structured feedback channel — and it belongs in a list of native alternatives,
not in a list of competing products.

### G8 — The VS Code extension opens the plan for inline comments
> "**Plan**: Claude describes what it will do and waits for approval before making
> changes. VS Code automatically opens the plan as a full Markdown document where
> you can add inline comments to give feedback before Claude begins."

Source: code.claude.com/docs/en/vs-code, bullet under "Permission modes", fetched
2026-08-23, verbatim.

### G9 — A Copilot Space is human-selected and machine-refreshed
> A Space holds "repositories, code, pull requests, issues, free-text content like
> transcripts or notes, images, and file uploads", and "GitHub files and other
> GitHub-based sources added to a space are automatically updated as they change."

Source: docs.github.com/en/copilot/concepts/spaces, fetched 2026-08-23, verbatim.
**Must accompany:** what a human curates is the selection; the GitHub-sourced
contents then refresh themselves. Write "human-selected, machine-refreshed", not
"human-curated".

### G10 — Logseq's file-based product is maintenance-only
> The split announcement names the two products **Logseq OG** (file-based) and
> **Logseq** (database), and says "We'll continue maintaining Logseq OG with:
> Security fixes and patches" and "Electron and dependency upgrades", and "Our
> focus will be on maintenance and reliability rather than new feature
> development."

Source: logseq.io/p/e3YDyX5AYr, linked from the Logseq 2.0 beta release of
2026-07-13; fetched 2026-08-23, verbatim.

### G11 — plannotator's Version Browser saves every submission
> "Plannotator saves each plan submission before opening the review." — "When the
> agent resubmits the same plan, a change badge shows added and removed lines."

Source: docs.plannotator.ai/open-source/workflows/plan-review, fetched
2026-08-23, verbatim.

### G12 — plannotator registers a different hook event
> plannotator's Claude Code integration registers a `PermissionRequest` hook with
> `"matcher": "ExitPlanMode"`.

Source: docs.plannotator.ai/open-source/agents/claude-code, fetched 2026-08-23.
**Must accompany:** rubricator registers `PreToolUse` on the same tool. Different
event, same matcher — do not write that the two implement the identical loop.

### G13 — Moat's own description of itself
> "The review layer for agent-written docs."

Source: moat.so, fetched 2026-08-23, verbatim.
**Must accompany:** hosted and account-based. The sentence is one noun away from
this project's own candidate positioning, so the distinguishing word has to be
the one about rewriting, not the one about review layers.

### G14 — the projects the README names, and their scale
Every figure from that project's own GitHub API, fetched **2026-08-27**. The
README names these projects and describes what distinguishes each; it carries no
figures, because a star count in a front page rots without anyone noticing. This
is where they live.

| project | stars | created | licence |
|---|---:|---|---|
| [plannotator](https://github.com/backnotprop/plannotator) | 8,145 | 2025-12-28 | Apache-2.0 |
| [PlanBridge](https://github.com/contextbridge/planbridge) | 27 | 2026-04-29 | MIT |
| [Imark](https://github.com/migsilva89/imark) | 49 | 2026-08-05 | MIT |
| [md-annotator](https://github.com/konradmichalik/md-annotator) | 5 | 2026-01-28 | MIT |
| [recensa](https://github.com/S40911120/recensa) | 70 | 2026-07-12 | MIT |
| [universal-session-viewer](https://github.com/tad-hq/universal-session-viewer) | 18 | 2025-12-23 | AGPL-3.0 |
| [cc_transcript_viewer](https://github.com/tim-hua-01/cc_transcript_viewer) | 12 | 2026-06-01 | MIT |
| [kortex](https://github.com/chicongst/kortex) | 7 | 2026-07-07 | none |

**Moat** is hosted and has no repository to count.

**Must accompany:** plannotator was created seven months before this repository
and is two orders of magnitude larger by stars. Any sentence comparing the two
has to survive that being true.

---

## Do not cite

Four numbered entries below, carrying five claims between them, and five more struck
at the foot: ten in all. They are listed so nobody quietly reinstates them. The
register's **X31** covers thirteen — these ten plus three competitor claims, which
are corrected in `scope-plan.md` §10 rather than here.

1. **"Verification happens after acceptance: 15.21 s post vs 3.25 s pre."**
   A misreading of Mozannar §6.4 — 15.21 s and 3.25 s are the same quantity measured
   with and without post-hoc verification, and 15.21 includes 3.25. Use **A2**.

2. **"METR is retiring its own 19% headline."** METR retracted nothing. Use **D5**.

3. **"The 'AI is rotting codebases' narrative is contradicted by the one
   preregistered RCT, 151 participants, null result."** The RCT arm is **N = 75**,
   the authors explicitly call it "evidence against large effects, rather than as
   evidence for the absence of any effect", and the study predates coding agents.
   Use **D6**, with "does not support", never "contradicts".

4. **"Review load roughly doubled"** (from Faros' +199.6%), and **"agents
   self-correct 2.99% of the time"** (from Tang). +199.6% is a tripling; the 2.99%
   is a share of the 9.33% of episodes with a *visible* resolution, on a measure its
   own authors say is not a resolution rate. Use **B1** and **C3**.

Also struck, already dropped by the panel and confirmed struck here: the Codacy
"200 → 1,050 minutes" pickup figures, the "CodeRabbit 2025 longitudinal analysis",
the BCG "AI brain fry" 14% figure, the AGENTS.md "35–55% fewer bugs" claim, and
DeepWiki's "50k+ repos".
