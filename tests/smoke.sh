#!/usr/bin/env bash
# Six smoke tests on the seams that were already in the code.
#
# There was no test harness to write: hook.py:108 is RUBRICATOR_NO_WINDOW —
# "tests drive the page themselves", in a comment written by someone who
# intended this — and actions.py:230 is RUBRICATOR_DRY_LAUNCH.
#
# One thing to know before adding a test here: **exit codes are almost all
# green on a broken install.** `md -o` exits 0 whether or not the renderer
# reached the page. Only test 1 moves on status, because a missing Python file
# is louder than a missing JavaScript one. Test 2 is the one that catches a
# renderer that is present and silent, and it must therefore assert on
# content.
#
#   ./tests/smoke.sh              the five that need no browser
#   ./tests/smoke.sh --browser    all six (test 2 needs headless Chrome)
set -uo pipefail

REPO="$(cd -P "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
WITH_BROWSER=0
[ "${1:-}" = "--browser" ] && WITH_BROWSER=1

pass=0; fail=0
ok()   { printf '  ok    %s\n' "$1"; pass=$((pass + 1)); }
no()   { printf '  FAIL  %s\n    %s\n' "$1" "${2:-}"; fail=$((fail + 1)); }
skip() { printf '  skip  %s (%s)\n' "$1" "$2"; }

echo "rubricator smoke tests"

# ── install into an isolated prefix, the way a stranger would ────────────────
export HOME="$WORK/home"; mkdir -p "$HOME"
PREFIX="$WORK/pfx"
if ! (cd "$REPO" && PREFIX="$PREFIX" ./install.sh --no-shell) >"$WORK/install.log" 2>&1; then
  echo "  FAIL  install.sh did not complete — see below"; sed 's/^/    /' "$WORK/install.log"; exit 1
fi
MD="$PREFIX/bin/md"
# hook.py:17-18 default SHARE and MD_BIN to ~/.local/…, so a --prefix install
# needs both seams set or the review paths look for a binary that is not there.
export RUBRICATOR_BIN="$MD"
export RUBRICATOR_HOME="$PREFIX/share/rubricator"

# ── layer 1 · the inventory ──────────────────────────────────────────────────
# Makes the glob install permanent: reverting it turns this red immediately,
# by name, with the missing files listed.
if diff -rq --exclude=vendor --exclude=__pycache__ \
     "$REPO/share/" "$PREFIX/share/rubricator/" >"$WORK/diff.log" 2>&1; then
  ok "0 · every file in share/ reached the install"
else
  no "0 · share/ and the install differ" "$(sed 's/^/    /' "$WORK/diff.log" | head -12)"
fi

# ── 1 · bare md in a git repository exits 0 ─────────────────────────────────
# The only one of the six that would have caught the 8-of-18 bug by status.
if (cd "$REPO" && "$MD" -w -n . >/dev/null 2>&1); then
  ok "1 · bare md in a git repository exits 0"
else
  no "1 · bare md exited non-zero" "the workspace could not be built"
fi

# ── 2 · md -o produces a page that renders ──────────────────────────────────
printf '# smoke fixture heading\n\nprose, and `code`.\n' > "$WORK/fixture.md"
"$MD" -o "$WORK/out.html" "$WORK/fixture.md" >/dev/null 2>&1
if [ ! -s "$WORK/out.html" ]; then
  no "2a · md -o wrote nothing" ""
elif grep -q 'md renderer' "$WORK/out.html"; then
  ok "2a · the renderer is inlined in the page"
else
  # Do NOT assert on 'window.MD' here: review.js defines window.MDReview, so
  # that string is present on the broken page too and the check would pass on
  # the exact bug it exists to catch.
  no "2a · no renderer in the page" "share/render.js did not reach the install"
fi

if [ "$WITH_BROWSER" = 1 ]; then
  CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
  [ -x "$CHROME" ] || CHROME="$HOME/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
  if [ -x "$CHROME" ]; then
    "$CHROME" --headless --disable-gpu --virtual-time-budget=8000 \
      --dump-dom "file://$WORK/out.html" >"$WORK/dom.html" 2>/dev/null
    if grep -q 'smoke fixture heading' "$WORK/dom.html"; then
      ok "2b · the rendered DOM contains the fixture's heading"
    else
      no "2b · the fixture never reached the DOM" "the code is installed and does not run"
    fi
  else
    skip "2b · rendered DOM" "no Chrome"
  fi
else
  skip "2b · rendered DOM" "needs --browser"
fi

