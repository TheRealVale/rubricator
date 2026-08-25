---
title: How every figure in the plans was obtained
subtitle: One machine, one day — the command behind each number in the five phase plans
status: reference — 2026-08-23
---

# How every figure in the plans was obtained

The five phase plans — `install-plan.md`, `signals-plan.md`, `anchoring-plan.md`,
`retention-plan.md`, `scope-plan.md` — are built almost entirely on local
measurement. That is the point of them, and it is also the thing a reader cannot
check unless the measurements are written down somewhere they can be re-run.

This is that page. Every count, percentage, byte size, timing and file:line those
five documents cite has an entry here, with the command or the method that
produces it. Entries carry stable ids, so a plan can cite
`measurements.md#m-ins-3` and land on the thing it is claiming.

Three kinds of figure are **not** here. External sources — papers, vendor
documentation, competitor repositories — live in `citations.md`, in the wording
cleared for them; where a plan quotes one, the entry below points there rather
than repeating it, because two copies of one quotation drift. Arithmetic done on
figures already in this file (a percentage of two counts on the same row) is
marked as arithmetic and not given a command of its own. And figures that could
not be re-derived from the working record are in the last section, named, with
what is missing.

---

## Conditions

| | |
|---|---|
| date | **2026-08-23**, runs between roughly 19:00 and 22:00 local (CEST) |
| machine | Apple Silicon Mac · macOS 26.5.2 · Darwin 25.5.0 |
| `claude --version` | **2.1.241 (Claude Code)** |
| rubricator | `HEAD` = **`a63e540`**, 27 commits, one author |
| working tree | `git status --porcelain` empty before and after every run |
| python | `python3` 3.14, standard library only — no third-party packages |
| node | v24.18.0 (used only to run browser code outside a browser) |
| git | 2.53.0 |
| browser | Google Chrome, `--headless=new`, for two entries only |

The five repositories, as `git ls-files '*.md' | wc -l` / `git ls-files | wc -l`.
Four of the five are private and appear throughout these plans as **repo A** to
**repo D**; the letters are stable across every document, so a figure quoted in
one plan can be matched to a figure in another. Nothing from inside them appears
anywhere in this repository beyond their aggregate counts — no titles, no paths,
no headings, no quoted lines. (That discipline is newer than the repository:
`workspace-plan.md` and `architecture-plan.md` were written before it and name
both the repositories and, in two places, documents inside them. See **O6**.)

| repo | tracked `*.md` | tracked files | documents the index builds |
|---|---:|---:|---:|
| rubricator | 11 | 37 | 11 |
| repo A | 94 | 108 | 99 |
| repo D | 84 | 324 | 84 |
| repo B | 328 | 2,194 | 330 |
| repo C | 492 | 3,363 | 502 |

The last column is larger than the first because `find_docs` also takes
`.markdown`, `.mdown` and `.mdx` (`workspace.py:16`). Plans quote the last
column; this table is the bridge.

Four of those five repositories are private. Nothing from inside them appears
here beyond their names and aggregate counts — no titles, no paths, no headings,
no quoted lines. The same rule was applied to `~/.claude`: prompt counts, yes;
prompt text, no.

**These are one machine's numbers.** Every corpus figure is a property of five
particular repositories and one person's session history on one day, and every
one of those grows. Re-running any of this elsewhere will give different numbers,
and re-running it here next month will too — three tables below already disagree
with themselves eighty minutes apart, and say so. Where a figure is used to
*decide* something, the decision is written against the shape of the number, not
its last digit.

### How the measurements were run

Almost nothing here shells out to `md`. The Python figures come from importing
`share/workspace.py`, `share/transcript.py` and `share/extract.py` directly and
calling their functions, so that no server starts and nothing is written. The
JavaScript figures come from porting the relevant function verbatim into node —
`viewGraph`'s spring loop, `graphEdges`, `docScore`, `palSearch.hit`, and the
`mapLines()`/`srcSlice()`/`addItem()` trio driven by rubricator's own vendored
marked 15.0.12. Install behaviour was measured in sandboxed `HOME` and `PREFIX`
directories under `/private/tmp`. Nothing was written into any repository, and
the scratch scripts are working files that are not part of this repository —
where one is load-bearing it is described below precisely enough to rewrite in an
afternoon.

Every timing is warm-cache. The page cache could not be dropped without `sudo`,
so treat each one as a lower bound for a cold first run; where a cold-ish figure
exists it is given beside the warm one.

---

# The install

Covers `install-plan.md`. Unless stated otherwise, `$COPY` is a scratch prefix
holding what `install.sh` ships today, `$GLOB` a second prefix holding all
eighteen `share/` files, and `$LINK` a `./install.sh --link` install.

### M-INS-1

**The maintainer's own `md` is a symlink into the checkout**, so the copy path the
README puts first has never been exercised on this machine.

```
$ ls -la ~/.local/bin/md
lrwxr-xr-x  …  ~/.local/bin/md -> ~/Repositories/rubricator/bin/md
```

### M-INS-2

**`share/` holds 18 regular files excluding `vendor/`**, and `git ls-files`
returns exactly the same eighteen — which is why K1's glob can be driven from git
rather than from a two-name exclusion list.

```
$ ls -p share/ | grep -v '/$' | sort | wc -l      # 18
$ git ls-files share/ | wc -l                     # 18
```

### M-INS-3

**A copy install lands 8 of those 18.** `install.sh:59` enumerates seven names and
`:62` adds `hook.py`. The ten that do not arrive:

```
$ env HOME=$H PREFIX=$COPY ./install.sh
$ comm -23 <(ls -p share/ | grep -v '/$' | sort) <(ls "$COPY/share/rubricator" | sort)
actions.py
extract.py
render.js
serve.py
shell.css
shell.js
transcript.py
workspace.html
workspace.js
workspace.py
```

Installed: `hook.py md.zsh review.css review.js template.html ui.css ui.js
vendor.txt`, plus a fetched `vendor/`.

### M-INS-4

**The copy install renders a 254,436-byte page; the `--link` install renders
267,263; the difference is 12,827 bytes, exactly `wc -c share/render.js`.** Both
runs exit 0 and both print `md: wrote …`.

```
$ env HOME=$H "$COPY/bin/md" -o out-copy.html sample.md   # exit 0 · 254436 bytes
$ env HOME=$H "$LINK/bin/md" -o out-link.html sample.md   # exit 0 · 267263 bytes
$ wc -c share/render.js                                   # 12827
```

`sample.md` is a 12-line fixture: an `h1`, bold text, a fenced code block, a list
and a table.

### M-INS-5

**Re-run with a fixture twenty bytes larger: 254,456 and 267,283 — the same
12,827-byte delta, to the byte.** Same two commands as `M-INS-4` against a longer
fixture. This is the check that the delta is the renderer and not the document.

### M-INS-6

**`grep -c 'md renderer'` is 0 on the broken artefact and 1 on the good one**, and
that string is unique to `render.js` in the whole repository.

```
$ grep -c 'md renderer' out-copy.html    # 0
$ grep -c 'md renderer' out-link.html    # 1
$ grep -rn 'md renderer' bin/ share/     # one line: share/render.js:1
```

### M-INS-7

**`grep -c 'window.MD'` returns 1 on the *broken* artefact** — the reason X1 is
dead. `review.js:570` defines `window.MDReview`, `window.MD` is a substring of it,
and `review.js` is one of the eight files a copy install does copy.

```
$ grep -c 'window.MD' out-copy.html      # 1
$ grep -n 'window.MD' out-copy.html
2710:window.MDReview = { open: openDoc, count: openCount, storage: Storage,
```

### M-INS-8

**Rendered, the copy artefact contains the fixture's heading zero times and the
link artefact once**, and the copy artefact's `<article class="md" id="doc">` is
empty.

```
$ "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
    --headless=new --dump-dom --virtual-time-budget=5000 \
    --user-data-dir=$SCRATCH/chrome "file://$PWD/out-copy.html" \
  | grep -c 'Hello Rubricator'          # 0   (link artefact: 1)
```

Kill the process afterwards; it does not always exit on its own. See
`M-GAP-3` for the re-run that did not finish.

### M-INS-9

**Bare `md` in a git repository exits 1 under the copy install and 0 under
`--link`.** It is the only exit code in this set that moves.

```
$ cd $SCRATCHREPO && env HOME=$H "$COPY/bin/md" -n
# exit 1 · stderr: … can't open file '…/share/rubricator/workspace.py': [Errno 2] …
$ cd $SCRATCHREPO && env HOME=$H "$LINK/bin/md" -n
# exit 0
```

### M-INS-10

**A zero-length `~/.zshrc` aborts the installer; an rc containing only our own
markers does not.** Four sandboxed `HOME`s, one rc state each:

| `~/.zshrc` | exit | block added | banner | `--with-hook` |
|---|---|---|---|---|
| two lines of content | 0 | yes | yes | runs |
| **zero-length** | **1** | no | **no, and no error** | never reached |
| absent | 0 | n/a — prints *no ~/.zshrc found* | yes | runs |
| only a stale rubricator block | 0 | yes | yes | runs |

```
$ printf '# my rc\nexport FOO=1\n' > $H/.zshrc   # then, per row:
$ : > $H/.zshrc          # zero-length
$ rm -f $H/.zshrc        # absent
$ env HOME=$H PREFIX=$H/.local ./install.sh ; echo "EXIT=$?"
```

Cause: `install.sh:79` pipes `grep -v '/md\.zsh"' "$RC"` under `set -euo pipefail`
(`install.sh:3`), and `grep -v` exits 1 when it emits nothing. `--with-hook` is at
`install.sh:102`, after the abort point.

### M-INS-11

**`RUBRICATOR_NO_WINDOW` works; `RUBRICATOR_DRY_LAUNCH` has been read, not run.**

```
$ RUBRICATOR_NO_WINDOW=1 RUBRICATOR_TIMEOUT=6 md --review sample.md
md: no feedback given
# exit 1 — same under both install modes
```

`RUBRICATOR_DRY_LAUNCH` is `actions.py:230`. It is present in the code and was not
exercised; `install-plan.md` §6 says so rather than implying it was.

### M-INS-12

**No tests, no tags, no releases, no `.github`; 27 commits by one author; 39
distinct paths in the whole history.**

```
$ git tag | wc -l                                                   # 0
$ gh api repos/TheRealVale/rubricator/tags --jq length              # 0
$ gh api repos/TheRealVale/rubricator/releases --jq length          # 0
$ ls .github                                                        # No such file or directory
$ git rev-list --count HEAD                                         # 27
$ git log --all --pretty=format: --name-only | sort -u | grep -v '^$' | wc -l   # 39
$ git log --all --pretty=format: --name-only | sort -u \
    | grep -iE 'test|spec|\.github|ci\.|workflow|Makefile|package.json|pyproject' # none
```

