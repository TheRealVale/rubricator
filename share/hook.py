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

TOKEN   = secrets.token_urlsafe(9)
RESULT  = {}
DONE    = threading.Event()
HTML    = b""


# ── locating the plan ────────────────────────────────────────────────────────
def find_plan(payload):
    """ExitPlanMode carries no plan text — the plan is a file the agent wrote.
    The transcript records its path, so read it from there; newest-file is the
    fallback when the transcript is unavailable."""
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


# ── decisions ────────────────────────────────────────────────────────────────
def emit(obj):
    sys.stdout.write(json.dumps(obj))
    sys.stdout.flush()


def hook_decision(action, text, label):
    if action == "approve":
        ctx = "The plan was reviewed and approved in rubricator."
        if (text or "").strip():
            ctx += "\n\n" + text.strip()
        return {"hookSpecificOutput": {
            "hookEventName": "PreToolUse", "permissionDecision": "allow",
            "additionalContext": ctx},
            "systemMessage": f"rubricator: {label} approved" +
                             (" with notes" if (text or "").strip() else "")}
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

    path = arg if not is_hook else find_plan(payload)
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
        emit(hook_decision(action, text, label))
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
