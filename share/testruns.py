"""The test runs each running session has going, and how far each one is.

A session runs its tests through Claude Code's Bash tool, and nothing in
Claude Code's own files says that a command is a test run or how far it has
got. The machine says both, the same way in every project. Measured on
2.1.312 to 2.1.314, 2026-10-30, against twelve sessions in one repository:

- every command a session runs is a process under the session's own, the
  `claude` at the pid its session file names: Claude Code starts a shell
  (`/bin/zsh -c …`) for each Bash call, foreground or background, and under it
  runs what the command names. One `ps` over that machine's 709 processes
  took 30 ms;
- that shell writes the command's output to a file of the session's own,
  `…/<session>/tasks/<id>.output`, as it is written, for a foreground call and
  a background one alike. A foreground call's file is gone once its result is
  back; a background call's `<id>` is the `backgroundTaskId` its result
  carries in the transcript, and its end a `<task-notification>` naming the
  call;
- a command can send its output elsewhere: into a log it names
  (`> .tree/affected.log`), a file too, or into a pipe (`| tail -25`), which
  no other process can read without taking from it. `lsof` says which, for a
  process, in 30 ms;
- a process that detaches itself from its shell, its parent then launchd,
  belongs to no session any more and is not found.

So a run is told by what it runs: a process under a session whose command line
is a test runner's (`runner`), and not under another such. How far it is, its
output says, where the runner counts as it goes and the output is a file
(`Count`). How long it took before, the transcripts say: the same command's
last run, from its call to its result or to the notice that it ended, in the
session's own transcript or in the latest others of its project (`_calls`).

Nothing is written. Each look reads the machine again; a run's output is read
once and after that only what it printed since; and a run's call, and the run
before it, are looked up once, while it runs.
"""

import json
import os
import re
import subprocess
import threading
import time
from pathlib import Path

import waiting as _W

try:
    from transcript import scrub                   # one scrubbing list, not two
except Exception:                                  # standalone
    def scrub(s):
        return s

# ── what runs tests ───────────────────────────────────────────────────────────
# A command line is split on its spaces, as `ps` gives it, and its program is
# taken by its name. A shell given a command string is passed over: what it
# runs is its child, and is looked at in its own right.
SHELLS = {"sh", "bash", "zsh", "dash", "fish", "ksh"}
INTERPRETERS = {"node", "nodejs", "ruby", "php", "perl", "bun", "deno", "tsx", "ts-node"}
PYTHON = re.compile(r"python(?:\d+(?:\.\d+)?)?$")
# an interpreter's options that take the next word as their value
VALUED = {"-r", "--require", "--import", "--loader", "--experimental-loader", "-e", "--eval",
          "-p", "--print", "-c", "-W", "-X", "--conditions", "-C"}
# programs that run tests by their name alone
RUNNERS = {"pytest", "py.test", "jest", "vitest", "mocha", "ava", "tap", "karma", "rspec", "phpunit",
           "pest", "ctest", "tox", "nox", "nextest", "cucumber", "cucumber-js", "behave",
           "nosetests", "nose2", "testem", "uvu", "busted"}
PY_MODULES = {"pytest", "unittest", "nose2", "tox", "nox", "behave"}
# programs that run tests under one of their subcommands
SUBCOMMANDS = {"cargo": {"test", "nextest"}, "go": {"test"}, "dotnet": {"test"}, "swift": {"test"},
               "mix": {"test"}, "playwright": {"test"}, "bun": {"test"}, "deno": {"test"},
               "flutter": {"test"}, "dart": {"test"}, "zig": {"test"}}
# build tools, whose test tasks can stand anywhere among their words
BUILDS = {"gradle": re.compile(r"^(?::?\S*:)?(?:test|check|connectedCheck)$"),
          "gradlew": re.compile(r"^(?::?\S*:)?(?:test|check|connectedCheck)$"),
          "mvn": re.compile(r"^(?:test|verify|integration-test)$"),
          "mvnw": re.compile(r"^(?:test|verify|integration-test)$"),
          "make": re.compile(r"^(?:test|tests|check)(?:[-_:]\S*)?$"),
          "just": re.compile(r"^(?:test|tests|check)(?:[-_:]\S*)?$"),
          "rake": re.compile(r"^(?:test|spec)(?:[-_:]\S*)?$")}
