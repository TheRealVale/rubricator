#!/usr/bin/env python3
"""
rubricator workspace indexer — walks a repo, reads git, optionally reads your own
Claude Code history, and emits one self-contained page.

Everything here is recomputed on every run: at ~0.6s for 500 MB there is nothing
worth caching, and nothing to invalidate.
"""
import html, json, os, re, subprocess, sys, time
from pathlib import Path

HOME = Path.home()
CACHE = Path(os.environ.get("RUBRICATOR_CACHE", HOME / ".cache/rubricator"))
SKIP_DIRS = {".git", "node_modules", "dist", "build", ".next", "vendor",
             ".venv", "venv", "__pycache__", ".cache", "coverage", ".turbo"}
MD_EXT = {".md", ".markdown", ".mdown", ".mdx", ".mdc"}
PROMPT_MAX = 2000        # was 600, which lost 13.6% of all prompt text
# the slash commands that are plumbing rather than something you asked
SLASH_NOISE = {"model", "compact", "clear", "cost", "exit", "quit", "help",
               "resume", "login", "logout", "status", "doctor", "init"}
DOC_EXT = {".pdf", ".docx", ".doc", ".rtf", ".odt"}      # read through share/extract.py
ALL_EXT = MD_EXT | DOC_EXT
SCRATCH = re.compile(r"^/(private/)?(tmp|var/folders)/|/\.cache/|/node_modules/|/\.claude/|/\.git/")


# ── the corpus ───────────────────────────────────────────────────────────────
def git(root, *args, timeout=25):
    try:
        r = subprocess.run(["git", "-C", str(root), *args],
                           capture_output=True, text=True, timeout=timeout)
        return r.stdout if r.returncode == 0 else ""
    except Exception:
        return ""


def find_docs(root):
    """Tracked files, plus the ones git can see and you have not staged.

    The `os.walk` below reads like a fallback and is unreachable in any real
    repository — `any(tracked)` is true the moment one file is tracked, so the
    document an agent wrote thirty seconds ago was invisible until `git add`.
    That is the exact inversion of what this tool is for: you switch to the
    workspace to review the plan Claude just wrote, and it is not there, not
    after a reindex and not after the watcher fires.

    `--others --exclude-standard` is the fix and it is cheap — measured at 23 ms
    against 19 ms for the existing call on a 3,363-file repository. Ignored
    files stay ignored, so this does not start indexing `node_modules`."""
    tracked = git(root, "ls-files", "-z").split("\0")
    untracked = {r for r in git(root, "ls-files", "--others", "--exclude-standard", "-z").split("\0") if r}
    if any(tracked) or untracked:
        seen = set()
        for rel in list(tracked) + sorted(untracked):
            if not rel or rel in seen:
                continue
            if Path(rel).suffix.lower() not in ALL_EXT:
                continue
            seen.add(rel)
            p = root / rel
            if p.is_file():
                yield p, rel, rel in untracked
        return
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS and not d.startswith(".")]
        for fn in filenames:
            if Path(fn).suffix.lower() in ALL_EXT:
                p = Path(dirpath) / fn
                yield p, str(p.relative_to(root)), False


HEADING = re.compile(r"^(#{1,6})\s+(.+?)\s*#*\s*$", re.M)
LINK = re.compile(r"\[[^\]]*\]\(([^)\s]+)")
MERMAID_FENCE = re.compile(r"^[ \t]*(?:```|~~~)[ \t]*mermaid\b", re.M)
WORD = re.compile(r"[A-Za-zÀ-ÿ][A-Za-zÀ-ÿ0-9_-]{2,}")


def read_doc(path, rel, root, allow_extract=False):
    """Markdown is read straight off disk. A PDF or a Word file has to be put
    through an extractor, which is slow enough that the index will not wait for
    it: unless we already have it cached, the document arrives without its text
    and the page fetches it when something actually needs it."""
    kind = extract_kind(path)
    if kind:
        return read_extracted(path, rel, root, kind, allow_extract)
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except Exception:
        return None
    heads = [{"level": len(m.group(1)), "text": m.group(2).strip(),
              "line": text[:m.start()].count("\n") + 1}
             for m in HEADING.finditer(text)]
    title = next((h["text"] for h in heads if h["level"] == 1), Path(rel).stem)
    links = []
    for m in LINK.finditer(text):
        t = m.group(1)
        if t.startswith(("http://", "https://", "#", "mailto:")):
            continue
        try:
            links.append(os.path.normpath(os.path.join(os.path.dirname(rel), t)))
        except Exception:
            pass
    st = path.stat()
    return {"rel": rel, "abs": str(path), "kind": "md", "title": title, "headings": heads,
            "links": links, "words": len(text.split()), "bytes": st.st_size,
            "mtime": int(st.st_mtime), "text": text}


_X = None


def _extractor():
    global _X
    if _X is None:
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        import extract as X
        _X = X
    return _X


def extract_kind(path):
    try:
        return _extractor().kind_of(path)
    except Exception:
        return None