The 39 includes two `share/__pycache__/*.pyc` paths.

### M-INS-13

**`awk`'s `getline` returns −1 on a file it cannot open, and awk still exits 0** —
the mechanism behind the silent include at `bin/md:380`.

```
$ awk 'BEGIN { print "getline returned:", (getline line < "/nonexistent") }'
getline returned: -1
$ echo $?
0
```

### M-INS-14

**The `diff -rq` assertion K1 and K3 both rest on.** Against the shipped install it
exits 1 and names the ten files; against an eighteen-file install it exits 0.

```
$ diff -rq --exclude=vendor --exclude=__pycache__ share/ "$COPY/share/rubricator/"
Only in share: actions.py
… ten lines …
$ echo $?            # 1
$ diff -rq --exclude=vendor --exclude=__pycache__ share/ "$GLOB/share/rubricator/"
$ echo $?            # 0
```

**`diff -rq` compares content, not mode**: with `chmod 0600` on an installed
`ui.css` the diff still exits 0. That is why `install-plan.md` §3 says the mode
question is cosmetic and that the assertion will not catch it either way — nothing
in `share/` is executed directly (`bin/md:165`, `:185`, `:248`, `:266`, `:270`
all invoke `"$PY" "$SHARE/….py"`).

### M-INS-15

**Both directories the obvious glob would have to skip are already gitignored** —
`.gitignore` lines 2, 4 and 5 are `share/vendor/`, `__pycache__/` and `*.pyc`.
`git ls-files share/` therefore returns the eighteen with no list of exclusions in
the installer. Read with `sed -n '1,6p' .gitignore`.

### M-INS-16

**All five pinned vendor libraries resolve and hash to their pinned values**, each
re-fetched with `curl` and hashed independently of the script.

```
$ while read -r name url sha; do
    curl -fsSL -o "$T/$name" "$url"
    printf '%s %s %s\n' "$name" "$(shasum -a 256 "$T/$name" | cut -d' ' -f1)" "$sha"
  done < share/vendor.txt
```

Five files, five HTTP 200s, five matches, all on `cdn.jsdelivr.net`:
marked 15.0.12, highlight.js cdn-assets 11.12.0, its `github-dark` and `github`
stylesheets, mermaid 11.16.1.

### M-INS-17

**Every run of `install.sh` re-downloads 3,737,839 bytes.** `install.sh:68` calls
`"$PREFIX/bin/md" --vendor`, `bin/md:289` maps `--vendor` to `VENDOR_FORCE=1`, and
`bin/md:103` then bypasses the `[ ! -s … ]` cache test.

```
$ cat share/vendor/* | wc -c            # 3737839
```

Re-running the installer over an already-populated prefix reproduces it, banner
and all.

### M-INS-18

**`md --version` prints `md 2.0.0`** (`bin/md:27`). Used by K2's proposed
self-check.

### M-INS-19

**Two fail-open branches on the checksum path**, both read at their lines:
`bin/md:109` is `if command -v shasum >/dev/null;` — a machine with no `shasum`
installs all five downloads unverified; `bin/md:111` is `[ -n "$sha" ]` — an entry
with an empty third field is skipped. `shasum` is at `/usr/bin/shasum` here, so
the live branch is the second.

### M-INS-20

**`README.md:46` says *the three render libraries* against five pinned files**, and
three is right: highlight.js contributes two theme stylesheets. `wc -l
share/vendor.txt` is 7 lines, five of them entries.

### M-INS-21

**`find_plan` reads one payload key and does archaeology on the transcript.**
`hook.py:30-55`: `transcript_path` at `:35`, a seek to the last 4 MB at `:40-41`,
a regex scan of the tail for `/…/.claude/plans/….md`, then a fallback to the
newest `*.md` in `~/.claude/plans` modified within 3,600 seconds (`:50-51`).
Failing all of it, `hook.py:200` emits `{"systemMessage": "md: no plan file found
— skipping review"}` and exits 0. Read, not run.

### M-INS-22

**Nothing in the repository touches the fields the platform injects.**

```
$ grep -rn "updatedInput\|planFilePath\|payload\[" share/ bin/     # no output
```

### M-INS-23

**What Claude Code's hooks documentation says about `ExitPlanMode`** — that
`tool_input` carries `plan` (the markdown) and `planFilePath`, that Claude Code
injects both before passing the input to hooks, and that PostToolUse should read
`tool_response.plan` rather than re-reading the file. Fetched 2026-08-23 from
`code.claude.com/docs/en/hooks`; the cleared wording is card **G1** in
`citations.md`, and the `defer` behaviour from the same page and the same fetch
is **G2**. Standing rule 12 applies: K5 is gated on firing the hook once against
the installed build, not on this page.

### M-INS-24

**Two of the vendor's pages disagree about whether `permissionDecision: "allow"`
alone skips the approval menu**, and the disagreement is about the interactive
case rubricator runs in. The sentence saying allow alone is insufficient sits
inside a paragraph scoped to non-interactive `-p`; the table row above it is
unqualified; and `permission-modes`' list of *actions no mode auto-approves* does
not include `ExitPlanMode`. Both pages fetched 2026-08-23. This is why the
question is open rather than answered — see `M-GAP-5`.

### M-INS-25

**`--link` does not populate `$PREFIX/share` at all**, which is why K1's *done
when* compares the copy install against the repository rather than against a
`--link` install. `install.sh:54` deletes the directory and `:56` points `SHARE`
at the checkout. Read at those lines; visible in the sandbox as an absent
`$LINK/share/rubricator`.

### M-INS-26

**Line attributions corrected against the working tree.** The register and the
findings that fed it cited several lines that had drifted:

| cited | actual |
|---|---|
| `install.sh:56-62` (the copy list) | `install.sh:58-62`; the loop is on **59**, `hook.py` on **62** |
| `install.sh:76` (`grep -v`) | `install.sh:79` |
| `install.sh:89-92` (the PATH note) | `install.sh:96-99` |
| `install.sh:100+` (`Done.`) | `install.sh:106-115` |
| `install.sh:73` (zsh-only) | `install.sh:74` |
| "37 paths ever" | **39** |
| "nineteen headings" in the README | **20** |

Method: `sed -n '<n>p' <file>` on each, and the two counts from `M-INS-12` and
`M-POS-2`.

Every other `file:line` in `install-plan.md` was opened the same way against
`a63e540` and is exact: `bin/md` 27, 103, 109, 111, 149, 165, 185, 248, 266, 270,
289, 300, 308-316, 380, 417; `install.sh` 3, 20, 48, 54, 56, 59, 62, 68, 79,
96-99, 102, 106-115; `share/template.html` 321, 322, 323, 364; `share/render.js:1`;
`share/review.js:570`; `share/hook.py` 20, 30-55, 35, 40-41, 50-51, 108, 200;
`share/actions.py:230`; `README.md` 15, 26, 43, 46, 52, 54.

### M-INS-27

**`uninstall.sh` round-trips cleanly.** Install into a sandbox with a two-line
`.zshrc`, uninstall, compare:

```
$ cmp $H/.zshrc $H-rc-orig       # identical, byte for byte
```

`uninstall.sh:29` trims trailing blank lines to achieve that. It leaves empty
`~/.local/bin` and `~/.local/share` directories and does not touch
`~/.config/rubricator/`, `.rubricator/` in repositories, or the
`.git/info/exclude` line.

---

# The signals

Covers `signals-plan.md`. The Python figures come from importing
`share/workspace.py` and calling `build()`, `load_sessions()`, `find_docs()` and
`git_activity()` directly against the five repositories; the JavaScript figures
from porting the named function into node and running it against the real index.

### M-SIG-1

**What the shipped phrase matcher returns on real corpora.** `count()`
(`workspace.js:157-162`) is a case-insensitive `indexOf` of the whole query
string; `docScore` (`:195-203`) is the ranking caller. Ported verbatim and run
against the built index:

```
repo B (330 docs)
  auth 132 · auth flow 2 · flow auth 0 · authentication flow 0
  rate limit 17 · limit rate 0 · database schema 1 · schema database 0
repo C (502 docs)
  auth 153 · auth flow 0 · authentication flow 1 · rate limit 2
```

Method: build the index with `workspace.build([root])`, reimplement `count()` and
`docScore()`'s field weights (name ×14, title ×8, path ×6, headings ×4, body ×1)
in Python, and count documents scoring above zero.

### M-SIG-2

**Thirty-seven two-word queries, each built from two words of a real document's
own title: the shipped matcher returns zero for 25 of 37 (68%); AND-of-terms
returns zero for none.**

```
phrase (indexOf, what ships today) returns ZERO hits: 25/37  (68%)
AND-of-terms                       returns ZERO hits:  0/37  ( 0%)
```

Method: from the repo B index, take documents whose title has at least two
words of four characters or more, emit one query per document as two of those
words, then score each query twice — once through the ported `count()`, once
requiring every term. The generated query list is not recorded; see `M-GAP-1`.

### M-SIG-3

**AND alone converts *no results* into *all results*: `business match` goes from
0 hits to 111, `reads that` from 1 to 132.** Same harness as `M-SIG-2`, on the
repo B corpus. This is the measurement that makes L1 an **M** rather than an
**S** — the ranking half is not optional.

### M-SIG-4

**`⌘K` on a fresh window returns 0 rows on repo B where the Search surface
returns 132**, and 3 against 153 on repo C.

Method: `workspace.py:459` strips `text` from every document in serve mode, so
reimplement `palSearch.hit` (`workspace.js:1341-1344`) with `d.text` undefined and
count rows. The Search-surface figure is `M-SIG-1`'s. Both surfaces, same corpus,
same window.

### M-SIG-5

**Two surfaces silently flip `⌘K` to full text**: the Search surface via
`needText()` (`workspace.js:883` → `:1484`) and the All navigator via `navAll`
(`:1264`), after which `textAll` stays true until a reindex resets it (`:1505`).
The default navigator mode is `docs` (`shell.js:19`), so a fresh window is
filename-only. Found by `grep -n ensureAllText share/*.js`, then reading each
call site.

### M-SIG-6

**The Stale detector, per repository.** Both JavaScript predicates —
`isStale` (`workspace.js:301-305`) and `viewStale` (`:365-369`) — reimplemented
exactly against a real `build()`:

| repo | docs | zero-target | nav ⚠ (`isStale`) | Stale surface (`viewStale`) | judgeable | flagged of judgeable |
|---|---:|---:|---:|---:|---:|---:|
| rubricator | 11 | 5 (45.5%) | 0 | 0 | 6 | 0 (0.0%) |
| repo A | 99 | 87 (87.9%) | 6 | 0 | 12 | 6 (50.0%) |
| repo B | 330 | 125 (37.9%) | 177 | 154 | 205 | 177 (86.3%) |
| repo D | 84 | 18 (21.4%) | 61 | 0 | 66 | 61 (92.4%) |
| repo C | 502 | 179 (35.7%) | 231 | 129 | 323 | 231 (71.5%) |

