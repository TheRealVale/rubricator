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
        e = commits.setdefault(chunk, {"n": 0, "last": 0})
        e["n"] += 1
        e["last"] = max(e["last"], cur or 0)

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


def load_sessions(limit_project=None):
    prompts, hist = [], HOME / ".claude/history.jsonl"
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
                prompts.append({"sid": d.get("sessionId"), "project": d.get("project") or "",
                                "t": int((d.get("timestamp") or 0) / 1000),
                                "text": scrub(txt)[:600]})
    touches, sessions = {}, {}
    root = HOME / ".claude/projects"
    if root.is_dir():
        for p in root.glob("*/*.jsonl"):
            sid = p.stem
            seen = set()
            try:
                with p.open(encoding="utf-8", errors="replace") as f:
                    for line in f:
                        if '"file_path"' not in line:
                            continue
                        seen.update(re.findall(r'"file_path":"([^"]+)"', line))
            except Exception:
                continue
            seen = {f for f in seen if not SCRATCH.search(f)}
            if not seen:
                continue
            sessions[sid] = sorted(seen)
            for f_ in seen:
                touches.setdefault(f_, []).append(sid)
    return prompts, sessions, touches


# ── assembly ─────────────────────────────────────────────────────────────────
def build(root, with_sessions):
    t0 = time.time()
    docs = []
    for path, rel in find_docs(root):
        d = read_doc(path, rel, root)
        if d:
            docs.append(d)
    commits, stale = git_activity(root, docs)
    data = {
        "root": str(root), "name": root.name, "generated": int(time.time()),
        "docs": docs, "stale": stale, "hasGit": bool(commits),
        "sessions": {}, "prompts": [], "touches": {}, "withSessions": with_sessions,
    }
    if with_sessions:
        prompts, sessions, touches = load_sessions()
        data["prompts"] = prompts
        data["sessions"] = sessions
        data["touches"] = touches
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


def emit_html(data, share):
    page = (share / "workspace.html").read_text(encoding="utf-8")
    vendor = share / "vendor"
    def v(name):
        f = vendor / name
        return f.read_text(encoding="utf-8", errors="replace") if f.is_file() else ""
    parts = {
        "__NAME__": html.escape(data["name"]),
        "__BASECSS__": design_css(share),
        "__MARKED__": v("marked.min.js"),
        "__HLJS__": v("highlight.min.js"),
        "__WSJS__": (share / "workspace.js").read_text(encoding="utf-8"),
        "__DATA__": json.dumps(data, ensure_ascii=False).replace("</", "<\\/"),
    }
    for k, val in parts.items():
        page = page.replace(k, val)
    hl = share / "vendor/hljs-dark.css"
    if hl.is_file():
        page = page.replace("</head>", "<style>html[data-theme=\"dark\"]{" +
                            hl.read_text(encoding="utf-8") + "}</style>\n</head>", 1)
    return page


def main():
    args = sys.argv[1:]
    with_sessions = "--sessions" in args
    args = [a for a in args if not a.startswith("--")]
    root = Path(args[0]).resolve() if args else Path.cwd()
    if not root.is_dir():
        sys.stderr.write(f"rubricator: not a directory: {root}\n")
        return 1
    data = build(root, with_sessions)
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
