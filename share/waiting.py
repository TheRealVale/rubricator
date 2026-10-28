"""Which of your Claude Code sessions are running now, and which wait on you.

Claude Code writes one small file per running session to
`~/.claude/sessions/<pid>.json`: the process, the session id, where it was
started, a name, and a `status` with the time it last changed. That file is
Claude Code's own and undocumented, so what this reads of it was measured
rather than assumed — on 2.1.309, 2026-10-26, against fourteen sessions
running at once:

- the binary's own list of statuses is `busy`, `shell`, `idle` and `waiting`,
  and three of the four were on disk: `busy` while a turn runs, `idle` once it
  has ended, and `shell`, which the binary derives from `idle` — 7, 6 and 1 in
  one reading, 7, 5 and 2 in the next. Both `shell` sessions had ended their
  turn with a background command they started still unreported, so each is
  likely to carry on by itself; the idle one whose command had reported was
  `idle` again;
- `waiting` was in neither reading. The binary's code writes it while a
  dialog is open on the human — a permission prompt, a question — with
  `waitingFor`, the dialog's one-line reason. A later reading, 2026-10-28 on
  2.1.302, found it on disk with `waitingFor` "input needed"; the list treats
  it as asking and shows the reason as written;
- a file outlives a crash, and a pid is reused, so a session counts as running
  only while `ps` finds a process called `claude` at that pid.

What a waiting session last said is in its transcript, and only at the end of
it. Transcripts on this machine run past a gigabyte, so this reads the tail
and nothing else: a quarter of a megabyte first, four times as much while no
reply of Claude's is in what was read, sixteen at most. On the 1.4 GB one that
is a quarter of a megabyte and two milliseconds.

What a running session is about is its first prompt, taken from
`~/.claude/history.jsonl` by the rule the history index names every session
with — the first thing you typed that is not plumbing like `/clear` — so a
session reads the same in the Sessions list before the index exists as after.
That file is every prompt ever typed and nothing else: 2.3 MB and 7,800 lines
here, scanned in 5 ms.

Nothing is cached and nothing is written: the list is built again each time
the page asks, because a session's state is minutes old at most.
"""

import calendar
import glob
import json
import os
import re
import subprocess
import time
from pathlib import Path

HOME = Path(os.path.expanduser("~"))
SESSIONS = Path(os.environ.get("RUBRICATOR_CLAUDE_SESSIONS", HOME / ".claude/sessions"))
PROJECTS = Path(os.environ.get("RUBRICATOR_CLAUDE_PROJECTS", HOME / ".claude/projects"))
HISTORY = Path(os.environ.get("RUBRICATOR_CLAUDE_HISTORY", HOME / ".claude/history.jsonl"))

# what each status means for the human, as measured above
ON_YOU = {"waiting": "asking", "idle": "done", "shell": "background"}
WORKING = {"busy"}

TAIL_FIRST = 256 * 1024
TAIL_MOST = 16 * 1024 * 1024
MAX_TEXT = 40_000

try:
    from transcript import scrub                   # one scrubbing list, not two
except Exception:                                  # standalone
    def scrub(s):
        return s
try:
    from transcript import harness_text            # what the harness writes, never yours
except Exception:                                  # standalone
    def harness_text(s):
        return False
try:
    from workspace import is_slash_noise           # the index's own rule for a name
except Exception:                                  # standalone
    def is_slash_noise(s):
        return False

SESSION_ID = re.compile(rb'"sessionId"\s*:\s*"([^"\\]{1,80})"')
FIRST_MAX = 120                                    # what the index keeps of it


def _alive(pids):
    """The pids `ps` finds a process called `claude` at. One call for all of
    them; a pid the kernel has since given to something else does not count."""
    if not pids:
        return set()
    try:
        out = subprocess.run(["ps", "-o", "pid=,comm=", "-p", ",".join(str(p) for p in pids)],
                             capture_output=True, text=True, timeout=5).stdout
    except Exception:
        return set()
    live = set()
    for line in out.splitlines():
        parts = line.split(None, 1)
        if len(parts) == 2 and parts[0].isdigit() and os.path.basename(parts[1].strip()) == "claude":
            live.add(int(parts[0]))
    return live