PACKAGERS = {"npm", "pnpm", "yarn", "bun"}
FETCHERS = {"npx", "bunx", "pnpx"}
SCRIPT = re.compile(r"^tests?(?:[-_:.]\S*)?$")
# a script named as tests are: test.sh, run_tests.py, scripts/test.ts, a.test.ts, b_spec.rb
TESTISH = re.compile(r"^(?:run[-_]?)?tests?(?:[._:-]|$)|[._-](?:test|spec)s?\.[a-z0-9]+$", re.I)


def runner(args):
    """Whether a process runs tests, by its command line: that line from the
    runner's own word on, its program by name — `npm run test:affected`,
    `vitest run`, `python3 -m pytest -x` — or None."""
    w = (args or "").split()
    if not w:
        return None
    return _runner([os.path.basename(w[0])] + w[1:])


def _words(rest):
    """An interpreter's words that are not options, an option's value left out."""
    out, skip = [], False
    for x in rest:
        if skip:
            skip = False
        elif x.startswith("-"):
            skip = x in VALUED
        else:
            out.append(x)
    return out


def _runner(w):
    prog, rest = w[0], w[1:]
    words = [x for x in rest if not x.startswith("-")]
    if prog in ("test", "["):
        return None                                # the shell's own test, which a loop runs
    if prog in SHELLS:
        if any(x.startswith("-") and "c" in x[1:] for x in rest[:3]) or not words:
            return None                            # a command string: its children are what run
        return " ".join(w) if TESTISH.search(os.path.basename(words[0])) else None
    if prog in FETCHERS:
        return _runner(words) if words else None
    if prog in PACKAGERS:
        if words[:1] in (["exec"], ["dlx"], ["x"]):
            return _runner(words[1:]) if len(words) > 1 else None
        if prog in SUBCOMMANDS and words[:1] == ["test"]:
            return " ".join(w)                     # bun's own runner
        if words[:1] in (["test"], ["t"], ["tst"]):
            return " ".join(w)
        if words[:1] in (["run"], ["run-script"]) and len(words) > 1 and SCRIPT.match(words[1]):
            return " ".join(w)
        if prog in ("yarn", "pnpm") and words and SCRIPT.match(words[0]):
            return " ".join(w)                     # yarn test:unit runs the script by its name
        if prog != "bun":
            return None                            # bun runs a script as node does, below
    if prog in INTERPRETERS or PYTHON.match(prog):
        if prog in ("node", "nodejs") and "--test" in rest:
            return " ".join(w)
        if prog in SUBCOMMANDS and words[:1] == ["test"]:
            return " ".join(w)
        if any(x in ("-c", "-e", "--eval", "-p", "--print") for x in rest):
            return None                            # code given inline, no script
        if "-m" in rest:
            i = rest.index("-m")
            return " ".join(w) if i + 1 < len(rest) and rest[i + 1] in PY_MODULES else None
        script = (_words(rest) or [""])[0]
        if not script:
            return None
        name = os.path.basename(script)
        bare = re.sub(r"\.(?:c|m)?js$|\.py$", "", name)
        after = rest[rest.index(script) + 1:]
        if "/node_modules/" in script:
            # a package's own entry: node_modules/.bin/vitest, node_modules/jest/bin/jest.js,
            # node_modules/@playwright/test/cli.js test
            pkg = script.split("/node_modules/")[-1].split("/")
            pkg = pkg[1] if pkg[0] == ".bin" else ("/".join(pkg[:2]) if pkg[0].startswith("@") else pkg[0])
            if pkg in RUNNERS or bare in RUNNERS:
                return " ".join([pkg if pkg in RUNNERS else bare] + after)
            if pkg in PACKAGERS or pkg in FETCHERS:
                return _runner([pkg] + after)      # a package manager not titled by its name
            if pkg in ("@playwright/test", "playwright") and after[:1] == ["test"]:
                return " ".join(["playwright"] + after)
            return None
        if bare in RUNNERS:
            return " ".join([bare] + after)
        if bare in PACKAGERS or bare in FETCHERS:
            return _runner([bare] + after)
        return " ".join(w) if TESTISH.search(name) else None
    if prog in RUNNERS:
        return " ".join(w)
    if prog in SUBCOMMANDS:
        return " ".join(w) if words[:1] and words[0] in SUBCOMMANDS[prog] else None
    if prog in BUILDS:
        return " ".join(w) if any(BUILDS[prog].match(x) for x in words) else None
    return " ".join(w) if TESTISH.search(prog) else None


