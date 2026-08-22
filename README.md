# rubricator

Read markdown in a beautiful window, mark it up like a document reviewer, and send the
notes straight to your AI coding agent.

*A rubricator was the scribe who went through a finished manuscript adding the red marks —
the headings, the corrections, the notes in the margin. Same job, different century.*

Built for one job: an agent writes a plan, you read it, and you need to say *"this bit —
no"* without retyping it into a terminal.

![rubricator reviewing a plan](docs/review.png)

```bash
md                    # the workspace for this directory, README already open
md README.md          # render and open one file
md docs/              # the workspace, scoped to a subdirectory
md docs/spec.md -b    # a normal browser tab instead of an app window
git show HEAD:NOTES.md | md -
```

The argument decides which door you come in by: a file opens the reader, a directory —
or nothing at all — opens the workspace. Documents opened from the workspace carry the
full review layer, so you can mark them up without leaving it.

One bash script and a page. No build step, no runtime dependency beyond what macOS ships.
Rendering happens in the browser from pinned local copies of the libraries, so it works
offline and the page you generate with `-o` is a single self-contained file you can send
to someone.

**Two tiers.** A single file opens as a static page — self-contained, shareable, no server.
The workspace starts a small local server instead, which is what lets it fetch documents as
you open them, reindex without regenerating, and keep your notes in the repo. It listens on
127.0.0.1 with a per-run token, refuses anything cross-site, and exits by itself when you
close the window — nothing is left running. `md --static` opts out and gives you a file
again; `-o` and `-n` always do.

## Install

```bash
git clone https://github.com/TheRealVale/rubricator.git
cd rubricator
./install.sh            # or: ./install.sh --link   (edits here take effect immediately)
```

Then open a new terminal. `install.sh` puts `md` in `~/.local/bin`, fetches the three
render libraries (pinned and checksum-verified), and adds a small block to `~/.zshrc` for
tab completion.

> [!NOTE]
> oh-my-zsh binds `md` to `mkdir -p`. rubricator takes the name and gives you `mkd` instead,
> so you lose nothing. Prefer to keep it? `./install.sh --no-shell` and alias it yourself.

Requires macOS, bash and curl. `python3` is needed only for the review modes below.
Uninstall with `./uninstall.sh` — it removes what it added and leaves your documents alone.

## Reading

![the reader](docs/reader.png)

- dark by default, `t` toggles; the choice is remembered
- `/` or `⌘F` searches the document — every hit highlighted, `⏎` steps through, with a count
- `o` cycles the outline: full → a mini rail of ticks that expands on hover → hidden
- GitHub-flavoured markdown: tables, task lists, footnotes, syntax highlighting for ~40
  languages, mermaid diagrams, GitHub alerts (`> [!WARNING]`), YAML front matter
- `⌘P` prints with a clean light stylesheet
- `⌘/` lists every shortcut

## Reviewing

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

Paste that into any agent. Line numbers are exact: they come from the markdown parser's
own token offsets, not guesswork.

**Notes are different.** A `n` Note records context rather than asking for a change, so it
never appears as a numbered instruction — it rides along in an appendix:

