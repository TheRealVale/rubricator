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

TERMINALS = {          # app name → how to run a script in a new window
    "iTerm.app":     "iTerm",
    "iTerm2.app":    "iTerm",
    "Apple_Terminal": "Terminal",
    "Terminal.app":  "Terminal",
}


def config():
    try:
        d = json.loads(CONFIG.read_text(encoding="utf-8"))
        return d if isinstance(d, dict) else {}
    except Exception:
        return {}


def enabled():
    if os.environ.get("RUBRICATOR_ALLOW_LAUNCH") == "1":
        return True
    return bool(config().get("allow_launch"))


def terminal():
    """Whatever ran `md`, remembered — never guessed from the browser."""
    want = os.environ.get("RUBRICATOR_TERM") or config().get("terminal") or ""
    app = TERMINALS.get(want)
    if app:
        return app
    if os.path.isdir("/Applications/iTerm.app"):
        return "iTerm"
    return "Terminal"


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
    if os.environ.get("RUBRICATOR_DRY_LAUNCH"):     # build the launcher, open nothing
        return
    named = TERMINALS.get(config().get("terminal") or "")
    if named:
        # you named a terminal, so drive it — and say plainly when macOS has not
        # been told to allow that yet, because the permission dialog blocks
        cmd = f"/bin/sh {shlex.quote(str(script))}"
        osa = (f'tell application "iTerm" to create window with default profile command "{cmd}"'
               if named == "iTerm" else
               f'tell application "Terminal"\n activate\n do script "{cmd}"\nend tell')
        try:
            r = subprocess.run(["osascript", "-e", osa], timeout=15,
                               stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
            if r.returncode == 0:
                return
            err = (r.stderr or b"").decode("utf-8", "replace").strip()[:160]
            raise RuntimeError(f"{named} refused the command: {err}")
        except subprocess.TimeoutExpired:
            raise RuntimeError(
                f"macOS is asking whether rubricator may control {named}. Allow it under "
                "System Settings › Privacy & Security › Automation, or drop "
                '"terminal" from ~/.config/rubricator/config.json to use Terminal.app instead.')

    # the default: hand the .command to Terminal through LaunchServices, which
    # needs no Automation permission
    r = subprocess.run(["open", "-a", "Terminal", str(script)], timeout=20,
                       stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    if r.returncode != 0:
        err = (r.stderr or b"").decode("utf-8", "replace").strip()[:200]
        raise RuntimeError("could not open a terminal window: " + (err or "unknown error"))


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
    _open_window(sc)
    return {"ok": True, "cwd": str(cwd), "script": str(sc)}


def resume(cwd, sid, fork=False):
    if not SESSION_ID.match(sid or ""):
        raise ValueError("not a session id")
    argv = [_claude(), "-r", sid] + (["--fork-session"] if fork else [])
    sc = _script(cwd, argv)
    _open_window(sc)
    return {"ok": True, "session": sid, "script": str(sc)}


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