Every headline figure in `signals-plan.md` §6 is a cell of this table: the
*87 of 99*, the *61 warning triangles beside an all-clear*, the
*71.5% · 86.3% · 92.4%*, and the corpus-wide 46.0% (231/502) and 53.6% (177/330)
that §10 warns against re-deriving.

### M-SIG-7

**The disagreement between the two predicates is one-directional on every corpus
tested** — the navigator is always a superset, never the reverse. Same harness as
`M-SIG-6`, comparing the two result sets per document: 23 nav-only on repo B,
102 on repo C, 61 on repo D, 6 on repo A, 0 surface-only anywhere.

### M-SIG-8

**`viewStale` truncates at 40 rows and says nothing**: `rows.slice(0, 40)` at
`workspace.js:375`. repo C hides 89 of 129 (69%), repo B 114 of 154
(74%). Arithmetic on `M-SIG-6`'s surface column.

### M-SIG-9

**`targetChurn` correlates r = 0.84 with the number of targets a document
resolved and r = 0.12 with the document's age.** On repo B, over all 330
documents, Pearson on the two pairs of vectors taken from `build()`'s `stale`
map. The cap at `workspace.py:178` — `sorted(targets)[:40]` — saturates the top:
repo B's top three documents all sit at exactly 40 targets.

### M-SIG-10

**The resolver picks arbitrarily about one time in ten.** `workspace.py:168-173`
takes the first path whose suffix matches and breaks. Counted over every token the
shipped regex matches:

| repo | tokens | ≥2 tracked paths match | 0 paths match |
|---|---:|---:|---:|
| repo B | 2,869 | 247 (9%) | 142 (5%) |
| repo C | 3,153 | 359 (11%) | 136 (4%) |

Method: run the regex from `workspace.py:168` over each document's text, and for
each token count how many entries of `all_paths` it suffix-matches.

### M-SIG-11

