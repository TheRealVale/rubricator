# rubricator

[![ci](https://github.com/TheRealVale/rubricator/actions/workflows/ci.yml/badge.svg)](https://github.com/TheRealVale/rubricator/actions/workflows/ci.yml)
[![licence: MIT](https://img.shields.io/badge/licence-MIT-blue.svg)](LICENSE)

**Mark up a document an agent is going to rewrite, and still have your marks afterwards.**
Read it, mark the parts that matter, send the marks to your agent. When it rewrites the
file, your notes follow their text to the new lines — and the ones whose text is gone say
so.

*A rubricator was the scribe who went through a finished manuscript adding the red marks —
the headings, the corrections, the notes in the margin. Same job, different century.*

![The review tray on a plan an agent has rewritten: an Expand and a Change still on their text, a Question tagged "moved" showing both what was marked and what the document says there now, and an Approve tagged "text gone" and greyed out. The tray header reads "3 · 1 moved · 1 gone" above the line "1 of your 1 approval was altered", and the foot reads "5 of 15 blocks marked".](docs/anchors.png)

*Four marks on a plan that has since been rewritten. Two are still on their text. The
Question **moved** — its opening sentence was rewritten, its longest line survived — and the
tray shows both what was marked and what is there now. The Approve's text is **gone**, which
is not the same as resolved: it gets its own line at the top, because an approval you did
not actually give is the expensive one.*

```bash
md                    # the workspace for this directory, README already open
md README.md          # render and open one file
md docs/              # the workspace, scoped to a subdirectory
md --sessions         # …and correlate it with your Claude Code history
md docs/spec.md -b    # a normal browser tab instead of an app window
git show HEAD:NOTES.md | md -
```

The argument decides which door you come in by: a file opens the reader, a directory — or
nothing at all — opens the workspace. Documents opened from the workspace carry the full
review layer, so marking one up never means leaving it.

## Install

```bash
git clone https://github.com/TheRealVale/rubricator.git
cd rubricator
./install.sh            # or: ./install.sh --link   (edits here take effect immediately)
```

Then open a new terminal. `install.sh` puts `md` in `~/.local/bin`, fetches the five pinned,
checksum-verified render libraries, renders a test page to prove the install works, and adds
a small block to `~/.zshrc` for tab completion.

> [!NOTE]
> oh-my-zsh binds `md` to `mkdir -p`. rubricator takes the name and gives you `mkd` instead,
> so you lose nothing. Prefer to keep it? `./install.sh --no-shell` and alias it yourself.

Requires macOS, bash and curl. `python3` is needed for the workspace and the review modes.
`./uninstall.sh` removes what was added and leaves your documents alone.

## Reading

![The reader on a plan: an outline down the left, front matter in a card, syntax-highlighted SQL and a rendered table.](docs/reader.png)

- dark by default, `t` toggles; the choice is remembered
- `/` or `⌘F` searches the document — every hit highlighted, `⏎` steps through, with a count
- `o` cycles the outline: full → a mini rail of ticks that expands on hover → hidden
- GitHub-flavoured markdown: tables, task lists, footnotes, syntax highlighting for ~40
  languages, mermaid diagrams, GitHub alerts (`> [!WARNING]`), YAML front matter
- `⌘P` prints with a clean light stylesheet
- `⌘/` lists every shortcut

Rendering happens in the browser from local copies of the libraries, so it works offline,
and a page written with `-o` is one self-contained file you can send to someone.

## Marking it up

![The same plan with the feedback panel open: three marks — Expand on the table, Change on the Authentication section, Approve on the open questions — each with its line range and note, above the Apply/Questions/Raw templates and a Copy feedback button.](docs/review.png)

Select any text for the verb popover, or hover a block and press a key:

| Key | Verb | Means |
|:---:|------|-------|
| `c` | Change | rewrite this, here's how |
| `?` | Question | explain or justify this |
| `x` | Cut | remove this |
| `e` | Expand | too thin, go deeper |
| `n` | Note | context you want recorded — asks for nothing |
| `a` | Approve | explicitly keep as-is |

`a` and `x` save instantly; the rest open a note box. Press a verb on a **heading** and it
covers that whole section. `f` opens the panel, which you can drag wider.

`⌘⏎` copies the lot as a numbered, line-anchored prompt:

```
Feedback on docs/plan.md — 2 items.
Apply this feedback. Don't restructure anything I didn't mention.

1. QUESTION — plan.md:12-18 — "1. Data model"
   > ```sql
   > CREATE TABLE applications (
   > … (7 lines)
   Why no created_by? And shouldn't status be indexed?

2. CHANGE — plan.md:31-37 — "2. Authentication"
   > ## 2. Authentication
   > … (7 lines in this section)
   No third-party IdP — we self-host. Use our own OIDC behind the gateway.
```

Paste that into any agent. Line numbers come from the markdown parser's own token offsets,
not from guesswork.

A `n` Note records context rather than asking for a change, so it never appears as a
numbered instruction — it rides along in an appendix instead. Which means a note cannot
accidentally reject a plan: with only notes outstanding the button reads **Approve with
notes**, and the approval carries them along as context.

### Across revisions

Marks are re-anchored by *content*, not by line number. Reopening a document that has been
rewritten states what happened before you scroll — *7 of your marks moved, 2 lost their
text* — and every mark carries one of three states:

- **Attached** — the text you marked is still there, verbatim.
- **Moved** — the exact text is gone, but its longest surviving line was found. The mark
  sits at that line, and the tray shows both what you marked and what the document says
  there.
- **Text gone** — nothing of it survived.

The third is not the same as *resolved*, and reporting it that way would turn a deletion
into an accomplishment. An `approve` that moved or lost its text is counted separately at
the top of the tray. The text you marked is never overwritten by whatever replaced it.

A mark on a single sentence is the case this cannot recover: with one line, there is no
longer line to fall back to. It says so rather than guessing.

## The workspace

A bare `md` points rubricator at a whole repository instead of one file. `-w` does the same
thing explicitly, which is what you want in a script.

![The workspace with the navigator's sort-and-filter row open — facets for has notes, behind its code, untracked and 14 days, and a "says" row built from front matter: delivered, draft, living, plan — beside the Notes surface listing every mark in the repository grouped by verb.](docs/workspace.png)

*Every mark in the repository, and the filters that narrow the document list down. `says` is
built from `status:` in front matter, so "everything that still calls itself a plan" is one
click.*

It walks every markdown file the repository tracks — plus anything untracked, so a document
an agent wrote thirty seconds ago is already there — reads `git log`, and indexes a few
hundred documents and several thousand prompts in about a second. There is nothing to cache
and nothing to invalidate.

### The window

The **navigator** down the left, **panes** in the middle, the review **tray** down the
right, a status strip along the bottom.

A **pane** holds any surface — a document, a session, a search, your notes, settings — and
keeps its own tabs and history. `⌘\` splits the window; ⌘-click opens in the split. Tabs sit
at the top of each pane rather than along the bottom of the window, because with two panes a
single strip cannot say which pane a tab belongs to. A tab owns its DOM for as long as it
lives, so leaving a document and coming back keeps its marks, its diagrams and where you
were reading.

The **tray follows focus**: one tray showing whichever document you are looking at, named in
its header, rather than one per pane.

`⌘K` is **find anything** — documents, sessions, your own marks and the surfaces of this
window in one list, because when you are hunting for something you rarely know which of
those it is. `⏎` opens it here, `⌘⏎` in a split, `⇥` filters by kind.

Document bodies stay on disk until the first search asks for them, and the session index
arrives after the window does, so a search can be answering from names and headings while
the rest is still coming. The box says so while that is true — and until the whole corpus is
there, an empty result reads *Searching…* rather than claiming nothing matched.

`⌘B` collapses the navigator · `⌘E` cycles its modes · `⌘1`–`⌘9` focus a pane · `⌘W` closes
a tab · `⌘⌥[` and `⌘⌥]` step through them · `/` filters the navigator · `?` lists the lot.
Every divider is draggable. Drag the navigator below the width its labels need and it
answers in kind: the modes become the icons the collapsed rail shows them as, group names
move above what they name, and a row spends what is left on the filename.

`⌘F` is deliberately unbound here. It falls through to the browser's own find bar, which
already has a hit count, next and previous, and wrap-around — and searches the page you are
actually looking at.

### The four navigator modes

**All** searches documents, sessions and your own marks in one field, because you remember
what something was about, not whether you wrote it down, said it to Claude or scribbled it
in a margin. With the field empty it shows the most recent of each.

**Documents** is the tree, and the only mode that nests — directories are how you remember
where a file is. Rows carry mark counts, a flag where the code a document describes has
moved on, and its `status:` if it declares one. Sorting and filters live behind *sort &
filter*, because most of the time you are looking for a name.

**Sessions** is your own agent history as something you can walk through: every session,
newest first, scoped to this repository by default — with **everywhere** beside it, because
the repository you are standing in is often not the one you said it in. `⇧⌘K` opens
find-anything already widened.

Indexing it reads every conversation on the machine, not only this project's, so it is off
until you ask: `md --sessions` for one run, or the switch the empty Sessions list offers,
which is the same switch as Settings → Indexing and stays on for future windows.
`--no-sessions` is the way back for a run. Documents are indexed in a tenth of a second and
transcripts in about two, so the window opens on its documents and history arrives while you
are looking at them. Each shows what you asked, which files
it changed, and which documents it bears on — worked out from the overlap between the files
a session touched and the files each document names. Opening one renders the conversation as
what it was: your turns on the right, Claude's on the left, thinking collapsed to a count,
tool calls behind a disclosure, files it wrote as chips you can open. Compactions,
interruptions and pasted images are marked where they happened.

A session is **resumable** while its transcript is on disk and **archived** once it is gone.
Prompts outlive transcripts, so most of your history can be read and searched but not picked
up again; the browser says which is which rather than offering a resume command that would
fail. For the live ones it hands you `cd <project> && claude -r <id>`, ready to paste.

**Notes** collects your marks across every document — every open Question, everything marked
Cut — because what you are hunting is often your own reaction, not the text. Its **copy**
emits exactly what is on screen.

### Surfaces

**Search** covers every document at once, by name or by content. A query is every term, not
a phrase: `auth flow` finds documents containing both words and ranks the ones where they
appear together first. Typing part of a filename finds that file before its body has been
read.

**Sessions search** covers everything you have ever typed, across every repository, and says
which one it was in — usually the question is not *what did I say* but *where was I when I
said it*. Results carry the line that matched, the repository and how long ago; opening one
jumps to that prompt with the word highlighted. Scoped to the current repository, with a
count of how many more are elsewhere and one key to widen.

**Behind its code** lists documents whose *named* files kept changing after the document
stopped — counted only in the paths each one mentions in backticks or links, so it says
*"this spec describes code that changed 392 times since you last touched it"* rather than
*"this repo is busy"*. It ranks by commits, which tracks how many paths a document quotes at
least as much as how stale it is, so read it as what a document claims about code rather
than as a quality score. It also says how many documents it could not judge at all: one that
names no file is not fresh, it is unmeasured.

**Dossier** assembles what you would paste to an agent before asking it anything — the
documents that cover a topic, your open marks with the text they were made against, what you
asked before, and the code most specific to those conversations. A saved search keeps the
question, never the answer, so opening one a week later rebuilds it from the index as it is
then.

### Live files

The workspace watches what it indexed: change a file on disk and the page says so; change
the one you are reading and it reloads in place, keeping your scroll position. Every
document carries a timeline of commits, the sessions that touched it, and its last edit.

### More than one project

Click the repository name in the bar to switch. The menu lists projects opened before and
offers a folder chooser; picking one opens it in its own window, the way an editor opens a
second project — which matters because session search already spans every repository on the
machine, so finding the conversation is only useful if there is somewhere to go with it.

```bash
md serve --port 7777        # a workspace that stays up, on a port you can bookmark
md . ../other-repo          # more than one repo at once (read-only past the first)
md --shallow                # skip subagent transcripts; they are counted by default
```

The rest is in `md --help`.

## The Claude Code loop

With the hook installed you never copy anything: Claude finishes a plan, the review window
opens by itself, and Claude waits while you read.

```
/plugin marketplace add TheRealVale/rubricator
/plugin install rubricator@rubricator
```

That is the whole install, typed inside Claude Code, and it edits nothing of yours.
`./install-hook.sh` does the same by writing the hook into your `settings.json`, if you
would rather not use plugins.

| You do | Claude gets |
|---|---|
| **Approve** (`⌘⇧⏎`) | `allow`, with the plan paired back as `updatedInput` |
| **Send feedback** (`⌘⏎`) | `deny` + your annotated marks, and it revises the plan |
| close the window | `ask` — falls back to the normal prompt |
| walk away | `ask` after nine minutes |

`ExitPlanMode` requires `allow` to carry `updatedInput` before Claude Code will skip its own
approval prompt. Rubricator sends it; whether the prompt is then skipped is the vendor's
side of the contract and worth checking once against your own build. **Send feedback** needs
no pairing.

The plan comes from the hook payload — `planFilePath` for where the agent wrote it, `plan`
for the text — and the path is preferred, because marks are keyed to a document's path and a
plan read from its real file keeps them across the rewrite. Searching the session transcript
is a fallback for builds that send neither: it can find only *a* recent plan, which on a
machine running two sessions is not necessarily yours.

Nothing here can wedge a session. Missing plan, malformed input, no `python3`, crashed
runner: every failure exits quietly and leaves the normal flow untouched. Closing the window
is never read as consent.

For any other agent:

```bash
claude "$(md --review docs/plan.md)"   # blocks until you decide, prints your marks
```

## Not only markdown

PDFs and Word files are indexed, searched and read alongside markdown. Both extractors ship
with macOS — `textutil` for Word, PDFKit through the JXA bridge for PDF — so this adds no
dependency, and results are cached against mtime and size.

Extraction never holds up the index: a workspace opens on its markdown immediately and a
document is extracted the first time something needs it. What comes back renders as an
ordinary document — one block per paragraph, a heading per page — so the reader, the review
layer, the outline, search and the export all work on it unchanged. You can mark up a page
of a contract and send the quote to Claude, and it will say which page it came from.

A PDF with no text layer says so rather than opening blank, and a password-protected one is
named rather than retried.

## For an agent, or a script

```bash
md --json .                 # the index, on stdout, as JSON
md --json --sessions .      # …with session ids and the files they touched
```

A flag, not a protocol: no server, no process to keep alive. It prints the documents, their
headings, your marks with their anchor states and the text they were made against, and how
many commits have landed in the files each document names. It exits 0 and starts nothing.

Two things deliberately do not come through that door. There is no staleness *verdict* — the
counts are there under `activity`, and what they mean is the reader's call, because a
machine-readable field called `stale` would be this tool deciding for you through an
interface where nobody reads the caveat. And there is no prompt text: it reports how many
prompts it withheld and nothing else.

Your marks are also just files. `.rubricator/notes/<path>.json` is small, plain JSON with a
version field — an agent can `cat` it without asking rubricator anything.

## Letting it start things

Off by default. With `md --allow-launch` — or `{"allow_launch": true}` in
`~/.config/rubricator/config.json` — the workspace can hand work to a terminal:

- **Send to Claude** on an open document: a new session at the repository root, with the
  marks you just took as its first prompt.
- **Resume** or **fork** a past session, offered only where a transcript still exists.
- **Reveal** a file in Finder, or open it in your editor.

Sessions open in **iTerm** if you have it, otherwise Terminal — or whichever terminal you
pick under Settings. The launcher is a `.command` file handed to that application through
LaunchServices, which needs no Automation permission, so macOS never interrupts with a
dialog.

The gate exists because a markdown document is untrusted input: it comes from a repository
you cloned, a plan an agent wrote, a file someone sent you, and markdown carries raw HTML.
Rendering it into a page that can talk to a local server makes `<img onerror=…>` worth
taking seriously. Two walls stand in front of that — the renderer strips scripts, event
handlers and `javascript:` URLs inside an inert `<template>` before anything is inserted,
and the served page runs under a content security policy where only scripts carrying that
page's nonce may execute — and this gate is the third, because the first two are code
written by the same hand.

What crosses the wire is a verb and an id. The page never sends a path and never sends a
command: every path is resolved on the server against the index it already holds, and every
argument goes into `argv` directly. The one thing the page may hand over is the prompt text
for a new session, written to a file and read back as a single argument, so a prompt
containing `$(…)`, backticks or `;` arrives as literal text. The server is loopback-only,
token-gated per run, refuses anything cross-site, and exits when the window closes.

## What it writes

Four directories, and nothing else:

| | |
|---|---|
| `.rubricator/notes/` | your marks, in the repository they belong to |
| `~/.config/rubricator/` | settings and saved searches, mode 0600 |
| `~/.cache/rubricator/` | the prompt index, mode 0700, files 0600 |
| `~/.local/state/rubricator/` | the log of plan reviews |

Never a file git tracks, never a file found by indexing. Your documents are not modified — a
mark is a sidecar, not an edit.

Marks are one file per document, keyed by the document's path **relative to the enclosing
git repository**. That is what makes them portable: a store written in one clone loads in
another at a different path, `md .` and `md docs/` read the same marks, and `git status`
names the document whose marks changed rather than one shared blob. Each mark carries an
`at` and, where git knows one, a `by`.

They are meant to be committed — that is the whole sharing story, and there is no other. Two
people marking different documents never touch the same file; two who mark the same one get
a merge conflict in a few kilobytes of JSON. Nothing hides the file: it appears in `git
status`, because you cannot commit what you do not know is there.

Nothing leaves the machine. There is no account, no telemetry and no network call after the
one-time library fetch. Both halves of an indexed conversation are scrubbed of keys, tokens,
JWTs, private keys, `.env` lines, auth headers and connection strings; the session index
expires after seven days and is excluded from Time Machine; and history never reaches a page
that becomes a file — `--sessions` refuses `--out`, and a page built to be moved takes
history only when that flag asks for it, never from the setting.

## How it works

Two tiers. A single file opens as a static page — self-contained, shareable, no server. A
workspace starts a small local server instead, which is what lets it fetch documents as you
open them, reindex without regenerating, and write marks into the repository. It listens on
127.0.0.1 with a per-run token, refuses anything cross-site, and exits when you close the
window. `md --static` opts out; `-o` and `-n` always do.

The two tiers do not share a browser store, and cannot: a workspace is served from
`http://127.0.0.1:<port>` on a fresh port each run, a static page is `file://`, and
different origins do not share local storage. What crosses is the repository file — a static
page built after you marked something up carries the marks with it, because the sidecar is
read at build time. Local storage is the fallback for the tier with nowhere else to put
anything.

```
bin/md              bash + awk: inlines the template, libraries and your markdown
                    (base64) into one self-contained HTML file, then opens it
share/template.html the reader page: CSS, chrome, TOC, theme
share/render.js     markdown into the DOM — shared by both pages, so a document
                    behaves the same wherever it is opened
share/review.*      annotation layer — anchors, verbs, storage, export
share/ui.*          outline modes, search, resizable panel, shortcuts (reader only)
share/shell.*       the window: navigator, panes, tabs, palette, status strip
share/workspace.*   the repo index, and what each surface looks like
share/serve.py      the local server: ephemeral port, per-run token, idle exit
share/actions.py    the verb allowlist — the only place the page can cause anything
share/extract.py    PDF and Word into text, cached on mtime and size
share/transcript.py one conversation, parsed on demand
share/hook.py       blocking review server for --review and --hook
.claude-plugin/     the Claude Code plugin manifest; hooks/hooks.json is the hook
```

Eighteen files, under ten thousand lines, plus five vendored render libraries. No build
step, no runtime dependency beyond what macOS ships. `./tests/smoke.sh` drives the whole
thing from a throwaway install; CI runs it on every push.

The reasoning behind the design is in [`docs/`](docs): [`tasks.md`](docs/tasks.md) is the
task register, the `*-plan.md` documents carry the arguments, and
[`platform.md`](docs/platform.md) says what is macOS-bound and what a port would cost.

## Prior art

**[plannotator](https://github.com/backnotprop/plannotator)** is the mature one: far larger
and older, with PR and MR diff review, team sharing and many agents. Its Version Browser
saves each plan submission and shows a change badge on resubmit, which rubricator has no
answer to. If you want this loop with more breadth than one person maintains, use it.

**[PlanBridge](https://github.com/contextbridge/planbridge)** is the same idea at a similar
size: MIT, localhost, precision feedback on agent plans. **Moat** is hosted rather than
local, which is the whole difference.

**[Imark](https://imarkmd.com)** is a native macOS markdown reader that stores its notes
*inside* the `.md` file as HTML comments — a better answer than local storage if you move
between machines, a worse one if you mind your documents being edited.
[md-annotator](https://github.com/konradmichalik/md-annotator) solves a neighbouring
problem.

**The tools you already have.** Claude Code opens a plan in `$EDITOR` with `Ctrl+G`, and the
vendor's own VS Code extension opens it as a Markdown document with inline comments. Both
are free and installed. rubricator is worth a window only if the verb grammar and the
marks-survive-the-rewrite part are worth it to you.

If it is the session half you want, several dedicated viewers read transcripts more
carefully than this does: [recensa](https://github.com/S40911120/recensa),
[universal-session-viewer](https://github.com/tad-hq/universal-session-viewer),
[cc_transcript_viewer](https://github.com/tim-hua-01/cc_transcript_viewer) and
[kortex](https://github.com/chicongst/kortex). Dated figures for every project named here
are in [`docs/citations.md`](docs/citations.md).

rubricator's bet is different: no server you leave running, no account, no daemon, and a
codebase small enough to read in an evening and change the parts you don't like.

## Limitations

- **macOS.** A decision rather than a *not yet*; the six places it is load-bearing, and the
  honest Linux answer to each, are in [`docs/platform.md`](docs/platform.md)
- a mark on a **single rewritten sentence** is not recovered — with one line there is no
  longer line to fall back to
- marks do not sync between machines on their own; committing them is the only transport,
  and there is no server, account or locking behind it
- a conversation can be read but not annotated: the review layer binds to a document, and a
  chat bubble is not one
- continuing a session from the window is designed but unbuilt
- a **multi-root workspace is read-only past the first repository** and cannot be reopened —
  deliberately unfinished, measured against how it is actually used
- the Claude Code hook is Claude Code specific; the clipboard and `--review` paths are not

## Licence

See [LICENSE](LICENSE). The bundled render libraries have their own permissive licences,
listed in [THIRD-PARTY-LICENSES.md](THIRD-PARTY-LICENSES.md).