# ── how far a run is, from what it printed ────────────────────────────────────
# Read the same way whatever the runner, since a script can run any of them:
# a share the runner printed itself, a count it announced before it began, and
# the lines that each say one thing finished, passed or failed. A line ending
# a run's summary stops the counting, as some runners list their failures
# again under it.
ANSI = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)")
PERCENT = re.compile(r"\[\s*(\d{1,3})%\]\s*$")                         # pytest
FRACTION = [re.compile(r"^\s*(\d+)/(\d+) Test\s+#"),                    # ctest
            re.compile(r"^\[(\d+)/(\d+)\]"),                            # playwright's line reporter
            re.compile(r"\b(\d+) / (\d+) \(\s*\d+%\)\s*$")]             # phpunit
ANNOUNCED = [re.compile(r"^collected \d+ items?(?: / \d+ deselected / (\d+) selected)?"),
             re.compile(r"^Running (\d+) tests? using \d+ workers?"),   # playwright
             re.compile(r"^(\d+) to run\b"),                            # a runner saying what it queued
             re.compile(r"^1\.\.(\d+)\b")]                              # TAP's plan
COLLECTED = re.compile(r"^collected (\d+) items?")
SUMMED = re.compile(r"^running (\d+) tests?$")                         # cargo, once for each binary
PASSED = re.compile(r"^\s*[✓✔√](?:\s|$)|^ok \d+\b|^PASS\s|^ok\s+\S+\s+(?:\(?[\d.]+m?s\b|\(cached\))|"
                    r"^test \S.* \.\.\. (?:ok|ignored)$")
FAILED = re.compile(r"^\s*[✗✖×✘](?:\s|$)|^not ok \d+\b|^FAIL\s|^test \S.* \.\.\. FAILED$")
ENDED = re.compile(r"^\s*(?:ℹ tests \d+|✖ failing tests:|Test Suites:|Test Files\s|Tests:\s+\d|"
                   r"\d+ test files?, |\d+ passing\b|=+ (?:short test summary|\d+ (?:passed|failed)))")


class Count:
    """What a run's output has said so far of how far it is."""

    def __init__(self):
        self.passed = self.failed = self.summed = 0
        self.announced = self.frac = self.pct = None
        self.ended = False

    def feed(self, line):
        line = ANSI.sub("", line).split("\r")[-1].rstrip()
        if not line:
            return
        m = PERCENT.search(line)
        if m:
            self.pct = min(100, int(m.group(1)))
        for f in FRACTION:
            m = f.search(line)
            if m and 0 < int(m.group(2)) and int(m.group(1)) <= int(m.group(2)):
                self.frac = (int(m.group(1)), int(m.group(2)))
                break
        m = SUMMED.match(line)
        if m:
            self.summed += int(m.group(1))
        for a in ANNOUNCED:
            m = a.match(line)
            if m:
                got = m.group(1) or (COLLECTED.match(line) or m).group(1)
                if got:
                    self.announced = int(got)
                break
        if ENDED.match(line):
            self.ended = True
        if self.ended:
            return
        if FAILED.search(line):
            self.failed += 1
        elif PASSED.search(line):
            self.passed += 1

    def result(self):
        """How far: what finished and failed, out of how many if that is known,
        or the share the runner printed itself."""
        done = self.passed + self.failed
        out = {"done": done, "failed": self.failed, "total": None, "pct": self.pct}
        if self.frac:
            out["done"], out["total"] = self.frac[0], self.frac[1]
            return out
        total = self.announced or self.summed or None
        if total and done <= total:
            out["total"] = total
        return out


def counted(text):
    """A whole output counted at once: a run's from before, or a test's."""
    c = Count()
    for line in (text or "").split("\n"):
        c.feed(line)
    return c.result()


# A run's output is read from where the last look left it. A first look at a
# file larger than this starts this far from its end, and says its counts are
# at least what it found.
OUT_MOST = 16 * 1024 * 1024


class _Out:
    """One output file of a run, as far as it has been read."""

    def __init__(self, path):
        self.path, self.ino, self.upto, self.rest = path, None, 0, b""
        self.count, self.whole, self.cut = Count(), True, False

    def look(self):
        st = os.stat(self.path)
        if st.st_ino != self.ino or st.st_size < self.upto:     # a file written anew under the name
            self.__init__(self.path)
            self.ino = st.st_ino
            if st.st_size > OUT_MOST:
                self.upto, self.whole, self.cut = st.st_size - OUT_MOST, False, True
        if st.st_size <= self.upto:
            return
        with open(self.path, "rb") as f:
            f.seek(self.upto)
            blob = f.read(st.st_size - self.upto)
        self.upto += len(blob)
        lines = (self.rest + blob).split(b"\n")
        self.rest = lines.pop()                                  # still being written
        if self.cut:
            lines, self.cut = lines[1:], False                   # the first line was cut in half
        for ln in lines:
            self.count.feed(ln.decode("utf-8", "replace"))