**Widening the target whitelist, priced as specified: 5.03 s on repo C and
1.12 s on repo B, against a whole index of 0.44 s.** The widened regex is
`` [`"']([\w./@+-]+)[`"'] `` with tokens of three characters or more, keeping the
existing `for p in all_paths: if p.endswith(t)` loop — 40,204 tokens against 4,789
paths. With a suffix dictionary built once it is 0.009 s to build plus 0.028 s to
match, and no version of the proposal says to build one.

### M-SIG-12

**Widening makes the over-firing worse**: repo C goes from 46% of the
corpus flagged to 62%.

| repo | zero-target shipped → widened | nav ⚠ shipped → widened |
|---|---|---|
| rubricator | 5 → 3 | 0 → 1 |
| repo A | 87 → 58 | 6 → 29 |
| repo B | 125 → 93 | 177 → 212 |
| repo D | 18 → 16 | 61 → 61 |
| repo C | 179 → 130 | 231 → **309** |

Same harness as `M-SIG-6`, with the extractor swapped for the widened one.

### M-SIG-13

**`all_paths` comes from the git log, not from `git ls-files`.**
`workspace.py:158` is `list(commits.keys())`, and `commits` is built from
`git log --since='2 years ago' --name-only`. On repo C that is **4,789 log
paths against 3,363 tracked files**: 1,450 no longer exist and 24 tracked files
never appear.

```
$ git -C <repo> log --since='2 years ago' --name-only --pretty=format: \
    | sort -u | grep -v '^$' | wc -l         # 4789
$ git -C <repo> ls-files | wc -l             # 3363
```

### M-SIG-14

**`repo_churn` costs 26% of the git pass and is read by nothing.**

```
$ grep -rn repoChurn share/*.js              # no output
```

`git_activity` on repo C, min of three warm runs: **0.323 s** with the
`repo_churn` line, **0.238 s** with it commented out, inside a whole build of
0.44 s. `stem` at `workspace.py:167` is a second dead local in the same loop.

### M-SIG-15

**Index build timings and payload sizes**, min of three warm runs with
`RUBRICATOR_CACHE` pointed at scratch:

| repo | docs | find+read | `git_activity` | build | `emit_html` | static page | JSON payload |
|---|---:|---|---|---|---|---:|---:|
| rubricator | 11 | 0.01 s | 0.01 s | 0.02 s | 0.05 s | 7.3 MB | 1.7 MB |
| repo A | 99 | 0.01 s | 0.01–0.03 s | 0.02 s | 0.05 s | 8.2 MB | 2.1 MB |
| repo D | 84 | 0.02 s | 0.05–0.19 s | 0.07–0.08 s | 0.07 s | 9.6 MB | 2.8 MB |
| repo B | 330 | 0.08 s | 0.16–0.42 s | **0.23–0.25 s** | 0.08 s | 13.7 MB | **6.6 MB** |
| repo C | 502 | 0.11 s | 0.33–0.64 s | **0.44–0.46 s** | 0.12 s | 24.4 MB | 10.2 MB |

Cold-ish first run, before anything was warm: repo C 0.95 s, repo B
0.53 s. The 0.44 s and the 6.6 MB are the two cells the plans cite.

### M-SIG-16

**The seven disk-blind annotation read sites**, all in `share/workspace.js`: 259,
299, 387, **774**, 1233, 1303, 1380. Found by reading `annosFor` (`:116-123`) and
`allAnnos` (`:124-126`) and then grepping every caller. Six of the seven are found
by `grep -n "i.state !== 'stale'"`; **the dossier at `:774` is written without
spaces and is missed by that grep** — which is how the earlier enumerations lost
it, and it is the only site that ships wrong data out of the tool into an agent
prompt.

`Storage.get`, the one disk-aware reader, has exactly one caller:

```
$ grep -rn "Storage.get\|storage.get" share/*.js
# the definition at workspace.js:76, and review.js:47
```

### M-SIG-17

**The live tier gets a new origin on every run**, so `localStorage` starts empty
every time rather than only on the first run. `serve.py:38` binds
`("127.0.0.1", 0)` — an ephemeral port — and `bin/md:165` launches the workspace
with no `--port`. `md serve --port N` (`bin/md:80`, `:235`) is the one path with a
stable origin. Confirmed by three consecutive `md --review` runs landing on three
different ports.

### M-SIG-18

**Chrome's store holds 31 `md-review:*` records across 21 distinct origins; five
hold any items, eight items in total.** See `M-ANC-9` for the method — the same
LevelDB read produces `M-ANC-9` and this figure.

### M-SIG-19

**The index cannot see an untracked file.** `find_docs` (`workspace.py:32-40`)
builds from `git ls-files` and returns as soon as any tracked file exists, which
makes the `os.walk` fallback below it unreachable in a real repository.

```
$ git init -q scratch && cd scratch
$ echo '# a' > a.md && git add a.md && git commit -qm a
$ echo '# b' > b.md                       # untracked
$ python3 -c "import workspace as W; print([d['rel'] for d in W.find_docs(...)])"
['a.md']
$ git add b.md                            # no commit
# both
```

### M-SIG-20

**Unioning in untracked files costs 23 ms on repo C, against 19 ms for the
call already being made.** Timed as `git ls-files --others --exclude-standard`
versus `git ls-files -z`, min of three warm runs.

### M-SIG-21

**Across four active repositories there are 0, 0, 2 and 3 untracked markdown files
right now** — the snapshot that makes L5 an **S** rather than an emergency.

```
$ git -C <repo> ls-files --others --exclude-standard '*.md' | wc -l
```

### M-SIG-22

**Zero `.mdc` files exist anywhere under `~/Repositories`**, which is the whole
argument for and against adding `.mdc` to `MD_EXT`.

```
$ find ~/Repositories -name '*.mdc' -not -path '*/node_modules/*' | wc -l   # 0
```

### M-SIG-23

**The slash filter drops 756 of 4,750 records (15.9%), of which 71 (1.5%) are
genuinely lost content.**

```
known-noise commands (/model, /compact, /clear, /effort, /context, /resume, …): 623
non-noise, bare, no arguments:                                                   62
non-noise, WITH arguments (actual lost content):                                 71
distinct slash commands: 46
top: /model 195 · /compact 159 · /clear 142 · /effort 28 · /goal 24 · /resume 23
```

Method: parse every line of `~/.claude/history.jsonl` as JSON, take `display`,
select those matching `workspace.py:233`'s `txt.startswith("/")`, then split the
first token against a hand-written noise list and test for arguments. The filter
line itself:

```
$ grep -n 'startswith("/")' share/workspace.py
233:                if not txt or txt.startswith("/"):        # slash commands aren't topics
```

### M-SIG-24

**Two slash commands named in the finding that proposed indexing them occur zero
times in this machine's entire history.** Same parse as `M-SIG-23`, counting the
first token. `/plan-feature` occurs 23 times; the other two occur 0 times each.
This is the confabulated detail inside a finding marked *verified*, and the reason
every number in `signals-plan.md` was re-measured.

### M-SIG-25

**The 600-character cap drops 86,020 characters — 13.6% of all indexed prompt
text — from 127 prompts (3.2%).**

```
indexed prompts: 3,995 · 634,579 chars total
prompts > 600 chars: 127 (3.2%)
chars dropped by [:600]: 86,020 = 13.6%
```

Method: the same parse as `M-SIG-23`, but over the *surviving* records, applying
`workspace.py:237`'s `scrub(txt)[:600]` and summing the difference. This
denominator is the index as it stood at 20:10; `M-RET-7` re-counts the same file
at 21:20 and gets 3,998 prompts. The share is what the item turns on, and the
share does not move.

### M-SIG-26

**The toast that reports a failed disk write clears itself after 1,900 ms** and is
the only report of the failure. Read at `workspace.js:96` (the call) and `:140`
(the timeout); the tray's own copy of `toast()` is `review.js:195`. `toast('note
not saved to disk')` appears nowhere else:

```
$ grep -rn "not saved to disk" share/
```

### M-SIG-27

**Nothing on this machine records a `/notes` POST ever having failed, and no hook
review has ever been recorded.** Absence of evidence, and the plans say so:
`~/.local/state/rubricator` does not exist (`M-RET-16`), and the hook writes
nothing else. This is an absence, not a zero — see `M-GAP-8`.

### M-SIG-28

**The hook window writes nothing to disk, by construction.** `hook.py:143-150`
renders the plan through the static tier into a temp file, `:221-223` unlinks it,
`hook.py:70-96` serves exactly two paths and neither is `notes`, and
`hook.py:231-232` sleeps 0.35 s past the deadline before AppleScripting the window
shut. Read at those lines; the static render was dumped and checked for a `DISK`
override and a notes payload — neither is present.

### M-SIG-29

**`innerHTML =` appears 34 times across `workspace.js` (11), `shell.js` (15) and
`review.js` (8)** — the measurement that prices the roving-tabindex proposal at a
week rather than an evening.

```
$ grep -c 'innerHTML =' share/workspace.js share/shell.js share/review.js
```

### M-SIG-30

**The Coverage inverse map: 916 of 1,702 tracked repo B code files (54%) and
1,223 of 2,169 on repo C (56%) are named by no document.** Method: take
`build()`'s resolved target set, subtract it from the tracked file list filtered
to the twelve code extensions, and count. This is X12's own arithmetic, and it is
why the surface would ship a 1,223-row to-do list.

### M-SIG-31

**The Stack Overflow 2025 trust figures** quoted in §2 — the 33,244 per-question
n, the 46% / 33% / 3% — are external and are card **D1** in `citations.md`,
quoted in the wording cleared there, with the instruction to quote the
per-question n rather than the 49,000 total.

### M-SIG-32

**Every `file:line` in `signals-plan.md` was opened against `a63e540`.** Method:
`sed -n '<n>p' <file>` on each, and `sed -n '<a>,<b>p'` on each range. All exact:

`workspace.js` 74-98, 96, 114-118, 140, 157-162, 207, 235, 250, 259, 299,
301-305, 309, 315, 321, 365-369, 370, 375, 387, 774, 883, 972, 1013, 1144-1146,
1233, 1263, 1303, 1341-1344, 1354, 1380, 1419, 1484, 1506 · `shell.js` 19, 290 ·
`review.js` 47, 195, 596-600, 611, 615, 664-676 · `workspace.py` 32-40, 167, 175,
179, 233, 237, 459, 513-548, 576, 647, 650-657 · `serve.py` 38 · `bin/md` 165 ·
`hook.py` 70-96, 118, 129, 143-150, 221-223, 231-232 · `README.md` 215 ·
`docs/workspace-plan.md` 42, 174 · `docs/tasks.md` 77.

Two corrections the plan carries over the register belong here, because they are
reads and not measurements. The register's L4 acceptance line asks for
`grep -c repoChurn share/*.js` to be 0, which is already true (`M-SIG-14`); the
deletion is `workspace.py:175` and the `"repoChurn"` key at `:179`, not `:178`,
which is `"targets": sorted(targets)[:40]`. And the register's L2 quotes a shipped
string, `N by name — loading full text…`, that is not in the code; the sentence
that is shipped is at `workspace.js:207` and `:250`.

---

# Anchoring

Covers `anchoring-plan.md`. Two different block extractors were used and their
results must not be multiplied; `M-ANC-2` and `M-ANC-3` say which is which.

### M-ANC-1

**The corpus: every git-tracked `*.md` in the five repositories — 1,009 files, 579
of them with more than one revision, giving 2,985 consecutive commit pairs in
which the blob actually changed.**

Method: for each file, `git log --follow --format=%H -- <path>` oldest to newest,
then every consecutive pair whose blob hash differs; both revisions read with
`git show <sha>:<path>`.

### M-ANC-2

**The survival funnel: 104,341 substantive anchors over those pairs, 93.4%
survive `indexOf`, 6.6% (6,896) vanish.** Of the vanished, the share with a
similar surviving block is 38.6% at 0.90, 45.9% at 0.85, 58.0% at 0.75 and 68.7%
at 0.60.

| repo | pairs | anchors | vanish | substantive | vanish | 0.90 | 0.85 | 0.75 | 0.60 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| rubricator | 48 | 3,310 | 172 | 1,925 | 132 | 26.5% | 33.3% | 44.7% | 54.5% |
| repo A | 154 | 3,883 | 209 | 2,248 | 209 | 54.5% | 74.6% | 92.3% | 97.1% |
| repo D | 106 | 8,521 | 256 | 6,283 | 232 | 42.2% | 51.3% | 62.1% | 77.6% |
| repo B | 470 | 37,323 | 1,554 | 20,743 | 1,279 | 28.6% | 35.3% | 45.6% | 55.9% |
| repo C | 2,207 | 119,311 | 5,625 | 73,142 | **5,044** | 40.6% | 47.5% | 59.9% | 70.7% |
| **all** | **2,985** | 172,348 | 7,816 | **104,341** | **6,896** | **38.6%** | 45.9% | 58.0% | **68.7%** |

**The extractor is the faithful one**: an exact port of `mapLines()` +
`srcSlice()` + `addItem()` driven by rubricator's own vendored marked 15.0.12
under `render.js`'s options (`gfm:true, breaks:false`) and its front-matter split,
with heading tokens additionally yielding the single-line section anchor.
Survival is literally `rawNext.indexOf(anchor) >= 0`, which is `review.js:119`.
*Substantive* means an anchor of 40 characters or more whose token type is not
`hr`. Similarity is `difflib.SequenceMatcher(autojunk=False)` against the block
anchors of the next revision.

Two caveats travel with it: this treats every block as if annotated, which no real
user does; and 6.6% is a base rate over random commits, not the rate for the case
that matters — conditional on the agent rewriting the passage you marked,
destruction is close to certain, and no corpus-wide rate speaks to that.

### M-ANC-3

**The recovery table — a different extractor and four repositories, not five.**

| strategy | three repos, 444 vanished | precision | repo B, 1,056 vanished | precision |
|---|---:|---:|---:|---:|
| whitespace-normalised `indexOf` | 1 (0.2%) | — | 0 (0.0%) | — |
| first line of the block | 210 (47.3%) | 99.5% | 273 (25.9%) | 97.4% |
| **longest surviving line** | **278 (62.6%)** | **98.6%** | **425 (40.2%)** | **96.5%** |
| fuzzy, cutoff 0.90 | 187 (42.1%) | 98.9% | 312 (29.5%) | 94.6% |
| fuzzy, cutoff 0.75 | 295 (66.4%) | 98.3% | 503 (47.6%) | 95.0% |
| fuzzy, cutoff 0.60 | 345 (77.7%) | 97.7% | 621 (58.8%) | 94.8% |

Method: a blank-line block splitter, restricted to blocks of 40 characters or
more, dropping any block opening with `---`, `|` or a code fence. For each block
that `indexOf` loses between consecutive revisions, apply each strategy and record
whether it re-attaches. **Precision** is the share of re-attachments that land on
the block an independent alignment says is correct — a `difflib` alignment over
the block *sequence*, driven by which blocks are identical rather than by
per-block text similarity, so it is not a restatement of the thing being measured.

**Do not multiply a figure from this table by one from `M-ANC-2`.** The sets are
not the same: this splitter also loses tables and fenced code that the funnel
keeps, and this run omits repo C, which contributes 5,044 of the funnel's
6,896 vanished substantive anchors.

### M-ANC-4

**The wrong-match rate is flat on repo B across thresholds — 5.2% at 0.60, 5.0%
at 0.75, 5.4% at 0.90 — while on the three smaller repositories it falls, 2.3% →
1.7% → 1.1%.** Arithmetic on `M-ANC-3`'s precision column, and the finding that
kills *pick a higher cutoff* as a safety measure: the wrong matches on repo B
are near-duplicate boilerplate, which a threshold cannot separate and position
can.

### M-ANC-5

**1,636 of 1,851 thematic-break anchors across the five repositories (88.4%)
resolve to the wrong offset, and 127 land on byte 0** — the file opens with YAML
front matter and its opening `---` is the first match in the buffer.

Method: for every anchor the extractor would store, compare `raw.indexOf(anchor)`
against that anchor's own byte offset, grouped by marked token type.

### M-ANC-6

**Section and block anchors that `indexOf` resolves to the wrong offset**, same
method as `M-ANC-5`:

| repo | section anchors | wrong | block anchors | wrong |
|---|---:|---:|---:|---:|
| rubricator | 147 | 0 (0.00%) | 599 | 58 (9.68%) |
| repo A | 458 | 0 (0.00%) | 1,292 | 23 (1.78%) |
| repo B | 4,394 | 62 (1.41%) | 13,525 | 993 (7.34%) |
| repo C | 5,776 | 13 (0.23%) | 16,891 | 603 (3.57%) |
| repo D | 1,135 | 7 (0.62%) | 4,027 | 193 (4.79%) |

The five-repo section figure is 82 of 11,910 — **0.69%**, not the 2.66% of
`M-ANC-7`, because a duplicate group of two produces one mis-anchor and not two.
**Four of the 82 are substring collisions with no exact duplicate anywhere**
(`raw.indexOf("## Scope")` matching inside an earlier `### Scope`), which is why
counting duplicate heading *lines* structurally undercounts.

### M-ANC-7

**The duplicate-heading rate, measured as both earlier lenses measured it** — the
share of heading lines duplicated within their own file, at `HEAD`:

| repo | plan files | headings | duplicated | other files | headings | duplicated |
|---|---:|---:|---:|---:|---:|---:|
| rubricator | 7 | 87 | 0.00% | 4 | 60 | 0.00% |
| repo A | 55 | 286 | 0.00% | 39 | 172 | 0.00% |
| repo B | 88 | 2,254 | **2.66%** | 240 | 2,140 | 0.37% |
| repo C | 115 | 1,796 | 1.11% | 377 | 3,980 | 0.10% |
| repo D | 30 | 542 | 0.00% | 54 | 593 | 1.69% |

Corpus-wide: 102 duplicated headings in 11,910, or 0.86%. *Plan file* is a path
containing `plan` or living under `docs/plans/`.

**This is the metric `anchoring-plan.md` §7 retires.** It reproduces, both
contradicting lenses were right about their own corpora, and it is not the
mis-anchor rate. The number that replaces it is `M-ANC-8`.

### M-ANC-8

**Eight mis-anchors in 25,094 anchors a human would plausibly mark — 0.03%.**
Same method as `M-ANC-5`, restricted to anchors of 40 characters or more that are
not thematic breaks:

```
rubricator      0 / 407      0.00%
repo A     0 / 902      0.00%
repo B        2 / 9,072    0.02%
repo C   6 / 11,681   0.05%
repo D        0 / 3,032    0.00%
                8 / 25,094   0.03%
```

### M-ANC-9

**Three real annotations on two documents, plus five on a throwaway fixture.**
On disk, `find ~ -type d -name .rubricator` returns exactly three directories, two
of them holding `{}`. In the browser, Chrome's `Default/Local Storage/leveldb`
holds **31 `md-review:*` records across 21 distinct origins** (one `file://` and
20 ephemeral `127.0.0.1:<port>`), of which **five hold any items, eight items in
total**; ten further records are real documents opened with the review layer live
and closed without a verb pressed.

Method: a minimal LevelDB sstable reader plus a snappy decompressor written for
this pass — no third-party packages — reading Chrome's leveldb directory
directly, then resolving each storage key back to a document by re-implementing
rubricator's own djb2 `hash()` (`review.js:29`) and hashing every candidate path
on the machine. The reader is a scratch script and is not committed; the
description above is enough to rewrite it, and `M-GAP-9` records what that costs.

One of the three real notes lives in Chrome's localStorage, in no `notes.json`,
in a repository with no `.rubricator` directory at all — the casualty
`signals-plan.md` §5 and `anchoring-plan.md` §10 both point at.

### M-ANC-10

**`review.js:119` is `raw.indexOf(it.anchor)` — exact substring, first occurrence,
no normalisation, no offset hint, no fallback — and there is no hash anywhere near
it.** `hash()` has one definition (`review.js:29`) and one call site (`:44`), and
it builds the localStorage key from the document *path*.

```
$ sed -n '116,132p;29p;44p' share/review.js
$ grep -n 'hash(' share/review.js
```

`reanchor()` is called from `openDoc()` at `review.js:564` — every open, every tab
return, every watch reload, every reindex.

### M-ANC-11

**Eleven fields are stored per item and none of them is a timestamp**:
`id, verb, quote, anchor, note, lineStart, lineEnd, partial, section, heading,
state`. The only clock in the file is one `store.saved` epoch per document,
written by `save()` (`review.js:51-54`). Read at `addItem()`,
`review.js:249-255`.

### M-ANC-12

**`.rubricator/notes.json` on this machine is 1,412 bytes with a single key — an
absolute path — and two items.** The key is
`~/Repositories/rubricator/README.md`; both items anchor to the same two-line
couplet, so `reanchor()` will move both to the same place forever and the export
will emit the paragraph twice.

```
$ wc -c ~/Repositories/rubricator/.rubricator/notes.json    # 1412
$ python3 -m json.tool ~/Repositories/rubricator/.rubricator/notes.json | head
```

### M-ANC-13

**The library that was measured and refused.** Fetched 2026-08-23:
`match-quote.ts` is **163 lines** and comes from `hypothesis/client`, which
declares `"license": "BSD-2-Clause"`; `approx-string-match`'s `src/index.ts` is
**362 lines**, MIT, with `dependencies: null`. 163 + 362 = **525**; stripped of
comments and blank lines, 94 + 174 = **268**. `robertknight/anchor-quote` returns
`license: null`, `created_at: 2019-05-26`, `pushed_at: 2019-06-30`.

```
$ curl -sS https://raw.githubusercontent.com/hypothesis/client/main/package.json
$ curl -sS https://raw.githubusercontent.com/hypothesis/client/main/src/annotator/anchoring/match-quote.ts
$ curl -sS https://raw.githubusercontent.com/hypothesis/client/main/LICENSE
$ curl -sS https://raw.githubusercontent.com/robertknight/approx-string-match-js/master/src/index.ts
$ curl -sS https://registry.npmjs.org/approx-string-match
$ curl -sS https://api.github.com/repos/robertknight/anchor-quote
```

Line counts are `wc -l` on the fetched files. The port's recovery and precision
are `M-ANC-3`'s *fuzzy* rows.

### M-ANC-14

**Real markdown revisions are small: across 2,982 revisions the median changes 6
to 20 lines and rewrites 2.1%–3.8% of the file, and wholesale rewrites are
0.0%–3.2%.**

| repo | revisions | median changed lines | p90 | median fraction rewritten | wholesale (>50%) |
|---|---:|---:|---:|---:|---:|
| rubricator | 48 | 19 | 50 | 3.8% | 2.1% |
| repo A | 154 | 6 | 29 | 3.7% | 0.0% |
| repo B | 470 | 7 | 48 | 2.1% | 3.2% |
| repo C | 2,204 | 13 | 70 | 3.5% | 2.1% |
| repo D | 106 | 20 | 129 | 3.3% | 2.8% |

Method: for each consecutive revision pair, `difflib` over the two line lists,
counting changed lines and dividing by the file length. **This is a separate run
from `M-ANC-1`** — a different script over a slightly different file set, which
is why it reports 2,982 pairs where the funnel reports 2,985. The difference of
three is the whole of the discrepancy and neither number is wrong.

### M-ANC-15

**`write_notes` does write the `.git/info/exclude` line, and the register's
report that a fresh clone shows untracked noise does not reproduce.** What does
reproduce is one level down — a root that is a *subdirectory* of a repository:

```
$ git clone -q ~/Repositories/rubricator clonetest && cd clonetest
$ python3 -c "…; W.write_notes(root, str(root/'README.md'), {'items':[{'id':1}]})"
exclude has entry: True
$ git status --porcelain
$

$ git clone -q ~/Repositories/rubricator clonetest2 && cd clonetest2
$ python3 -c "…; W.write_notes(pathlib.Path('docs').resolve(), …, {'items':[{'id':1}]})"
root exclude touched: False
$ git status --porcelain
?? docs/.rubricator/
```

`.rubricator/` is excluded in rubricator's own checkout via
`.git/info/exclude:7`, a machine-local file, and is **not** in `.gitignore`:

```
$ git -C ~/Repositories/rubricator check-ignore -v .rubricator/notes.json
.git/info/exclude:7 ...
```

### M-ANC-16

**The pane invariant bug (M7) is traced in code and has not been reproduced in a
browser.** The trace: the verb handler at `review.js:518` is bound to `document`
and its only guard is `live()`, which asks whether the *bound* document is
visible; `blocks` and `focusIdx` belong to the bound document and `focusIdx` is
last set by `onHover`, attached only to that document's element
(`review.js:503-517`); `openDoc()` resets `focusIdx` to `-1` at `:556` and
`addFromBlock` guards `if (!el)` at `:272`, which is why a first hover in the
source pane is a precondition. `shell.js:390-396` focuses a pane on `mousedown`,
which is why the mouse path is safe. `anchoring-plan.md` §11 states this as a
trace, not a reproduction.

### M-ANC-17

**The 30-day transcript retention quote** that closes §11 is Anthropic's own
documentation, fetched 2026-08-23. It is card F1 in `citations.md` and is quoted
from there, in that wording. The count of transcript files older than thirty days
on this machine is `M-RET-4`.

### M-ANC-18

**Every `file:line` in `anchoring-plan.md` was opened against `a63e540`**, by
`sed -n '<n>p'`. All exact: `review.js` 20, 29, 44, 57, 119, 122, 125, 162-173,
249-255, 272, 347, 370, 414, 503-517, 518, 552, 556, 564 · `workspace.js` 960-961,
1002 · `workspace.py:526` · `shell.css:101` · `shell.js:390-396` ·
`README.md` 122, 285, 459 · `docs/documents-plan.md:72` ·
`docs/review-design.md:244`.

**One off-by-one, and it is in the plan's favour to state it.** The plan cites
`docs/review-design.md:141-142` for the per-item *quote-hash*; the phrase is on
**142** alone. The plan also silently corrects the register, which cites
`docs/review-design.md:245` for the maintainer's stale/resolved question — it is
on **244**.

---

# Retention

Covers `retention-plan.md`. Two clocks matter here: the *verify* run at 20:10
local and the *re-run for the document* at 21:20. Where a figure moved, both are
given, because the movement is itself the finding.

### M-RET-1

**452 sessions in `~/.claude/history.jsonl` back to 2026-04-17, a span of 127.97
days; 71 main transcripts; 68 in common; 384 sessions (85.0%) findable and
unreadable.**

```
python3 - <<'PY'
import json
from pathlib import Path
H = Path.home(); sess = {}
for line in (H / '.claude/history.jsonl').open(encoding='utf-8', errors='replace'):
    try: d = json.loads(line)
    except Exception: continue
    if d.get('sessionId'): sess.setdefault(d['sessionId'], d.get('timestamp', 0))
mains = list((H / '.claude/projects').glob('*/*.jsonl')); names = {p.stem for p in mains}
lo, hi = min(sess.values()) / 1000, max(sess.values()) / 1000
lost = set(sess) - names
print(len(sess), "sessions · %.2f days" % ((hi - lo) / 86400))
print(len(mains), "main transcripts ·", len(set(sess) & names), "in common ·",
      len(lost), "unreadable (%.1f%%)" % (100 * len(lost) / len(sess)))
PY
```

**Re-run at 21:20: 454 sessions, 79 transcripts, 70 in common, 384 unreadable —
84.6%.** The count of lost sessions did not move; the percentage fell because the
denominator grew. Quote the 384.

### M-RET-2

**`wc -l ~/.claude/history.jsonl` is 4,749 lines and is not the session count.**
It grew to 4,750 mid-run. A reader who reaches for the shorter command is off by
an order of magnitude, which is why `retention-plan.md` §1.3 names the
substitution and forbids it.

### M-RET-3

**The oldest main transcript is 29.44 days by mtime and none is older than 30;
the oldest readable *content* is dated 2026-06-05, 79 days back.** The sweep keys
on mtime, so one surviving file holds 7,563 timestamped records running
2026-06-05 to 2026-07-19.

```
$ find ~/.claude/projects -maxdepth 2 -name '*.jsonl' -mtime +30 | wc -l   # 0 at depth 1
```

Content age is a walk over each main transcript reading the first line's
`timestamp` — one `json.loads` of the first line per file, sorted ascending.

### M-RET-4

**443 transcript files on this machine are older than 30 days, every one of them a
subagent transcript.** Subagent transcripts are removed *with* their parent, so
they age on the parent's mtime.

```
$ find ~/.claude/projects -name '*.jsonl' -mtime +30 | wc -l      # 443
$ find ~/.claude/projects -name '*.jsonl' | wc -l                 # 660
$ find ~/.claude/projects -maxdepth 2 -name '*.jsonl' | wc -l     # 71 main
```

589 of the 660 are subagent transcripts.

### M-RET-5

**`du -sh ~/.claude/projects` is 960 MB accumulated in one 30-day window**, which
is about 11.4 GB/year at that rate. The extrapolation is arithmetic on the
directory size and the retention window, not a measurement of a year.

### M-RET-6

**`cleanupPeriodDays` is absent from `~/.claude/settings.json`, so the default
applies**, and the sweep marker shows it ran the same day.

```
$ grep -c cleanupPeriodDays ~/.claude/settings.json || true    # 0
$ ls -l ~/.claude/.last-cleanup                                # 2026-08-23T15:39:01Z
$ ls -a ~/.claude | grep -i 'trash\|deleted'                   # nothing
```

There is no trash directory anywhere under `~/.claude`, no restore command in the
documentation, and no recovery path. That absence is the basis for calling the
loss effectively unrecoverable at the application level; it was not verified at
the syscall level.

### M-RET-7

**What rubricator leaves in its cache**, re-measured at 21:20:

| | |
|---|---|
| `~/.cache/rubricator/index/sessions.json` | 1,507,930 bytes, mode 0644 |
| its contents | **3,998 prompts · 419 sessions · 1,313 file paths · 20 project directories** |
| `~/.cache/rubricator/index/sessions-deep.json` | 1,577,153 bytes, mode 0644 |
| `~/.cache/rubricator/workspace-<hash>.html` | 7,984,399 bytes, mode 0644 |
| that page | **7,792 occurrences of `"sid"`** |
| files under the cache root | **33 of 33 world-readable**, dirs 0755, 34 MB total |

```
$ python3 -c "import json,os;d=json.load(open(os.path.expanduser(\
'~/.cache/rubricator/index/sessions.json')))['data'];print(len(d['prompts']),\
'prompts ·',len(d['sessions']),'sessions ·',len(d['touches']),'paths ·',\
len({m['p'] for m in d['sessions'].values()}),'dirs')"
$ ls -l ~/.cache/rubricator/index/ ~/.cache/rubricator/*.html
$ for f in ~/.cache/rubricator/*.html; do
    printf '%s ' "$(basename "$f")"; grep -o '"sid"' "$f" | wc -l
  done                                     # occurrences, not lines — grep -c says 2
$ find ~/.cache/rubricator -type f | wc -l
$ find ~/.cache/rubricator -type f ! -perm 600 | wc -l
$ du -sh ~/.cache/rubricator
```

**The source of that data is kept at 0600 inside a 0700 directory**, so this is a
downgrade rather than a default:

```
$ ls -ld ~/.claude/projects ~/.claude/history.jsonl ~/.claude/projects/*/*.jsonl | head
drwx------  …  ~/.claude/projects
-rw-------  …  ~/.claude/history.jsonl
-rw-------  …  ~/.claude/projects/<project>/<session>.jsonl
```

The code to do it right is already in the repository and is read at its lines:
`actions.py:113` is `os.chmod(tmp, 0o600)` for the settings file and
`actions.py:222` is `f.chmod(0o700)` for a directory. `workspace.py:309-317`,
which writes the session index, does neither.

### M-RET-8

**The cache is not excluded from Time Machine and `~/Library/Caches` is.**

```
$ tmutil isexcluded ~/Library/Caches        # [Excluded]
$ tmutil isexcluded ~/.cache/rubricator     # [Included]
```

Whether a backup is configured, and where it writes, this does not say. The
exclusion status is the finding and it is the only part rubricator controls.

### M-RET-9

**Rendered HTML is pruned after seven days; the index JSON never is.** Read at
`bin/md:413`:

```sh
find "$CACHE" -maxdepth 1 -name '*.html' -mtime +7 -delete 2>/dev/null || true
```

`-maxdepth 1` does not reach `index/` and `-name '*.html'` does not match `.json`.
This is a read of two flags, not a measurement.

### M-RET-10

**The cache root is hardcoded in three places** — `bin/md:25`, `workspace.py:13`
and `extract.py:18` — each behind a `RUBRICATOR_CACHE` override, so moving it is a
three-site change. `grep -rn 'cache/rubricator' bin/ share/`.

### M-RET-11

**`transcript.SCRUB` is one pattern where `workspace.SECRET` is ten**, and the
comment above it claims otherwise. Read at `transcript.py:29-36` and
`workspace.py:184-204`; the mismatch is also demonstrable by importing both
modules and calling each `scrub()` on the same inputs, where seven of eight
credential shapes pass the reader unchanged.

### M-RET-12

**118 of 7,830 assistant text blocks (1.5%) match `workspace.SECRET`; the shipped
transcript scrubber matches 0.** Breakdown: 51 emails, 30 opaque blobs, 25
credential assignments, 8 authorization headers, 3 env lines, 1 connection string.

Method: import both `share/workspace.py` and `share/transcript.py`, walk every
main transcript, take every assistant `text` block, and run each of the two
`scrub()` functions over it, counting blocks whose output differs from the input.

**Re-run at 21:20: 7,876 blocks, 119 matches (1.5%), 0.** A second re-run
minutes later gave 7,880 — monotone growth on a live corpus. The share does not
move.

### M-RET-13

**The extraction cache holds 22 files of extracted plaintext, the largest
123,746 characters.**

```
$ ls ~/.cache/rubricator/extract/*.json | wc -l          # 22
$ python3 -c "import glob,json;print(max(len(json.load(open(f)).get('text','')) \
    for f in glob.glob(os.path.expanduser('~/.cache/rubricator/extract/*.json'))))"
```

What is in those files is the maintainer's own document text and is not described
further here.

### M-RET-14

**The index knows about 20 project directories where `history.jsonl` knows 18**,
because `load_sessions` fills a session's project path from the transcript's `cwd`
when history has no record of it. Both counts are in `M-RET-7` and
`M-RET-1`'s parse respectively; the 18 is `len({d['project'] for d in
history})`.

### M-RET-15

**The tool's own totals are 419 sessions and 78 resumable, where
`history.jsonl` says 452 and 68**, because `workspace.py:233` drops every record
whose text begins with `/` and a session of nothing but slash commands never
enters `meta`. Both numbers are defensible; `retention-plan.md` §6 forbids mixing
them. Method: `M-RET-7`'s parse for the first pair, `M-RET-1`'s for the second.

### M-RET-16

**`~/.local/state/rubricator` does not exist and no hook review has ever been
recorded**; `~/.claude/settings.json` is 51 lines including a `hooks` block and an
`autoMode` section; and a backup left by the hook installer under the tool's old
name is still on disk.

```
$ ls ~/.local/state/rubricator                    # No such file or directory
$ wc -l ~/.claude/settings.json                   # 51
$ ls -l ~/.claude/settings.json.bak-markside-*    # exists, 2,749 bytes
```

### M-RET-17

**Every main transcript's basename is a UUID shape, 79 of 79 at 21:20** — the
check behind N6's *derive the session id from the basename of `transcript_path`*.

```
$ ls ~/.claude/projects/*/*.jsonl | xargs -n1 basename \
  | grep -cE '^[0-9a-f-]{36}\.jsonl$'      # 79, of 79 files
```

This tests the *shape*, not that the basename equals the session id — see
`M-GAP-6`.

### M-RET-18

**Provenance coverage on two repositories at opposite ends of the retention
window: repo A 64 of 99 documents, repo B 66 of 330** — and all 64 of
repo A' come from a single session id that touched 80 files, so the join's
answer is a constant for 65% of that corpus. Method: `load_sessions()` and count
documents with a non-empty `touches[d['abs']]`; then group those documents by the
session ids in their entry. First commits: `git log --reverse --format=%ad | head
-1` gives 2026-08-18 and 2026-03-22.

### M-RET-19

**`touches` is only ever populated inside the `~/.claude/projects/*/*.jsonl`
loop** (`workspace.py:255-295`), so document↔session coverage is the retention
window exactly. Read at those lines, and confirmed by the absence of any other
writer: `grep -n touches share/workspace.py`.

### M-RET-20

**The session index is a cache of a computation that takes about one second.**
`load_sessions(deep=False)` runs in 0.75–1.02 s over 798 MB across 75 transcripts
and 162,478 lines, producing 3,995 prompts and 416 sessions; `deep=True` is no
slower (1.01 s) and only adds file-path edges, taking `touches` from 1,312 to
1,611. Min of three warm runs, timed around the imported function.

### M-RET-21

**The vendor's retention documentation** — the 30-day default, `cleanupPeriodDays`
with a minimum of 1 and `0` rejected, `history.jsonl` listed under *Kept until you
delete them*, the *Plaintext storage* section whose first mitigation is to
**lower** the retention period, and what `claude project purge` deletes — was
fetched 2026-08-23 from `code.claude.com/docs/en/{data-usage,claude-directory,
settings-reference,sessions}`. Four cards in `citations.md` carry the cleared
wordings and the plans quote from there: **F1** (the 30-day default),
**G4** (`history.jsonl` under *Kept until you delete them*), **G5** (*Plaintext
storage* and its first mitigation) and **G6** (what `claude project purge`
deletes). The `cleanupPeriodDays` minimum and the `0` rejection are on this
entry, not on a card — no plan quotes them.

```
$ curl -s https://code.claude.com/docs/en/claude-directory.md | grep -n cleanupPeriodDays
```

### M-RET-22

**The re-measure block published in `retention-plan.md` §1.3 is the reproduction
procedure for §1.1 and §1.2**, and it is deliberately incomplete: five rows need
more than a command and the block does not fake them. Those five are the two
content-age rows (`M-RET-3`), the two pattern rows (`M-RET-9` and `M-RET-11`, both
reads rather than measurements) and the scrub-gap row (`M-RET-12`).

### M-RET-23

**Every `file:line` in `retention-plan.md` was opened against `a63e540`**, by
`sed -n '<n>p'`. Correct: `README.md` 160, 228 · `bin/md` 25, 148-149, 180, 413 ·
`workspace.py` 13, 184-204, 216-222, 233, 255-295, 309-317, 383, 459, 526,
540-546 · `extract.py:18` · `actions.py` 113, 222 · `transcript.py` 29, 74, 149,
176, 200 · `workspace.js` 41, 434, 440, 1195-1197, 1200, 1203-1207, 1228, 1337,
1363, 1709-1710 · `hook.py` 20, 35, 159-179, 221-223.

Three corrections to the register that this plan carries, all of them reads:
`bin/md:413` (the register says 412), `workspace.py:184-204` for `SECRET` (an
earlier log says 196-208), and `transcript.py:200` for the unscrubbed assistant
branch (the register says 181-204). The settings file is 51 lines, not the 60 the
register carries (`M-RET-16`).

---

# Positioning

Covers `scope-plan.md`. Two kinds of figure here move on their own: GitHub
numbers, which change hourly, and the repository's own line counts, which change
on commit. Both are dated where they appear.

### M-POS-1

**7,372 lines across 18 files of own code — 7,379 with `vendor.txt`, 12,314 with
the five vendored libraries.**

```
$ git ls-files share/ bin/md | xargs wc -l | tail -1        # 7379 total
$ wc -l share/vendor.txt                                    # 7
$ wc -l share/vendor/* | tail -1                            # 4935
$ wc -l install.sh install-hook.sh uninstall.sh | tail -1   # 217
```

Per file: workspace.js 1,728 · workspace.py 835 · review.js 684 · shell.js 558 ·
bin/md 429 · template.html 422 · workspace.html 337 · render.js 308 · ui.js 298 ·
actions.py 293 · transcript.py 267 · hook.py 258 · review.css 229 · shell.css 201
· serve.py 188 · extract.py 161 · ui.css 153 · md.zsh 23 · vendor.txt 7.

*One bash script and a page* describes `bin/md` (429) plus `template.html` (422)
= 851, which is **11.5%** of 7,372. That is arithmetic on this entry.

### M-POS-2

**The README is 473 lines, 4,074 words, 20 headings**, and the material a
suspicious reader wants is at the bottom.

```
$ wc -l README.md                        # 473
$ wc -w README.md                        # 4074
$ grep -c '^#\{1,3\} ' README.md         # 20
$ grep -n '^## \|^### ' README.md
```

Line positions the plan cites, all from that `grep -n`: `## How it works` **264**,
`## Watching, and the rest` 296, the Graph paragraph **301-303**, the power-flag
code block **309-313**, `### Extending it` **320**, `## Not only markdown`
**377**, `## Themes` **409**, `## Prior art` **442**, `## Limitations` 454, and
the admitted-and-fixed `<img onerror>` paragraph at **465 of 473**.

### M-POS-3

**The README has had a prior-art section since the first commit.**

```
$ git log -S'## Prior art' --format=%h        # 61550b2 — the first commit
```

Recorded because the register said it had none, and writing that into a plan
would have reproduced the defect the plan exists to fix.

### M-POS-4

**Four register lines misdescribe the code**, each checked against the working
tree:

| line | claims | code |
|---|---|---|
| `tasks.md:108` · C7 | an index cache at `index/<roothash>.json` | `grep -rn roothash bin share docs README.md` returns two hits, both prose; `_cache_read`/`_cache_write` (`workspace.py:300-317`) serve only `sessions.json` and `sessions-deep.json`; `workspace.py:6-7` argues against document caching |
| `tasks.md:75` · B1 | facets `has-notes · stale · untracked · front-matter tag` | `workspace.js:1149` is `[['notes','has notes'],['stale','stale'],['recent','14 days']]` — two claimed facets absent, one shipped facet unlisted |
| `tasks.md:106` · C6 | *a one-time migration* | `workspace.js:76-90` is lazy and per-document, and cannot cross the `file://` → `http://127.0.0.1:PORT` boundary |
| `tasks.md:140` · E3 | *gated behind a node budget* | `workspace.js:603-609` is a click gate plus an advisory string at `n > 120`; `graphEdges` caps groups, not nodes |

A fifth, `E8 · Multi-root`, is `M-POS-5`.

### M-POS-5

**A two-root build produces 110 documents and 99 orphan stale keys**, and every
second-root document reports `commits: 0`.

```
$ python3 -c "import workspace as W; d=W.build(['~/Repositories/rubricator', \
    '~/Repositories/repo A'], False); …"
two-root build: 110 docs, stale keys=110
stale keys of the form repo A/repo A/: 99
root1 docs=11, rel in stale: 11
root2 docs=99, rel in stale: 0
orphan stale keys (no doc): 99
```

Mechanism: `workspace.py:399-400` prefixes `d["rel"]` inside the `find_docs`
loop, `git_activity` is then handed rels that are already prefixed, and `:404-405`
prefixes again.

Three shortcuts behind it, reproduced on two scratch repositories by replicating
the `/notes` and `/asset` routes: a note taken on the second root's document lands
in the first root's `notes.json` and reading the second root alone returns `{}`;
`asset()` resolves against `roots[0]`; and `remember_project` stores a flat list
of single path strings, so a multi-root workspace can never be reopened as one.

### M-POS-6

**Nobody has ever run the multi-root feature, including its author.**

```
$ python3 -m json.tool ~/.config/rubricator/config.json   # recents: 4, all single paths
$ grep -o '"roots":\[[^]]*\]' ~/.cache/rubricator/*.html  # all single-root
$ cat ~/Repositories/.rubricator/notes.json               # {}
```

That last file — an empty notes file at the top of the repositories directory —
is somebody having tried `md ~/Repositories` once.

### M-POS-7

**`md ~/Repositories` builds a 1,982-document, git-less workspace in 0.65 s and
emits a 41.1 MB static page, silently.** Method as `M-SIG-15`, with
`hasGit=False` and 0 stale entries; the JSON payload alone is 18.6 MB, which is
the figure earlier reports mistook for the page.

### M-POS-8

**The literal `/Applications/Google Chrome.app` appears six times in two files and
there are four guard sites.**

```
$ grep -rn '/Applications/Google Chrome.app' bin/md share/
bin/md:175  :176  :188  :189  :417
share/hook.py:20
```

Guard sites: `bin/md:175`, `:188`, `:423` and `hook.py:110`
(`os.path.isdir(CHROME)`, fed by the literal at `:20`). Only `bin/md:423` and
`hook.py:110` go through a `CHROME` variable; the two workspace launchers test the
literal inline, which is why a fix at `:417` alone leaves them broken. Every guard
falls back to plain `open`, silently, exit 0.

### M-POS-9

**Six capabilities are bound to macOS, across four files of own code plus
`install.sh` and `share/md.zsh`.** Found by a marker grep plus a full
`subprocess.(run|Popen)` sweep:

```
$ grep -rniE "darwin|osascript|/Applications|textutil|pbcopy|mdfind|open -na|LaunchServices|\.command|sw_vers" \
    bin/md share/*.py share/*.js share/*.html share/*.zsh *.sh
```

1. opening a URL as an app window (`open -na`) — `bin/md`, `hook.py:112`
2. closing that window by AppleScript — `hook.py:126`, `:136`
3. the native folder chooser — `actions.py:151`
4. `.command` + LaunchServices dispatch against a hardcoded app table —
   `actions.py:37-42`, `:201-240`
5. `textutil` and JXA/PDFKit extraction — `extract.py:87`, `:116`
6. `shasum` — `bin/md:110`, `:183`, `:357`

Plus `install.sh:48` (`uname -s` = Darwin), `install.sh:74-93` (zsh-only rc
editing) and `share/md.zsh:23` (`compdef`).

**Zero markers** in `workspace.py`, `serve.py`, `transcript.py`, `workspace.js`,
`shell.js`, `render.js`, `review.js`, `ui.js`, every stylesheet and every
template; `workspace.py:25` shells out only to `git`. The earlier claim of *five
capabilities in three files* is wrong in both halves.

### M-POS-10

**The largest transcript on this machine is 105.0 MB and `transcript.read()`
parses it in 0.28 s into 795 turns.** Five places in the repository still carry
the old *17 MB / 0.05 s* figure — `README.md:185`, `share/transcript.py:8`,
`share/workspace.py:620`, `docs/conversations-plan.md:341`, `docs/tasks.md:170` —
while `docs/conversations-plan.md:31-32` already says 105 MB.

Method: `ls -S ~/.claude/projects/*/*.jsonl | head -1`, then time
`transcript.read()` on it, min of three warm runs.

### M-POS-11

**The document↔session join: 49 of 419 indexed sessions carry a file list;
341 of the 370 without are older than thirty days.** Median age of sessions
carrying files is **22 days**; without, **95**. Per-repo document coverage:
repo A 65%, repo C 12%, repo B 20%, rubricator 9%.

Method: `load_sessions()`, count sessions whose `files` list is non-empty, and
take the median of `now − last_activity` for each group. Coverage is
`M-RET-18`'s count applied to all four repositories. The repo A 65% is the
trap `M-RET-18` unpacks.

### M-POS-12

**The correlation graph draws 11 nodes on a 99-document repository and 300 on a
502-document one**, into a fixed 900×560 viewBox.

`graphEdges` replicated against the live indexes: repo A 11 of 99,
repo C 300 of 502, repo B 196 of 330. The 1,680 px² per labelled node is
arithmetic: 900 × 560 ÷ 300.

### M-POS-13

**There is no freeze.** `viewGraph`'s spring loop ported verbatim into node 24.18
— the same V8 that Chrome runs — warm, 220 steps:

```
299 nodes / 1,561 edges   →   19.5 ms
301 nodes / 1,600 edges   →   43.5 ms
1,000 nodes / 8,000 edges →    234 ms
```

`graphEdges`, ported verbatim over 500 documents × 300 sessions — 919,500 string
comparisons — costs **3.0 ms**. The ungated operation counts the earlier claim
was built on are real (repo D 0.6M, repo B 4.6M, repo C 10.4M) and
nobody had timed one. That claim is struck; the deletion argument is
`M-POS-12`'s.

### M-POS-14

**plannotator, `gh api`, 2026-08-23.** 7,970 stars at the verification fetch and
**7,971** when `scope-plan.md` was written a couple of hours later; 590 forks;
**1,072 commits**; created **2025-12-28**; Apache-2.0; TypeScript (11.1 MB of
12.1); **147 releases**; nine agents, of which three are manual invocation.

```
$ gh api repos/backnotprop/plannotator --jq \
    '{created_at,stars:.stargazers_count,forks:.forks_count,lang:.language,license:.license.spdx_id}'
