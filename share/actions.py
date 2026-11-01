#!/usr/bin/env python3
"""
rubricator actions — the only place where a page can cause something to happen.

The rule that makes this safe to have at all: **the page sends a verb and an id,
never a path and never a command.** Every path is resolved here, against the
index the server already built; every argument is placed in argv directly, never
inside a shell string. The one thing a page may hand over is the prompt text for
a new session, and that is written to a file and read back as a single argument.

Off unless asked for: `md --allow-launch`, or `{"allow_launch": true}` in
~/.config/rubricator/config.json. A fresh install can start nothing.

A session running in a terminal is answered in that terminal: a reply is typed
into its own iTerm tab, the way you would type it, while Claude waits there for
input or, once you confirm it, while it works; and a working one is stopped with
the Escape key in that tab — see "a running session's own terminal" below.
"""
import json, os, plistlib, re, shlex, subprocess, tempfile, time
from pathlib import Path

HOME    = Path.home()
CONFIG  = Path(os.environ.get("RUBRICATOR_CONFIG", HOME / ".config/rubricator/config.json"))
CACHE   = Path(os.environ.get("RUBRICATOR_CACHE", HOME / ".cache/rubricator"))
SESSION_ID = re.compile(r"^[0-9a-fA-F-]{8,64}$")
MAX_PROMPT = 100_000

# TERM_PROGRAM as your shell reports it → the application to hand the launcher to.
# All of these run a .command file when opened with it, which is why none of this
# needs Automation permission.
TERMINALS = {
    "iTerm.app":      "iTerm",
    "iTerm2.app":     "iTerm",
    "Apple_Terminal": "Terminal",
    "Terminal.app":   "Terminal",
    "WarpTerminal":   "Warp",
    "ghostty":        "Ghostty",
    "WezTerm":        "WezTerm",
    "kitty":          "kitty",
}
APP_PATHS = {
    "iTerm":    "/Applications/iTerm.app",
    "Terminal": "/System/Applications/Utilities/Terminal.app",
    "Warp":     "/Applications/Warp.app",
    "Ghostty":  "/Applications/Ghostty.app",
    "WezTerm":  "/Applications/WezTerm.app",
    "kitty":    "/Applications/kitty.app",
}


def config():
    try:
        d = json.loads(CONFIG.read_text(encoding="utf-8"))
        return d if isinstance(d, dict) else {}
    except Exception:
        return {}


# ── settings ─────────────────────────────────────────────────────────────────
# Only these keys are ever written, and only these values are ever accepted. The
# page can ask for a change; it cannot invent a setting or store arbitrary text.
SETTABLE = {
    "terminal":     lambda v: v in ("",) or v in TERMINALS or v in APP_PATHS,
    "allow_launch": lambda v: isinstance(v, bool),
    "editor":       lambda v: v == "" or _is_program(v),
    "deep":         lambda v: isinstance(v, bool),
    # whether a bare `md` indexes your Claude Code history. Off on a fresh
    # install: turning it on loads every conversation on the machine into the
    # page, which is a thing you decide once rather than discover.
    "sessions":     lambda v: isinstance(v, bool),
    "idle":         lambda v: isinstance(v, int) and 30 <= v <= 86400,
    "theme":        lambda v: v in THEMES,
    # Q3 · a saved search is {name, query} and nothing else. Standing rule 4:
    # persist the selection, never the assembly — what is stored is the question,
    # and the answer is rebuilt from today's index every time it is opened. A
    # saved dossier would be a snapshot that quietly goes stale; this cannot.
    # Rule 2 puts it here rather than in localStorage, because it has to survive
    # a restart and every run is a new origin.
    "searches":     lambda v: _searches_ok(v),
}


def _searches_ok(v):
    if not isinstance(v, list) or len(v) > 50:
        return False
    for x in v:
        if not isinstance(x, dict) or set(x) - {"name", "query"}:
            return False
        if not isinstance(x.get("name"), str) or not isinstance(x.get("query"), str):
            return False
        if not (0 < len(x["name"]) <= 60) or not (0 < len(x["query"]) <= 200):
            return False
    return True
THEMES = ("rubric", "slate", "bone")
# Q1 · `deep` defaults to True now: a session that delegated its editing to
# subagents otherwise looks like it touched nothing, for a fifth of a second.
# The setting survives so it can be turned off.
DEFAULTS = {"terminal": "", "allow_launch": False, "editor": "", "deep": True,
            "sessions": False, "idle": 120, "theme": "rubric", "searches": []}