# ── the machine ───────────────────────────────────────────────────────────────

def _secs(etime):
    """`ps`'s elapsed time, [[dd-]hh:]mm:ss, in seconds."""
    days, _, clock = etime.strip().rpartition("-")
    parts = [int(p) for p in clock.split(":") if p.isdigit()]
    s = 0
    for p in parts:
        s = s * 60 + p
    return s + (int(days) * 86400 if days.isdigit() else 0)


def processes():
    """Every process on the machine: its parent, how long it has run, its CPU
    and its command line, by pid. One `ps` for all of them."""
    try:
        out = subprocess.run(["ps", "-ww", "-Ao", "pid=,ppid=,etime=,%cpu=,args="],
                             capture_output=True, text=True, timeout=5).stdout
    except Exception:
        return {}
    table = {}
    for line in out.splitlines():
        parts = line.split(None, 4)
        if len(parts) < 5 or not parts[0].isdigit() or not parts[1].isdigit():
            continue
        try:
            cpu = float(parts[3].replace(",", "."))
        except ValueError:
            cpu = 0.0
        table[int(parts[0])] = (int(parts[1]), _secs(parts[2]), cpu, parts[4])
    return table


def runs_under(pid, table):
    """The test runs under one session's process: each a process whose command
    line is a runner's and none of whose parents up to the session's is, with
    the shell that Claude Code started it in, its CPU with all that runs under
    it, and how many processes that is."""
    kids = {}
    for p, (pp, *_rest) in table.items():
        kids.setdefault(pp, []).append(p)
    out = []

    def walk(p, shell, inside):
        for k in sorted(kids.get(p, ())):
            label = None if inside else runner(table[k][3])
            if label:
                stack, cpu, n = [k], 0.0, 0
                while stack:
                    q = stack.pop()
                    cpu += table[q][2]
                    n += 1
                    stack += kids.get(q, [])
                out.append({"pid": k, "label": label, "secs": table[k][1], "cpu": round(cpu, 1),
                            "procs": n, "shell": shell or k})
            walk(k, shell or k, inside or bool(label))

    walk(pid, None, False)
    return out


TASK = re.compile(r"/tasks/([A-Za-z0-9_-]{4,40})\.output$")


def outputs(pids):
    """Where each process's output goes, by pid: for its fd 1 and 2, the file
    it writes to, or what else it is (a pipe, a socket, a terminal)."""
    got = {}
    if not pids:
        return got
    try:
        out = subprocess.run(["lsof", "-nP", "-a", "-p", ",".join(str(p) for p in sorted(pids)),
                              "-d", "1,2", "-F", "pftn"], capture_output=True, text=True, timeout=5).stdout
    except Exception:
        return got
    pid = fd = kind = None
    for line in out.splitlines():
        tag, val = line[:1], line[1:]
        if tag == "p":
            pid = int(val) if val.isdigit() else None
        elif tag == "f":
            fd, kind = val, None
        elif tag == "t":
            kind = val
        elif tag == "n" and pid is not None and fd in ("1", "2"):
            got.setdefault(pid, {})[fd] = (kind or "?", val)
    return got


# ── the run's call, and the run before it ─────────────────────────────────────
# A transcript is read from its end, a megabyte first and four times as much
# while the call is not in it, sixteen at most; the latest other transcripts of
# its project two megabytes each, for the run before when the session's own
# has none, as a session cleared or begun afresh starts a transcript of its
# own. Only the lines that can bear on a Bash call are parsed.
CALLS_FIRST = 1024 * 1024
CALLS_MOST = 16 * 1024 * 1024
OTHERS = 6
OTHERS_EACH = 2 * 1024 * 1024
BEARS = re.compile(rb'"Bash"|task-notification|"tool_use_id"\s*:\s*"([^"]+)"')
NOTICE = re.compile(r"<tool-use-id>([^<]+)</tool-use-id>.*?<status>([^<]+)</status>", re.S)
WRITTEN_TO = re.compile(r"Output is being written to: (\S+\.output)")


