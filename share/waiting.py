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

What a working session is doing is read from the end of its transcript as
well, for the band at the foot of its view, and only while that view is open:
the tool calls of Claude's latest message whose results have not come back,
and how many calls and output tokens the turn has taken. A turn is read once
from the end and then followed, a look reading only what was written since
the last — `doing` below.
"""

import calendar
import glob
import json
import os
import re
import subprocess
import threading
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
try:
    from transcript import brief, short            # what a tool was asked, in one line
except Exception:                                  # standalone
    def brief(name, inp):
        return ""

    def short(path, cwd):
        return path

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


def end(path, size=TAIL_FIRST):
    """The records in the last `size` bytes of a transcript, and no more."""
    total = path.stat().st_size
    n = min(size, total)
    with path.open("rb") as f:
        f.seek(total - n)
        blob = f.read(n)
    lines = blob.split(b"\n")
    if n < total:
        lines = lines[1:]                         # the first line was cut in half
    recs = []
    for ln in lines:
        if not ln.strip():
            continue
        try:
            recs.append(json.loads(ln))
        except Exception:
            continue                              # a line being written as we read
    return recs


# ── where a session works ────────────────────────────────────────────────────
# A session is a repository's when it was started in it or in one of its
# worktrees, and also when it works there: one started in ~/Repositories that
# edits, reads and runs commands in one checkout beside it says nothing by its
# cwd, but its tool calls do. They are read from the end of its transcript —
# the end already read for what a waiting session said, a quarter of a
# megabyte for a working one, and only for a session its cwd left out. Each
# call names the places it works in: the file a file tool works on, the folder
# a search looks in, and for a command, the folder it `cd`s to first and every
# absolute path it names — or, naming none, the shell's own folder, which
# every record carries as `cwd`. The places that are somebody's work vote,
# those in your home folder and on other volumes; scratch space, caches, the
# tools' own folders (`~/.claude`, `~/Library`) and the system do not. It works
# here when most of the votes lie in the repository or its worktrees, three at
# least. Measured 2026-10-28 on a session started in ~/Repositories and working
# in a worktree of one checkout beside it: the last quarter of a megabyte held
# six votes for that checkout and none elsewhere, and a session started in
# another repository held none for it and three against.
WORKS_MIN = 3
PATHISH = re.compile(r"""(?:^|(?<=[\s'"=:(,]))((?:~|/)[^\s'"`;|&<>(){}*?\[\]$\\,]+)""")
CD_FIRST = re.compile(r"""^\s*cd\s+(?:"([^"]+)"|'([^']+)'|([^\s;&|]+))""")


def places(recs):
    """Every place the tool calls in these records work in, once per call that
    names it."""
    out = []
    for r in recs:
        if r.get("type") != "assistant" or r.get("isSidechain"):
            continue
        cwd = r.get("cwd") or ""
        content = (r.get("message") or {}).get("content")
        for b in content if isinstance(content, list) else []:
            if not (isinstance(b, dict) and b.get("type") == "tool_use"):
                continue
            inp = b.get("input") if isinstance(b.get("input"), dict) else {}
            got = [inp[k] for k in ("file_path", "notebook_path", "path")
                   if isinstance(inp.get(k), str) and inp[k].startswith(("/", "~"))]
            if b.get("name") in ("Grep", "Glob") and not got and cwd:
                got.append(cwd)
            cmd = inp.get("command") if b.get("name") == "Bash" else None
            if isinstance(cmd, str):
                m = CD_FIRST.match(cmd)
                there = next((g for g in m.groups() if g), "") if m else ""
                named = PATHISH.findall(cmd)
                if there.startswith(("/", "~")):
                    got.append(there)
                elif not named:
                    got.append(cwd)                # it works where its shell is
                got += [x for x in named if x != there]
            out += [x for x in dict.fromkeys(got) if x]
    return out


def works_in(recs, scope):
    """How many of the places these records' tool calls work in that are
    somebody's work lie in the scope, and how many elsewhere."""
    home = str(HOME)
    mine = away = 0
    for p in places(recs):
        if p.startswith("~/"):
            p = home + p[1:]
        p = p.rstrip(".:")
        if not (p.startswith(home + "/") or p.startswith("/Volumes/")):
            continue                              # the system, scratch space: nobody's work
        if p.startswith((home + "/.", home + "/Library/")):
            continue                              # the tools' own folders
        if _inside(p, scope):
            mine += 1
        else:
            away += 1
    return mine, away


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
        recs = None
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
        if not row["inRepo"] and scope and p is not None:
            # started elsewhere: the files it works on may still be this repository's
            if recs is None:
                try:
                    recs = end(p)
                except OSError:
                    recs = []
            mine, away = works_in(recs, scope)
            if mine >= WORKS_MIN and mine > away:
                row["inRepo"] = row["worksHere"] = True
                row["named"] = [mine, away]
                home = str(HOME)
                row["began"] = ("~" + row["cwd"][len(home):]
                                if row["cwd"] == home or row["cwd"].startswith(home + "/") else row["cwd"])
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


# ── what a working session is doing ──────────────────────────────────────────
# A working session has no reply to show, but its transcript says what it is
# at. Claude's latest message holds the tool calls it made last, each a record
# of its own sharing the message's id, and each result comes back as a record
# that names its call: the calls of that message whose results have not come
# back are what runs now, and when every one has, Claude is thinking — or
# writing — its next message. Measured on 2.1.309: a busy session's transcript
# ends on the tool result and the harness's attachment after it while Claude
# thinks, and on the tool call while it runs.
#
# The turn is the stretch since the status turned `busy` (`statusUpdatedAt`),
# which is where its clock on the page starts too, and its tool calls and the
# output tokens of its messages are counted from there. A message's records
# each carry the message's usage, so tokens are counted once per message id.
#
# Only the end is read, and once. The first look at a turn reads backwards: a
# quarter of a megabyte, then four times as much until a record from before
# the turn is in it, sixteen megabytes at most, past which the counts are
# "at least" (`whole` false). The turn is kept here after that, by its session
# and the moment it began, with the byte its reading reached, and every later
# look reads only what was written since: a few kilobytes, every few seconds,
# while its view is open. A line still being written is left for the next
# look. Records of a kind no turn is made of — the logged API requests above
# all — are passed over by their first bytes, unparsed. On this machine, a turn
# of seventy calls was its transcript's last 4 MB, read the first time in
# 42 ms.
DOING_FIRST = 256 * 1024
DOING_MOST = 16 * 1024 * 1024
NOT_A_TURN = re.compile(rb'\{"type"\s*:\s*"(?!user"|assistant")')
STAMP = re.compile(rb'"timestamp"\s*:\s*"([0-9T:.-]+)Z?"')
WHAT_MAX = 160
_turns, _turns_lock = {}, threading.Lock()


def _ms(ts):
    """A transcript's timestamp, `2026-10-28T20:18:31.536Z`, in milliseconds."""
    try:
        s = calendar.timegm(time.strptime(ts[:19], "%Y-%m-%dT%H:%M:%S")) * 1000
    except Exception:
        return 0
    frac = ts[20:23] if ts[19:20] == "." else ""
    return s + (int(frac.ljust(3, "0")) if frac.isdigit() else 0)


def _what(name, inp, cwd):
    """What a tool call is about, in one line: a command's own description, the
    file a file tool works on, an agent's task, or whatever names its target."""
    if not isinstance(inp, dict):
        return ""
    if name in ("Read", "Edit", "Write", "MultiEdit", "NotebookEdit"):
        v = inp.get("file_path") or inp.get("notebook_path") or ""
        return short(v, cwd)[-WHAT_MAX:] if isinstance(v, str) else ""   # a path, which scrubbing mangles
    if name == "Bash":
        v = inp.get("description") or inp.get("command") or ""
    elif name in ("Agent", "Task"):
        v = inp.get("description") or inp.get("prompt") or ""
    else:
        v = brief(name, inp)
    v = v.strip().split("\n")[0] if isinstance(v, str) else ""
    return scrub(v[:WHAT_MAX])


class _Turn:
    """One working session's turn, as far as it has been read."""

    def __init__(self, path, since):
        self.path, self.since = path, since
        self.upto = 0              # the byte after the last whole line read
        self.read = 0              # bytes read by the latest look
        self.whole = False         # whether the turn's start was in what was read
        self.calls = 0
        self.tokens = {}           # message id → its output tokens
        self.msg = None            # Claude's latest message
        self.tools = []            # its calls: (id, tool, what)
        self.back = set()          # the ids of those whose result is back
        self.last = None           # the latest call whose result came back

    def fold(self, r):
        kind = r.get("type")
        if kind not in ("user", "assistant") or r.get("isSidechain"):
            return
        mine = _ms(r.get("timestamp") or "") >= self.since
        m = r.get("message") if isinstance(r.get("message"), dict) else {}
        content = m.get("content") if isinstance(m.get("content"), list) else []
        if kind == "assistant":
            mid = m.get("id") or ""
            if mid != self.msg:
                self.msg, self.tools, self.back = mid, [], set()
            out = (m.get("usage") or {}).get("output_tokens")
            if mine and isinstance(out, int):
                self.tokens[mid] = max(out, self.tokens.get(mid, 0))
            for b in content:
                if isinstance(b, dict) and b.get("type") == "tool_use":
                    self.calls += 1 if mine else 0
                    self.tools.append((b.get("id"), b.get("name") or "?",
                                       _what(b.get("name"), b.get("input"), r.get("cwd") or "")))
            return
        came = [b.get("tool_use_id") for b in content
                if isinstance(b, dict) and b.get("type") == "tool_result"]
        if not came:                               # a prompt: what was called before it is over
            self.msg, self.tools, self.back = None, [], set()
        for i in came:
            self.back.add(i)
            hit = next((t for t in self.tools if t[0] == i), None)
            if hit:
                self.last = hit

    @staticmethod
    def records(lines):
        for ln in lines:
            if not ln.strip() or NOT_A_TURN.match(ln):
                continue
            try:
                r = json.loads(ln)
            except Exception:
                continue                           # a line being written as we read
            if isinstance(r, dict):
                yield r

    def look(self):
        size = self.path.stat().st_size
        if size < self.upto:                       # written anew under the same name
            self.__init__(self.path, self.since)
        if self.upto:                              # what was written since the last look
            with self.path.open("rb") as f:
                f.seek(self.upto)
                blob = f.read(size - self.upto)
            lines = blob.split(b"\n")
            rest = lines.pop()                     # after the last line break: still being written
            for r in self.records(lines):
                self.fold(r)
            self.read = len(blob)
            self.upto += len(blob) - len(rest)
            return
        n = DOING_FIRST
        while True:
            n = min(n, size)
            with self.path.open("rb") as f:
                f.seek(size - n)
                blob = f.read(n)
            lines = blob.split(b"\n")
            rest = lines.pop()
            if n < size and lines:
                lines = lines[1:]                  # the first line was cut in half
            # the lines run oldest first, so the first one dated says whether
            # what was read reaches back past the turn's start
            first = next((m.group(1).decode() for m in map(STAMP.search, lines) if m), "")
            before = 0 < _ms(first) < self.since
            if before or n >= size or n >= DOING_MOST or not self.since:
                recs = list(self.records(lines))
                break
            n *= 4
        for r in recs:
            self.fold(r)
        self.whole = before or n >= size
        self.read = n
        self.upto = size - len(rest)


def doing(sid):
    """What the running session with this id is doing, read now: its status
    and since when, and while it works, the calls running now — none while it
    thinks — the latest whose result came back, and how many calls and output
    tokens its turn has taken so far."""
    d = session_file(sid)
    if not d:
        return {"sid": sid, "running": False}
    status = d.get("status") or ""
    since = d.get("statusUpdatedAt") if isinstance(d.get("statusUpdatedAt"), int) else 0
    out = {"sid": sid, "running": True, "status": status,
           "since": since // 1000 or int(time.time())}
    if status not in WORKING:
        with _turns_lock:
            _turns.pop(sid, None)
        return out
    p = _transcript(sid)
    if p is None:
        return dict(out, transcript=False)
    t0 = time.time()
    with _turns_lock:
        t = _turns.get(sid)
        if t is None or t.since != since or t.path != p:
            t = _Turn(p, since)
        try:
            t.look()
        except OSError:
            return dict(out, transcript=False)
        _turns[sid] = t
        while len(_turns) > 16:                    # sessions that stopped being looked at
            _turns.pop(next(iter(_turns)))
        now = [{"tool": n, "what": w} for i, n, w in t.tools if i not in t.back]
        last = {"tool": t.last[1], "what": t.last[2]} if t.last else None
        out.update(transcript=True, now=now, last=last, calls=t.calls,
                   tokens=sum(t.tokens.values()), whole=t.whole, counted=bool(since),
                   read=t.read, took=round(time.time() - t0, 4))
    return out


if __name__ == "__main__":
    import sys
    got = running([sys.argv[1]] if len(sys.argv) > 1 else [])
    for r in got["sessions"]:
        r["text"] = (r.get("text") or "")[:80]
    print(json.dumps(got, indent=1))