def _is_program(v):
    if not isinstance(v, str) or not v or len(v) > 200 or "\n" in v:
        return False
    if v.startswith("/"):
        return os.path.isfile(v) and os.access(v, os.X_OK)
    import shutil
    return bool(re.match(r"^[\w.+-]+$", v)) and bool(shutil.which(v))


def settings():
    """What is in effect, and what is merely stored — a flag on the command line
    beats the file, and the screen should say so rather than lie about it."""
    stored = config()
    out = dict(DEFAULTS)
    for k in SETTABLE:
        if k in stored:
            out[k] = stored[k]
    forced = {}
    if os.environ.get("RUBRICATOR_ALLOW_LAUNCH") == "1" and not out["allow_launch"]:
        forced["allow_launch"] = "enabled for this window by --allow-launch"
    ses = os.environ.get("RUBRICATOR_SESSIONS")
    if ses == "1" and not out["sessions"]:
        forced["sessions"] = "on for this window by --sessions"
    elif ses == "0" and out["sessions"]:
        forced["sessions"] = "off for this window by --no-sessions"
    return {"values": out, "forced": forced, "path": str(CONFIG),
            "terminal_effective": terminal(),
            "terminals": sorted(a for a in APP_PATHS if installed(a))}


def save_settings(patch):
    if not isinstance(patch, dict):
        raise ValueError("not settings")
    stored = config()
    for k, v in patch.items():
        if k not in SETTABLE:
            raise ValueError(f"there is no setting called {k!r}")
        if not SETTABLE[k](v):
            raise ValueError(f"{k} cannot be set to {v!r}")
        stored[k] = v
    _write_config(stored)
    return settings()


def _write_config(d):
    CONFIG.parent.mkdir(parents=True, exist_ok=True)
    tmp = CONFIG.with_suffix(".part")
    tmp.write_text(json.dumps(d, indent=1, sort_keys=True) + "\n", encoding="utf-8")
    os.chmod(tmp, 0o600)                 # your machine, your settings, nobody else's
    tmp.replace(CONFIG)


# ── projects ─────────────────────────────────────────────────────────────────
# The page never sends a path. It asks for the picker, which the *server* opens,
# or it names one of the projects the server itself remembered — so an arbitrary
# directory can never be indexed on a page's say-so.
RECENTS = 8


def recents():
    out, seen = [], set()
    for p in (config().get("recents") or []):
        if isinstance(p, str) and p not in seen and os.path.isdir(p):
            seen.add(p)
            out.append(p)
    return out[:RECENTS]


def remember_project(path):
    path = str(Path(path).resolve())
    stored = config()
    keep = [p for p in (stored.get("recents") or []) if isinstance(p, str) and p != path]
    stored["recents"] = ([path] + keep)[:RECENTS]
    try:
        _write_config(stored)
    except Exception:
        pass
    return stored["recents"]


def choose_folder():
    """A native folder chooser, opened by the server. Standard Additions, not
    app scripting, so no Automation permission and no dialog about a dialog."""
    osa = ('POSIX path of (choose folder with prompt '
           '"Open a project in rubricator")')
    try:
        r = subprocess.run(["osascript", "-e", osa], timeout=300, capture_output=True)
    except subprocess.TimeoutExpired:
        return None
    if r.returncode != 0:
        return None                       # cancelled, which is not an error
    path = r.stdout.decode("utf-8", "replace").strip().rstrip("/")
    return path if path and os.path.isdir(path) else None


OPEN_WAIT = 20      # seconds; md is done in under one, and past this it is building a static page