$ gh api 'repos/backnotprop/plannotator/commits?sha=main&per_page=1' -i | grep -i '^link:'
$ gh api 'repos/backnotprop/plannotator/releases?per_page=100' --paginate --jq length
```

**The one-star drift between two fetches on the same day is the point**: the
struck *8,000+* was objected to over a rounding error of thirty, so this row
carries a date and moves. The Version Browser and hook-event quotes are external:
they are cards **G11** and **G12** in `citations.md`, and Moat's own tagline,
quoted in the same section, is **G13**.

### M-POS-15

**plannotator leads rubricator by 7 months 21 days.** Its first commit is
2025-12-28 (`gh api …/commits?per_page=1&page=1072`); rubricator's is
2026-08-18 (`git log --reverse --format='%h %ad' | head -1` → `61550b2`).
Arithmetic between the two dates.

### M-POS-16

**rubricator: 0 stars, 0 tags, 0 releases, `topics: []`, homepage `null`.**

```
$ gh api repos/TheRealVale/rubricator --jq \
    '{stargazers_count,forks_count,open_issues_count,topics,homepage,license:.license.spdx_id,size}'
```

Returned `size: 883` on 2026-08-23. Tags and releases are `M-INS-12`.

### M-POS-17

**The other named projects, `gh api`, 2026-08-23.** PlanBridge 27 stars, 1 fork,
created 2026-04-29, MIT. Imark 46 stars, created **2026-08-05** — eighteen days
old — Swift, MIT, 134 commits. md-annotator 5 stars, 392 commits, created
2026-01-28. Moat is hosted and account-based; its tagline is fetched from
`moat.so`. One `gh api repos/<owner>/<name>` per row.

### M-POS-18

**The session-viewer star counts do not sum to 2,885.** Re-queried 2026-08-23:
`jhlee0409/claude-code-history-viewer` **2,089**, `raine/claude-history` **457**,
`eckardt/cchistory` **137**, `adewale/claude-history-explorer` **18** — **2,683**
for the three largest, 2,701 for all four. One `gh api` per repository. Print the
repositories and their numbers, or print 2,683.

### M-POS-19

**`anthropics/claude-plugins-community` lists 2,282 plugins**, roughly 700 of
which keyword-match plan, review, markdown or doc. Method: fetch the
marketplace's `marketplace.json`, count entries, then count entries whose name or
description matches those four keywords case-insensitively.

### M-POS-20

**plannotator's installer is 2,130 lines and downloads a prebuilt per-platform
binary**, so *no Bun needed* is not a differentiator.

```
$ curl -fsSL https://plannotator.ai/install.sh -o pl-install.sh && wc -l pl-install.sh   # 2130
$ grep -n 'binary_name\|binary_url' pl-install.sh
```

Bun is the development runtime. The honest remaining difference is an opaque
compiled binary behind a 2,130-line installer versus 7,379 readable lines
(`M-POS-1`).

### M-POS-21

**`all:unset` appears 23 times across the three stylesheets** — 9 in `review.css`,
11 in `shell.css`, 3 in `ui.css` — and it resets `outline-style`, so the
platform's focus ring is gone by construction.

```
$ grep -c 'all:unset' share/review.css share/shell.css share/ui.css
```

`shell.js:437` handles `Tab` with no shift check, so `⇧Tab` advances the palette's
kind filter instead of stepping back; selection is `ArrowDown`/`ArrowUp` at
`:433-434` and is not involved. The reader tier's shortcuts sheet is `ui.js:288`
and `template.html:308`; the workspace does not load `ui.js`.

### M-POS-22

**The document link graph is nearly edgeless: 0 doc→doc links across 330 repo B
documents, 1 across 84 in repo D.**

| repo | docs | links resolving to another indexed doc | docs with ≥1 |
|---|---:|---:|---:|
| repo B | 330 | **0** | 0 (0%) |
| repo C | 502 | 420 | 110 (22%) |
| repo A | 99 | 36 | 12 (12%) |
| repo D | 84 | **1** | 1 (1%) |

Method: for each document, resolve every markdown link relative to its own
directory and test membership in the indexed document set.

### M-POS-23

**An agent touches 8.8 to 56 markdown files per active day in one repository, and
the user works across 2.5 repositories a day on average.**

```
$ git -C <repo> log --since=60.days --name-only --pretty=format:'%ad' -- '*.md'
# markdown touches ÷ days with at least one
repo D 8.8 · repo B 18.5 · repo C 23.5 · repo A 56
```

Repositories per day: distinct `project` values per calendar day in
`history.jsonl` over the last 21 days — mean **2.5**, max 4, 7 distinct in 30
days.

### M-POS-24

**`PermissionRequest` is documented and fired zero times.** Against `claude`
2.1.241 under `claude -p`, in five configurations — top level, subagent, via
`--settings`, via project settings, and with `--debug hooks` — `PermissionRequest`
fired 0 times while `PreToolUse` from the identical configuration fired every
time. The interactive case was not tested and no claim is made about it.

Method: three hook scripts logging their stdin, registered as `PermissionRequest`,
`PreToolUse` and `PermissionDenied`, in a throwaway non-git directory, driving
`claude -p "…" --output-format json --max-turns 4 < /dev/null`. This is the
justification for standing rule 12.

### M-POS-25

**`continue-plan.md`'s rows 3 and 4 measured the author's own settings.**
`~/.claude/settings.json` carries `"defaultMode": "auto"`; with default or manual
mode in an untrusted directory the identical shell call is **denied**, visibly,
and the denial appears in `result.permission_denials`. Same harness as
`M-POS-24`, reading the JSON result rather than the hook logs.

### M-POS-26

**The `## How it works` block would fail the CI assertion P1 proposes today.**
It lists `share/review.*`, `share/ui.*`, `share/shell.*` and `share/workspace.*`
as globs and never mentions `share/md.zsh`. Read at `README.md:264-282` against
`git ls-files share/`.