def _calls(path, size):
    """The Bash calls in the last `size` bytes of a transcript, oldest first:
    when each was made, its command and its description, whether it went to
    the background, when it ended and what it printed, where that is known."""
    with open(path, "rb") as f:
        f.seek(0, 2)
        n = f.tell()
        f.seek(max(0, n - size))
        blob = f.read()
    lines = blob.split(b"\n")
    if n > size:
        lines = lines[1:]
    calls = {}
    for ln in lines:
        m = BEARS.search(ln)
        if not m or (m.group(1) and m.group(1).decode("utf-8", "replace") not in calls
                     and b"task-notification" not in ln):
            continue
        try:
            r = json.loads(ln)
        except Exception:
            continue
        if not isinstance(r, dict) or r.get("isSidechain"):
            continue
        ts = _W._ms(r.get("timestamp") or "")
        content = (r.get("message") or {}).get("content")
        blocks = content if isinstance(content, list) else [{"type": "text", "text": content}] if isinstance(content, str) else []
        for b in blocks:
            if not isinstance(b, dict):
                continue
            if b.get("type") == "tool_use" and b.get("name") == "Bash" and isinstance(b.get("input"), dict):
                inp = b["input"]
                calls[b.get("id")] = {"at": ts, "cmd": inp.get("command") or "", "desc": inp.get("description") or "",
                                      "bg": None, "end": None, "out": None, "file": None, "ok": True}
            elif b.get("type") == "tool_result" and b.get("tool_use_id") in calls:
                c, res = calls[b["tool_use_id"]], r.get("toolUseResult")
                res = res if isinstance(res, dict) else {}
                if res.get("backgroundTaskId"):
                    c["bg"] = res["backgroundTaskId"]
                    text = b.get("content") if isinstance(b.get("content"), str) else ""
                    w = WRITTEN_TO.search(text)
                    c["file"] = w.group(1) if w else None
                else:
                    c["end"] = ts
                    c["ok"] = not res.get("interrupted")
                    out = (res.get("stdout") or "") + "\n" + (res.get("stderr") or "")
                    c["out"] = out if out.strip() else (b.get("content") if isinstance(b.get("content"), str) else "")
            elif b.get("type") == "text" and "task-notification" in (b.get("text") or ""):
                for tid, status in NOTICE.findall(b["text"]):
                    if tid in calls:
                        calls[tid]["end"] = ts
                        calls[tid]["ok"] = status.strip() in ("completed", "failed")
    return [dict(c, id=k) for k, c in sorted(calls.items(), key=lambda kv: kv[1]["at"])]


def keys(label):
    """What an earlier command has to hold to be a run of this one: the
    runner's line, or that line without its interpreter or shell, as a command
    names `python -m pytest` and `ps` shows `python3 -m pytest`, and a command
    runs `./run_tests.sh` and `ps` shows `bash ./run_tests.sh`."""
    w = label.split()
    out = [label]
    if len(w) > 1 and (w[0] in INTERPRETERS or w[0] in SHELLS or PYTHON.match(w[0]) or w[0] in FETCHERS):
        out.append(" ".join(w[1:]))
    return out


def _before(calls, key_list, until):
    """The latest run of a command holding one of the keys that ended before
    `until`, and ended as a run ends, not stopped."""
    best = None
    for c in calls:
        if c["end"] and c["ok"] and c["at"] < until and any(k in c["cmd"] for k in key_list):
            if best is None or c["at"] > best["at"]:
                best = c
    return best


def _last(c):
    """What the run before took, and what its output counted when the whole of
    it is to hand: printed straight into its result, or its background file
    still on disk. A command that piped its output on kept only what came
    through the pipe, so it says nothing of the count."""
    out = {"secs": max(0, round((c["end"] - c["at"]) / 1000)), "done": None}
    if "|" in c["cmd"]:
        return out
    text = c["out"]
    if text is None and c["file"]:
        try:
            with open(c["file"], "rb") as f:
                text = f.read(OUT_MOST).decode("utf-8", "replace")
        except OSError:
            text = None
    if text:
        got = counted(text)
        out["done"] = got["done"] or None
    return out