def open_project(path, sessions=False):
    """Open a second workspace, the way an editor opens a second window. This
    starts rubricator on a directory — never an arbitrary program.

    md is done once it has asked for the window, and exits non-zero when it
    could start no workspace at all, so this waits for it and raises what it
    said: the page answers "opened" only for a window that is coming. Its stdin
    is /dev/null, never this server's own, which may be a terminal closed since
    and revoked: every python3 md runs dies on a revoked stdin before its first
    line, and md with it."""
    md = os.environ.get("RUBRICATOR_BIN") or str(HOME / ".local/bin/md")
    if not os.path.isfile(md):
        raise RuntimeError("cannot find the md command to open a second window")
    env = {k: v for k, v in os.environ.items()
           if not k.startswith(("RUBRICATOR_OUT", "RUBRICATOR_OPEN", "RUBRICATOR_INJECT",
                                "RUBRICATOR_HOME", "RUBRICATOR_JSON"))}
    argv = [md, str(path)] + (["--sessions"] if sessions else [])
    # a file, not a pipe: whatever md leaves running must not hold this open
    with tempfile.TemporaryFile() as err:
        p = subprocess.Popen(argv, env=env, cwd=str(path), start_new_session=True,
                             stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=err)
        try:
            code = p.wait(timeout=OPEN_WAIT)
        except subprocess.TimeoutExpired:
            code = 0                     # still at work on a page, which opens when done
        if code:
            err.seek(0)
            said = [l.strip() for l in err.read().decode("utf-8", "replace").splitlines() if l.strip()]
            why = next((l[4:] for l in reversed(said) if l.startswith("md: ")), None) \
                or (said[0] if said else "md exited with %d" % code)
            raise RuntimeError("could not open %s: %s" % (Path(path).name, why))
    remember_project(path)
    return {"ok": True, "opened": str(path)}


def enabled():
    if os.environ.get("RUBRICATOR_ALLOW_LAUNCH") == "1":
        return True
    return bool(config().get("allow_launch"))


def installed(app):
    p = APP_PATHS.get(app)
    return bool(p and os.path.isdir(p))


def terminal():
    """Which terminal to hand a launcher to: what you chose, else whatever ran
    `md`, else iTerm if it is here, else Terminal — which always is."""
    chosen = config().get("terminal") or ""
    if chosen:
        app = TERMINALS.get(chosen, chosen)
        if installed(app):
            return app
    app = TERMINALS.get(os.environ.get("RUBRICATOR_TERM") or "")
    if app and installed(app):
        return app
    return "iTerm" if installed("iTerm") else "Terminal"


def _script(cwd, argv, prompt_file=None):
    """A launcher script, so nothing has to survive a trip through a shell.

    Written as a .command file: macOS hands those to your terminal through
    LaunchServices, which needs no Automation permission. Driving a named
    terminal over AppleScript does, and that permission dialog blocks — so it
    is only used when you have asked for a specific terminal by name."""
    CACHE.joinpath("launch").mkdir(parents=True, exist_ok=True)
    for old in CACHE.joinpath("launch").glob("*.sh"):      # yesterday's launchers
        try:
            if time.time() - old.stat().st_mtime > 3600:
                old.unlink()
        except Exception:
            pass
    body = ["#!/bin/sh", f"cd {shlex.quote(str(cwd))} || exit 1"]
    line = " ".join(shlex.quote(a) for a in argv)
    if prompt_file:
        line += f' "$(cat {shlex.quote(str(prompt_file))})"'
    body.append("exec " + line)
    f = CACHE / "launch" / f"run-{int(time.time()*1000)}.command"
    f.write_text("\n".join(body) + "\n", encoding="utf-8")
    f.chmod(0o700)
    return f


def _dry():
    """Every door this module can open, held shut by one switch. `edit` falls
    back to `open -t` when no editor is configured, and that is the default, so
    a caller who only wants to know whether a verb resolves its target has to be
    able to ask without a text editor and a Finder window arriving on the
    reader's screen to answer it."""
    return bool(os.environ.get("RUBRICATOR_DRY_LAUNCH"))