### M-POS-27

**Cross-origin note sharing is impossible, not merely unbuilt.** The static tier
is `file://` and the live tier is `http://127.0.0.1:PORT`; the same-origin policy
separates their `localStorage`, and `M-SIG-17`'s new-port-every-run makes it
doubly so. `README.md:287-289` promises it anyway. This is a read of the two tiers
plus `M-SIG-17`, not a separate measurement.

### M-POS-28

**External claims used for positioning** are all in `citations.md`, each with its
source and, where it has one, its *must accompany* qualifier — the Ctrl+G quote
is **G7**, the VS Code plan-comment quote **G8**, the plugins-reference `bin/`
quote **G3**, the Copilot Spaces and Logseq quotations behind standing rules 4
and 6 are **G9** and **G10**, and the CHI 2024 verification-time figures behind
standing rule 11 are **A1**. The two vendor-telemetry refusals in §12 are **B1**
(Faros AI) and **B2** (LinearB). Nothing in this file restates them. `/insights`
is **F2** there, flagged as **secondary-sourced**: no primary announcement page
was located, so it is reported as reported behaviour.

### M-POS-29

**Every `file:line` in `scope-plan.md` was opened against `a63e540`**, by
`sed -n '<n>p'`, including all of `docs/tasks.md`'s cited register lines (75, 77,
106, 108, 140, 145, 186, 187) and all of the README positions in `M-POS-2`. The
figures that are *not* from this disk are the two GitHub rows, and they are marked
as such in the plan's own §1 table: `M-POS-14`, `M-POS-16`, `M-POS-17`,
`M-POS-18`, `M-POS-19` all move on their own and carry the date they were fetched.

