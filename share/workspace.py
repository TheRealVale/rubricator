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
MD_EXT = {".md", ".markdown", ".mdown", ".mdx"}
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
    tracked = git(root, "ls-files", "-z").split("\0")
    if any(tracked):
        for rel in tracked:
            if rel and Path(rel).suffix.lower() in MD_EXT:
                p = root / rel
                if p.is_file():
                    yield p, rel
        return
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS and not d.startswith(".")]
        for fn in filenames:
            if Path(fn).suffix.lower() in MD_EXT:
                p = Path(dirpath) / fn
                yield p, str(p.relative_to(root))


HEADING = re.compile(r"^(#{1,6})\s+(.+?)\s*#*\s*$", re.M)
LINK = re.compile(r"\[[^\]]*\]\(([^)\s]+)")
MERMAID_FENCE = re.compile(r"^[ \t]*(?:```|~~~)[ \t]*mermaid\b", re.M)
WORD = re.compile(r"[A-Za-zÀ-ÿ][A-Za-zÀ-ÿ0-9_-]{2,}")


def read_doc(path, rel, root):
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
    return {"rel": rel, "abs": str(path), "title": title, "headings": heads,
            "links": links, "words": len(text.split()), "bytes": st.st_size,
            "mtime": int(st.st_mtime), "text": text}


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
        stem = Path(d["rel"]).parent.as_posix()
        for m in re.finditer(r"[`\"']([\w./-]+\.(?:ts|tsx|js|jsx|py|sql|go|rs|java|kt|vue|svelte))[`\"']", d["text"]):
            t = m.group(1).lstrip("./")
            for p in all_paths:
                if p.endswith(t):
                    targets.add(p)
                    break
        churn = sum(commits[t]["n"] for t in targets if commits[t]["last"] > last)
        repo_churn = sum(1 for p in all_paths if commits[p]["last"] > last)
        stale[d["rel"]] = {"commits": info.get("n", 0), "last": last,
                           "ts": info.get("ts", [])[:40],
                           "targets": sorted(targets)[:40],
                           "targetChurn": churn, "repoChurn": repo_churn}
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
                if not txt or txt.startswith("/"):        # slash commands aren't topics
                    continue
                sid = d.get("sessionId") or ""
                t = int((d.get("timestamp") or 0) / 1000)
                text = scrub(txt)[:600]
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
def build(roots, with_sessions, deep=False):
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
        for path, rel in find_docs(r):
            d = read_doc(path, rel, r)
            if d:
                d["root"] = str(r)
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


def emit_html(data, share, base=None):
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
        libs_html = "".join(f'<script src="{base}/lib/{n}"></script>' for n in libs)
        data = dict(data, docs=[{k: x for k, x in d.items() if k != "text"} for d in data["docs"]])
    else:
        libs_html = "".join("<script>" + v(n) + "</script>" for n in libs)
    parts = {
        "__NAME__": html.escape(data["name"]),
        "__BASECSS__": design_css(share),
        "__REVIEWCSS__": sh("review.css"),
        "__LIBS__": libs_html,
        "__RENDERJS__": sh("render.js"),
        "__REVIEWJS__": sh("review.js"),
        "__WSJS__": sh("workspace.js"),
        "__DATA__": json.dumps(data, ensure_ascii=False).replace("</", "<\\/"),
    }
    for k, val in parts.items():
        page = page.replace(k, val)
    hl = share / "vendor/hljs-dark.css"
    if hl.is_file():
        page = page.replace("</head>", "<style>html[data-theme=\"dark\"]{" +
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
    state = {"data": build(roots, with_sessions, deep)}
    state["data"]["open"] = open_rel or ""

    def page(method, query, body):
        data = dict(state["data"])
        data["base"] = srv.base
        data["caps"] = {"live": 1, "text": 1, "reindex": 1, "notes": 1, "asset": 1,
                        "watch": 1, "launch": 1 if A.enabled() else 0,
                        "reveal": 1 if A.enabled() else 0}
        data["views"] = user_views()
        data["notes"] = read_notes(root)
        html_out = emit_html(data, share, base=srv.base)
        inject = os.environ.get("RUBRICATOR_INJECT")     # a seam for driving the live page
        if inject and os.path.isfile(inject):
            html_out = html_out.replace("</body>", Path(inject).read_text(encoding="utf-8") + "</body>", 1)
        return 200, "text/html; charset=utf-8", html_out

    def text(method, query, body):
        want = set(S.json_body(body).get("rels") or [])
        out = {}
        for d in state["data"]["docs"]:
            if not want or d["rel"] in want:
                out[d["rel"]] = d.get("text", "")
        return S.J(out)

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

    routes = {"": page, "text": text, "asset": asset, "reindex": reindex,
              "notes": notes, "act": act, "events": events}
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
        srv = serve_workspace(roots, with_sessions, share,
                              os.environ.get("RUBRICATOR_OPEN") or "", deep=deep,
                              port=port, idle=None if not stay else 10 ** 9)
        sys.stdout.write(srv.base + "/\n")
        sys.stdout.flush()
        srv.wait()
        return 0

    data = build(roots, with_sessions, deep)
    # a document to open straight away — bare `md` passes the README this way
    want = os.environ.get("RUBRICATOR_OPEN") or ""
    if want:
        try:
            rel = str((root / want).resolve().relative_to(root))
        except Exception:
            rel = ""
        if any(d["rel"] == rel for d in data["docs"]):
            data["open"] = rel
    if os.environ.get("RUBRICATOR_JSON"):
        json.dump(data, sys.stdout)
        return 0
    share = Path(os.environ.get("RUBRICATOR_HOME", Path(__file__).resolve().parent))
    out = os.environ.get("RUBRICATOR_OUT")
    page = emit_html(data, share)
    if out:
        Path(out).write_text(page, encoding="utf-8")
        sys.stdout.write(out + "\n")
    else:
        sys.stdout.write(page)
    return 0


if __name__ == "__main__":
    sys.exit(main())
