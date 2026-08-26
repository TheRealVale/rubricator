#!/usr/bin/env python3
"""
rubricator review server — opens the review window and blocks until the human decides.

Used two ways:
  md --hook plan   (from a Claude Code PreToolUse/ExitPlanMode hook; JSON on stdin,
                    hook decision JSON on stdout)
  md --review FILE (manual; prints the feedback text to stdout)

Guiding rule: a failure here must never block Claude Code. Anything unexpected
exits 0 with no decision, so the normal flow continues untouched.
"""
import http.server, json, os, re, secrets, socket, subprocess, sys, threading, time
from pathlib import Path

HOME    = Path.home()
SHARE   = Path(os.environ.get("RUBRICATOR_HOME", HOME / ".local/share/rubricator"))
MD_BIN  = os.environ.get("RUBRICATOR_BIN", str(HOME / ".local/bin/md"))
PLANS   = HOME / ".claude" / "plans"
CHROME  = "/Applications/Google Chrome.app"
WAIT    = int(os.environ.get("RUBRICATOR_TIMEOUT", "540"))    # under the hook's 600s ceiling
CACHE   = Path(os.environ.get("RUBRICATOR_CACHE", str(HOME / ".cache/rubricator")))
ROUTE_KEEP = 50          # the route log answers one question; it is not history

TOKEN   = secrets.token_urlsafe(9)
RESULT  = {}
DONE    = threading.Event()
HTML    = b""


# ── locating the plan ────────────────────────────────────────────────────────
def plan_from_payload(payload):
    """Claude Code hands the hook the plan directly: `planFilePath` for where it
    wrote it, `plan` for the text. Both are documented, on the tool input and
    sometimes at the top level depending on the build, so look in both places.

    Preferring the path over the text is not fussiness — annotations key off the
    document's path, so a plan read from its real file keeps its notes across the
    rewrite, and one read from a temporary copy does not."""
    ti = payload.get("tool_input") or {}
    for src, val in (("tool_input.planFilePath", ti.get("planFilePath")),
                     ("planFilePath", payload.get("planFilePath"))):
        if isinstance(val, str) and val and os.path.isfile(val):
            return val, src
    return None, None


def find_plan(payload):
    """The fallback, and the reason K5 exists.

    ExitPlanMode was believed to carry no plan text, so this greps the tail of
    the transcript for a path under ~/.claude/plans and falls back to the newest
    file there. Both halves are guesses: anyone who set `plansDirectory` gets no
    hit at all, and the mtime fallback can pick up a *concurrent* session's plan
    and hand you the wrong document to review.

    Kept only until one real hook fire confirms the payload fields arrive on this
    build — standing rule 12. `RUBRICATOR_HOOK_LOG` records which path was taken,
    so the confirmation is a by-product of ordinary use rather than an errand."""
    hits = []
    tp = payload.get("transcript_path")
    if tp and os.path.isfile(tp):
        try:
            size = os.path.getsize(tp)
            with open(tp, "rb") as f:
                if size > 4_000_000:
                    f.seek(size - 4_000_000)          # only the tail matters
                blob = f.read().decode("utf-8", "replace")
            hits = re.findall(r'/[^"\s\\]+/\.claude/plans/[^"\s\\]+\.md', blob)
        except Exception:
            pass
    for p in reversed(hits):                          # most recent mention wins
        if os.path.isfile(p):
            return p
    try:
        files = sorted(PLANS.glob("*.md"), key=lambda p: p.stat().st_mtime, reverse=True)
        if files and time.time() - files[0].stat().st_mtime < 3600:
            return str(files[0])
    except Exception:
        pass
    return None


# ── the tiny local server the page talks back through ────────────────────────
class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def _guard(self):
        # localhost only, and the path must carry this run's token
        host = (self.headers.get("Host") or "").split(":")[0]
        return host in ("127.0.0.1", "localhost")

    def do_GET(self):
        if not self._guard():
            return self.send_error(403)
        if self.path.rstrip("/") == "/" + TOKEN:
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(HTML)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(HTML)
        else:
            self.send_error(404)

    def do_POST(self):
        if not self._guard() or self.path.rstrip("/") != "/" + TOKEN + "/verdict":
            return self.send_error(404)
        try:
            n = int(self.headers.get("Content-Length") or 0)
            data = json.loads(self.rfile.read(n) or b"{}")
        except Exception:
            data = {}
        if not DONE.is_set():
            RESULT.update(data if isinstance(data, dict) else {})
            DONE.set()
        self.send_response(204)
        self.send_header("Content-Length", "0")
        self.end_headers()