---

# Cited but not reproducible from this record

Nine figures or claims cited in the five plans cannot be re-derived from what is
written above. None of them is load-bearing on a decision, and three of them the
plans already flag themselves. They are listed because a reference file that
quietly rounds its own gaps is the defect the whole programme is about.

### M-GAP-1 · The 37-query sample is not recorded

`M-SIG-2`'s *25 of 37 (68%)* and `M-SIG-3`'s *0 → 111* and *1 → 132* come from one
scratch script whose generated query list was not kept. The method is described
and the harness is a morning's work to rewrite, but the **exact** 68% is not
reproducible: a re-run generates a different 37 queries. What is reproducible is
the shape — a sample of two-word queries drawn from titles that are in the corpus,
scored twice. L1 turns on the shape. Anyone re-running it should record the query
list.

### M-GAP-2 · `RUBRICATOR_DRY_LAUNCH` has never been fired

`install-plan.md` §6 says so in the text. It is present at `actions.py:230` and
was read, not run. Smoke test 3 in K4 assumes it works.

### M-GAP-3 · The headless flake is one observation, not a measurement

`install-plan.md` §4 records that a re-run of `M-INS-8` exceeded a two-minute
budget and had to be killed. No command line, wall time or Chrome version was
kept for that run, and it has not been repeated. It is enough to keep layer 3 off
the per-push path until someone has watched it run ten times; it is not evidence
of anything else.

