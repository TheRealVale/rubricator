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
"""
import json, os, re, shlex, subprocess, time
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
            "idle": 120, "theme": "rubric", "searches": []}


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


def open_project(path, sessions=False):
    """Open a second workspace, the way an editor opens a second window. This
    starts rubricator on a directory — never an arbitrary program."""
    md = os.environ.get("RUBRICATOR_BIN") or str(HOME / ".local/bin/md")
    if not os.path.isfile(md):
        raise RuntimeError("cannot find the md command to open a second window")
    env = {k: v for k, v in os.environ.items()
           if not k.startswith(("RUBRICATOR_OUT", "RUBRICATOR_OPEN", "RUBRICATOR_INJECT",
                                "RUBRICATOR_HOME", "RUBRICATOR_JSON"))}
    argv = [md, str(path)] + (["--sessions"] if sessions else [])
    subprocess.Popen(argv, env=env, cwd=str(path), start_new_session=True,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
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


def _open_window(script):
    """LaunchServices, not AppleScript. Every terminal here runs a .command file
    when it is opened with one, so nothing needs Automation permission — and the
    permission dialog, which blocks, never appears."""
    if os.environ.get("RUBRICATOR_DRY_LAUNCH"):     # build the launcher, open nothing
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
    subprocess.run(["open", "-R", str(path)], check=True, timeout=15,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return {"ok": True}


def edit(path):
    ed = os.environ.get("RUBRICATOR_EDITOR") or config().get("editor") or ""
    if ed:
        _open_window(_script(Path(path).parent, [ed, str(path)]))
    else:
        subprocess.run(["open", "-t", str(path)], check=True, timeout=15,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return {"ok": True}