```
Notes — context, not change requests:

— plan.md:17-23 — "1. Data model"
   > ```sql
   > CREATE TABLE applications (
   > … (7 lines)
   Ties into the migration guard work from #211.
```

Which means a note can't accidentally reject a plan: with only notes outstanding the button
reads **Approve with notes**, and the approval carries them along as context.

**Across revisions.** Notes are stored per file and re-anchored by *content*, not line
number. After the agent rewrites the document, reopen it: untouched notes follow their text
to its new lines, and notes whose text is gone are marked *resolved* and greyed out. What's
left is your open-items list.

## Workspace mode

A bare `md` points rubricator at a whole repo instead of one file. `-w` does the same
thing explicitly, which is what you want in a script.

```bash
md                       # index this repo and open it
md ~/code/thing          # somewhere else
md --sessions            # also index your own agent history (local only)
md -w                    # the same thing, named explicitly
```

It walks every markdown file the repo tracks, reads `git log`, and builds one static page
— 328 documents and 3,800 prompts index in about a second, so there is nothing to cache
and nothing to invalidate.

**Library** is the tree: every document, with its note count and a mark where the code it
describes has moved on. Sort by recency, staleness, notes, size or name; filter to the ones
you have annotated. Selecting a document opens it beside the tree, with the full review
layer — so marking something up never means leaving the workspace.

**Sessions** is your own history as something you can walk through. Every session you have
run, newest first, scoped to this repo by default. Each one shows what you asked, which
files it changed, and which documents it bears on — worked out from the overlap between the
files a session touched and the files each document describes.

A session is **resumable** while its transcript is still on disk and **archived** once it is
gone: the prompts survive far longer than the transcripts, so most of your history can be
read and searched but not picked up again. The browser says which is which instead of
offering you a resume command that would fail — for the live ones it hands you
`cd <project> && claude -r <id>`, ready to paste.

**Search** every document at once, with matches in context. Click a result to read it.

**Stale** lists documents whose code moved on without them. Churn is counted only in the
files each document actually mentions or links, so it flags *"this spec describes code that
changed 392 times since you last touched it"* rather than *"this repo is busy"*.

**Notes** collects your annotations across every document — every open Question, everything
marked Cut — because what you are hunting is often your own reaction, not the text.

**With `--sessions`** a topic also resolves to the sessions that discussed it and the code
those sessions changed, ranked by how specific each file is to the topic rather than by
whether it was touched. Then **Copy dossier** puts the whole picture — documents, your open
notes, what you asked before, the files — on the clipboard for your agent.

> [!IMPORTANT]
> Session data never leaves the machine. Prompt text is scrubbed of keys, tokens, JWTs,
> private keys, `.env` lines and connection strings at index time, and `--sessions` refuses
> `--out` outright so it cannot be written to a shareable file.

## The Claude Code loop

With the hook installed you never copy anything.

```bash
./install-hook.sh          # adds one PreToolUse/ExitPlanMode hook; backs up your settings
./install-hook.sh --remove # undo
```

Claude finishes a plan → the review window opens by itself → Claude waits while you read.

| You do | Claude gets |
|---|---|
| **Approve** (`⌘⇧⏎`) | `allow` — the plan proceeds, no terminal prompt |
| **Send feedback** (`⌘⏎`) | `deny` + your annotated notes, and it revises the plan |
| close the window | `ask` — falls back to the normal prompt |
| walk away | `ask` after nine minutes |

`ExitPlanMode` doesn't carry the plan text — the plan is a file the agent wrote — so the
hook reads the session transcript to find it. Feedback then anchors into that real file,
and because notes key off its path, they survive the rewrite.

Nothing here can wedge a session. Missing plan, malformed input, no `python3`, crashed
runner: every failure exits quietly and leaves the normal flow untouched. Closing the window
is never read as consent.

**Without the hook**, for any agent:

```bash
claude "$(md --review docs/plan.md)"   # blocks until you decide, prints your notes
```

## How it works

```
bin/md              bash + awk: inlines the template, libraries and your markdown
                    (base64) into one self-contained HTML file, then opens it
share/template.html the reader page: CSS, chrome, TOC, theme
share/render.js     markdown into the reader's DOM — shared by both pages, so a
                    document behaves the same wherever it is opened
share/review.*      annotation layer — anchors, verbs, storage, export
share/ui.*          outline modes, search, resizable panel, shortcuts
share/workspace.*   the repo index and its views
share/hook.py       blocking review server for --review and --hook
```

In the live tier, annotations are written to `.rubricator/notes.json` in the repo, so they
survive a cleared browser and can be grepped, diffed or committed. Rubricator adds that path
to `.git/info/exclude` rather than your `.gitignore`: nothing tracked is touched, the file
never shows up as untracked noise, and committing it stays your choice. In the static tier
they live in the browser's local storage, keyed by the document's absolute path —
the same key from either page, so a note written in the workspace is there when you open
the file on its own. Nothing is written into your files and nothing leaves the machine.

Where rubricator is going next is written down: [`docs/architecture-plan.md`](docs/architecture-plan.md)
for the shape, [`docs/tasks.md`](docs/tasks.md) for the work.

## Watching, and the rest

The live workspace watches the files it indexed. Change one on disk and the page
says so; change the one you are reading and it reloads in place, keeping your
scroll position. Nothing to enable.

**Graph** draws which documents belong together, from the files they describe and
the sessions that touched them. It asks before laying out, because that is a real
computation and you should be the one to ask for it.

Every document carries a small **timeline**: commits as grey marks, sessions that
touched it in accent, the last edit in green. Click a session mark to open it.

```bash
md serve --port 7777        # a workspace that stays up, on a port you can bookmark
md . ../other-repo          # more than one repo in one workspace
md --deep                   # count what subagents changed, not just the main thread
```

`--deep` matters more than it sounds: work you delegated is recorded in separate
transcripts, so without it a session that did most of its editing through subagents
looks like it touched nothing. Here it is the difference between 1,286 files
attributed and 1,579.

### Extending it

Two directories, both optional:

- `~/.config/rubricator/views/*.js` — each file may call
  `RB.view({id, label, render})` and gets its own tab. `RB` hands you the index,
  the helpers and `RB.open(rel)`.
- `~/.config/rubricator/providers/*.py` — each file may define `provide(root)`,
  and whatever it returns lands in the page as `D.extra[name]`.

## Letting it start things

Off by default. With `md --allow-launch` — or `{"allow_launch": true}` in
`~/.config/rubricator/config.json` — the workspace can hand work to a terminal:

- **Send to Claude** on an open document: a new session at the repo root, with the
  notes you just took as its first prompt. Read a plan, mark six passages, press the
  button — the conversation starts where you left off thinking.
- **Resume** or **fork** a past session, offered only where a transcript still exists.
- **Reveal** a file in Finder, or open it in your editor.

### What keeps that safe

The page sends a verb and an id. It never sends a path and never sends a command; every
path is resolved on the server against the index it already holds, and every argument
goes into `argv` directly. The one thing the page may hand over is the prompt text for a
new session, and that is written to a file and read back as a single argument — a prompt
containing `$(…)`, backticks or `;` arrives as literal text, because no shell ever parses
it.

On top of that the server is loopback-only, token-gated per run, refuses anything
cross-site, and exits when the window closes. Session ids are matched against a strict
pattern before they reach a command line, and a session with no transcript is refused
rather than attempted.

The launcher is a `.command` file opened through LaunchServices, so no Automation
permission is involved. If you set `"terminal": "iTerm.app"` in the config, rubricator
drives that terminal over AppleScript instead — macOS will ask for permission the first
time, and if it is refused the error tells you where to grant it.

## Prior art

If you want this loop with more breadth than one person maintains, look at
[plannotator](https://github.com/backnotprop/plannotator) — code diffs, PR review, many
agents, team sharing. [md-annotator](https://github.com/konradmichalik/md-annotator) and
[Imark](https://imarkmd.com) solve neighbouring problems; Imark's approach of storing notes
inside the `.md` file is better than local storage if you move between machines.

rubricator's bet is different: no server, no daemon, no install beyond a script, and small
enough that you can read all of it and change the parts you don't like. The palette is one
CSS block at the top of `share/template.html`.

## Limitations

- macOS only in practice (uses `open`; the Chrome app window is a nicety, any browser works)
- annotations are per-browser-profile; they don't sync between machines
- raw HTML inside markdown is rendered, not sanitised — same as VS Code's preview. Render
  documents you trust
- the Claude Code hook is Claude Code specific; the clipboard and `--review` paths are not

## Licence

MIT — free to use, modify and sell, **at your own risk and with no warranty of any kind**.
See [LICENSE](LICENSE). The bundled render libraries have their own permissive licences,
reproduced in [THIRD-PARTY-LICENSES.md](THIRD-PARTY-LICENSES.md).