### M-GAP-4 · The palette's round trip has not been timed

`signals-plan.md` §4 says this outright. L2 calls `ensureAllText` when the palette
opens; what is measured is the work behind the fetch (`M-SIG-15`: 0.23–0.25 s to
rebuild repo B, a 6.6 MB payload), not the round trip a user would feel.

### M-GAP-5 · Whether Approve skips the approval menu — settled 2026-08-25

*Closed. Kept here because a gap that is filled is worth more as a record of how
than as a deletion.*

`M-INS-24` records that two vendor pages disagree and that the disagreement is
about the interactive case. It could not be settled by reading more documentation
and it could not be settled by the harness — `M-POS-24`'s is non-interactive by
construction. It took one human, one plan and one keypress.

Taken 2026-08-25 against `claude` 2.1.241, interactive, in a throwaway git
repository started with `--permission-mode plan`. The plan was written to
`~/.claude/plans/` at 20:58:01 and `ExitPlanMode` loaded at 20:58:03; the hook
fired, the window opened, Approve (`⌘⇧⏎`) was pressed with nothing marked, and
the window closed. **Claude Code's approval menu then appeared.** The session
transcript corroborates it by ending at the `ExitPlanMode` schema load, the
session still sitting at the menu when it was read.

So `permissionDecision: "allow"` alone is not sufficient for `ExitPlanMode`;
`citations.md` **G1** is right and `permission-modes.md`'s omission is the
misleading page. `hook.py:160-167` sends `additionalContext` and no
`updatedInput`. Recorded as **K5b**; `README.md:245` claimed the opposite and now
carries a warning until **P1**.

Not reproducible by script, and that is the point: any re-measurement is another
human, another plan, another keypress, against a named `claude` version.

### M-GAP-6 · The session-id derivation was tested by shape, not by identity

`M-RET-17` counts basenames matching a UUID shape, 79 of 79. N6 derives the
session id *from* that basename, which requires the basename to equal the session
id — a stronger statement. It is very likely true and it was not checked; the
check is to cross-reference each basename against a session id appearing inside
the file, which `M-RET-1`'s parse already reads and did not compare.

### M-GAP-7 · Which of the three static paths wrote the 8 MB page is not recorded

`retention-plan.md` §2 says the file is on this machine because `--static`, `-n`
or the server fallback at `bin/md:180` happened on 21 August. Only the file's
mtime supports that; nothing distinguishes the three, and no log records the
invocation. The finding — that a path with no flag can write the corpus to disk —
is a read of `bin/md:180` and does not depend on knowing which one ran.

### M-GAP-8 · Two zero counts are absences, not measurements

`M-SIG-27`: no `/notes` POST failure has ever been recorded, and no hook review
has ever been recorded. Neither is instrumented, so *never happened* and
*happened and left nothing* are indistinguishable. `retention-plan.md` §8 makes
that exact point and is the reason N6's first half exists — it converts the
absence into a count.

### M-GAP-9 · Two figures depend on scratch tooling that is not committed

`M-ANC-9`'s 31 records across 21 origins, and the ten documents opened and closed
unmarked, come from a hand-written LevelDB reader and snappy decompressor. The
method is described and uses no third-party packages, but re-deriving the numbers
means writing that reader again — a day, not a command. The same applies in
lesser degree to the ported JavaScript in `M-SIG-1`, `M-SIG-4` and `M-POS-13`,
where the port is short enough that the entry names the source function and the
options it was run under.

**One further caveat that is not a gap, but belongs beside them.** Twelve workflow
runs over eleven weeks, cited in `retention-plan.md` §7 as the reason X28 is dead,
comes from the register rather than from a command; the underlying transcript
census (`M-RET-4`) counted 589 subagent files but did not group them into runs.
The claim X28 rests on is not the count — it is that the runs are read-only
analysis panels whose output was read immediately, which is a reading of their
content and not a number at all.