def read_extracted(path, rel, root, kind, allow_extract):
    X = _extractor()
    st = path.stat()
    got = X.cached(str(path)) or (X.extract(str(path)) if allow_extract else None)
    d = {"rel": rel, "abs": str(path), "kind": kind, "title": Path(rel).stem,
         "headings": [], "links": [], "words": 0, "bytes": st.st_size,
         "mtime": int(st.st_mtime)}
    if not got:
        return d                      # known about, not yet read
    if got.get("error"):
        d["note"] = got["error"]
        d["text"] = ""
        return d
    text = got.get("text") or ""
    d["text"] = text
    d["words"] = len(text.split())
    if got.get("pages"):
        d["pages"] = got["pages"]
    if got.get("empty"):
        d["note"] = "no text layer — this is a picture of a document"
    d["headings"] = [{"level": len(m.group(1)), "text": m.group(2).strip(),
                      "line": text[:m.start()].count("\n") + 1}
                     for m in HEADING.finditer(text)]
    first = next((l.strip() for l in text.split("\n")
                  if l.strip() and not l.startswith("#")), "")
    if first:
        d["title"] = first[:90]
    return d


# ── git activity, and the doc/code staleness signal ──────────────────────────
def git_activity(root, docs):
    """Commits per file, and how much the code a doc points at moved since the
    doc was last touched. Scoped to what the doc mentions, not the whole repo."""
    log = git(root, "log", "--since=2 years ago", "--name-only",
              "--format=%x01%ct", "-z", timeout=60)
    if not log:
        return {}, {}
    commits, cur = {}, None
    for chunk in log.replace("\0", "\n").split("\n"):
        chunk = chunk.strip()
        if not chunk:
            continue
        if chunk.startswith("\x01"):
            cur = int(chunk[1:] or 0)
            continue
        e = commits.setdefault(chunk, {"n": 0, "last": 0, "ts": []})
        e["n"] += 1
        e["last"] = max(e["last"], cur or 0)
        if len(e["ts"]) < 60:
            e["ts"].append(cur or 0)

    stale = {}
    all_paths = list(commits.keys())
    for d in docs:
        info = commits.get(d["rel"], {})
        last = info.get("last") or d["mtime"]
        # which files does this doc actually talk about?
        targets = set()
        for l in d["links"]:
            if l in commits:
                targets.add(l)
        for m in re.finditer(r"[`\"']([\w./-]+\.(?:ts|tsx|js|jsx|py|sql|go|rs|java|kt|vue|svelte))[`\"']", d.get("text") or ""):
            t = m.group(1).lstrip("./")
            for p in all_paths:
                if p.endswith(t):
                    targets.add(p)
                    break
        churn = sum(commits[t]["n"] for t in targets if commits[t]["last"] > last)
        # `repoChurn` was computed here for every document — a whole pass over
        # all_paths each time, 26% of the git work — and read by no JavaScript
        # in the page. Deleted rather than surfaced: it measures how busy the
        # repository is, which is not a fact about the document.
        stale[d["rel"]] = {"commits": info.get("n", 0), "last": last,
                           "ts": info.get("ts", [])[:40],
                           "targets": sorted(targets)[:40],
                           "targetChurn": churn}
    return commits, stale