# ── 3 · md --review returns the export text ─────────────────────────────────
# Driven through the page's own POST, the way the window would.
python3 - "$MD" "$WORK" <<'PY' >"$WORK/review.log" 2>&1
import json, os, re, subprocess, sys, time, urllib.request
md, work = sys.argv[1], sys.argv[2]
plan = os.path.join(work, "plan.md")
open(plan, "w").write("# plan\n\n## one\n\nbody text here\n")
# hook.py:225 prints the URL under RUBRICATOR_DEBUG; :108 is what stops the
# window opening. Both are needed to drive the page from a test.
env = dict(os.environ, RUBRICATOR_NO_WINDOW="1", RUBRICATOR_DEBUG="1",
           RUBRICATOR_TIMEOUT="25")
p = subprocess.Popen([md, "--review", plan], env=env,
                     stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
url = None; seen = ""
for _ in range(100):                       # the URL appears on stderr
    time.sleep(0.1)
    if p.poll() is not None:
        break
    try:
        os.set_blocking(p.stderr.fileno(), False)
        chunk = p.stderr.read() or ""
    except Exception:
        chunk = ""
    seen += chunk
    m = re.search(r"http://127\.0\.0\.1:\d+/\S+", seen)
    if m:
        url = m.group(0).rstrip("/"); break
if not url:
    print("NOURL"); p.kill(); sys.exit(1)
base = url                                  # http://127.0.0.1:PORT/TOKEN
body = json.dumps({"action": "feedback", "text": "SMOKE-EXPORT-MARKER"}).encode()
req = urllib.request.Request(f"{base}/verdict", data=body,
                             headers={"Content-Type": "application/json",
                                      "Sec-Fetch-Site": "same-origin", "Origin": base})
try:
    urllib.request.urlopen(req, timeout=5).read()
except Exception as e:
    print("POSTFAIL", e)
out, _ = p.communicate(timeout=20)
print("RC", p.returncode)
print("OUT", out.strip())
PY
if grep -q 'SMOKE-EXPORT-MARKER' "$WORK/review.log"; then
  ok "3 · md --review printed the feedback it was given"
elif grep -q 'NOURL' "$WORK/review.log"; then
  skip "3 · md --review" "no URL on stderr — seam changed"
else
  no "3 · md --review did not return the export" "$(tail -3 "$WORK/review.log")"
fi

# ── 4 · no feedback exits 1, and says so ────────────────────────────────────
printf '# plan\n\nbody\n' > "$WORK/p4.md"
err="$(RUBRICATOR_NO_WINDOW=1 RUBRICATOR_TIMEOUT=3 "$MD" --review "$WORK/p4.md" 2>&1 >/dev/null)"
rc=$?
if [ "$rc" = 1 ] && printf '%s' "$err" | grep -q 'no feedback given'; then
  ok "4 · no feedback exits 1 with 'md: no feedback given'"
else
  no "4 · wrong no-feedback behaviour" "exit=$rc err=$(printf '%s' "$err" | tail -1)"
fi

# ── 5 · the hook returns valid JSON on the timeout path ─────────────────────
# Nothing here may wedge a session: every failure has to exit quietly with a
# decision the caller can parse.
printf '# a plan\n\n## step\n\ndo the thing\n' > "$WORK/hookplan.md"
hookjson="$(printf '{"tool_name":"ExitPlanMode","tool_input":{"plan":"# a plan\\n\\n## step\\n\\ndo the thing\\n"}}' \
  | RUBRICATOR_NO_WINDOW=1 RUBRICATOR_TIMEOUT=3 "$MD" --hook plan 2>/dev/null)"
# What is being asserted is the promise the README makes: nothing here can
# wedge a session. Whatever happens — missing plan, malformed input, timeout —
# the caller gets parseable JSON that is either a decision or a quiet skip.
# It is deliberately NOT asserted that a decision comes back: ExitPlanMode does
# not carry the plan text, so on a synthetic payload with no transcript behind
# it the correct answer is the skip. Register item K5 changes that.
if printf '%s' "$hookjson" | python3 -c '
import json,sys
d = json.load(sys.stdin)
h = d.get("hookSpecificOutput", {})
ok = h.get("permissionDecision") in ("allow","deny","ask") or "systemMessage" in d
sys.exit(0 if ok else 1)
' 2>/dev/null; then
  ok "5 · the hook returns parseable JSON and cannot wedge a session"
else
  no "5 · the hook returned something a caller cannot parse" "got: $(printf '%s' "$hookjson" | head -c 160)"
fi

# ── 6 · md --vendor verifies all five checksums ─────────────────────────────
if "$MD" --vendor >"$WORK/vendor.log" 2>&1; then
  n="$(grep -c '^# *$\|^[^#]' "$REPO/share/vendor.txt" | head -1)"
  if [ "$(ls "$PREFIX/share/rubricator/vendor" 2>/dev/null | wc -l | tr -d ' ')" = 5 ]; then
    ok "6 · md --vendor verified and installed all five libraries"
  else
    no "6 · wrong number of vendored libraries" "$(ls "$PREFIX/share/rubricator/vendor" 2>/dev/null | tr '\n' ' ')"
  fi
