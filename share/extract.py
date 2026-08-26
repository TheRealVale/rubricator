#!/usr/bin/env python3
"""
Text out of the documents that are not markdown.

Both extractors ship with macOS, which is the whole reason this is worth doing:

  Word (.docx .doc .rtf .odt)  textutil, a normal command
  PDF                          PDFKit, reached through the JXA ObjC bridge,
                               because PyObjC is not installed anywhere here

Neither needs Automation permission — a framework call is not scripting another
application — and neither adds a dependency. Results are cached against mtime
and size, so a second look at the same file costs nothing.
"""
import hashlib, json, os, subprocess, time
from pathlib import Path

CACHE = Path(os.environ.get("RUBRICATOR_CACHE", Path.home() / ".cache/rubricator")) / "extract"
WORD = {".docx": 1, ".doc": 1, ".rtf": 1, ".odt": 1, ".wordml": 1}
MAX_BYTES = 80_000_000
MAX_TEXT = 4_000_000
TIMEOUT = 90


def kind_of(path):
    ext = Path(path).suffix.lower()
    if ext == ".pdf":
        return "pdf"
    if ext in WORD:
        return "word"
    return None


def _stamp(p):
    st = os.stat(p)
    return f"{int(st.st_mtime)}:{st.st_size}"


def _cache_path(p):
    return CACHE / (hashlib.sha1(str(p).encode("utf-8")).hexdigest()[:16] + ".json")


def cached(path):
    """What we already know, or None. Never extracts."""
    try:
        f = _cache_path(path)
        d = json.loads(f.read_text(encoding="utf-8"))
        return d if d.get("stamp") == _stamp(path) else None
    except Exception:
        return None


def _store(path, data):
    try:
        CACHE.mkdir(parents=True, exist_ok=True)
        os.chmod(CACHE, 0o700)
        data["stamp"] = _stamp(path)
        f = _cache_path(path)
        tmp = f.with_suffix(".part")
        tmp.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
        tmp.replace(f)
        os.chmod(f, 0o600)      # this is the plaintext of the document
    except Exception:
        pass
    return data


# ── PDF ──────────────────────────────────────────────────────────────────────
JXA = """
ObjC.import("Quartz");
var path = %s;
var doc = $.PDFDocument.alloc.initWithURL($.NSURL.fileURLWithPath(path));
if (doc.isNil()) { JSON.stringify({error: "unreadable"}) }
else if (doc.isLocked) { JSON.stringify({error: "locked"}) }
else {
  var pages = [];
  for (var i = 0; i < doc.pageCount; i++) {
    var pg = doc.pageAtIndex(i);
    pages.push(pg.isNil() ? "" : ObjC.unwrap(pg.string));
  }
  JSON.stringify({pages: pages});
}
"""


def _pdf(path):
    src = JXA % json.dumps(str(path))
    try:
        r = subprocess.run(["osascript", "-l", "JavaScript", "-e", src],
                           capture_output=True, timeout=TIMEOUT)
    except subprocess.TimeoutExpired:
        return {"kind": "pdf", "error": "took too long to read"}
    if r.returncode != 0:
        return {"kind": "pdf", "error": "could not be opened"}
    try:
        d = json.loads(r.stdout.decode("utf-8", "replace") or "{}")
    except Exception:
        return {"kind": "pdf", "error": "could not be read"}
    if d.get("error"):
        return {"kind": "pdf", "error": {"locked": "password protected",
                                         "unreadable": "not a readable PDF"}.get(d["error"], d["error"])}
    pages = [p or "" for p in d.get("pages", [])]
    # a heading per page: the outline gets entries, and a quote can cite one
    parts = []
    for i, txt in enumerate(pages):
        txt = txt.strip()
        parts.append(f"## Page {i + 1}\n\n" + txt if txt else f"## Page {i + 1}")
    text = "\n\n".join(parts)[:MAX_TEXT]
    body = "".join(pages).strip()
    return {"kind": "pdf", "pages": len(pages), "text": text,
            "empty": len(body) < 40}


# ── Word ─────────────────────────────────────────────────────────────────────
def _word(path, as_html=False):
    fmt = "html" if as_html else "txt"
    try:
        r = subprocess.run(["textutil", "-convert", fmt, "-stdout", str(path)],
                           capture_output=True, timeout=TIMEOUT)
    except subprocess.TimeoutExpired:
        return {"kind": "word", "error": "took too long to read"}
    if r.returncode != 0:
        return {"kind": "word", "error": "could not be converted"}
    out = r.stdout.decode("utf-8", "replace")[:MAX_TEXT]
    key = "html" if as_html else "text"
    return {"kind": "word", key: out, "empty": len(out.strip()) < 40}


# ── the one door ─────────────────────────────────────────────────────────────
def extract(path, refresh=False, html=False):
    path = str(Path(path).resolve())
    kind = kind_of(path)
    if not kind:
        return None
    if not refresh:
        hit = cached(path)
        if hit and (not html or "html" in hit):
            return hit
    try:
        if os.path.getsize(path) > MAX_BYTES:
            return _store(path, {"kind": kind, "error": "too large to read"})
    except OSError:
        return {"kind": kind, "error": "gone"}

    t = time.time()
    if kind == "pdf":
        out = _pdf(path)
    else:
        out = _word(path)
        if html and not out.get("error"):
            out.update(_word(path, as_html=True))
    out["took"] = round(time.time() - t, 2)
    return _store(path, out)


if __name__ == "__main__":
    import sys
    for f in sys.argv[1:]:
        d = extract(f) or {"error": "not a kind we read"}
        t = d.get("text") or ""
        print(f'{Path(f).name}: kind={d.get("kind")} pages={d.get("pages","-")} '
              f'chars={len(t)} empty={d.get("empty")} took={d.get("took")}s '
              f'{d.get("error","")}')