def history(sid, label, bg, began):
    """A run's Bash call and the run of the same command before it: the call
    is the background one whose task the run's shell writes to, or else the
    session's Bash call still waiting on its result; the run before, the
    latest one found in the session's transcript or the latest others of its
    project."""
    p = _W._transcript(sid)
    found = {"what": "", "last": None}
    if p is None:
        return found
    ks, size, me = keys(label), CALLS_FIRST, None
    while True:
        calls = _calls(p, size)
        # a foreground call writes to a task's file too, under an id no result names
        me = next((c for c in reversed(calls) if bg and c["bg"] == bg), None) or \
            next((c for c in reversed(calls) if not c["end"] and not c["bg"]), None)
        prev = _before(calls, ks, me["at"] if me else began)
        if (me and prev) or size >= CALLS_MOST or size >= p.stat().st_size:
            break
        size *= 4
    if me:
        found["what"] = scrub((me["desc"] or me["cmd"]).strip().split("\n")[0][:_W.WHAT_MAX])
    if prev is None:
        others = sorted((q for q in p.parent.glob("*.jsonl") if q != p),
                        key=lambda q: -q.stat().st_mtime)[:OTHERS]
        for q in others:
            try:
                prev = _before(_calls(q, OTHERS_EACH), ks, began)
            except OSError:
                continue
            if prev:
                break
    if prev:
        found["last"] = _last(prev)
    return found


# ── the look ──────────────────────────────────────────────────────────────────
_outs, _known, _lock = {}, {}, threading.Lock()


def _sessions():
    """The running sessions, by their pid: each one's session id."""
    rows = {}
    if not _W.SESSIONS.is_dir():
        return rows
    for f in _W.SESSIONS.glob("*.json"):
        try:
            d = json.loads(f.read_text(encoding="utf-8"))
            if isinstance(d.get("pid"), int) and isinstance(d.get("sessionId"), str):
                rows[d["pid"]] = d["sessionId"]
        except Exception:
            continue
    live = _W._alive(list(rows))
    return {p: s for p, s in rows.items() if p in live}


def runs():
    """Every test run the running sessions have going, by session id: what it
    runs, how long it has, its CPU, where its output goes and how far that
    says it is, and how long the same command's run before took."""
    t0 = time.time()
    out = {"runs": {}, "took": 0}
    sessions = _sessions()
    if not sessions:
        return out
    table = processes()
    now = time.time()
    found = {sid: runs_under(pid, table) for pid, sid in sessions.items() if pid in table}
    found = {sid: rs for sid, rs in found.items() if rs}
    where = outputs({r["pid"] for rs in found.values() for r in rs} |
                    {r["shell"] for rs in found.values() for r in rs})
    seen_outs, seen_known = set(), set()
    with _lock:
        for sid, rs in found.items():
            for r in rs:
                began = int((now - r["secs"]) * 1000)
                # where its output goes is said by its stdout; a file its stderr
                # goes to is read too, as some runners count there (jest)
                fds = where.get(r["pid"], {})
                files = sorted({v[1] for v in fds.values() if v[0] == "REG"})
                kind = fds.get("1", ("?", ""))[0]
                r["out"] = ("file" if kind == "REG" else "pipe" if kind in ("PIPE", "FIFO", "unix") else
                            "terminal" if kind == "CHR" else "unknown")
                count = Count().result()
                whole = True
                for path in files[:2]:
                    key = (r["pid"], path)
                    seen_outs.add(key)
                    o = _outs.get(key) or _outs.setdefault(key, _Out(path))
                    try:
                        o.look()
                    except OSError:
                        continue
                    got = o.count.result()
                    whole = whole and o.whole
                    for k in ("done", "failed"):
                        count[k] += got[k]
                    count["total"] = count["total"] or got["total"]
                    count["pct"] = count["pct"] if count["pct"] is not None else got["pct"]
                r.update(count, whole=whole)
                task = TASK.search(where.get(r["shell"], {}).get("1", ("", ""))[1])
                bg = task.group(1) if task else None
                mine = (sid, r["pid"])
                seen_known.add(mine)
                if mine not in _known:
                    try:
                        _known[mine] = history(sid, r["label"], bg, began)
                    except OSError:
                        _known[mine] = {"what": "", "last": None}
                r.update(_known[mine])
                r["label"] = scrub(r["label"][:_W.WHAT_MAX])
                del r["shell"]
        for k in [k for k in _outs if k not in seen_outs]:
            del _outs[k]                                         # runs that ended
        for k in [k for k in _known if k not in seen_known]:
            del _known[k]
    out["runs"] = found
    out["took"] = round(time.time() - t0, 3)
    return out


if __name__ == "__main__":
    print(json.dumps(runs(), indent=1))