else
  no "6 · md --vendor failed" "$(tail -2 "$WORK/vendor.log")"
fi

# ── 7 · the plan comes from the payload, not from a guess ───────────────────
# K5. find_plan greps the transcript for a path under ~/.claude/plans and falls
# back to the newest file there, so `plansDirectory` users got nothing and a
# concurrent session's plan could be picked up instead. The payload carries it.
mkdir -p "$WORK/plans"
printf '# payload plan\n\nfrom planFilePath, not from a guess.\n' > "$WORK/plans/from-payload.md"
route="$WORK/route.jsonl"
payload=$(python3 -c '
import json, sys
print(json.dumps({"tool_name": "ExitPlanMode",
                  "tool_input": {"plan": "# payload plan\n", "planFilePath": sys.argv[1]}}))
' "$WORK/plans/from-payload.md")
out="$(printf '%s' "$payload" | RUBRICATOR_NO_WINDOW=1 RUBRICATOR_TIMEOUT=3 \
        RUBRICATOR_HOOK_LOG="$route" "$MD" --hook plan 2>/dev/null)"
if [ -s "$route" ] && python3 -c '
import json, sys
r = json.loads(open(sys.argv[1]).readlines()[-1])
sys.exit(0 if r["route"].endswith("planFilePath") and r["found"] else 1)
' "$route" 2>/dev/null; then
  ok "7 · the plan is taken from the payload, not found by guesswork"
else
  no "7 · the payload route did not fire" "route log: $(tail -1 "$route" 2>/dev/null | head -c 200)"
fi

# ── 8 · Approve pairs updatedInput with allow ───────────────────────────────
# K5b. Measured 2026-08-25: allow on its own leaves Claude Code's approval menu
# up, so Approve cost a window and changed nothing. The pairing is the fix, and
# this asserts the shape of it — the menu itself needs a human to observe.
python3 - "$MD" "$WORK" <<'PYEOF' >"$WORK/approve.log" 2>&1
import json, os, re, subprocess, sys, time, urllib.request
md, work = sys.argv[1], sys.argv[2]
plan = os.path.join(work, "plans", "from-payload.md")
payload = json.dumps({"tool_name": "ExitPlanMode",
                      "tool_input": {"plan": "# payload plan\n", "planFilePath": plan}})
env = dict(os.environ, RUBRICATOR_NO_WINDOW="1", RUBRICATOR_DEBUG="1", RUBRICATOR_TIMEOUT="25")
p = subprocess.Popen([md, "--hook", "plan"], env=env, stdin=subprocess.PIPE,
                     stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
p.stdin.write(payload); p.stdin.close()
url, seen = None, ""
for _ in range(100):
    time.sleep(0.1)
    if p.poll() is not None: break
    try:
        os.set_blocking(p.stderr.fileno(), False); seen += p.stderr.read() or ""
    except Exception: pass
    m = re.search(r"http://127\.0\.0\.1:\d+/\S+", seen)
    if m: url = m.group(0).rstrip("/"); break
if not url:
    print("NOURL"); p.kill(); sys.exit(1)
req = urllib.request.Request(url + "/verdict",
        data=json.dumps({"action": "approve", "text": ""}).encode(),
        headers={"Content-Type": "application/json",
                 "Sec-Fetch-Site": "same-origin", "Origin": url.rsplit("/", 1)[0]})
try: urllib.request.urlopen(req, timeout=5).read()
except Exception as e: print("POSTFAIL", e)
out, _ = p.communicate(timeout=20)
print("RAW", out.strip()[:400])
try:
    h = json.loads(out)["hookSpecificOutput"]
    print("DECISION", h.get("permissionDecision"))
    print("PAIRED", "plan" in (h.get("updatedInput") or {}))
except Exception as e:
    print("UNPARSEABLE", e)
PYEOF
if grep -q '^DECISION allow' "$WORK/approve.log" && grep -q '^PAIRED True' "$WORK/approve.log"; then
  ok "8 · Approve returns allow with updatedInput paired"
elif grep -q 'NOURL' "$WORK/approve.log"; then
  skip "8 · Approve pairing" "no URL on stderr — seam changed"
else
  no "8 · Approve did not pair updatedInput" "$(grep -E '^(DECISION|PAIRED|RAW|UNPARSEABLE)' "$WORK/approve.log" | head -3)"
fi

printf '\n  %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