def _transcript(sid):
    if not re.fullmatch(r"[0-9a-fA-F-]{8,40}", sid or ""):
        return None
    hits = glob.glob(str(PROJECTS / "*" / f"{sid}.jsonl"))
    return Path(hits[0]) if hits else None


def _is_reply(r):
    if r.get("type") != "assistant" or r.get("isSidechain"):
        return False
    content = (r.get("message") or {}).get("content")
    return isinstance(content, list) and any(
        isinstance(b, dict) and b.get("type") == "text" and (b.get("text") or "").strip()
        for b in content)


def tail(path):
    """The records at the end of a transcript, and how many bytes it took."""
    size = path.stat().st_size
    n = TAIL_FIRST
    while True:
        n = min(n, size)
        with path.open("rb") as f:
            f.seek(size - n)
            blob = f.read(n)
        lines = blob.split(b"\n")
        if n < size:
            lines = lines[1:]                     # the first line was cut in half
        recs = []
        for ln in lines:
            if not ln.strip():
                continue
            try:
                recs.append(json.loads(ln))
            except Exception:
                continue                          # a line being written as we read
        if n >= size or n >= TAIL_MOST or any(_is_reply(r) for r in recs):
            return recs, n
        n *= 4


def _when(ts):
    try:
        return calendar.timegm(time.strptime((ts or "")[:19], "%Y-%m-%dT%H:%M:%S"))
    except Exception:
        return 0


def last_reply(recs):
    """What Claude said last: the text of its records after the last record
    that wears the user's name — a tool's result or your prompt — so a reply
    that ran tools first reads as the part it ended on."""
    turn = [r for r in recs if r.get("type") in ("user", "assistant") and not r.get("isSidechain")]
    cut = max((i for i, r in enumerate(turn) if r["type"] == "user"), default=-1)
    after = [r for r in turn[cut + 1:] if _is_reply(r)]
    if not after:                                 # the turn ended on a tool; say what came before
        after = [r for r in turn if _is_reply(r)][-1:]
    if not after:
        return "", 0
    text = "\n\n".join(
        b.get("text").strip()
        for r in after for b in r["message"]["content"]
        if isinstance(b, dict) and b.get("type") == "text" and (b.get("text") or "").strip())
    return scrub(text[:MAX_TEXT]), _when(after[-1].get("timestamp"))


def first_prompts(sids):
    """The first thing you asked in each of these sessions, by the history
    index's rule, so a running session is named the way the Sessions list
    names it once its index arrives. A session with nothing typed yet is not
    in the result, and the page names it by its terminal name instead."""
    want, out = set(sids), {}
    if not want:
        return out
    try:
        f = HISTORY.open("rb")
    except OSError:
        return out
    with f:
        for line in f:
            m = SESSION_ID.search(line)
            if not m:
                continue
            sid = m.group(1).decode("utf-8", "replace")
            if sid not in want or sid in out:
                continue
            try:
                txt = json.loads(line).get("display") or ""
            except Exception:
                continue                          # a line being written as we read
            if not isinstance(txt, str) or not txt or is_slash_noise(txt) or harness_text(txt):
                continue
            out[sid] = scrub(txt)[:FIRST_MAX]
            if len(out) == len(want):
                break
    return out


def signature():
    """What the session files say, cheap enough to compare every second: which
    files there are and the status each gives. It compares the status, not when
    a file was written, so it moves when a session starts, ends, or changes what
    it is doing — the moments the list on screen goes out of date."""
    if not SESSIONS.is_dir():
        return ()
    out = []
    for f in sorted(SESSIONS.glob("*.json")):
        try:
            d = json.loads(f.read_text(encoding="utf-8"))
            out.append((f.name, d.get("sessionId"), d.get("status"),
                        d.get("statusUpdatedAt"), d.get("waitingFor")))
        except Exception:
            out.append((f.name,))                 # a file mid-write, or of another shape
    return tuple(out)


def _inside(path, roots):
    if not path:
        return False
    path = os.path.realpath(path)          # git names worktrees by their real path
    return any(path == r or path.startswith(r + "/") for r in roots)