def _open_window(script):
    """LaunchServices, not AppleScript. Every terminal here runs a .command file
    when it is opened with one, so nothing needs Automation permission — and the
    permission dialog, which blocks, never appears."""
    if _dry():                                     # build the launcher, open nothing
        return terminal()
    app = terminal()
    r = subprocess.run(["open", "-a", app, str(script)], timeout=25,
                       stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    if r.returncode != 0 and app != "Terminal":
        r = subprocess.run(["open", "-a", "Terminal", str(script)], timeout=25,
                           stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        app = "Terminal"
    if r.returncode != 0:
        err = (r.stderr or b"").decode("utf-8", "replace").strip()[:200]
        raise RuntimeError("could not open a terminal window: " + (err or "unknown error"))
    return app


def _claude():
    override = os.environ.get("RUBRICATOR_CLAUDE")
    if override:
        return override
    for p in (HOME / ".local/bin/claude", Path("/usr/local/bin/claude"), Path("/opt/homebrew/bin/claude")):
        if p.is_file():
            return str(p)
    return "claude"


# ── the verbs ────────────────────────────────────────────────────────────────
def launch(root, doc_abs, text):
    """A new session where the document lives, with your notes as its first word."""
    # the session opens at the workspace root, not beside the file: that is where
    # CLAUDE.md, the git repo and the rest of the project context live
    cwd = root
    prompt = None
    if text:
        CACHE.joinpath("launch").mkdir(parents=True, exist_ok=True)
        prompt = CACHE / "launch" / f"prompt-{int(time.time()*1000)}.md"
        prompt.write_text(str(text)[:MAX_PROMPT], encoding="utf-8")
    sc = _script(cwd, [_claude()], prompt)
    app = _open_window(sc)
    return {"ok": True, "cwd": str(cwd), "script": str(sc), "terminal": app}


def resume(cwd, sid, fork=False):
    if not SESSION_ID.match(sid or ""):
        raise ValueError("not a session id")
    argv = [_claude(), "-r", sid] + (["--fork-session"] if fork else [])
    sc = _script(cwd, argv)
    app = _open_window(sc)
    return {"ok": True, "session": sid, "script": str(sc), "terminal": app}


def reveal(path):
    if _dry():                                     # resolved and checked, opened nowhere
        return {"ok": True, "dry": str(path)}
    subprocess.run(["open", "-R", str(path)], check=True, timeout=15,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return {"ok": True}


def edit(path):
    if _dry():                                     # resolved and checked, opened nowhere
        return {"ok": True, "dry": str(path)}
    ed = os.environ.get("RUBRICATOR_EDITOR") or config().get("editor") or ""
    if ed:
        _open_window(_script(Path(path).parent, [ed, str(path)]))
    else:
        subprocess.run(["open", "-t", str(path)], check=True, timeout=15,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return {"ok": True}


# ── a running session's own terminal ─────────────────────────────────────────
# A session running in a terminal already has a writer: the `claude` process in
# that terminal. Resuming it from here would be a second process on the same
# transcript (the guard on `resume` refuses that), so a reply goes the other way
# in: it is typed into the session's own tab, exactly as you would type it. A
# slash command runs, the words count as yours, and the one writer stays one.
#
# The way there is read, never taken from the page: Claude Code's file for the
# session gives its pid (waiting.session_file); `ps` gives that process's tty;
# the process's ancestors give the terminal application it runs under, and that
# application's own Info.plist says whether it is iTerm. iTerm's AppleScript
# dictionary has every session's `tty`, so the session to type into is the one
# whose tty is Claude's. Only iTerm, whose dictionary this is written against;
# a session in any other terminal is told so, with that terminal's name.
#
# What makes typing safe is what is typed into. A terminal whose Claude has
# exited is a shell, and a reply typed there is a shell command. So before
# anything is sent, and again immediately before it is, three things must hold,
# and if one does not, nothing is sent and the answer says which:
#
#   - the session's `claude` process lives;
#   - its status is one the keys are meant for. A reply goes in on your turn —
#     `idle` — and, when you confirmed it on the page, while it works — `busy` —
#     where Claude Code queues what is typed during a turn and reads it when it
#     can. The Escape key, which interrupts a turn, goes in only while it works.
#     Neither goes into `waiting`, whose question or permission dialog would
#     take the Return as its answer, choosing whatever option is highlighted, or
#     the Escape as a refusal: that is answered in its tab; nor into `shell`,
#     whose turn ended with a command of its own still running;
#   - `claude` is in its terminal's foreground: `ps` marks the foreground
#     process group with `+`, and a shell that took the terminal back after
#     Claude exited, or was suspended, holds the `+` instead.
#
# The script is a constant, and what it is given travels as `argv` to its `run`
# handler, never inside its text: `osascript -` reads the script from stdin and
# hands every argument after it to `on run argv` as a string. The reply is one
# line — line breaks become spaces, and every other control character, which a
# terminal would read as a key (^C, ^D, escape), becomes a space too. It is
# written without a line ending and followed, a moment later, by a carriage
# return of its own: the Return key, which is what sends a prompt in Claude
# Code, where a line feed may be taken for a line break inside it. A stop is
# one key and no words: `character id 27`, the Escape key, written once with
# no line ending, by the script's own text — the page sends no key.
#
# The first reply makes macOS ask, once, whether rubricator may control iTerm
# (System Settings → Privacy & Security → Automation keeps the answer). Until it
# is given, osascript waits on the dialog, so the call allows two minutes.
# RUBRICATOR_DRY_LAUNCH stops short of osascript and says what would have run.
ITERM_ID = "com.googlecode.iterm2"
MAX_REPLY = 8000
WAITS_FOR_YOU = frozenset({"idle"})
WHILE_WORKING = frozenset({"idle", "busy"})      # a reply you confirmed while it works
STOPPABLE = frozenset({"busy"})                  # what the Escape key is sent into
TTY = re.compile(r"^tty[a-z]*\d{1,5}$")

ITERM_SCRIPT = '''on run argv
  set theTTY to item 1 of argv
  set theVerb to item 2 of argv
  set theText to ""
  if (count of argv) > 2 then set theText to item 3 of argv
  tell application id "com.googlecode.iterm2"
    repeat with aWindow in windows
      repeat with aTab in tabs of aWindow
        repeat with aSession in sessions of aTab
          if tty of aSession is theTTY then
            if theVerb is "write" then
              tell aSession to write text theText newline no
              delay 0.15
              tell aSession to write text (character id 13) newline no
              return "sent"
            end if
            if theVerb is "stop" then
              tell aSession to write text (character id 27) newline no
              return "stopped"
            end if
            tell aSession to select
            tell aTab to select
            tell aWindow to select
            activate
            return "shown"
          end if
        end repeat
      end repeat
    end repeat
  end tell
  return "none"
end run
'''


class Refused(Exception):
    """Why nothing was sent: which check failed, in words for the page, and for
    a status, which status it was."""
    def __init__(self, check, why, status=""):
        super().__init__(why)
        self.check, self.why, self.status = check, why, status


def _not_now(status, allow):
    """Why the keys are not for a session in this status, for what was asked."""
    if allow == STOPPABLE:
        return {"idle": "its turn is over: there is nothing to stop",
                "shell": "its turn is over, and the command of its own still running is not "
                         "stopped by Escape: stop that in its tab",
                "waiting": "it is asking you something in its terminal, a question or a permission "
                           "that Escape would answer for you: answer it in its tab"}.get(
                    status, "its status is %r, not one that is working" % status)
    return {"busy": "it is working — a line sent now waits in its queue, and is sent only "
                    "once you confirm that",
            "shell": "its turn ended with a command of its own still running, "
                     "so it will likely carry on by itself",
            "waiting": "it is asking you something in its terminal, a question or a "
                       "permission whose Return would choose for you: answer it in its tab"}.get(
                status, "its status is %r, not one that waits for you" % status)


def one_line(text):
    """A reply as the one line typed: line breaks are spaces, every other
    control character is a space, and nothing else changes."""
    s = re.sub(r"[ \t]*(?:\r\n|[\r\n\u0085\u2028\u2029])+[ \t]*", " ", str(text or ""))
    return re.sub(r"[\x00-\x1f\x7f-\x9f]", " ", s).strip()


def _ps(*args):
    try:
        return subprocess.run(["ps"] + list(args), capture_output=True, text=True, timeout=5).stdout
    except Exception:
        return ""


def held(sid, writing=True):
    """The guard, read now: the running session with this id, its pid, its tty
    and its status, or Refused saying which check failed. `writing` adds the
    two checks that only typing needs, the status against what the keys are
    for — True is a reply on your turn, or the statuses themselves — and the
    foreground; bringing its tab forward needs a live process with a terminal
    and nothing more."""
    import waiting as _W
    d = _W.session_file(sid)
    if not d:
        raise Refused("running", "it is not running: no live Claude process has that session")
    pid = d["pid"]
    row = _ps("-o", "tty=,stat=,comm=", "-p", str(pid)).split(None, 2)
    if len(row) < 3 or os.path.basename(row[2].strip()) != "claude":
        raise Refused("running", "its Claude process (pid %d) has ended" % pid)
    tty, stat = row[0], row[1]
    if not TTY.match(tty):
        raise Refused("terminal", "it has no terminal to type into")
    status = d.get("status") or ""
    if writing:
        allow = writing if isinstance(writing, frozenset) else WAITS_FOR_YOU
        if status not in allow:
            raise Refused("status", _not_now(status, allow), status)
        front = [ln.split(None, 2) for ln in _ps("-t", tty, "-o", "pid=,stat=,comm=").splitlines()]
        front = [r for r in front if len(r) == 3 and "+" in r[1]]
        if not any(r[0] == str(pid) for r in front) or "+" not in stat:
            who = ", ".join(sorted({os.path.basename(r[2].strip()).lstrip("-") for r in front})) or "nothing"
            raise Refused("foreground", "Claude is not in its terminal's foreground (%s is), "
                                        "so what is typed would not reach it" % who)
    return {"sid": sid, "pid": pid, "tty": tty, "status": status, "name": d.get("name") or ""}


def _host(pid):
    """The application bundle a process runs under: the first of its ancestors
    whose program lives inside an .app — for a session in iTerm, iTerm itself,
    above its server, `login` and the shell."""
    table = {}
    for ln in _ps("-A", "-o", "pid=,ppid=,comm=").splitlines():
        parts = ln.split(None, 2)
        if len(parts) == 3 and parts[0].isdigit() and parts[1].isdigit():
            table[int(parts[0])] = (int(parts[1]), parts[2].strip())
    seen, cur = set(), table.get(pid, (0, ""))[0]
    while cur > 1 and cur not in seen:
        seen.add(cur)
        ppid, comm = table.get(cur, (0, ""))
        m = re.match(r"^(/.+?\.app)/Contents/MacOS/", comm)
        if m:
            return m.group(1)
        cur = ppid
    return ""


def _bundle(path):
    """What an application's Info.plist says it is, read from disk."""
    try:
        with open(os.path.join(path, "Contents", "Info.plist"), "rb") as f:
            info = plistlib.load(f)
        return info.get("CFBundleIdentifier") or "", info.get("CFBundleName") or os.path.basename(path)
    except Exception:
        return "", os.path.basename(path)


def iterm_of(pid):
    """The iTerm a session runs under, by name as its bundle gives it, or
    Refused naming the terminal it runs under instead."""
    app = _host(pid)
    ident, name = _bundle(app) if app else ("", "")
    if ident != ITERM_ID:
        raise Refused("iterm", "only iTerm: this session runs in " +
                      (name.replace(".app", "") if app else "no terminal application this can tell — tmux, ssh or the like"))
    return name                                    # "iTerm2", from CFBundleName


def to_terminal(sid, verb, text="", working=False):
    """Type a reply into a running session's own tab (`write`), send it the
    Escape key that stops a turn (`stop`), or bring that tab forward (`show`).
    The page sends the session id and, for a reply, the words, and says with
    `working` that you confirmed a reply while it works; everything else is
    read here."""
    if verb not in ("write", "show", "stop"):
        raise ValueError("unknown verb")
    writing = verb == "write"
    line = one_line(text) if writing else ""
    if writing and not line:
        raise Refused("text", "there is nothing to send")
    if writing and len(line) > MAX_REPLY:
        raise Refused("text", "a reply is one line of at most %d characters" % MAX_REPLY)
    # what the keys are for: a tab brought forward types nothing; a reply goes
    # in on your turn, or while it works when you confirmed that, and only the
    # boolean says so; the Escape key goes in only while it works
    if verb == "show":
        keys = False
    elif verb == "stop":
        keys = STOPPABLE
    else:
        keys = WHILE_WORKING if working is True else True
    g = held(sid, keys)
    app = iterm_of(g["pid"])
    if keys:
        again = held(sid, keys)                    # read again, as late as it can be
        if (again["pid"], again["tty"]) != (g["pid"], g["tty"]):
            raise Refused("running", "the session changed terminals while this was sent")
    argv = ["osascript", "-", "/dev/" + g["tty"], verb] + ([line] if writing else [])
    out = {"ok": True, "session": sid, "name": g["name"], "tty": g["tty"], "app": app,
           "verb": verb, "text": line, "status": g["status"]}
    if _dry():                                     # resolved and checked; nothing is scripted
        return dict(out, dry=True, argv=argv, script=ITERM_SCRIPT)
    try:
        r = subprocess.run(argv, input=ITERM_SCRIPT, capture_output=True, text=True, timeout=120)
    except subprocess.TimeoutExpired:
        raise Refused("iterm", "iTerm did not answer within two minutes — if macOS asked whether "
                               "rubricator may control it, answer and send again")
    said = (r.stdout or "").strip()
    if r.returncode != 0:
        err = (r.stderr or "").strip()
        if "-1743" in err or "not allowed" in err.lower() or "not authorized" in err.lower():
            raise Refused("iterm", "macOS does not let rubricator control iTerm — allow it under "
                                   "System Settings → Privacy & Security → Automation")
        raise Refused("iterm", "iTerm refused: " + (err[:200] or "no reason given"))
    if said == "none":
        raise Refused("iterm", "no iTerm tab has its terminal (%s)" % g["tty"])
    return out