def serve():
    srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    srv.daemon_threads = True
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv, srv.server_address[1]


# ── window handling ──────────────────────────────────────────────────────────
def open_window(url):
    if os.environ.get("RUBRICATOR_NO_WINDOW"):   # tests drive the page themselves
        return
    if os.path.isdir(CHROME):
        try:
            subprocess.run(["open", "-na", CHROME, "--args", "--app=" + url,
                            "--window-size=1180,940"],
                           check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return
        except Exception:
            pass
    subprocess.run(["open", url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def close_window(port):
    """Close only the window showing this run's URL — matched on the port."""
    # only ever close a single-tab window showing exactly this URL: never a
    # window the user has other tabs in
    script = f'''
    tell application "Google Chrome"
      repeat with w in (windows as list)
        try
          if (count of tabs of w) is 1 then
            if (URL of tab 1 of w) contains "127.0.0.1:{port}" then close w
          end if
        end try
      end repeat
    end tell'''
    try:
        subprocess.run(["osascript", "-e", script], timeout=6,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        pass


# ── rendering ────────────────────────────────────────────────────────────────
def render(path, hook_meta, out):
    env = dict(os.environ, RUBRICATOR_HOOK=json.dumps(hook_meta))
    r = subprocess.run([MD_BIN, "-o", out, path], env=env,
                       stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    if r.returncode != 0 or not os.path.isfile(out):
        raise RuntimeError((r.stderr or b"").decode()[:200] or "render failed")
    with open(out, "rb") as f:
        return f.read()


def read_plan(path):
    """The plan as it was written, for pairing back as `updatedInput`. Read from
    disk rather than carried from the render, because the render subprocess owns
    its own copy and this has to be the bytes Claude Code will act on."""
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    except Exception:
        return None            # better an unpaired allow than a wedged session


def note_review(payload, path, action, items, label):
    """One line per plan review, appended to ~/.local/state/rubricator/reviews.jsonl.

    The hook produces a decision, a systemMessage and nothing on disk, and every
    invocation is a fresh ephemeral origin — so it cannot leave a mark that
    survives to the next one. Zero recorded reviews and two hundred look
    identical from here, which makes the flagship loop the one thing rubricator
    cannot tell you anything about.

    Everything written is already in hand: no new read, no new permission, no
    UI. Grep-readable, `rm`-deletable, and `md` never reads it back — this is a
    record, not an index. The approved plan *text* is the other half of N6 and
    lands with M6, which decides what `.rubricator/` is on disk."""
    d = Path(os.environ.get("RUBRICATOR_STATE",
                            str(HOME / ".local/state/rubricator")))
    try:
        d.mkdir(parents=True, exist_ok=True)
        os.chmod(d, 0o700)
        f = d / "reviews.jsonl"
        with f.open("a", encoding="utf-8") as fh:
            fh.write(json.dumps({
                "at": int(time.time()),
                "decision": action,
                "plan": os.path.basename(path or ""),
                "items": items,
                "session": payload.get("session_id") or "",
                "repo": os.path.basename(payload.get("cwd") or os.getcwd()),
            }) + "\n")
        os.chmod(f, 0o600)
    except Exception:
        pass          # a review that cannot be recorded is still a review


def note_route(payload, path, how):
    """Standing rule 12: do not scope a design on a documented-but-unfired
    platform feature. This is the firing. One line per hook run, appended to
    RUBRICATOR_HOOK_LOG if it is set — which the smoke tests set, and which a
    curious user can set for one session. It records the payload's shape rather
    than its contents, so the plan text never reaches the log."""
    dest = os.environ.get("RUBRICATOR_HOOK_LOG") or str(CACHE / "hook-route.jsonl")
    ti = payload.get("tool_input") or {}
    line = json.dumps({
        "at": int(time.time()),
        "top_keys": sorted(payload.keys()),
        "tool_input_keys": sorted(ti.keys()),
        "has_plan_text": bool(ti.get("plan") or payload.get("plan")),
        "route": how, "found": bool(path),
    })
    try:
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        old = []
        if os.path.isfile(dest):
            with open(dest, encoding="utf-8") as f:
                old = f.read().splitlines()[-(ROUTE_KEEP - 1):]
        with open(dest, "w", encoding="utf-8") as f:
            f.write("\n".join(old + [line]) + "\n")
        os.chmod(dest, 0o600)
    except Exception:
        pass          # a log that cannot be written must not break a review


# ── decisions ────────────────────────────────────────────────────────────────
def emit(obj):
    sys.stdout.write(json.dumps(obj))
    sys.stdout.flush()


def hook_decision(action, text, label, plan_text=None):
    if action == "approve":
        ctx = "The plan was reviewed and approved in rubricator."
        if (text or "").strip():
            ctx += "\n\n" + text.strip()
        out = {"hookSpecificOutput": {
            "hookEventName": "PreToolUse", "permissionDecision": "allow",
            "additionalContext": ctx},
            "systemMessage": f"rubricator: {label} approved" +
                             (" with notes" if (text or "").strip() else "")}
        # `allow` alone does not approve an ExitPlanMode. Measured 2026-08-25 on
        # claude 2.1.241: the window closed and Claude Code's own approval menu
        # appeared anyway, so Approve cost a window and changed nothing. The
        # hooks page is explicit — allow "skips the permission prompt, except
        # for … AskUserQuestion and ExitPlanMode, which need updatedInput paired
        # with it". So pair it, with the plan exactly as it was proposed:
        # rubricator reviews a plan, it does not rewrite one, and handing back
        # an edited plan would cross the write rule.
        if plan_text:
            out["hookSpecificOutput"]["updatedInput"] = {"plan": plan_text}
        return out
    if action == "feedback" and (text or "").strip():
        return {"hookSpecificOutput": {
            "hookEventName": "PreToolUse", "permissionDecision": "deny",
            "permissionDecisionReason": text.strip()},
            "systemMessage": f"md: feedback sent on {label}"}
    reason = {"closed": "Review window closed without a decision.",
              "timeout": "Review timed out."}.get(action, "No decision from md.")
    return {"hookSpecificOutput": {
        "hookEventName": "PreToolUse", "permissionDecision": "ask",
        "permissionDecisionReason": reason},
        "systemMessage": f"md: {reason.lower()} falling back to the usual prompt"}


# ── main ─────────────────────────────────────────────────────────────────────
def main():
    global HTML
    mode = sys.argv[1] if len(sys.argv) > 1 else "plan"
    arg  = sys.argv[2] if len(sys.argv) > 2 else None
    is_hook = mode == "plan"

    payload = {}
    if is_hook:
        try:
            raw = sys.stdin.read()
            payload = json.loads(raw) if raw.strip() else {}
        except Exception:
            payload = {}

    if is_hook:
        path, how = plan_from_payload(payload)
        if not path:
            path, how = find_plan(payload), "find_plan"
        note_route(payload, path, how)
    else:
        path, how = arg, "argument"
    if not path or not os.path.isfile(path):
        if is_hook:
            emit({"systemMessage": "md: no plan file found — skipping review"})
        else:
            sys.stderr.write("md: no such file\n")
        return 0 if is_hook else 1

    srv, port = serve()
    base = f"http://127.0.0.1:{port}/{TOKEN}"
    deadline = time.time() + WAIT
    label = os.path.basename(path)
    meta = {"url": base + "/verdict", "deadline": int(deadline * 1000),
            "mode": "plan" if is_hook else "manual", "label": label}

    tmp = Path(os.environ.get("TMPDIR", "/tmp")) / f"md-review-{TOKEN}.html"
    try:
        HTML = render(path, meta, str(tmp))
    except Exception as e:
        if is_hook:
            emit({"systemMessage": f"md: could not render the plan ({e}) — skipping review"})
            return 0
        sys.stderr.write(f"md: {e}\n")
        return 1
    finally:
        try: os.unlink(tmp)
        except Exception: pass

    if os.environ.get("RUBRICATOR_DEBUG"):
        sys.stderr.write(base + "/\n"); sys.stderr.flush()
    open_window(base + "/")
    DONE.wait(timeout=max(5, deadline - time.time()))
    action = RESULT.get("action", "timeout")
    text   = RESULT.get("text", "")
    time.sleep(0.35)                    # let the page paint its confirmation
    close_window(port)

    if is_hook:
        note_review(payload, path, action, RESULT.get("items", 0), label)
        emit(hook_decision(action, text, label, plan_text=read_plan(path)))
    else:
        if action == "feedback" and text.strip():
            sys.stdout.write(text.strip() + "\n")
        elif action == "approve":
            if (text or "").strip():
                sys.stdout.write(f"Approved {label} — no changes requested.\n\n" + text.strip() + "\n")
            else:
                sys.stdout.write(f"Approved {label} with no changes requested.\n")
        else:
            sys.stderr.write("md: no feedback given\n")
            return 1
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(0)
    except Exception as e:                     # never break the caller
        try: emit({"systemMessage": f"md: review hook error ({e})"})
        except Exception: pass
        sys.exit(0)