def _worktrees(roots):
    """A repository's worktrees count as the repository: a session working in
    a tree beside the checkout is still working on it."""
    out = list(roots)
    for r in roots:
        try:
            got = subprocess.run(["git", "-C", r, "worktree", "list", "--porcelain"],
                                 capture_output=True, text=True, timeout=5).stdout
        except Exception:
            continue
        out += [ln[len("worktree "):] for ln in got.splitlines() if ln.startswith("worktree ")]
    return sorted({os.path.realpath(p) for p in out})


def running(roots=(), replies=True):
    """Every running session, what state it is in and since when, what it is
    about, and for each one that waits on you what it last said. `state` says
    which kind of empty an empty list is. Without `replies` it is only which
    sessions run, for the guard on resume."""
    t0 = time.time()
    out = {"state": "ok", "sessions": [], "files": 0, "misshapen": 0, "took": 0}
    if not SESSIONS.is_dir():
        out["state"] = "no-dir"
        return out
    rows = []
    for f in SESSIONS.glob("*.json"):
        out["files"] += 1
        try:
            d = json.loads(f.read_text(encoding="utf-8"))
            pid, sid, status = d["pid"], d["sessionId"], d["status"]
            if not (isinstance(pid, int) and isinstance(sid, str) and isinstance(status, str)):
                raise ValueError
        except Exception:
            out["misshapen"] += 1
            continue
        rows.append(d)
    if out["files"] and not rows:
        out["state"] = "unreadable"
        return out

    live = _alive([d["pid"] for d in rows])
    rows = [d for d in rows if d["pid"] in live]
    scope = _worktrees([str(r) for r in roots])
    first = first_prompts([d["sessionId"] for d in rows]) if replies else {}
    now = int(time.time())
    for d in rows:
        sid, status = d["sessionId"], d["status"]
        row = {"sid": sid, "pid": d["pid"], "status": status,
               "on": ON_YOU.get(status) or ("working" if status in WORKING else "unknown"),
               "name": d.get("name") or "", "cwd": d.get("cwd") or "",
               "since": int((d.get("statusUpdatedAt") or 0) / 1000) or now,
               "waitingFor": d.get("waitingFor") or "",
               "first": first.get(sid, "")}
        # whether there is a conversation to open, for every session; what it
        # last said, only for the ones that wait on you
        p = _transcript(sid) if replies else None
        row["transcript"] = p is not None
        if p is not None and row["on"] != "working":
            try:
                recs, n = tail(p)
            except OSError:
                recs, n = [], 0
            row["read"] = n
            row["text"], row["said"] = last_reply(recs)
            row["title"] = next((r.get("aiTitle") for r in reversed(recs)
                                 if r.get("type") == "ai-title" and r.get("aiTitle")), "")
            row["here"] = next((r.get("cwd") for r in reversed(recs) if r.get("cwd")), "")
        row["inRepo"] = _inside(row["cwd"], scope) or _inside(row.get("here", ""), scope)
        out["sessions"].append(row)
    out["sessions"].sort(key=lambda r: -r["since"])
    out["took"] = round(time.time() - t0, 3)
    return out


def ids():
    """The ids of the sessions running now, for the guard on resume."""
    return {r["sid"] for r in running(replies=False)["sessions"]}


def session_file(sid):
    """What Claude Code's own file says of the running session with this id,
    read now, or None. A crash leaves its file behind and a resume writes a new
    one, so two files can carry one id; the one whose process lives is it."""
    if not SESSIONS.is_dir():
        return None
    found = []
    for f in SESSIONS.glob("*.json"):
        try:
            d = json.loads(f.read_text(encoding="utf-8"))
        except Exception:
            continue
        if (isinstance(d, dict) and d.get("sessionId") == sid and isinstance(d.get("pid"), int)
                and isinstance(d.get("status"), str)):
            found.append(d)
    live = _alive([d["pid"] for d in found])
    return next((d for d in found if d["pid"] in live), None)


if __name__ == "__main__":
    import sys
    got = running([sys.argv[1]] if len(sys.argv) > 1 else [])
    for r in got["sessions"]:
        r["text"] = (r.get("text") or "")[:80]
    print(json.dumps(got, indent=1))