# ── your own sessions ────────────────────────────────────────────────────────
SECRET = [
    # private key blocks first — they span lines
    (re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----.*?-----END [A-Z ]*PRIVATE KEY-----", re.S), "[private key]"),
    # provider-shaped tokens
    (re.compile(r"\b(sk-[A-Za-z0-9_-]{16,}|[sprk]k_(?:live|test)_[A-Za-z0-9]{10,}|gh[pousr]_[A-Za-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{12,}|AIza[0-9A-Za-z_-]{20,})"), "[key]"),
    # JWTs: three dot-separated segments, each too short for the base64 rule below
    (re.compile(r"\beyJ[A-Za-z0-9_-]{6,}\.[A-Za-z0-9_-]{6,}(?:\.[A-Za-z0-9_-]+)?"), "[jwt]"),
    # a whole auth header, value and all
    (re.compile(r"(?i)\b(proxy-)?authorization\b\s*[:=]\s*[^\n]+"), "authorization: [redacted]"),
    (re.compile(r"(?i)\bbearer\s+[A-Za-z0-9._~+/=-]{8,}"), "bearer [redacted]"),
    # key: value / KEY=value
    # the keyword may sit inside an identifier: STRIPE_SECRET_KEY, dbPassword
    (re.compile(r"(?i)[\w-]*(?:api[_-]?key|secret|password|passwd|access[_-]?token|refresh[_-]?token|token|credential)[\w-]*\s*[:=]\s*[^\s,;\n]+"), "[credential]"),
    # VAR=value, with or without an export in front
    (re.compile(r"(?im)^\s*(?:export\s+)?[A-Z][A-Z0-9_]{2,}=(?!\s*$).+$"), "[env]"),
    # connection strings carry inline passwords
    (re.compile(r"(?i)\b[a-z][a-z0-9+.-]*://[^\s/@]+:[^\s/@]+@\S+"), "[connection string]"),
    # long opaque blobs
    (re.compile(r"\b[A-Za-z0-9+/]{40,}={0,2}\b"), "[blob]"),
    (re.compile(r"\b[\w.+-]+@[\w-]+\.[\w.]{2,}\b"), "[email]"),
]


def scrub(s):
    """Prompt text can hold pasted credentials. Nothing leaves this machine, but
    a dossier can — so scrub at index time, not at export time."""
    for pat, rep in SECRET:
        s = pat.sub(rep, s)
    return s


def is_slash_noise(txt):
    """`/compact` is plumbing. `/api/orders returns 500 after the migration` is
    a prompt that happens to start with a path, and the old blanket
    `startswith("/")` lost both."""
    if not txt.startswith("/"):
        return False
    first = txt.split(None, 1)[0]
    return first.lstrip("/").lower() in SLASH_NOISE


def load_sessions(limit_project=None, deep=False):
    """Two records of the same history, joined on the session id.

    history.jsonl remembers every prompt you have ever typed and outlives the
    transcripts. The transcripts know which files a session touched — but only
    while they are still on disk. A session with no transcript can still be read
    and searched; it cannot be resumed. The page has to say which is which, or
    the resume button lies."""
    prompts, hist = [], HOME / ".claude/history.jsonl"
    meta = {}
    if hist.is_file():
        with hist.open(encoding="utf-8", errors="replace") as f:
            for line in f:
                try:
                    d = json.loads(line)
                except Exception:
                    continue
                txt = d.get("display") or ""
                # A blanket startswith("/") dropped 756 of 4,750 records, but 82%
                # of those are /model, /compact and /clear — plumbing nobody
                # searches for. The rest is a real prompt that happens to open
                # with a path, and there is no reason to lose it. A short
                # skiplist keeps both.
                if not txt or is_slash_noise(txt):
                    continue
                sid = d.get("sessionId") or ""
                t = int((d.get("timestamp") or 0) / 1000)
                # The cap was 600, which dropped 86,020 characters — 13.6% of all
                # prompt text — from the 3.2% of prompts that exceed it, and made
                # a long prompt unfindable by anything in its second half. The
                # slash filter above was the visible loss; this was nine times
                # larger and silent.
                text = scrub(txt)[:PROMPT_MAX]
                prompts.append({"sid": sid, "project": d.get("project") or "",
                                "t": t, "text": text})
                if not sid:
                    continue
                m = meta.get(sid)
                if m is None:
                    m = meta[sid] = {"p": d.get("project") or "", "t": "", "n": 0,
                                     "a": t, "b": t, "live": 0, "files": []}
                m["n"] += 1
                if t:
                    if not m["a"] or t < m["a"]:
                        m["a"] = t
                    if t > m["b"]:
                        m["b"] = t
                if not m["t"]:
                    m["t"] = text[:120]                   # the first thing you asked names it

    touches = {}
    root = HOME / ".claude/projects"
    if root.is_dir():
        for p in root.glob("*/*.jsonl"):                  # subagent runs live deeper; not ours
            sid = p.stem
            seen, cwd = set(), ""
            try:
                with p.open(encoding="utf-8", errors="replace") as f:
                    for line in f:
                        if not cwd and '"cwd"' in line:
                            m = re.search(r'"cwd":"([^"]+)"', line)
                            if m:
                                cwd = m.group(1)
                        if '"file_path"' not in line:
                            continue
                        seen.update(re.findall(r'"file_path":"([^"]+)"', line))
            except Exception:
                continue
            if deep:
                # a subagent's edits belong to the session that delegated them
                for sub_ in (p.parent / sid / "subagents").rglob("*.jsonl"):
                    try:
                        with sub_.open(encoding="utf-8", errors="replace") as f:
                            for line in f:
                                if '"file_path"' in line:
                                    seen.update(re.findall(r'"file_path":"([^"]+)"', line))
                    except Exception:
                        pass
            seen = {f for f in seen if not SCRATCH.search(f)}
            m = meta.get(sid)
            if m is None:
                st = p.stat()
                m = meta[sid] = {"p": cwd, "t": "", "n": 0,
                                 "a": int(st.st_mtime), "b": int(st.st_mtime),
                                 "live": 0, "files": []}
            m["live"] = 1                                 # a transcript exists: resumable
            if cwd and not m["p"]:
                m["p"] = cwd
            m["files"] = sorted(seen)
            for f_ in seen:
                touches.setdefault(f_, []).append(sid)
    return prompts, meta, touches


def secure_cache():
    """The cache holds every prompt you have typed, the plaintext of every PDF
    indexed, and — until N2 — whole rendered workspaces. It was 0644 in a
    directory macOS does not exclude from Time Machine, which meant the corpus
    `--sessions` refuses to write with `--out` was being backed up instead.

    Two properties, asserted rather than assumed: nothing under the cache root
    is readable by anyone else, and the root is out of Time Machine. The second
    is `tmutil addexclusion` — unprivileged, reversible with `removeexclusion`,
    and it needs no migration, which moving under ~/Library/Caches would."""
    try:
        CACHE.mkdir(parents=True, exist_ok=True)
        os.chmod(CACHE, 0o700)
    except Exception:
        return
    for sub in CACHE.rglob("*"):
        try:
            os.chmod(sub, 0o700 if sub.is_dir() else 0o600)
        except Exception:
            pass
    mark = CACHE / ".tm-excluded"
    if mark.exists() or sys.platform != "darwin":
        return
    try:
        r = subprocess.run(["tmutil", "isexcluded", str(CACHE)],
                           capture_output=True, text=True, timeout=5)
        if "[Excluded]" not in (r.stdout or ""):
            subprocess.run(["tmutil", "addexclusion", str(CACHE)],
                           capture_output=True, timeout=5)
        mark.write_text("", encoding="utf-8")
        os.chmod(mark, 0o600)
    except Exception:
        pass          # a backup exclusion that cannot be set must not stop an index


def prune_cache(days=7):
    """`bin/md:429` already expires rendered HTML after seven days, but its
    `-maxdepth 1 -name '*.html'` misses `index/`, so the session index — the most
    sensitive file rubricator writes — was the one thing that never expired."""
    cut = time.time() - days * 86400
    for f in list((CACHE / "index").glob("sessions*.json")):
        try:
            if f.stat().st_mtime < cut:
                f.unlink()
        except Exception:
            pass


def retention():
    """How much of your own history can still be read, and how much only found.

    Two sources, deliberately: the session ids in `history.jsonl`, which is kept
    until you delete it, against the transcripts in `~/.claude/projects`, which
    Claude Code sweeps after `cleanupPeriodDays` — 30 by default. The gap is not
    a rubricator limitation and it is not recoverable, so the page says the
    number rather than letting the Sessions list imply that a `○ archived` row
    is a rubricator problem.

    Counted from `history.jsonl` directly rather than from the built index,
    which drops slash-command prompts and would give a different, smaller
    denominator for the same question."""
    hist = HOME / ".claude/history.jsonl"
    if not hist.is_file():
        return None
    ids = set()
    try:
        with hist.open(encoding="utf-8", errors="replace") as f:
            for line in f:
                try:
                    sid = json.loads(line).get("sessionId")
                except Exception:
                    continue
                if sid:
                    ids.add(sid)
    except Exception:
        return None
    if not ids:
        return None
    live = {p.stem for p in (HOME / ".claude/projects").glob("*/*.jsonl")}
    kept = len(ids & live)
    return {"known": len(ids), "readable": kept, "lost": len(ids) - kept,
            "setting": "cleanupPeriodDays"}


def say_once_about_retention(r):
    """One sentence, once per install, naming the setting that controls it.

    Deliberately printed and not written. Raising `cleanupPeriodDays` is a
    one-line edit to `~/.claude/settings.json`, and a markdown reader that
    edits another tool's config is one malformed write away from breaking the
    agent it exists to help. The marker lives in rubricator's own cache."""
    if not r or not r.get("lost"):
        return
    mark = CACHE / "said-retention"
    if mark.exists():
        return
    pct = round(100 * r["lost"] / r["known"])
    sys.stderr.write(
        f"rubricator: {r['lost']} of your {r['known']} sessions ({pct}%) can be found but "
        f"not read — Claude Code removes transcripts after 30 days.\n"
        f"            Raise `{r['setting']}` in ~/.claude/settings.json to keep them longer. "
        f"Said once.\n")
    try:
        CACHE.mkdir(parents=True, exist_ok=True)
        mark.write_text(str(int(time.time())), encoding="utf-8")
    except Exception:
        pass


# ── caching ──────────────────────────────────────────────────────────────────
def _cache_read(name, stamp):
    f = CACHE / "index" / name
    try:
        d = json.loads(f.read_text(encoding="utf-8"))
        return d["data"] if d.get("stamp") == stamp else None
    except Exception:
        return None


def _cache_write(name, stamp, data):
    try:
        (CACHE / "index").mkdir(parents=True, exist_ok=True)
        tmp = CACHE / "index" / (name + ".part")
        tmp.write_text(json.dumps({"stamp": stamp, "data": data}, ensure_ascii=False),
                       encoding="utf-8")
        tmp.replace(CACHE / "index" / name)
        os.chmod(CACHE / "index" / name, 0o600)
    except Exception:
        pass


def session_stamp(deep=False):
    """History grows by appending and transcripts by rewriting, so size plus the
    newest mtime is enough to know whether a re-scan would find anything new."""
    parts = []
    h = HOME / ".claude/history.jsonl"
    if h.is_file():
        st = h.stat()
        parts.append(f"{st.st_size}:{int(st.st_mtime)}")
    root = HOME / ".claude/projects"
    n, newest = 0, 0
    if root.is_dir():
        for p in root.glob("*/*.jsonl"):
            try:
                n += 1
                newest = max(newest, int(p.stat().st_mtime))
            except Exception:
                pass
    parts.append(f"{n}:{newest}")
    return "|".join(parts) + ("|deep" if deep else "")


def cached_sessions(deep=False):
    stamp = session_stamp(deep)
    name = "sessions-deep.json" if deep else "sessions.json"
    hit = _cache_read(name, stamp)
    if hit is not None:
        return hit["prompts"], hit["sessions"], hit["touches"]
    prompts, meta, touches = load_sessions(deep=deep)
    _cache_write(name, stamp, {"prompts": prompts, "sessions": meta, "touches": touches})
    return prompts, meta, touches


# ── providers ────────────────────────────────────────────────────────────────
PROVIDERS = {}


def provider(name):
    """Anything that can answer 'give me things about this tree'. The built-ins
    are registered the same way a stranger's would be, so adding a source means
    dropping a file in ~/.config/rubricator/providers/ that defines provide(root)."""
    def wrap(fn):
        PROVIDERS[name] = fn
        return fn
    return wrap


def load_extra_providers():
    d = Path(os.environ.get("RUBRICATOR_CONFIG_DIR", HOME / ".config/rubricator")) / "providers"
    if not d.is_dir():
        return
    import importlib.util
    for f in sorted(d.glob("*.py")):
        try:
            spec = importlib.util.spec_from_file_location("rb_provider_" + f.stem, f)
            mod = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(mod)
            if hasattr(mod, "provide"):
                PROVIDERS[f.stem] = mod.provide
        except Exception as e:
            sys.stderr.write(f"rubricator: provider {f.name} failed to load: {e}\n")


# ── assembly ─────────────────────────────────────────────────────────────────
def build(roots, with_sessions, deep=False, extract_now=False):
    """roots may be one directory or several; the first is the one the page is
    named after and the one relative paths are shown against."""
    if isinstance(roots, (str, Path)):
        roots = [Path(roots)]
    roots = [Path(r) for r in roots]
    root = roots[0]
    t0 = time.time()

    docs, stale, has_git = [], {}, False
    for r in roots:
        mine = []
        for path, rel, untracked in find_docs(r):
            d = read_doc(path, rel, r, allow_extract=extract_now)
            if d:
                d["root"] = str(r)
                if untracked:
                    d["untracked"] = 1
                if len(roots) > 1:
                    d["rel"] = (r.name + "/" + rel) if r != root else rel
                mine.append(d)
        commits, st = git_activity(r, mine)
        has_git = has_git or bool(commits)
        for k, v in st.items():
            stale[(r.name + "/" + k) if (len(roots) > 1 and r != root) else k] = v
        docs.extend(mine)

    data = {
        "root": str(root), "roots": [str(r) for r in roots], "name": root.name,
        "generated": int(time.time()),
        "docs": docs, "stale": stale, "hasGit": has_git,
        "sessions": {}, "prompts": [], "touches": {}, "withSessions": with_sessions,
    }
    if with_sessions:
        prompts, sessions, touches = cached_sessions(deep)
        data["prompts"] = prompts
        data["sessions"] = sessions
        data["touches"] = touches
        data["deep"] = bool(deep)
        data["retention"] = retention()
        say_once_about_retention(data["retention"])

    secure_cache()
    prune_cache()

    load_extra_providers()
    for name, fn in PROVIDERS.items():
        try:
            data.setdefault("extra", {})[name] = fn(root)
        except Exception as e:
            sys.stderr.write(f"rubricator: provider {name} failed: {e}\n")

    data["took"] = round(time.time() - t0, 2)
    return data


# ── page assembly ────────────────────────────────────────────────────────────
def design_css(share):
    """Reuse the reader's design system verbatim — one source of truth for the
    palette and typography."""
    tpl = (share / "template.html").read_text(encoding="utf-8")
    blocks = re.findall(r"<style>(.*?)</style>", tpl, re.S)
    for b in blocks:
        if "--accent" in b and ".md p{" in b:
            return b
    return blocks[1] if len(blocks) > 1 else ""


def emit_html(data, share, base=None, nonce=""):
    """base set → the live tier: the libraries and the document bodies are
    fetched from the local server instead of being carried in the page."""
    page = (share / "workspace.html").read_text(encoding="utf-8")
    vendor = share / "vendor"
    def v(name):
        f = vendor / name
        return f.read_text(encoding="utf-8", errors="replace") if f.is_file() else ""
    def sh(name):
        return (share / name).read_text(encoding="utf-8")
    # mermaid is 3 MB — carry it only when a document in this tree actually needs it
    wants_mermaid = any(MERMAID_FENCE.search(d.get("text") or "") for d in data["docs"])
    libs = ["marked.min.js", "highlight.min.js"] + (["mermaid.min.js"] if wants_mermaid else [])
    if base:
        libs_html = "".join(f'<script nonce="{nonce}" src="{base}/lib/{n}"></script>' for n in libs)
        data = dict(data, docs=[{k: x for k, x in d.items() if k != "text"} for d in data["docs"]])
    else:
        libs_html = "".join(f'<script nonce="{nonce}">' + v(n) + "</script>" for n in libs)
    # a static page has no server to ask, so the theme is baked in at build time
    theme = os.environ.get("RUBRICATOR_THEME") or ""
    if theme not in ("rubric", "slate", "bone"):
        try:
            sys.path.insert(0, str(share))
            import actions as _A
            theme = _A.config().get("theme") or "rubric"
        except Exception:
            theme = "rubric"
        if theme not in ("rubric", "slate", "bone"):
            theme = "rubric"
    page = page.replace('<html lang="en" data-theme="rubric" data-mode="dark">',
                        f'<html lang="en" data-theme="{theme}" '
                        f'data-mode="{"light" if theme == "bone" else "dark"}">', 1)
    parts = {
        "__NAME__": html.escape(data["name"]),
        "__BASECSS__": design_css(share),
        "__SHELLCSS__": sh("shell.css"),
        "__REVIEWCSS__": sh("review.css"),
        "__LIBS__": libs_html,
        "__RENDERJS__": sh("render.js"),
        "__REVIEWJS__": sh("review.js"),
        "__SHELLJS__": sh("shell.js"),
        "__WSJS__": sh("workspace.js"),
        "__DATA__": json.dumps(data, ensure_ascii=False).replace("</", "<\\/"),
        "__NONCE__": nonce,
    }
    for k, val in parts.items():
        page = page.replace(k, val)
    hl = share / "vendor/hljs-dark.css"
    if hl.is_file():
        page = page.replace("</head>", "<style>html[data-mode=\"dark\"]{" +
                            hl.read_text(encoding="utf-8") + "}</style>\n</head>", 1)
    return page


# ── your own views ───────────────────────────────────────────────────────────
def user_views():
    """Anything in ~/.config/rubricator/views/*.js is loaded into the page and can
    register a tab of its own through RB.view({id, label, render})."""
    d = Path(os.environ.get("RUBRICATOR_CONFIG_DIR", HOME / ".config/rubricator")) / "views"
    out = []
    if d.is_dir():
        for f in sorted(d.glob("*.js")):
            try:
                out.append({"name": f.stem, "src": f.read_text(encoding="utf-8")[:400_000]})
            except Exception:
                pass
    return out


# ── notes on disk ────────────────────────────────────────────────────────────
def notes_file(root):
    return root / ".rubricator" / "notes.json"


def read_notes(root):
    try:
        d = json.loads(notes_file(root).read_text(encoding="utf-8"))
        return d if isinstance(d, dict) else {}
    except Exception:
        return {}


def write_notes(root, path, store):
    """One file per repo, keyed by absolute document path. Kept out of git's way
    via .git/info/exclude rather than .gitignore, so nothing tracked is touched
    and committing it stays your choice."""
    f = notes_file(root)
    all_notes = read_notes(root)
    if store and store.get("items"):
        all_notes[path] = store
    else:
        all_notes.pop(path, None)
    f.parent.mkdir(parents=True, exist_ok=True)
    tmp = f.with_suffix(".part")
    tmp.write_text(json.dumps(all_notes, ensure_ascii=False, indent=1), encoding="utf-8")
    tmp.replace(f)
    ex = root / ".git" / "info" / "exclude"
    try:
        if ex.parent.is_dir():
            body = ex.read_text(encoding="utf-8") if ex.is_file() else ""
            if ".rubricator/" not in body:
                ex.write_text(body.rstrip("\n") + "\n.rubricator/\n", encoding="utf-8")
    except Exception:
        pass
    return len(all_notes)


# ── the live tier ────────────────────────────────────────────────────────────
def serve_workspace(roots, with_sessions, share, open_rel, deep=False, port=0, idle=None):
    sys.path.insert(0, str(share))
    import serve as S

    import actions as A
    root = Path(roots[0]) if isinstance(roots, list) else Path(roots)
    A.remember_project(root)        # opening it is what makes it recent
    state = {"data": build(roots, with_sessions, deep)}
    state["data"]["open"] = open_rel or ""

    def page(method, query, body):
        data = dict(state["data"])
        data["base"] = srv.base
        data["caps"] = {"live": 1, "text": 1, "reindex": 1, "notes": 1, "asset": 1,
                        "conversation": 1,
                        # a seam for driving the page: an open SSE channel stops
                        # headless Chrome's virtual clock from ever finishing
                        "watch": 0 if os.environ.get("RUBRICATOR_NO_WATCH") else 1,
                        "settings": 1,
                        "launch": 1 if A.enabled() else 0,
                        "reveal": 1 if A.enabled() else 0}
        data["settings"] = A.settings()
        data["recents"] = [p for p in A.recents() if p != str(root)]
        data["views"] = user_views()
        data["notes"] = read_notes(root)
        # a second wall behind the sanitiser: only scripts carrying this run's
        # nonce may execute, so an inline handler that slipped through is inert
        import secrets as _s
        nonce = _s.token_urlsafe(12)
        html_out = emit_html(data, share, base=srv.base, nonce=nonce)
        inject = os.environ.get("RUBRICATOR_INJECT")     # a seam for driving the live page
        if inject and os.path.isfile(inject):
            extra_js = Path(inject).read_text(encoding="utf-8").replace(
                "<script>", f'<script nonce="{nonce}">')   # the policy applies to it too
            html_out = html_out.replace("</body>", extra_js + "</body>", 1)
        csp = ("default-src 'none'; "
               f"script-src 'nonce-{nonce}' 'unsafe-eval'; "
               "style-src 'unsafe-inline'; img-src 'self' data: blob:; "
               "font-src data:; connect-src 'self'; base-uri 'none'; "
               "form-action 'none'; frame-ancestors 'none'")
        return 200, "text/html; charset=utf-8", html_out, {"Content-Security-Policy": csp}

    def text(method, query, body):
        """A PDF or a Word file is read here, the first time anything asks for
        it, and cached from then on."""
        want = set(S.json_body(body).get("rels") or [])
        out, meta = {}, {}
        X = _extractor()
        for d in state["data"]["docs"]:
            if want and d["rel"] not in want:
                continue
            if d.get("text") is None and d.get("kind") in ("pdf", "word"):
                got = X.extract(d["abs"]) or {}
                if got.get("error"):
                    d["text"], d["note"] = "", got["error"]
                else:
                    d["text"] = got.get("text") or ""
                    d["words"] = len(d["text"].split())
                    if got.get("pages"):
                        d["pages"] = got["pages"]
                    if got.get("empty"):
                        d["note"] = "no text layer — this is a picture of a document"
                meta[d["rel"]] = {k: d[k] for k in ("words", "pages", "note") if k in d}
            out[d["rel"]] = d.get("text") or ""
        return S.J({"text": out, "meta": meta})

    def session(method, query, body):
        """The other half of a conversation. Read straight off disk, never
        indexed: the largest transcript here is 17 MB and parses in 0.05 s,
        so there is nothing worth caching and nothing to invalidate."""
        sid = (query.get("id") or [""])[0]
        try:
            sys.path.insert(0, str(share))
            import transcript as _T
            return S.J(_T.read(sid))
        except Exception as e:
            return S.J({"id": sid, "error": str(e)[:200], "turns": []})

    def asset(method, query, body):
        rel = (query.get("p") or [""])[0]
        try:
            f = (root / rel).resolve()
            f.relative_to(root)                    # never serve outside the tree
            if not f.is_file() or f.stat().st_size > 40_000_000:
                raise ValueError
        except Exception:
            return 404, "text/plain", b"no"
        import mimetypes
        ctype = mimetypes.guess_type(f.name)[0] or "application/octet-stream"
        return 200, ctype, f.read_bytes()

    def reindex(method, query, body):
        state["data"] = build(roots, with_sessions, deep)
        d = dict(state["data"])
        d["docs"] = [{k: x for k, x in doc.items() if k != "text"} for doc in d["docs"]]
        d["notes"] = read_notes(root)
        return S.J(d)

    def notes(method, query, body):
        if method == "GET":
            return S.J(read_notes(root))
        b = S.json_body(body)
        path, store = b.get("path") or "", b.get("store")
        if not path or not isinstance(store, dict):
            return S.J({"error": "bad note"}, 400)
        n = write_notes(root, path, store)
        return S.J({"ok": True, "documents": n})

    def act(method, query, body):
        """A verb and an id. Everything else is resolved here, from the index."""
        b0 = S.json_body(body)
        if b0.get("verb") in ("open-project", "open-recent"):
            try:
                if b0["verb"] == "open-project":
                    chosen = A.choose_folder()
                    if not chosen:
                        return S.J({"cancelled": True})
                else:
                    chosen = b0.get("id") or ""
                    if chosen not in A.recents():        # only what we remembered
                        return S.J({"error": "that project is not on the list"}, 400)
                return S.J(A.open_project(chosen, sessions=with_sessions))
            except Exception as e:
                return S.J({"error": str(e)}, 500)
        if not A.enabled():
            return S.J({"error": "actions are off — start with md --allow-launch"}, 403)
        b = S.json_body(body)
        verb, ident = b.get("verb") or "", b.get("id") or ""
        docs = {d["rel"]: d for d in state["data"]["docs"]}
        try:
            if verb == "launch":
                d = docs.get(ident)
                return S.J(A.launch(root, d["abs"] if d else "", b.get("text") or ""))
            if verb in ("resume", "fork"):
                m = (state["data"].get("sessions") or {}).get(ident)
                if not m or not m.get("live"):
                    return S.J({"error": "that session has no transcript to resume"}, 400)
                cwd = m.get("p") or str(root)
                if not os.path.isdir(cwd):
                    cwd = str(root)
                return S.J(A.resume(cwd, ident, fork=(verb == "fork")))
            if verb in ("reveal", "edit"):
                d = docs.get(ident)
                if not d:
                    return S.J({"error": "no such document"}, 400)
                return S.J(A.reveal(d["abs"]) if verb == "reveal" else A.edit(d["abs"]))
        except Exception as e:
            return S.J({"error": str(e)}, 500)
        return S.J({"error": "unknown verb"}, 400)

    def snapshot():
        out = {}
        for d in state["data"]["docs"]:
            try:
                out[d["rel"]] = int(os.stat(d["abs"]).st_mtime)
            except OSError:
                out[d["rel"]] = 0
        return out

    @S.stream
    def events(wfile):
        """Watch mode. The page asked to be told when a document changes, so tell
        it — one line per change, until the window goes away."""
        last = snapshot()
        wfile.write(b": watching\n\n")
        wfile.flush()
        while not srv.stop.is_set():
            if srv.stop.wait(1.0):
                break
            now_ = snapshot()
            changed = [r for r, t in now_.items()
                       if t and last.get(r) is not None and t != last[r]]
            added = [r for r in now_ if r not in last]
            gone = [r for r in last if r not in now_]
            last = now_
            if changed or added or gone:
                for d in state["data"]["docs"]:
                    if d["rel"] in changed:
                        try:
                            d["text"] = Path(d["abs"]).read_text(encoding="utf-8", errors="replace")
                            d["mtime"] = now_[d["rel"]]
                        except Exception:
                            pass
                msg = json.dumps({"changed": changed, "added": added, "gone": gone})
                wfile.write(b"data: " + msg.encode() + b"\n\n")
                wfile.flush()

    def settings(method, query, body):
        if method == "GET":
            return S.J(A.settings())
        try:
            saved = A.save_settings(S.json_body(body).get("set") or {})
        except ValueError as e:
            return S.J({"error": str(e)}, 400)
        # a change to what may be launched takes effect at once, without a restart
        return S.J({"settings": saved,
                    "caps": {"launch": 1 if A.enabled() else 0,
                             "reveal": 1 if A.enabled() else 0}})

    routes = {"": page, "text": text, "asset": asset, "reindex": reindex,
              "notes": notes, "act": act, "events": events, "settings": settings,
              "session": session}
    srv = S.Server(routes, idle=idle if idle is not None else S.IDLE)
    if port:
        srv.httpd.server_close()
        import http.server as _h
        srv.httpd = _h.ThreadingHTTPServer(("127.0.0.1", port), srv._handler())
        srv.httpd.daemon_threads = True
        srv.port = port
    for name in ("marked.min.js", "highlight.min.js", "mermaid.min.js"):
        def one(method, query, body, _n=name):
            f = share / "vendor" / _n
            if not f.is_file():
                return 404, "text/plain", b"no"
            return 200, "application/javascript; charset=utf-8", f.read_bytes()
        routes["lib/" + name] = one
    routes.update(S.lifecycle_routes(srv))
    srv.start()
    return srv


def main():
    args = sys.argv[1:]
    with_sessions = "--sessions" in args
    live = "--serve" in args
    deep = "--deep" in args
    stay = "--stay" in args
    port = 0
    for a in args:
        if a.startswith("--port="):
            port = int(a.split("=", 1)[1] or 0)
    args = [a for a in args if not a.startswith("--")]
    roots = [Path(a).resolve() for a in args] or [Path.cwd()]
    for r in roots:
        if not r.is_dir():
            sys.stderr.write(f"rubricator: not a directory: {r}\n")
            return 1
    root = roots[0]

    if live:
        share = Path(os.environ.get("RUBRICATOR_HOME", Path(__file__).resolve().parent))
        # settings you stored count as if you had typed them
        sys.path.insert(0, str(share))
        try:
            import actions as _A
            cfg = _A.config()
            deep = deep or bool(cfg.get("deep"))
            idle = int(cfg.get("idle") or 0) or None
        except Exception:
            idle = None
        srv = serve_workspace(roots, with_sessions, share,
                              os.environ.get("RUBRICATOR_OPEN") or "", deep=deep,
                              port=port, idle=10 ** 9 if stay else idle)
        sys.stdout.write(srv.base + "/\n")
        sys.stdout.flush()
        srv.wait()
        return 0

    data = build(roots, with_sessions, deep, extract_now=True)   # a static page carries it all
    # …except your prompts. `bin/md:165` refuses `--out` with `--sessions` on the
    # principle that your history stays on this machine, and then this path wrote
    # the same corpus into ~/.cache/rubricator/workspace-<hash>.html — 8 MB of it,
    # reached with no flag whenever the local server does not come up. A refusal
    # that guards one write path and not the other is not a refusal. The cost is
    # real and is the right cost: a static workspace loses prompt search, and
    # says so rather than returning nothing.
    if data.get("prompts"):
        data["promptsWithheld"] = len(data["prompts"])
        data["prompts"] = []
    # a document to open straight away — bare `md` passes the README this way
    want = os.environ.get("RUBRICATOR_OPEN") or ""
    if want:
        try:
            rel = str((root / want).resolve().relative_to(root))
        except Exception:
            rel = ""
        if any(d["rel"] == rel for d in data["docs"]):
            data["open"] = rel
    # The notes on disk travel with a static page too. Without this the static
    # tier could only ever see what that browser profile happened to hold, which
    # is the same defect as L3 with a different cause — and a page you hand to
    # someone should carry the marks you made in it.
    data["notes"] = read_notes(root)

    if os.environ.get("RUBRICATOR_JSON"):
        json.dump(data, sys.stdout)
        return 0
    share = Path(os.environ.get("RUBRICATOR_HOME", Path(__file__).resolve().parent))
    out = os.environ.get("RUBRICATOR_OUT")
    page = emit_html(data, share)
    if out:
        Path(out).write_text(page, encoding="utf-8")
        # A page that lands in the cache was never asked for and carries every
        # document body in the repository, so it gets the cache's mode. A path
        # the human typed keeps their umask: `--out` is the one gesture that
        # means *I intend to move this*, and surprising them with 0600 there
        # would be a different kind of dishonesty.
        try:
            if Path(out).resolve().is_relative_to(CACHE.resolve()):
                os.chmod(out, 0o600)
        except Exception:
            pass
        sys.stdout.write(out + "\n")
    else:
        sys.stdout.write(page)
    return 0


if __name__ == "__main__":
    sys.exit(main())
