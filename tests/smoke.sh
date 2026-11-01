#!/usr/bin/env bash
# Smoke tests on the seams that were already in the code, plus the ones later
# phases had to build.
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
# Two of these were mutation-tested on 2026-08-26: the suite was run against a
# clone with one regression introduced at a time, and only a test that went red
# is a test. That exercise is why 14-17 exist — a syntax error appended to
# workspace.js, shell.js or review.js left the whole suite green, the anchoring
# ladder had no coverage at all, and test 10 was passing on an empty corpus.
#
#   ./tests/smoke.sh              everything that needs no browser
#   ./tests/smoke.sh --browser    and the two that render a page
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

# ── nothing here scripts another application ─────────────────────────────────
# A run of this suite happens on a desk where terminals hold live sessions, and
# one AppleScript that reached them would type into one or switch its tabs. So
# `osascript` on the PATH is a tripwire: it scripts nothing, writes down that it
# was called, and fails. Test 50, the last, reads what it wrote, which has to be nothing.
TRIP="$WORK/tripwire"; mkdir -p "$TRIP"
printf '#!/bin/sh\nprintf "%%s\\n" "osascript $*" >> "%s"\nexit 1\n' "$WORK/osascript.log" > "$TRIP/osascript"
chmod +x "$TRIP/osascript"
export PATH="$TRIP:$PATH"

# ── install into an isolated prefix, the way a stranger would ────────────────
export HOME="$WORK/home"; mkdir -p "$HOME/.claude"
# Tests 10 and 14 assert that prompt text does not reach a static page. Under a
# fresh HOME there is no history at all, so both used to pass on an empty
# corpus: deleting the withholding code outright left the suite green. Three
# records is enough to make the assertion bite, and one of them carries a
# credential so the scrubber is exercised on the way past.
cat > "$HOME/.claude/history.jsonl" <<'HIST'
{"display":"how does the auth flow work","project":"/tmp/p","timestamp":1756000000000,"sessionId":"s-aaa"}
{"display":"set STRIPE_SECRET_KEY=sk_live_00smoketest00 and retry","project":"/tmp/p","timestamp":1756000001000,"sessionId":"s-aaa"}
{"display":"/compact","project":"/tmp/p","timestamp":1756000002000,"sessionId":"s-aaa"}
HIST
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
    # --use-mock-keychain is not optional. Headless Chrome on the default
    # profile reaches into the login Keychain for "Chrome Safe Storage", and on
    # a machine where that lookup does not go cleanly it raises a system dialog
    # per run — one of whose buttons resets a keychain. This says: do not go
    # near it. Observed while building phase N, ~20 runs in.
    #
    # The obvious fix is --user-data-dir, and it does not work here: on Chrome
    # 151.0.7922.174, an isolated profile makes --dump-dom hang indefinitely.
    # Measured, all against the same fixture: shared profile 2.0s; isolated
    # minimal, isolated with networking and sync off, --headless=new, and a
    # pre-seeded "First Run" sentinel — all >40s, no output. If a later Chrome
    # fixes that, prefer isolation and drop this comment; until then the
    # keychain is the harm and this removes it.
    "$CHROME" --headless --disable-gpu --virtual-time-budget=8000 \
      --use-mock-keychain --password-store=basic --disable-background-networking \
      --dump-dom "file://$WORK/out.html" >"$WORK/dom.html" 2>/dev/null
    if grep -q 'smoke fixture heading' "$WORK/dom.html"; then
      ok "2b · the rendered DOM contains the fixture's heading"
    else
      no "2b · the fixture never reached the DOM" "the code is installed and does not run"
    fi

    # 2c · and the workspace page, which is the product. Nothing rendered it
    # until 2026-08-26: workspace.js is the largest file in the repo, and a
    # syntax error in it left every other test green. Test 14 now catches that
    # statically; this catches the runtime half — code that parses and then
    # throws on the way to the first paint.
    (cd "$REPO" && "$MD" -w -o "$WORK/ws.html" . >/dev/null 2>&1) || true
    if [ -s "$WORK/ws.html" ]; then
      "$CHROME" --headless --disable-gpu --virtual-time-budget=12000 \
        --use-mock-keychain --password-store=basic --disable-background-networking \
        --dump-dom "file://$WORK/ws.html" >"$WORK/wsdom.html" 2>/dev/null
      # a document row for this repo's own README, drawn by workspace.js from
      # the payload — present only if the page got as far as its first paint
      if grep -q 'README.md' "$WORK/wsdom.html" && grep -qi 'class="row\|class="doc' "$WORK/wsdom.html"; then
        ok "2c · the workspace page paints its first document row"
      else
        no "2c · the workspace page never painted" "$(wc -c < "$WORK/wsdom.html" | tr -d ' ') bytes of DOM, no rows"
      fi
    else
      skip "2c · workspace page" "the page was not built"
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

# ── 9 · nothing under the cache is readable by anyone else ──────────────────
# N1. It was 0644 across 34 of 35 files, including the plaintext of every PDF
# indexed and every prompt ever typed, in the one cache directory macOS does
# not exclude from Time Machine.
export RUBRICATOR_CACHE="$WORK/cache"
(cd "$REPO" && "$MD" -w -n --sessions . >/dev/null 2>&1) || true
bad=$(find "$RUBRICATOR_CACHE" -type f ! -perm 600 2>/dev/null | wc -l | tr -d ' ')
baddir=$(find "$RUBRICATOR_CACHE" -type d ! -perm 700 2>/dev/null | wc -l | tr -d ' ')
if [ "${bad:-1}" = 0 ] && [ "${baddir:-1}" = 0 ]; then
  ok "9 · every file under the cache is 0600, every directory 0700"
else
  no "9 · the cache is readable by others" "$bad files, $baddir directories"
fi

# ── 10 · a static workspace carries no prompt text ──────────────────────────
# N2. bin/md refuses --out with --sessions because your history stays on this
# machine; the static build wrote the same corpus to a world-readable page with
# no flag at all. Asserts on the shape the corpus leaves behind, not on a count.
# `md -o` cannot reach this: bin/md:165 refuses --out with --sessions. The path
# that *did* write the corpus is the cache fallback, which calls workspace.py
# directly when the local server does not come up — so drive that, or the test
# proves only that a refusal the shell already makes is still made.
static="$WORK/static.html"
live=$(python3 -c 'import sys, os; sys.path.insert(0, os.environ["RUBRICATOR_HOME"])
import workspace as W; print(len(W.load_sessions()[0]))' 2>/dev/null || echo 0)
(cd "$REPO" && RUBRICATOR_OUT="$static" python3 "$RUBRICATOR_HOME/workspace.py" \
   . --sessions >/dev/null 2>&1) || true
if [ ! -s "$static" ]; then
  skip "10 · static workspace" "the page was not built"
elif [ "${live:-0}" -lt 1 ]; then
  no "10 · the test has no corpus to withhold" "load_sessions() returned ${live:-0} prompts — the assertion below is vacuous"
else
  # Assert on the payload, not on the page text. `grep '"sid"'` was a proxy for
  # "a prompt record reached the page", and it collides with any markup that
  # happens to carry class="sid" — a false red that says nothing about prompts.
  # The payload is the thing that must not carry them, so read it.
  python3 - "$static" <<'PYEOF' > "$WORK/st.txt" 2>&1
import json, re, sys
s = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r'id="wsdata" type="application/json">(.*?)</script>', s, re.S)
if not m:
    print("XX no payload in the page"); sys.exit(1)
d = json.loads(m.group(1).replace("<\\/", "</"))
checks = {
  "the prompts array is empty":      not d.get("prompts"),
  "and it says how many it held":    int(d.get("promptsWithheld") or 0) > 0,
  "no prompt record survives":       not any("sid" in x for x in (d.get("prompts") or [])),
}
for k, v in checks.items(): print(("ok " if v else "XX ") + k)
sys.exit(0 if all(checks.values()) else 1)
PYEOF
  if [ $? = 0 ]; then
    ok "10 · no prompt text in a static workspace ($live indexed, 0 written, and it says so)"
  else
    no "10 · a static page carries the prompt corpus" "$(grep '^XX' "$WORK/st.txt" | tr '\n' ' ')"
  fi
fi

# ── 10b · the scrubber runs before anything is written ──────────────────────
# N3. Nothing leaves the machine, but a dossier can — so credentials are
# scrubbed at index time. Neutering scrub() left the whole suite green.
sec=$(python3 -c 'import sys, os; sys.path.insert(0, os.environ["RUBRICATOR_HOME"])
import workspace as W
p = W.load_sessions()[0]
print(sum(1 for x in p if "sk_live_00smoketest00" in x["text"]))' 2>/dev/null || echo -1)
case "$sec" in
  0) ok "10b · a credential in a prompt is scrubbed at index time" ;;
  -1) skip "10b · scrubber" "load_sessions did not run" ;;
  *) no "10b · a credential survived the scrubber" "$sec prompt(s) still carry it" ;;
esac

# ── 11 · a plan review leaves a record ──────────────────────────────────────
# N6. The hook produced a decision and nothing on disk, and each fire is a fresh
# ephemeral origin — so zero reviews and two hundred looked identical.
export RUBRICATOR_STATE="$WORK/state"
mkdir -p "$WORK/plans"
printf '# recorded plan\n\nbody\n' > "$WORK/plans/rec.md"
rp=$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"ExitPlanMode","session_id":"s1","cwd":sys.argv[2],"tool_input":{"plan":"# recorded plan\n","planFilePath":sys.argv[1]}}))' \
      "$WORK/plans/rec.md" "$WORK")
for _ in 1 2 3; do
  printf '%s' "$rp" | RUBRICATOR_NO_WINDOW=1 RUBRICATOR_TIMEOUT=1 "$MD" --hook plan >/dev/null 2>&1
done
n=$(wc -l < "$RUBRICATOR_STATE/reviews.jsonl" 2>/dev/null | tr -d ' ')
if [ "${n:-0}" = 3 ] && [ "$(find "$RUBRICATOR_STATE" -type f ! -perm 600 | wc -l | tr -d ' ')" = 0 ]; then
  ok "11 · three hook fires leave three records, 0600"
else
  no "11 · the hook left no usable record" "lines=${n:-0}"
fi
unset RUBRICATOR_CACHE RUBRICATOR_STATE

# ── 12 · the index payload tells the truth ─────────────────────────────────
# L3, L4, L5 and M6 at once, through the RUBRICATOR_JSON seam: an unstaged
# document is indexed and flagged, ignored files stay ignored, notes travel with
# the page under the key the page will look them up by, and repoChurn — 26% of
# the git pass, read by nothing — is gone.
scratch="$WORK/idx"; mkdir -p "$scratch/node_modules"
(cd "$scratch" && git init -q . \
  && printf '# tracked\n' > tracked.md && git add tracked.md \
  && git -c user.email=t@t -c user.name=t commit -qm init) >/dev/null 2>&1
printf '# the agent just wrote this\n' > "$scratch/fresh.md"
printf 'node_modules/\n' > "$scratch/.gitignore"
printf '# should stay ignored\n' > "$scratch/node_modules/ignored.md"
mkdir -p "$scratch/.rubricator"
python3 -c 'import json,sys,os
p=sys.argv[1]
json.dump({os.path.realpath(os.path.join(p,"tracked.md")):{"saved":1,"items":[{"id":1,"verb":"note","quote":"x"}]}},
          open(os.path.join(p,".rubricator","notes.json"),"w"))' "$scratch"
RUBRICATOR_JSON=1 python3 "$REPO/share/workspace.py" "$scratch" > "$WORK/idx.json" 2>/dev/null
python3 - "$WORK/idx.json" "$scratch" <<'PYEOF' > "$WORK/idx.txt" 2>&1
import json, os, sys
d = json.load(open(sys.argv[1])); scratch = sys.argv[2]
rels = {x["rel"]: x for x in d["docs"]}
checks = {
  "unstaged document indexed":      "fresh.md" in rels,
  "and flagged untracked":          bool(rels.get("fresh.md", {}).get("untracked")),
  "tracked one not flagged":        not rels.get("tracked.md", {}).get("untracked"),
  "gitignored file stays out":      not any("node_modules" in r for r in rels),
  "notes travel with the payload":  bool(d.get("notes")),
  # M6: relative to the enclosing repository, and the page looks it up by
  # `nkey`. An absolute key cannot survive a second checkout.
  "notes key is the relative path": list(d.get("notes") or {}) == ["tracked.md"],
  "and it is the key the page uses": rels.get("tracked.md", {}).get("nkey") == "tracked.md",
  "the legacy file was migrated":   os.path.isfile(os.path.join(scratch, ".rubricator", "notes", "tracked.md.json")),
  "and kept":                       os.path.isfile(os.path.join(scratch, ".rubricator", "notes.json.pre-v1")),
  "repoChurn is gone":              not any("repoChurn" in v for v in (d.get("stale") or {}).values()),
}
for k, v in checks.items(): print(("ok " if v else "XX ") + k)
sys.exit(0 if all(checks.values()) else 1)
PYEOF
if [ $? = 0 ]; then
  ok "12 · the index sees untracked files, carries notes, and drops repoChurn"
else
  no "12 · the payload is wrong" "$(grep '^XX' "$WORK/idx.txt" | tr '\n' ' ')"
fi

# ── 13 · search requires every term, and ranks the phrase first ─────────────
# L1. The shipped matcher was one indexOf of the whole query, so `flow auth`
# and `auth flow` were different questions and neither found much.
if command -v node >/dev/null; then
  python3 -c 'import re,sys
src = open(sys.argv[1]).read()
i = src.index("function terms(q)"); j = src.index("function snippet(text, q, len)")
open(sys.argv[2], "w").write(src[i:j])' "$REPO/share/workspace.js" "$WORK/parser.js"
  cat >> "$WORK/parser.js" <<'JSEOF'
var doc = "the auth flow is described here; auth appears again, and flow too";
var other = "auth is mentioned but the other word appears nowhere near it";
var fail = [];
if (hits(doc, "auth flow") !== hits(doc, "flow auth")) fail.push("term order changes the matched set");
if (!(count(doc, "auth flow") > count(doc, "flow auth"))) fail.push("the phrase gets no bonus over its reverse");
if (!count(doc, "authentication") === false && count(doc, "authentication") !== 0) fail.push("absent term still matches");
if (count(other, "auth flow") !== 0) fail.push("AND not enforced");
if (!(count(doc, "auth flow") > count(other, "auth"))) fail.push("phrase not ranked above a lone term");
if (occurrences(doc, "auth") !== 2) fail.push("occurrences() miscounts: " + occurrences(doc, "auth"));
console.log(fail.length ? "XX " + fail.join("; ") : "ok");
JSEOF
  res=$(node "$WORK/parser.js" 2>&1)
  case "$res" in ok*) ok "13 · search requires every term and ranks the phrase first" ;;
                 *)   no "13 · the query parser is wrong" "$res" ;; esac
else
  skip "13 · query parser" "no node"
fi

# ── 14 · every shipped file parses ──────────────────────────────────────────
# The cheapest test here and the one that closes the widest gap. Mutation-tested
# 2026-08-26: appending `function ((broken{` to workspace.js, shell.js or
# review.js left all fourteen other tests green, with --browser as well —
# nothing in the suite opens the workspace page, and it is the largest file in
# the repo. 60 ms.
if command -v node >/dev/null; then
  bad=""
  for f in "$REPO"/share/*.js; do
    node --check "$f" >"$WORK/chk.log" 2>&1 || bad="$bad $(basename "$f"): $(head -3 "$WORK/chk.log" | tail -1)"
  done
  for f in "$REPO"/share/*.py; do
    python3 -m py_compile "$f" 2>"$WORK/chk.log" || bad="$bad $(basename "$f"): $(tail -1 "$WORK/chk.log")"
  done
  bash -n "$REPO/bin/md" 2>"$WORK/chk.log" || bad="$bad bin/md: $(tail -1 "$WORK/chk.log")"
  bash -n "$REPO/install.sh" 2>"$WORK/chk.log" || bad="$bad install.sh: $(tail -1 "$WORK/chk.log")"
  [ -z "$bad" ] && ok "14 · every file in share/ and bin/ parses" \
                || no "14 · a shipped file does not parse" "$bad"
else
  skip "14 · syntax gate" "no node"
fi

# ── 15 · a mark survives the rewrite ────────────────────────────────────────
# Phase M's whole point, and it had no coverage: the re-anchoring ladder runs in
# the browser and nothing here opened the workspace. The functions are lifted
# out of review.js the way test 13 lifts the query parser, so this asserts on
# the shipped source rather than on a copy of it.
if command -v node >/dev/null; then
  python3 - "$REPO/share/review.js" "$WORK/anchor.js" <<'PYEOF'
import sys
src = open(sys.argv[1], encoding="utf-8").read()
def sl(a, b):
    i = src.index(a); return src[i:src.index(b, i)]
open(sys.argv[2], "w", encoding="utf-8").write("\n".join([
    sl("function anchorOf(it){", "\n/* ── storage"),
    sl("function srcSlice(a, b)", "\n/* ── 1. map rendered blocks"),
    sl("function headingLevel(line)", "\nfunction blockOf(node)"),
    sl("var MIN_FUZZY = 12;", "\n/* ── highlights"),
]))
PYEOF
  { printf 'var raw="",rawLines=[],store={items:[]},said=null,window={};\n'
    printf 'function save(){}function toast(m){said=m}function esc(s){return s}\n'
    cat "$WORK/anchor.js"
    cat <<'JSEOF'
function load(t, items){ raw=t; rawLines=t.split('\n'); store={items:items}; said=null; reanchor(); return store.items; }
var f = [];
function eq(w, got, want){ if (got !== want) f.push(w + ': ' + JSON.stringify(got) + ' != ' + JSON.stringify(want)); }

/* M1 · three rules in one document, each mark keeps its own */
var r = load('---\ntitle: x\n---\n\nalpha\n\n---\n\nbeta\n\n---\n\ngamma\n',
  [{id:1,verb:'note',anchor:'---',lineStart:1},
   {id:2,verb:'note',anchor:'---',lineStart:7},
   {id:3,verb:'note',anchor:'---',lineStart:11}]);
eq('M1 first rule', r[0].lineStart, 1);
eq('M1 second rule', r[1].lineStart, 7);
eq('M1 third rule', r[2].lineStart, 11);

/* M1 · a repeated heading anchors to the section it was made in */
var h = load('# A\n\none\n\n## Notes\n\nfirst\n\n# B\n\ntwo\n\n## Notes\n\nsecond\n',
  [{id:1,verb:'change',anchor:'## Notes',lineStart:13,section:1}]);
eq('M1 repeated heading', h[0].lineStart, 13);

/* M2 · first sentence rewritten, longest line survives */
var was = 'Intro sentence here.\nThe longest surviving line in this paragraph is right here.';
var m = load('# t\n\nCompletely different opening.\nThe longest surviving line in this paragraph is right here.\n',
  [{id:1,verb:'change',anchor:was,quote:was,lineStart:1}]);
eq('M2 moved', m[0].anchorState, 'moved');
eq('M2 kept both texts', m[0].quote, was);
eq('M2 landed on the survivor', m[0].lineStart, 4);
eq('M5 said so', said, '1 of your marks moved');

/* M2 · and does not re-anchor a vanished block onto its leftover rule */
var g = load('---\n\nnothing else at all\n', [{id:1,verb:'cut',anchor:'---\nvanished body\n---',lineStart:1}]);
eq('M2 short-line guard', g[0].anchorState, 'orphaned');

/* M3 · a section mark still shows the text it was made against */
var sec = '## S\n\nold body\n';
var s2 = load('# top\n\n## S\n\nrewritten body, quite different\n',
  [{id:1,verb:'approve',anchor:'## S',quote:sec,section:1,lineStart:1}]);
eq('M3 quote never overwritten', s2[0].quote, sec);
eq('M3 current text differs', currentText(s2[0]) !== s2[0].quote, true);

/* M4 · three states, and a legacy store loads without migration */
var L = load('kept\n', [{id:1,verb:'note',anchor:'kept',state:'open',lineStart:1},
                        {id:2,verb:'approve',anchor:'deleted entirely from the file',state:'open',lineStart:2}]);
eq('M4 attached', L[0].anchorState, 'attached');
eq('M4 orphaned', L[1].anchorState, 'orphaned');
eq('M4 old bit dropped', 'state' in L[0], false);
eq('M4 legacy stale reads orphaned', anchorOf({state:'stale'}), 'orphaned');
eq('M4 legacy open reads attached', anchorOf({state:'open'}), 'attached');
eq('M4 an orphan is not live', isLive({state:'stale'}), false);

/* M5 · both counts, in one sentence */
load('a paragraph line that is definitely still here\n',
  [{id:1,verb:'note',anchor:'gone one entirely from this file',lineStart:1},
   {id:2,verb:'note',anchor:'gone two entirely from this file',lineStart:2},
   {id:3,verb:'note',anchor:'an opening that changed\na paragraph line that is definitely still here',lineStart:3}]);
eq('M5 both counts', said, '1 of your marks moved, 2 lost their text');
console.log(f.length ? 'XX ' + f.join(' | ') : 'ok');
JSEOF
  } > "$WORK/anchor_test.js"
  res=$(node "$WORK/anchor_test.js" 2>&1)
  case "$res" in ok*) ok "15 · marks re-anchor, move, or say their text is gone" ;;
                 *)   no "15 · the anchoring ladder is wrong" "$res" ;; esac
else
  skip "15 · anchoring ladder" "no node"
fi

# ── 16 · notes survive a second checkout ────────────────────────────────────
# M6. The old layout was one file per repo keyed by absolute path, so the store
# could not survive a clone at a different path — while the README promised it
# would sync if you committed it.
nrepo="$WORK/nrepo"; mkdir -p "$nrepo/docs"
(cd "$nrepo" && git init -q . && printf '# a\n' > README.md && printf '# p\n' > docs/plan.md \
  && git add -A && git -c user.email=t@t -c user.name='Smoke Person' commit -qm init) >/dev/null 2>&1
printf '# comment\n.rubricator/\n' > "$nrepo/.git/info/exclude"
mkdir -p "$nrepo/.rubricator"
python3 -c 'import json,os,sys
p = sys.argv[1]
json.dump({os.path.realpath(os.path.join(p,"README.md")): {"saved":1,"items":[{"id":1,"verb":"note"}]}},
          open(os.path.join(p,".rubricator","notes.json"),"w"))' "$nrepo"
python3 - "$nrepo" <<'PYEOF' > "$WORK/n.txt" 2>&1
import sys, os, json, shutil, subprocess
sys.path.insert(0, os.environ["RUBRICATOR_HOME"])
import workspace as W
repo = sys.argv[1]
n = W.read_notes(repo)                                    # migrates
W.write_notes(repo + "/docs", "docs/plan.md",
              {"saved": 2, "items": [{"id": 1, "verb": "note", "at": 1, "by": "Smoke Person"}]})
d = json.load(open(repo + "/.rubricator/notes/docs/plan.md.json"))
ex = open(repo + "/.git/info/exclude").read()
clone = repo + "-two"
subprocess.run(["git", "clone", "-q", repo, clone], check=True)
shutil.copytree(repo + "/.rubricator", clone + "/.rubricator")
checks = {
  "absolute key migrated to relative": list(n) == ["README.md"],
  "one file per document":             os.path.isfile(repo + "/.rubricator/notes/README.md.json"),
  "the old file is kept, not deleted": os.path.isfile(repo + "/.rubricator/notes.json.pre-v1"),
  "and kept out of git":               "notes.json.pre-v1" in open(repo + "/.rubricator/.gitignore").read(),
  "md . and md docs/ agree":           W.notes_key(repo, repo + "/docs/plan.md") ==
                                       W.notes_key(repo + "/docs", repo + "/docs/plan.md") == "docs/plan.md",
  "version stamped":                   d.get("v") == 1,
  "at and by survive the round trip":  d["items"][0].get("at") == 1 and d["items"][0].get("by") == "Smoke Person",
  "the exclude line is withdrawn":     ".rubricator/" not in ex,
  "and nothing else in it is touched": "# comment" in ex,
  "traversal refused":                 W.notes_path(repo, "../../etc/x") is None and W.notes_key(repo, "/etc/x") is None,
  "loads in a clone at another path":  sorted(W.read_notes(clone)) == ["README.md", "docs/plan.md"],
}
for k, v in checks.items(): print(("ok " if v else "XX ") + k)
sys.exit(0 if all(checks.values()) else 1)
PYEOF
if [ $? = 0 ]; then
  ok "16 · marks are relative, per-document, and no longer hidden from git"
else
  no "16 · the notes layout is wrong" "$(grep '^XX' "$WORK/n.txt" | tr '\n' ' ')"
fi

# ── 17 · a second root is read-only, and its rows line up ───────────────────
# O2. Reproduced before the fix: build([A, B]) gave 110 documents, 99 of them
# with a staleness key of the form `B/B/…` matching nothing and reading as
# commits: 0 — the prefix was applied inside the find_docs loop and again after
# git_activity. And a mark taken on B was written into A's notes store.
mr="$WORK/mr"
for d in a b; do
  mkdir -p "$mr/$d/src"
  printf '# %s\n\nsee `src/main.py`\n' "$d" > "$mr/$d/doc.md"
  printf 'x=1\n' > "$mr/$d/src/main.py"
  (cd "$mr/$d" && git init -q . && git add -A \
    && git -c user.email=t@t -c user.name=t commit -qm one \
    && printf 'x=2\n' > src/main.py && git add -A \
    && git -c user.email=t@t -c user.name=t commit -qm two) >/dev/null 2>&1
done
RUBRICATOR_JSON=1 python3 "$RUBRICATOR_HOME/workspace.py" "$mr/a" "$mr/b" \
  > "$WORK/mr.json" 2>/dev/null
python3 - "$WORK/mr.json" <<'PYEOF' > "$WORK/mr.txt" 2>&1
import json, sys
d = json.load(open(sys.argv[1]))
rels = {x["rel"] for x in d["docs"]}
by = {x["rel"]: x for x in d["docs"]}
checks = {
  "the second root is prefixed once":   rels == {"doc.md", "b/doc.md"},
  "staleness keys match documents":     set(d["stale"]) and set(d["stale"]) <= rels,
  "the first root is writable":         by["doc.md"].get("readonly") == 0,
  "the second is not":                  by["b/doc.md"].get("readonly") == 1,
  "and the row says which repo":        by["b/doc.md"].get("repo") == "b",
}
for k, v in checks.items(): print(("ok " if v else "XX ") + k)
sys.exit(0 if all(checks.values()) else 1)
PYEOF
if [ $? = 0 ]; then
  ok "17 · a multi-root workspace lines up and says which rows are read-only"
else
  no "17 · multi-root is still confused" "$(grep '^XX' "$WORK/mr.txt" | tr '\n' ' ')"
fi

# ── 18 · a static page reads the marks it carries ───────────────────────────
# Found by looking at a screenshot: the tab badge said 3 and the tray beside it
# said "Nothing yet". workspace.py ships the sidecar with a static page on
# purpose, and the page then read localStorage instead — L3's defect, one tier
# over. Asserts on the wiring, because the DOM assertion needs a browser and
# this must fail on the per-push path.
if command -v node >/dev/null; then
  python3 - "$REPO/share/workspace.js" "$WORK/bridge.js" <<'PYEOF'
import sys
src = open(sys.argv[1], encoding="utf-8").read()
i = src.index("function nkeyOf(d)")
j = src.index("if (can('notes') && window.MDReview){")
open(sys.argv[2], "w", encoding="utf-8").write(src[i:j])
PYEOF
  { printf 'var CAPS={};\n'
    printf 'function can(k){ return !!CAPS[k]; }\n'
    printf 'var D={ notes:{ "docs/p.md": {saved:100, items:[{id:1,verb:"note"}]} }, by:"" };\n'
    printf 'var DISK = D.notes;\n'
    printf 'var localStorage={ getItem:function(){ return null; }, setItem:function(){} };\n'
    printf 'var window={ MDReview:{ identity:null, storage:{ get:function(){ return null; }, set:function(){} } } };\n'
    cat "$WORK/bridge.js"
    cat <<'JSEOF'
var f = [];
var got = window.MDReview.storage.get('md-review:x', '/abs/docs/p.md', 'docs/p.md');
if (!got || !got.items || got.items.length !== 1)
  f.push('a static page did not read the notes it was built with');
var none = window.MDReview.storage.get('md-review:y', '/abs/docs/other.md', 'docs/other.md');
if (none !== null) f.push('an unmarked document invented a store');
console.log(f.length ? 'XX ' + f.join('; ') : 'ok');
JSEOF
  } > "$WORK/bridge_test.js"
  res=$(node "$WORK/bridge_test.js" 2>&1)
  case "$res" in ok*) ok "18 · a static page reads the marks it carries" ;;
                 *)   no "18 · a static page ignores its own sidecar" "$res" ;; esac
else
  skip "18 · static notes bridge" "no node"
fi

# ── 19 · md --json is facts, and only facts ─────────────────────────────────
# Q5. The machine-readable door: a flag, not a protocol. Two things must never
# come through it — the staleness verdict, which L4 stopped the surface claiming
# and which a field called `stale` would put straight back, and prompt text,
# which is N2's rule applied to a second write path.
"$MD" --json "$REPO" > "$WORK/m.json" 2>"$WORK/m.err"; jrc=$?
"$MD" --json --sessions "$REPO" > "$WORK/ms.json" 2>>"$WORK/m.err"; src=$?
python3 - "$WORK/m.json" "$WORK/ms.json" "$jrc" "$src" <<'PYEOF' > "$WORK/m.txt" 2>&1
import json, sys
try:
    d = json.load(open(sys.argv[1])); ds = json.load(open(sys.argv[2]))
except Exception as e:
    print("XX not parseable: %s" % e); sys.exit(1)
blob = json.dumps(ds)
checks = {
  "exits 0":                          sys.argv[3] == "0" and sys.argv[4] == "0",
  "parseable JSON":                   True,
  "documents, with headings":         bool(d["documents"]) and "headings" in d["documents"][0],
  "carries a version":                d.get("v") == 1,
  "no staleness verdict field":       "stale" not in d,
  "activity is counts, not a verdict": all(
      set(v) <= {"commits", "lastCommit", "namedFiles", "commitsInNamedFiles"}
      for v in d["activity"].values()),
  "no document bodies":               all("text" not in x for x in d["documents"]),
  "no prompt array":                  "prompts" not in ds,
  "and it says how many it withheld": isinstance(ds.get("promptsWithheld"), int),
  "sessions are there":               bool(ds.get("sessions")),
}
for k, v in checks.items(): print(("ok " if v else "XX ") + k)
sys.exit(0 if all(checks.values()) else 1)
PYEOF
if [ $? = 0 ]; then
  ok "19 · md --json prints facts, no verdict, no prompt text"
else
  no "19 · the machine-readable door is wrong" "$(grep '^XX' "$WORK/m.txt" | tr '\n' ' ')$(head -2 "$WORK/m.err")"
fi

# ── 20 · the navigator holds its shape at both ends of the divider ──────────
# The divider drags the panel between 168px and 480px, so every control in it
# has two widths to survive. Three ways it fails, all of them silent: a mode
# button runs past the panel edge and the tab strip paints over it, so a whole
# navigator mode becomes unreachable; a filename gives up its width to a fixed
# badge until it reads `w.`; an <svg> in a button that `all:unset` stripped lays
# out at 0x0, leaving a control you can click and cannot see. All three are
# geometry, so this measures them in a browser rather than reading the CSS.
if [ "$WITH_BROWSER" = 1 ]; then
  CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
  [ -x "$CHROME" ] || CHROME="$HOME/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
fi
if [ "$WITH_BROWSER" = 1 ] && [ -x "$CHROME" ]; then
  (cd "$REPO" && "$MD" -w -o "$WORK/nav.html" . >/dev/null 2>&1) || true
  for px in 252 168; do
    python3 - "$WORK/nav.html" "$WORK/nav-$px.html" "$px" <<'PYEOF'
import sys
src = open(sys.argv[1], encoding="utf-8").read()
# the panel opens at its stored width; there is no drag to simulate headless
assert src.count("navW = 252;") == 1, "shell.js no longer defaults navW to 252"
probe = """<script>window.addEventListener('load',function(){setTimeout(function(){
function R(e){return e.getBoundingClientRect();}
function seen(e){return e.offsetWidth>0||e.offsetHeight>0;}
var nav=R(document.getElementById('nav')), out={};
var modes=[].map.call(document.querySelectorAll('.nvh button'),R);
out.modes=modes.length;
out.modesShown=modes.filter(function(r){return r.width>6&&r.right<=nav.right+0.5;}).length;
var h=document.querySelector('.nvh');
out.modeOverflow=h.scrollWidth-h.clientWidth;
out.glyphs=[].filter.call(document.querySelectorAll('.nvctl .opt'),seen)
  .map(function(b){var s=b.querySelector('svg');return s?Math.round(R(s).width):0;});
var rows=[].filter.call(document.querySelectorAll('.nvb .tfile'),function(t){
  return t.querySelector('.nm');});
out.names=rows.length; out.narrowestName=99999; out.nameLosesTo='';
rows.forEach(function(t){
  var w=R(t.querySelector('.nm')).width;
  if(w<out.narrowestName) out.narrowestName=Math.round(w);
  [].forEach.call(t.children,function(c){
    if(!c.classList.contains('nm')&&R(c).width>w&&!out.nameLosesTo)
      out.nameLosesTo=(c.className||'?')+' on '+t.textContent.slice(0,20);});});
if(!rows.length) out.narrowestName=0;
var d=document.createElement('div'); d.id='probe';
d.textContent=JSON.stringify(out); document.body.appendChild(d);
},700);});</script>"""
src = src.replace("navW = 252;", "navW = %s;" % sys.argv[3])
i = src.rindex("</body>")
open(sys.argv[2], "w", encoding="utf-8").write(src[:i] + probe + src[i:])
PYEOF
    "$CHROME" --headless --disable-gpu --virtual-time-budget=12000 \
      --use-mock-keychain --password-store=basic --disable-background-networking \
      --window-size=1280,900 --dump-dom "file://$WORK/nav-$px.html" \
      >"$WORK/nav-$px.dom" 2>/dev/null
  done
  python3 - "$WORK/nav-252.dom" "$WORK/nav-168.dom" >"$WORK/nav.txt" 2>&1 <<'PYEOF'
import json, re, sys
def probe(path):
    dom = open(path, encoding="utf-8", errors="replace").read()
    m = re.search(r'<div id="probe">(.*?)</div>', dom, re.S)
    if not m: return None
    return json.loads(m.group(1))
wide, narrow = probe(sys.argv[1]), probe(sys.argv[2])
if not wide or not narrow:
    print("XX the page never reached the probe"); sys.exit(1)
checks = {
  "four modes, both widths":     wide["modes"] == 4 and wide["modesShown"] == 4
                                 and narrow["modes"] == 4 and narrow["modesShown"] == 4,
  "the mode row never overflows": wide["modeOverflow"] <= 0 and narrow["modeOverflow"] <= 0,
  "every icon button drawn":     len(wide["glyphs"]) == 3 and all(w >= 8 for w in wide["glyphs"])
                                 and all(w >= 8 for w in narrow["glyphs"]),
  # the invariant is not a pixel count, it is what the row spends its width on
  "the name outweighs its badges": narrow["names"] > 0 and not narrow["nameLosesTo"]
                                   and not wide["nameLosesTo"]
                                   and narrow["narrowestName"] >= 40,
}
for k, v in checks.items():
    print(("ok " if v else "XX ") + k + "  252:" + json.dumps(wide) + " 168:" + json.dumps(narrow))
sys.exit(0 if all(checks.values()) else 1)
PYEOF
  if [ $? = 0 ]; then
    ok "20 · at 168px and at 252px every mode, control and filename holds its ground"
  else
    no "20 · the navigator loses something at one of its widths" \
       "$(grep '^XX' "$WORK/nav.txt" | head -2 | cut -c1-220 | tr '\n' ' ')"
  fi
else
  skip "20 · navigator geometry" "needs --browser and Chrome"
fi

# ── 21 · the history preference, and the doors it does not open ─────────────
# `{"sessions": true}` makes a bare `md` index your Claude Code history. That is
# every conversation on the machine, not only this project's, so the setting is
# deliberately weaker than the flag: it never reaches a page that becomes a file
# (-o, --static), and it never changes the shape of --json, which is a contract a
# script depends on. The index is also deferred — the window opens on its
# documents and the page asks for history once — so the page has to say that
# history is coming and the route has to be the thing that waits.
python3 - "$MD" "$WORK" >"$WORK/pref.txt" 2>&1 <<'PYEOF'
import json, os, re, socket, subprocess, sys, time, urllib.request
md, work = sys.argv[1], sys.argv[2]
cfg = os.path.join(work, "pref.json")
repo = os.path.join(work, "prefrepo"); os.makedirs(repo, exist_ok=True)
open(os.path.join(repo, "README.md"), "w").write("# pref\n\ntext\n")
env0 = dict(os.environ, RUBRICATOR_CONFIG=cfg)

def run(args, **kw):
    return subprocess.run([md] + args, capture_output=True, text=True, cwd=repo, **kw)

def with_sessions(path):
    m = re.search(r'"withSessions":\s*([a-z0-9]+)', open(path, encoding="utf-8").read())
    return m.group(1) if m else "?"

checks = {}
# the setting on, and nothing else
open(cfg, "w").write(json.dumps({"sessions": True}))

out1 = os.path.join(work, "pref-o.html")
run(["-w", "-o", out1], env=env0)
checks["-o ignores the setting"] = os.path.isfile(out1) and with_sessions(out1) == "false"

r = run(["-w", "--sessions", "-o", os.path.join(work, "pref-o2.html")], env=env0)
checks["-o still refuses the flag"] = r.returncode != 0 and "refusing --out" in (r.stdout + r.stderr)

r = run(["--json", "."], env=env0)
checks["--json stays explicit"] = r.returncode == 0 and "sessions" not in json.loads(r.stdout)

r = run(["--json", "--sessions", "."], env=env0)
checks["--json --sessions still works"] = r.returncode == 0 and "sessions" in json.loads(r.stdout)

# the served tier: history is promised at once and delivered later
def free_port():
    s = socket.socket(); s.bind(("127.0.0.1", 0)); p = s.getsockname()[1]; s.close(); return p

def serve(extra):
    port = free_port()
    env = dict(env0, RUBRICATOR_NO_WINDOW="1", RUBRICATOR_DEBUG="1", RUBRICATOR_NO_WATCH="1")
    p = subprocess.Popen([md, "serve", "--port", str(port)] + extra + [repo],
                         env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    url = None
    for _ in range(200):
        time.sleep(0.1)
        try:
            got = urllib.request.urlopen("http://127.0.0.1:%d/" % port, timeout=1).read()
        except Exception:
            continue
        break
    # the token is in the URL the server printed; read it off the process output
    os.set_blocking(p.stdout.fileno(), False)
    seen = ""
    for _ in range(50):
        seen += p.stdout.read() or ""
        m = re.search(r"(http://127\.0\.0\.1:%d/[A-Za-z0-9_-]+/)" % port, seen)
        if m:
            url = m.group(1); break
        time.sleep(0.1)
    return p, url

def get(url, data=None):
    req = urllib.request.Request(url, data=data,
                                 headers={"Content-Type": "application/json"})
    return json.loads(urllib.request.urlopen(req, timeout=120).read())

proc, url = serve([])
try:
    if not url:
        checks["the server came up"] = False
    else:
        checks["the server came up"] = True
        page = urllib.request.urlopen(url, timeout=20).read().decode("utf-8", "replace")
        m = re.search(r'"withSessions":\s*([a-z0-9]+)', page)
        checks["the setting reaches the window"] = bool(m) and m.group(1) in ("true", "1")
        # the page carries the flag the client waits on. Whether it is still
        # true by the time a test can read it is a race the fixture cannot win
        # — a corpus of two transcripts indexes faster than a socket accepts —
        # so this pins the channel, and the 1.9s figure is a measurement.
        checks["and says whether it is still coming"] = '"sessionsPending"' in page
        j = get(url + "sessions")
        checks["the route delivers it"] = j.get("withSessions") is True and j.get("pending") is False
finally:
    proc.kill()

# the main door: a bare `md`, which is where the setting is for
r = subprocess.run([md], capture_output=True, text=True, cwd=repo,
                   env=dict(env0, RUBRICATOR_NO_WINDOW="1", RUBRICATOR_NO_WATCH="1"))
bare = (r.stdout or "").strip().splitlines()
bare = bare[0] if bare else ""
if bare.startswith("http://127.0.0.1:"):
    page = urllib.request.urlopen(bare, timeout=20).read().decode("utf-8", "replace")
    m = re.search(r'"withSessions":\s*([a-z0-9]+)', page)
    checks["a bare md honours it"] = bool(m) and m.group(1) in ("true", "1")
    try:
        urllib.request.urlopen(bare + "bye", data=b"{}", timeout=5)
    except Exception:
        pass
else:
    checks["a bare md honours it"] = False

# and --no-sessions turns the setting off for one run
proc, url = serve(["--no-sessions"])
try:
    if url:
        page = urllib.request.urlopen(url, timeout=20).read().decode("utf-8", "replace")
        m = re.search(r'"withSessions":\s*([a-z0-9]+)', page)
        checks["--no-sessions overrides it"] = bool(m) and m.group(1) in ("false", "0")
        j = get(url + "sessions")
        checks["and the route agrees"] = j.get("withSessions") is False
        # the page may still ask for it, and asking is what turns it on
        j = get(url + "sessions", data=b"{}")
        checks["asking for it indexes it"] = j.get("withSessions") is True
    else:
        checks["--no-sessions overrides it"] = False
finally:
    proc.kill()

for k, v in checks.items(): print(("ok " if v else "XX ") + k)
sys.exit(0 if all(checks.values()) else 1)
PYEOF
if [ $? = 0 ]; then
  ok "21 · the history setting reaches the window and no further"
else
  no "21 · the history setting is not honoured where it should be" \
     "$(grep '^XX' "$WORK/pref.txt" | tr '\n' ' ')$(tail -2 "$WORK/pref.txt")"
fi

# ── 22 · the file ranking runs, and the filename still counts ───────────────
# `fileRank` declared a local `hits` counter over the top of the `hits()`
# matcher two functions up, so the one line that used both threw
# `hits is not a function`. It is reached only when a matching session touched
# a file — a narrow query never gets there, a broad one always does — and a
# builder that throws left the last good DOM in place, so the Search surface
# looked like it was ignoring the keystroke. Lifted from the shipped source the
# way tests 13 and 15 are, so this asserts on what ships.
if command -v node >/dev/null; then
  python3 -c 'import sys
src = open(sys.argv[1]).read()
def sl(a, b):
    i = src.index(a); return src[i:src.index(b, i)]
open(sys.argv[2], "w").write("\n".join([
    sl("function terms(q)", "function snippet(text, q, len)"),
    sl("function fileRank(sids, weights, q)", "function baseName(rel)"),
]))' "$REPO/share/workspace.js" "$WORK/rank.js"
  { printf 'var D = { root: "/root", touches: {\n'
    printf '  "/root/src/auth.ts": ["s1"],\n'
    printf '  "/root/src/other.ts": ["s1"],\n'
    printf '  "/elsewhere/auth.ts": ["s1"]\n} };\n'
    cat "$WORK/rank.js"
    cat <<'JSEOF'
var fail = [];
var out;
try { out = fileRank(["s1"], { s1: 1 }, "auth"); }
catch (e) { fail.push("fileRank threw: " + e.message); out = []; }
if (!fail.length){
  if (out.length !== 3) fail.push("expected all three touched files, got " + out.length);
  var by = {}; out.forEach(function(r){ by[r.file] = r; });
  if (!by["/root/src/auth.ts"] || !by["/root/src/other.ts"]) fail.push("a touched file went missing");
  else if (!(by["/root/src/auth.ts"].s > by["/root/src/other.ts"].s))
    fail.push("the filename no longer counts: auth.ts scores " + by["/root/src/auth.ts"].s +
              " against other.ts " + by["/root/src/other.ts"].s);
  if (by["/root/src/auth.ts"] && by["/root/src/auth.ts"].hits !== 1)
    fail.push("the 'in these' count is wrong: " + by["/root/src/auth.ts"].hits);
  if (by["/root/src/auth.ts"] && by["/root/src/auth.ts"].here !== true) fail.push("a file in the root read as elsewhere");
  if (by["/elsewhere/auth.ts"] && by["/elsewhere/auth.ts"].here !== false) fail.push("a file elsewhere read as here");
  /* a query nothing matches must still come back, and quietly */
  try { if (fileRank(["s1"], { s1: 1 }, "zzzz").length !== 3) fail.push("a non-matching query lost rows"); }
  catch (e) { fail.push("a non-matching query threw: " + e.message); }
}
console.log(fail.length ? "XX " + fail.join("; ") : "ok");
JSEOF
  } > "$WORK/rank-run.js"
  res=$(node "$WORK/rank-run.js" 2>&1)
  case "$res" in ok*) ok "22 · file ranking survives a broad query and still weighs the name" ;;
                 *)   no "22 · the file ranking is broken" "$res" ;; esac
else
  skip "22 · file ranking" "no node"
fi

# ── 23 · an abandoned composer takes its mark with it ───────────────────────
# A verb writes its mark before the composer opens, so the composer is the only
# thing standing between a keystroke and a stored item. Close it having written
# nothing — Escape, or a click anywhere else — and the mark used to stay: a
# highlight over an empty note, in the tray and in the export. The rule has
# three edges and all three are in one browser run, because this is event
# ordering and DOM state, not a function that can be lifted out.
if [ "$WITH_BROWSER" = 1 ]; then
  CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
  [ -x "$CHROME" ] || CHROME="$HOME/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
fi
if [ "$WITH_BROWSER" = 1 ] && [ -x "$CHROME" ]; then
  printf '# composer fixture\n\nAlpha paragraph.\n\nBeta paragraph.\n' > "$WORK/composer.md"
  "$MD" -o "$WORK/composer.html" "$WORK/composer.md" >/dev/null 2>&1
  python3 - "$WORK/composer.html" "$WORK/composer-probe.html" <<'PYEOF'
import sys
src = open(sys.argv[1], encoding="utf-8").read()
probe = """<script>window.addEventListener('load',function(){setTimeout(function(){
function K(t,k){ t.dispatchEvent(new KeyboardEvent('keydown',{key:k,bubbles:true,cancelable:true})); }
function type(t,v){ t.value=v; t.dispatchEvent(new Event('input',{bubbles:true})); }
var out={}, doc=document.querySelector('article.md')||document.querySelector('.md');
var blocks=[].filter.call(doc.children,function(e){return e.dataset.lineStart;});
var b=blocks[1]||blocks[0];
var comp=document.getElementById('composer'), t=document.getElementById('c-text');
function hover(){ b.dispatchEvent(new MouseEvent('mouseover',{bubbles:true})); }
function items(){ return __mdReview.store.items.length; }
function hl(){ return doc.querySelectorAll('.has-anno').length; }

hover(); K(document,'c');
out.opens=comp.classList.contains('show'); out.openHl=hl();
K(t,'Escape');
out.escItems=items(); out.escHl=hl(); out.escClosed=!comp.classList.contains('show');

hover(); K(document,'n');
document.body.dispatchEvent(new MouseEvent('mousedown',{bubbles:true}));
out.awayItems=items(); out.awayHl=hl();

hover(); K(document,'c'); type(t,'written'); K(t,'Escape');
out.keptItems=items(); out.keptNote=(__mdReview.store.items[0]||{}).note;

hover(); K(document,'a');
out.silentItems=items();

var card=document.querySelector('#tray-list > div');
if (card) card.dispatchEvent(new MouseEvent('click',{bubbles:true}));
setTimeout(function(){
  out.reopened=comp.classList.contains('show');
  type(t,''); K(t,'Escape');
  out.emptiedItems=items();
  var d=document.createElement('div'); d.id='probe';
  d.textContent=JSON.stringify(out); document.body.appendChild(d);
},450);
},500);});</script>"""
i = src.rindex("</body>")
open(sys.argv[2], "w", encoding="utf-8").write(src[:i] + probe + src[i:])
PYEOF
  "$CHROME" --headless --disable-gpu --virtual-time-budget=12000 \
    --use-mock-keychain --password-store=basic --disable-background-networking \
    --window-size=1280,900 --dump-dom "file://$WORK/composer-probe.html" \
    >"$WORK/composer.dom" 2>/dev/null
  python3 - "$WORK/composer.dom" >"$WORK/composer.txt" 2>&1 <<'PYEOF'
import json, re, sys
dom = open(sys.argv[1], encoding="utf-8", errors="replace").read()
m = re.search(r'<div id="probe">(.*?)</div>', dom, re.S)
if not m:
    print("XX the page never reached the probe"); sys.exit(1)
p = json.loads(m.group(1))
checks = {
  "a verb opens the composer on the block":  p["opens"] and p["openHl"] == 1,
  "escape discards the empty mark":          p["escClosed"] and p["escItems"] == 0 and p["escHl"] == 0,
  "so does clicking away":                   p["awayItems"] == 0 and p["awayHl"] == 0,
  "a written note is kept":                  p["keptItems"] == 1 and p["keptNote"] == "written",
  "a silent verb needs no note":             p["silentItems"] == 2,
  "emptying an existing note keeps it":      p["reopened"] and p["emptiedItems"] == 2,
}
for k, v in checks.items():
    print(("ok " if v else "XX ") + k + "  " + json.dumps(p))
sys.exit(0 if all(checks.values()) else 1)
PYEOF
  if [ $? = 0 ]; then
    ok "23 · a composer closed with nothing written leaves no mark behind"
  else
    no "23 · the composer keeps an empty mark" \
       "$(grep '^XX' "$WORK/composer.txt" | head -2 | cut -c1-220 | tr '\n' ' ')"
  fi
else
  skip "23 · composer lifecycle" "needs --browser and Chrome"
fi

# ── 24 · a session's files can be reached, and only those ───────────────────
# `reveal` and `edit` resolve their target through the document index, so they
# reach the markdown in a repository and nothing else — while a session touches
# hundreds of files that are not documents. `reveal-file`/`edit-file` take a
# session id and an ORDINAL into the file list the server already holds, so the
# page still never sends a path. This checks that the ordinal is the only key
# that works, and that everything else is refused.
#
# The session index is seeded through the code's own cache writer rather than
# from a transcript: workspace.py drops anything under /var/folders as scratch
# (SCRATCH), and every path a test can write to is scratch. Using the real
# writer means a change to that format fails this test loudly instead of
# quietly seeding nothing.
python3 - "$MD" "$WORK" "$REPO" >"$WORK/files.txt" 2>&1 <<'PYEOF'
import json, os, re, socket, subprocess, sys, time, urllib.error, urllib.request
md, work, repo_root = sys.argv[1], sys.argv[2], sys.argv[3]
repo = os.path.join(work, "filerepo"); os.makedirs(repo, exist_ok=True)
open(os.path.join(repo, "README.md"), "w").write("# files\n\nbody\n")
real = os.path.join(repo, "README.md")
gone = os.path.join(repo, "deleted.md")
sid = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"

sys.path.insert(0, os.path.join(repo_root, "share"))
import workspace as W
W._cache_write("sessions-deep.json", W.session_stamp(True), {
    "prompts": [{"sid": sid, "t": 1785000000, "text": "touch two files", "project": repo}],
    "sessions": {sid: {"p": repo, "t": "touch two files", "n": 1,
                       "a": 1785000000, "b": 1785000000, "live": 1,
                       "files": [real, gone]}},
    "touches": {real: [sid], gone: [sid]},
})

def free_port():
    s = socket.socket(); s.bind(("127.0.0.1", 0)); p = s.getsockname()[1]; s.close(); return p

def serve(extra, env_extra):
    port = free_port()
    env = dict(os.environ, RUBRICATOR_NO_WINDOW="1", RUBRICATOR_DEBUG="1",
               RUBRICATOR_NO_WATCH="1", **env_extra)
    p = subprocess.Popen([md, "serve", "--port", str(port), "--sessions"] + extra + [repo],
                         env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    os.set_blocking(p.stdout.fileno(), False)
    seen, url = "", None
    for _ in range(200):
        time.sleep(0.1)
        # Python 3.14 raises where earlier ones returned None on an empty pipe
        try: seen += p.stdout.read() or ""
        except BlockingIOError: pass
        m = re.search(r"(http://127\.0\.0\.1:%d/[A-Za-z0-9_-]+/)" % port, seen)
        if m: url = m.group(1); break
    return p, url

def post(url, body):
    r = urllib.request.Request(url + "act", data=json.dumps(body).encode(),
                               headers={"Content-Type": "application/json"})
    try: return json.load(urllib.request.urlopen(r, timeout=30)), 200
    except urllib.error.HTTPError as e: return json.load(e), e.code

checks = {}
p, url = serve(["--allow-launch"], {"RUBRICATOR_DRY_LAUNCH": "1"})
try:
    checks["the server came up"] = bool(url)
    if url:
        j = json.load(urllib.request.urlopen(url + "sessions", timeout=180))
        m = (j.get("sessions") or {}).get(sid) or {}
        checks["the seeded session reached the page"] = m.get("files") == [real, gone]
        i = 0 if m.get("files") and m["files"][0] == real else -1
        r1 = post(url, {"verb": "reveal-file", "id": sid, "n": i})[0]
        r2 = post(url, {"verb": "edit-file", "id": sid, "n": i})[0]
        checks["an ordinal reveals the file"] = r1.get("ok") is True
        checks["and opens it in an editor"] = r2.get("ok") is True
        # under the dry seam nothing reaches Finder or an editor: a run of this
        # suite that opened windows on the desk is caught here, by name
        checks["the dry seam holds for reveal and edit"] = r1.get("dry") == real and r2.get("dry") == real
        # the refusal has to be the RANGE refusal, not whatever the runtime
        # happened to raise: an unchecked files[99] throws IndexError and an
        # unchecked files[-1] quietly resolves to the last file, and both would
        # satisfy a test that only asked whether something went wrong
        NOTINLIST = "not in this session's list"
        for label, n in [("past the end", 99), ("negative", -1),
                         ("a path instead of an ordinal", "../../../etc/passwd"),
                         ("no ordinal at all", None)]:
            body = {"verb": "reveal-file", "id": sid}
            if n is not None: body["n"] = n
            got, code = post(url, body)
            checks["refused: " + label] = code == 400 and NOTINLIST in got.get("error", "")
        got, code = post(url, {"verb": "reveal-file", "id": "nope", "n": 0})
        checks["refused: an unknown session"] = code == 400 and NOTINLIST in got.get("error", "")
        got, code = post(url, {"verb": "reveal-file", "id": sid, "n": 1})
        checks["refused: a file that is gone"] = code == 400 and "no longer on disk" in got.get("error", "")
        # a path in the body is not a key: the ordinal decides, or nothing does
        got, _ = post(url, {"verb": "reveal-file", "id": sid, "n": i,
                            "path": os.path.join(work, "does-not-exist.md"),
                            "file": os.path.join(work, "does-not-exist.md")})
        checks["a path in the body is ignored"] = got.get("ok") is True
finally:
    p.kill()

# and with actions off, none of it is reachable at all
q, url2 = serve([], {})
try:
    if url2:
        got, code = post(url2, {"verb": "reveal-file", "id": sid, "n": 0})
        checks["without --allow-launch it is 403"] = code == 403 and "actions are off" in got.get("error", "")
    else:
        checks["without --allow-launch it is 403"] = False
finally:
    q.kill()

for k, v in checks.items(): print(("ok " if v else "XX ") + k)
sys.exit(0 if all(checks.values()) else 1)
PYEOF
if [ $? = 0 ]; then
  ok "24 · a session's files open by ordinal, and by nothing else"
else
  no "24 · the file verbs are wrong" "$(grep '^XX' "$WORK/files.txt" | tr '\n' ' ')$(tail -2 "$WORK/files.txt")"
fi

# ── 25 · the repeated path stem is elided, and only whole segments ──────────
# A session's folders are listed in path order so the row above can carry the
# head the next one repeats. Getting this wrong by a character means `docs/` and
# `docsets/` share a stem, and the row names a folder that does not exist.
if command -v node >/dev/null; then
  python3 -c 'import sys
src = open(sys.argv[1]).read()
i = src.index("function elideStem(dir, prev)")
open(sys.argv[2], "w").write(src[i:src.index("\nfunction sesFileGroup", i)])' \
    "$REPO/share/workspace.js" "$WORK/stem.js"
  { cat "$WORK/stem.js"
    cat <<'JSEOF'
var fail = [];
function is(dir, prev, want, why){
  var got = elideStem(dir, prev);
  if (got !== want) fail.push(why + ' — got "' + got + '", wanted "' + want + '"');
  /* whatever is elided, the row still spells the whole path */
  if (dir.indexOf(got) !== 0) fail.push(why + ' — the stem is not a prefix of the path');
  if (got && dir.slice(got.length) === '') fail.push(why + ' — nothing left to name the folder');
}
is('src/app/', '', '', 'nothing above it');
is('src/app/', 'src/lib/', 'src/', 'one shared segment');
is('a/b/c/d/', 'a/b/c/x/', 'a/b/c/', 'three shared segments');
is('docs/', 'docsets/', '', 'a shared prefix that is not a shared segment');
is('docsets/', 'docs/', '', 'and the same the other way round');
is('e2e/', 'docs/plans/', '', 'nothing in common');
is('supabase/functions/_shared/', 'supabase/migrations/', 'supabase/', 'siblings under one root');
is('src/app/b/', 'src/app/', 'src/app/', 'a folder below the one above it');
console.log(fail.length ? 'XX ' + fail.join('; ') : 'ok');
JSEOF
  } > "$WORK/stem-run.js"
  res=$(node "$WORK/stem-run.js" 2>&1)
  case "$res" in ok*) ok "25 · folder rows elide the stem above them, by segment" ;;
                 *)   no "25 · the stem eliding is wrong" "$res" ;; esac
else
  skip "25 · stem eliding" "no node"
fi

# ── 26 · every verb the page emits can be clicked ───────────────────────────
# The failure this closes: `data-lstatus` and `data-lclear` were read in the body
# of the click dispatcher while the selector that has to match first was left
# alone, so the navigator's status chips and both Clear buttons were inert from
# the day they were written — and nothing threw, so nothing here noticed. Verbs
# registered through RB.table derive their own selector and cannot drift; this
# is the net under the selectors still written by hand.
if command -v node >/dev/null; then
  { cat <<'JSEOF'
var fs = require('fs');
var src = fs.readFileSync(process.argv[2], 'utf8');
function dash(k){ return k.replace(/[A-Z]/g, function(c){ return '-' + c.toLowerCase(); }); }

/* an attribute that carries a value for some handler to read, rather than
   naming the thing to do — `data-doc="…" data-line="12"` is one verb, one
   payload. A new one belongs here only if nothing is meant to click it:
   `an` is the artifact `data-asrc` opens, `cap` and `ref` a picture's caption
   and place, `arts` the slot a session's artifacts fill. */
var PAYLOAD = ['an','arts','cap','copy-note','f','fg','id','line','n','q','ref','sid','t','val'];

var emitted = {}, handled = {}, m;
var reEmit = /data-([a-z][a-z-]*)="/g;
while ((m = reEmit.exec(src))) emitted[m[1]] = 1;
var reSel = /\[data-([a-z][a-z-]*)\]/g;
while ((m = reSel.exec(src))) handled[m[1]] = 1;

/* the keys of every RB.table({…}) spec, found by matching braces so a handler
   body that closes with `},` does not end the search early */
var i = 0;
while ((i = src.indexOf('RB.table({', i)) !== -1){
  var j = src.indexOf('{', i), depth = 0, start = j;
  for (; j < src.length; j++){
    if (src[j] === '{') depth++;
    else if (src[j] === '}' && !--depth) break;
  }
  var spec = src.slice(start, j + 1), km, reKey = /^\s+([a-zA-Z][a-zA-Z0-9]*)\s*:/gm;
  while ((km = reKey.exec(spec))) handled[dash(km[1])] = 1;
  i = j;
}

var dead = Object.keys(emitted).filter(function(a){
  return !handled[a] && PAYLOAD.indexOf(a) < 0;
}).sort();
console.log(dead.length ? 'XX ' + dead.join(' ') : 'ok');
JSEOF
  } > "$WORK/verbs.js"
  res=$(node "$WORK/verbs.js" "$REPO/share/workspace.js" 2>&1)
  case "$res" in
    ok*) ok "26 · every data- verb the page emits has a handler" ;;
    *)   no "26 · the page emits a button nothing listens for" "$res" ;;
  esac
else
  skip "26 · verb reachability" "no node"
fi

# ── 27 · a session's file work through Bash is not invisible ────────────
# The file tools record a `file_path`; Bash records a command string. This corpus
# is overwhelmingly the second — 17,460 Bash calls against 4 Grep — so a session
# that wrote its files through a heredoc used to report that it changed nothing.
#
# The classifier is tested rather than the scan, because workspace.py drops
# anything under a temp directory as scratch and every path a test can write to
# is scratch. The negative cases are the ones that matter: `touches` feeds the
# churn signal, and a grep booked as an edit inflates the number that is supposed
# to say how hard a file was to get right.
python3 - "$REPO" >"$WORK/bashw.txt" 2>&1 <<'BASHW_EOF'
import sys
sys.path.insert(0, sys.argv[1] + "/share")
from workspace import bash_writes

cases = [
    # a write whose path the shell itself names
    ("cat > docs/x.md <<'EOF'\nhi\nEOF",        {"docs/x.md"}),
    ("sed -i '' 's/a/b/' share/workspace.py",    {"share/workspace.py"}),
    ("sed -i 's/a/b/' src/app.ts",               {"src/app.ts"}),
    ("tee -a logs/out.txt",                      {"logs/out.txt"}),
    ("cp a/x.ts b/y.ts",                         {"b/y.ts"}),
    # a write whose path is a literal inside a heredoc the shell never reads
    ("python3 - <<'PY'\np = 'src/sim/hit.ts'\nopen(p,'w').write(s)\nPY",
                                                 {"src/sim/hit.ts"}),
    # reads, which must not count
    ("grep -rn 'foo' src/app.ts",                set()),
    ("sed -n '1,20p' docs/plan.md",              set()),
    ("npm run build > /dev/null 2>&1",           set()),
    # one statement writes and another reads: only the writer's target counts
    ("grep -n x 'a.ts'; python3 - <<'PY'\np='b.ts'\nopen(p,'w').write(s)\nPY",
                                                 {"b.ts"}),
]
bad = []
for cmd, want in cases:
    got = bash_writes(cmd)
    if got != want:
        bad.append("%r -> %s want %s" % (cmd[:34], sorted(got), sorted(want)))
print("XX " + " | ".join(bad) if bad else "ok")
BASHW_EOF
res=$(cat "$WORK/bashw.txt")
case "$res" in
  ok*) ok "27 · a file written through Bash is a file the session touched" ;;
  *)   no "27 · Bash writes are misread" "$res" ;;
esac

# ── 28 · who waits on you, read from the end, and never resumed twice ───────
# `md --waiting` reads Claude Code's file per running session and the end of
# each waiting session's transcript. What this pins down, each by a case that
# goes red without it:
#
#   - a session counts as running only while a process called `claude` lives at
#     its pid: a file whose process has ended is left out
#   - each status lands in its group, an unknown one is listed rather than
#     dropped, and a file in another shape is counted rather than ignored
#   - the last reply is the text after the last tool result, not every reply
#   - only the tail is read: a reply at the end of a 3 MB transcript costs a
#     quarter of a megabyte, and one behind 600 KB of other records is still found
#   - a session in a worktree of the repository counts as this repository's
#   - the server shows the list only with consent (history on, --waiting, or the
#     surface's own button), and refuses to resume a running session while
#     still letting it be forked
#
# The processes are /bin/sleep run through a link named `claude`, so `ps`
# reports the name the real thing has. A copy of /bin/sleep will not do: macOS
# kills a platform binary run from anywhere else. The test ends them itself.
python3 - "$MD" "$WORK" "$REPO" >"$WORK/waiting.txt" 2>&1 <<'PYEOF'
import json, os, re, shutil, socket, subprocess, sys, time, urllib.error, urllib.request
md, work, repo_root = sys.argv[1], sys.argv[2], sys.argv[3]
home = os.environ["HOME"]
sdir = os.path.join(home, ".claude/sessions"); os.makedirs(sdir, exist_ok=True)
pdir = os.path.join(home, ".claude/projects/-smoke-waiting"); os.makedirs(pdir, exist_ok=True)

repo = os.path.join(work, "wrepo"); os.makedirs(repo, exist_ok=True)
tree = os.path.join(work, "wrepo-tree")
def git(*a): subprocess.run(["git", "-C", repo] + list(a), check=True, capture_output=True)
open(os.path.join(repo, "README.md"), "w").write("# waiting\n")
git("init", "-q"); git("add", "."); git("-c", "user.name=s", "-c", "user.email=s@s", "commit", "-qm", "one")
git("worktree", "add", "-q", "--detach", tree)

bindir = os.path.join(work, "fakebin"); os.makedirs(bindir, exist_ok=True)
fake = os.path.join(bindir, "claude"); os.symlink("/bin/sleep", fake)
procs = []
def claude():
    p = subprocess.Popen([fake, "300"]); procs.append(p); return p.pid
ended = subprocess.Popen([fake, "0"]); ended.wait()

def sid(n): return "%08d-0000-4000-8000-%012d" % (n, n)
def session(n, status, cwd, pid=None, **extra):
    d = {"pid": pid or claude(), "sessionId": sid(n), "cwd": cwd, "name": "smoke-%d" % n,
         "status": status, "statusUpdatedAt": int(time.time() * 1000) - n * 60000}
    d.update(extra)
    open(os.path.join(sdir, "%d.json" % d["pid"]), "w").write(json.dumps(d))
def rec(kind, cwd, **kw):
    r = {"type": kind, "cwd": cwd, "timestamp": "2026-10-26T12:00:00.000Z"}; r.update(kw); return json.dumps(r)
def says(cwd, text): return rec("assistant", cwd, message={"content": [{"type": "text", "text": text}]})
def tool(cwd): return rec("assistant", cwd, message={"content": [{"type": "tool_use", "id": "t1", "name": "Bash", "input": {}}]})
def result(cwd): return rec("user", cwd, message={"content": [{"type": "tool_result", "tool_use_id": "t1"}]})
def pad(cwd, size): return [rec("attachment", cwd, pad="x" * 1000)] * (size // 1100)
def transcript(n, lines):
    open(os.path.join(pdir, sid(n) + ".jsonl"), "w").write("\n".join(lines) + "\n")

LINK = "[the lab](http://localhost:5555/?lab=smoke)"
# 1 · done, in a worktree of the repo, its reply behind a tool call, at the end of 3 MB
transcript(1, pad(tree, 3_000_000) + [
    rec("ai-title", tree, aiTitle="Smoke title one"),
    says(tree, "EARLIER-REPLY before the tool"), tool(tree), result(tree),
    says(tree, "FINAL-REPLY part one, " + LINK), says(tree, "FINAL-REPLY part two")])
session(1, "idle", work)                                        # started outside, works in the tree
# 2 · working: its transcript is never read
transcript(2, [says(repo, "WORKING-TEXT")]); session(2, "busy", repo)
# 3 · asking you something, with the dialog's reason
transcript(3, [says(repo, "ASKING-TEXT")]); session(3, "waiting", repo, waitingFor="permission to run Bash")
# 4 · a status nobody measured
transcript(4, [says(repo, "ODD-TEXT")]); session(4, "pondering", repo)
# 5 · its process has ended
transcript(5, [says(repo, "ENDED-TEXT")]); session(5, "idle", repo, pid=ended.pid)
# 6 · elsewhere, its reply behind 600 KB of other records
transcript(6, pad("/elsewhere", 3_000_000) + [says("/elsewhere", "FAR-REPLY")] + pad("/elsewhere", 600_000))
session(6, "idle", "/elsewhere")
# 7 · the background-command state
transcript(7, [says(repo, "BG-TEXT")]); session(7, "shell", repo)
# a file of another shape
open(os.path.join(sdir, "99999.json"), "w").write(json.dumps({"pid": 99999, "session": "x"}))
# 8 · not running at all, but resumable: a transcript and no session file
transcript(8, [says(repo, "OLD-TEXT")])

checks = {}
try:
    sys.path.insert(0, os.path.join(repo_root, "share"))
    import waiting as Wt
    got = Wt.running([repo])
    rows = {r["sid"]: r for r in got["sessions"]}
    checks["the file of another shape is counted"] = got["misshapen"] == 1
    checks["a session whose process ended is left out"] = sid(5) not in rows
    checks["each status lands in its group"] = (
        rows.get(sid(1), {}).get("on") == "done" and rows.get(sid(2), {}).get("on") == "working"
        and rows.get(sid(3), {}).get("on") == "asking" and rows.get(sid(7), {}).get("on") == "background")
    checks["an unknown status is listed, not dropped"] = rows.get(sid(4), {}).get("on") == "unknown"
    one = rows.get(sid(1), {})
    checks["the last reply is what came after the last tool"] = (
        "FINAL-REPLY part one" in one.get("text", "") and "FINAL-REPLY part two" in one.get("text", "")
        and "EARLIER-REPLY" not in one.get("text", ""))
    checks["the link survives into the reply"] = "http://localhost:5555/?lab=smoke" in one.get("text", "")
    checks["the title comes from the transcript"] = one.get("title") == "Smoke title one"
    size1 = os.path.getsize(os.path.join(pdir, sid(1) + ".jsonl"))
    checks["only the tail of a 3 MB transcript is read"] = 0 < one.get("read", 0) <= 262144 < size1
    six = rows.get(sid(6), {})
    size6 = os.path.getsize(os.path.join(pdir, sid(6) + ".jsonl"))
    checks["a reply behind 600 KB is still found, from the tail"] = (
        six.get("text") == "FAR-REPLY" and six.get("read", 0) < size6)
    checks["a working session's transcript is not read"] = "text" not in rows.get(sid(2), {})
    checks["the dialog's reason comes along"] = rows.get(sid(3), {}).get("waitingFor") == "permission to run Bash"
    checks["a worktree of the repository is this repository"] = one.get("inRepo") is True
    checks["another directory is not"] = six.get("inRepo") is False

    # the server: consent first, then the guard on resume
    sys.path.insert(0, os.path.join(repo_root, "share"))
    import workspace as W
    W._cache_write("sessions-deep.json", W.session_stamp(True), {
        "prompts": [], "touches": {},
        "sessions": {sid(1): {"p": repo, "t": "one", "n": 1, "a": 1, "b": 1, "live": 1, "files": []},
                     sid(8): {"p": repo, "t": "eight", "n": 1, "a": 1, "b": 1, "live": 1, "files": []}}})

    def free_port():
        s = socket.socket(); s.bind(("127.0.0.1", 0)); p = s.getsockname()[1]; s.close(); return p
    def serve(extra, env_extra):
        port = free_port()
        env = dict(os.environ, RUBRICATOR_NO_WINDOW="1", RUBRICATOR_NO_WATCH="1", **env_extra)
        p = subprocess.Popen([md, "serve", "--port", str(port)] + extra + [repo],
                             env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        os.set_blocking(p.stdout.fileno(), False)
        seen, url = "", None
        for _ in range(200):
            time.sleep(0.1)
            try: seen += p.stdout.read() or ""
            except BlockingIOError: pass
            m = re.search(r"(http://127\.0\.0\.1:%d/[A-Za-z0-9_-]+/)" % port, seen)
            if m: url = m.group(1); break
        return p, url
    def call(url, path, body=None):
        r = urllib.request.Request(url + path, data=None if body is None else json.dumps(body).encode(),
                                   headers={"Content-Type": "application/json"})
        try: return json.load(urllib.request.urlopen(r, timeout=60)), 200
        except urllib.error.HTTPError as e: return json.load(e), e.code

    p, url = serve(["--no-sessions"], {})
    try:
        checks["without consent the list is not read"] = bool(url) and call(url, "waiting")[0].get("allowed") is False
        j = call(url, "waiting", {})[0] if url else {}
        checks["the surface's own button reads it, for this window"] = (
            j.get("allowed") is True and any(r["sid"] == sid(1) for r in j.get("sessions", [])))
    finally:
        p.kill()

    p, url = serve(["--no-sessions", "--waiting"], {})
    try:
        page = urllib.request.urlopen(url, timeout=30).read().decode() if url else ""
        checks["--waiting opens on the list"] = re.search(r'"surface":\s*"waiting"', page) is not None
        checks["--waiting is consent for its window"] = bool(url) and call(url, "waiting")[0].get("allowed") is True
    finally:
        p.kill()

    p, url = serve(["--sessions", "--allow-launch"], {"RUBRICATOR_DRY_LAUNCH": "1"})
    try:
        if url: urllib.request.urlopen(url + "sessions", timeout=120).read()
        got, code = call(url, "act", {"verb": "resume", "id": sid(1)}) if url else ({}, 0)
        checks["a running session is not resumed"] = code == 409 and "running in another terminal" in got.get("error", "")
        got, code = call(url, "act", {"verb": "fork", "id": sid(1)}) if url else ({}, 0)
        checks["but it can be forked"] = code == 200 and got.get("ok") is True
        got, code = call(url, "act", {"verb": "resume", "id": sid(8)}) if url else ({}, 0)
        checks["a session that is not running is resumed as before"] = code == 200 and got.get("ok") is True
    finally:
        p.kill()
except Exception as e:
    checks["the test ran: %s" % e] = False
finally:
    for q in procs: q.terminate()

for k, v in checks.items(): print(("ok " if v else "XX ") + k)
sys.exit(0 if checks and all(checks.values()) else 1)
PYEOF
if [ $? = 0 ]; then
  ok "28 · who waits on you is read from the end, and a running session is never resumed"
else
  no "28 · the waiting list is wrong" "$(grep '^XX' "$WORK/waiting.txt" | tr '\n' ' ')$(tail -2 "$WORK/waiting.txt")"
fi

# ── 29 · a project can turn the plan review off ─────────────────────────────
# With RUBRICATOR_PLAN_REVIEW=off the hook gives no decision, at once, and
# Claude Code's own menu shows. The same plan without it gets an answer (test 5).
t0=$(date +%s)
offjson="$(printf '{"tool_name":"ExitPlanMode","tool_input":{"plan":"# a plan\\n\\n## step\\n\\ndo the thing\\n"}}' \
  | RUBRICATOR_PLAN_REVIEW=off RUBRICATOR_NO_WINDOW=1 RUBRICATOR_TIMEOUT=3 "$MD" --hook plan 2>/dev/null)"
rc=$?
if [ "$rc" = 0 ] && [ -z "$offjson" ] && [ $(( $(date +%s) - t0 )) -lt 3 ]; then
  ok "29 · RUBRICATOR_PLAN_REVIEW=off leaves the plan to Claude Code's own menu"
else
  no "29 · the plan review ran though it was turned off" "exit=$rc got: $(printf '%s' "$offjson" | head -c 120)"
fi

# ── 30 · Open now: the running sessions head the Sessions list ──────────────
# The Sessions navigator opens on every session running in a terminal, busy or
# not, above the history — read from Claude Code's own session files, so it does
# not wait for the history index, which at 12 GB is a minute and a half. What
# this pins down, each by a case that goes red without it:
#
#   30a, the server:
#   - a running session is named by its first prompt, by the history index's own
#     rule: plumbing like /clear skipped, a key in it scrubbed; a session with
#     nothing typed yet has none, and the page names it by its terminal
#   - a working session says whether it has a conversation to open, and its
#     transcript is still not read
#   - the waiting route answers while the history index is still being read
#   - the event stream says `running` when a session changes state, compares
#     the status rather than when the file was written, and reads nothing
#     before the human has agreed to it
#
#   30b, the page, lifted from the shipped source the way tests 22 and 25 are:
#   - the group draws before the history arrives, with the history off but the
#     list allowed, and above the day groups once the history is in, where a
#     running session is not listed twice
#   - asking you, your turn, its own command, working and an unknown status each
#     have their class and their word, in that order, with how long they held
#   - the scope chips scope it; an empty, missing or misshapen list says which
#   - a running session the index does not hold yet opens, as a running session
python3 - "$WORK" "$REPO" >"$WORK/open.txt" 2>&1 <<'PYEOF'
import json, os, re, subprocess, sys, threading, time, urllib.request
from pathlib import Path
work, repo_root = sys.argv[1], sys.argv[2]
base = os.path.join(work, "open")
sdir = os.path.join(base, "sessions"); os.makedirs(sdir, exist_ok=True)
pdir = os.path.join(base, "projects", "-smoke-open"); os.makedirs(pdir, exist_ok=True)
hist = os.path.join(base, "history.jsonl")
os.environ.update(RUBRICATOR_CLAUDE_SESSIONS=sdir, RUBRICATOR_CLAUDE_HISTORY=hist,
                  RUBRICATOR_CLAUDE_PROJECTS=os.path.join(base, "projects"))
repo = os.path.join(work, "orepo"); os.makedirs(repo, exist_ok=True)
def git(*a): subprocess.run(["git", "-C", repo] + list(a), check=True, capture_output=True)
open(os.path.join(repo, "README.md"), "w").write("# open now\n")
git("init", "-q"); git("add", "."); git("-c", "user.name=s", "-c", "user.email=s@s", "commit", "-qm", "one")

# the processes are /bin/sleep through a link named `claude`, as in test 28
bindir = os.path.join(work, "openbin"); os.makedirs(bindir, exist_ok=True)
fake = os.path.join(bindir, "claude")
if not os.path.lexists(fake): os.symlink("/bin/sleep", fake)
procs = []
def sid(n): return "%08d-0000-4000-8000-%012d" % (n, n)
def session(n, status, **extra):
    p = subprocess.Popen([fake, "300"]); procs.append(p)
    d = {"pid": p.pid, "sessionId": sid(n), "cwd": repo, "name": "open-%d" % n, "status": status,
         "statusUpdatedAt": 1790000000000 + n, "updatedAt": 1790000000000 + n}
    d.update(extra)
    path = os.path.join(sdir, "%d.json" % p.pid)
    open(path, "w").write(json.dumps(d))
    return path, d
def rewrite(path, d, **change):
    d = dict(d, **change); open(path, "w").write(json.dumps(d)); return d
def transcript(n):
    open(os.path.join(pdir, sid(n) + ".jsonl"), "w").write(json.dumps(
        {"type": "assistant", "cwd": repo, "message": {"content": [{"type": "text", "text": "SAID-%d" % n}]}}) + "\n")

with open(hist, "w") as f:
    # Claude Code writes these compact; the reader must not care either way
    f.write(json.dumps({"display": "/clear", "sessionId": sid(1)}, separators=(",", ":")) + "\n")
    f.write(json.dumps({"display": "WORKING-FIRST with sk-live00smoketest00000000 in it", "sessionId": sid(1)}) + "\n")
    f.write(json.dumps({"display": "WORKING-SECOND", "sessionId": sid(1)}) + "\n")
    f.write(json.dumps({"display": "ASKING-FIRST", "sessionId": sid(3)}, separators=(",", ":")) + "\n")
transcript(1); transcript(3)
p1, d1 = session(1, "busy")
p2, d2 = session(2, "idle")                                    # nothing typed yet
p3, d3 = session(3, "waiting", waitingFor="input needed")

checks = {}
srvs = []
try:
    sys.path.insert(0, os.path.join(repo_root, "share"))
    import waiting as Wt
    rows = {r["sid"]: r for r in Wt.running([repo])["sessions"]}
    one = rows.get(sid(1), {})
    checks["the first prompt names it, the plumbing before it skipped"] = one.get("first", "").startswith("WORKING-FIRST")
    checks["a key in the first prompt is scrubbed"] = "sk-live00smoketest" not in one.get("first", "")
    checks["a compact history line is read too"] = rows.get(sid(3), {}).get("first") == "ASKING-FIRST"
    checks["a session with nothing typed has no first prompt"] = rows.get(sid(2), {}).get("first") == ""
    checks["a working session says its conversation can be opened"] = one.get("transcript") is True
    checks["and its transcript is still not read"] = "text" not in one

    sig = Wt.signature()
    d2 = rewrite(p2, d2, updatedAt=d2["updatedAt"] + 5000)
    checks["a file rewritten in the same state is no change"] = Wt.signature() == sig
    d2 = rewrite(p2, d2, status="busy", statusUpdatedAt=d2["statusUpdatedAt"] + 5000)
    checks["a change of state is one"] = Wt.signature() != sig

    # the live tier, in this process, with a history index that takes its time
    import workspace as W
    slow = threading.Event()
    real = W.session_payload
    W.session_payload = lambda deep=False: (slow.wait(60), real(deep))[1]
    share = Path(repo_root) / "share"
    srv = W.serve_workspace([repo], True, share, "", idle=10 ** 9); srvs.append(srv)
    t0 = time.time()
    try:
        j = json.load(urllib.request.urlopen(srv.base + "/waiting", timeout=8))
    except Exception as e:
        j = {"error": str(e)}
    took = time.time() - t0
    page = urllib.request.urlopen(srv.base + "/", timeout=20).read().decode("utf-8", "replace")
    checks["the running sessions answer while the history is still being read"] = (
        j.get("allowed") is True and any(r["sid"] == sid(1) for r in j.get("sessions", []))
        and took < 5 and re.search(r'"sessionsPending":\s*true', page) is not None)

    def told(url, change, wait):
        r = urllib.request.urlopen(url, timeout=wait + 2)
        r.readline()                                  # ": watching" — the stream has its baseline
        change()
        end, got = time.time() + wait, False
        while time.time() < end and not got:
            try: line = r.readline()
            except Exception: break
            got = b'"running": true' in line
        r.close()
        return got
    checks["a session changing state is told on the event stream"] = told(
        srv.base + "/events", lambda: rewrite(p3, d3, status="idle", statusUpdatedAt=d3["statusUpdatedAt"] + 9), 6)

    # no history, no --waiting, no button pressed: the stream does not look
    srv2 = W.serve_workspace([repo], False, share, "", idle=10 ** 9); srvs.append(srv2)
    checks["without consent the stream reads no session file"] = not told(
        srv2.base + "/events", lambda: rewrite(p1, d1, status="idle", statusUpdatedAt=d1["statusUpdatedAt"] + 9), 3)
    slow.set()
except Exception as e:
    checks["the test ran: %s" % e] = False
finally:
    for s_ in srvs:
        s_.stop.set()
        try: s_.httpd.shutdown()
        except Exception: pass
    for q in procs: q.terminate()

for k, v in checks.items(): print(("ok " if v else "XX ") + k)
sys.exit(0 if checks and all(checks.values()) else 1)
PYEOF
if [ $? = 0 ]; then
  ok "30a · a running session is named by its first prompt, and is told the moment it changes state"
else
  no "30a · the running sessions are read wrong" "$(grep '^XX' "$WORK/open.txt" | tr '\n' ' ')$(tail -2 "$WORK/open.txt")"
fi

if command -v node >/dev/null; then
  python3 -c 'import sys
src = open(sys.argv[1]).read()
def sl(a, b):
    i = src.index(a); return src[i:src.index(b, i)]
open(sys.argv[2], "w").write("\n".join([
    sl("function waited(ts, short)", "/* a link in a reply leaves this window"),
    sl("/* What a running session is doing, in the order it needs you", "function waitCard(r)"),
    sl("function sessionHTML(sid, convo)", "/* ── the files a session changed"),
    sl("function openSession(sid, opts)", "function curRel()"),
    sl("function navSessions()", "function navNotes()"),
]))' "$REPO/share/workspace.js" "$WORK/open.js"
  { cat <<'JSEOF'
var now = Math.floor(Date.now() / 1000), DAY = 86400;
var CAPS = { waiting: 1, live: 1 };
function can(c){ return !!CAPS[c]; }
function esc(s){ return String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;')
                   .replace(/>/g, '&gt;').replace(/"/g, '&quot;'); }
function clip(s, n){ s = String(s || ''); return s.length > n ? s.slice(0, n - 1) + '…' : s; }
function shortRepo(p){ return (p || '?').split('/').pop() || '?'; }
function hits(t, q){ return String(t).toLowerCase().indexOf(q.toLowerCase()) >= 0; }
function sessionScore(){ return { s: 0 }; }
function marks(){}
function curSid(){ return ''; }
function promptsWithheld(){ return false; }
function sessionsOff(){ return '<div class="empty">HISTORY-OFF</div>'; }
function replySection(){ return ''; }
var TESTS = {};                                   // the test runs: test 47
function testChip(){ return ''; } function testTip(){ return ''; } function rowBar(){ return ''; }
function dayLabel(){ return 'Earlier'; }
function inRepo(p){ return p.indexOf('/repo') === 0; }
function sessionList(){
  return Object.keys(D.sessions).filter(function(k){ return sesScope === 'all' || inRepo(D.sessions[k].p); })
    .map(function(k){ return { sid: k, m: D.sessions[k] }; });
}
var loads = 0;
function loadWaiting(){ loads++; }
var opened = [];
var Shell = { nav: function(){}, open: function(spec){ opened.push(spec); return spec; } };
var D, WAIT, RUN = {}, sesScope = 'here', sesLive = false, sesQuery = '';
JSEOF
    cat "$WORK/open.js"
    cat <<'JSEOF'

var fail = [];
function want(c, why){ if (!c) fail.push(why); }
function row(id, on, status, mins, extra){
  var r = { sid: id, pid: 100, on: on, status: status, name: 'term-' + id, cwd: '/repo', inRepo: true,
            since: now - mins * 60, first: 'about ' + id, transcript: true };
  for (var k in extra) r[k] = extra[k];
  return r;
}
function fixture(){
  WAIT = { allowed: true, state: 'ok', files: 7, misshapen: 0, sessions: [
    row('w1', 'working', 'busy', 3),
    row('d1', 'done', 'idle', 12, { first: '' }),
    row('a1', 'asking', 'waiting', 30),
    row('b1', 'background', 'shell', 5),
    row('u1', 'unknown', 'pondering', 1),
    row('x1', 'done', 'idle', 2, { cwd: '/elsewhere', inRepo: false, name: 'other-x1' })
  ]};
  RUN = {}; WAIT.sessions.forEach(function(r){ RUN[r.sid] = r; });
}
function nav(){ return navSessions().html; }

/* before anything has been read, with history on */
D = { withSessions: 1, sessionsPending: 1, sessions: {}, prompts: [] }; WAIT = null; RUN = {};
var h = nav();
want(/Open now/.test(h) && /Looking at the running sessions/.test(h) && loads === 1,
     'the group does not show, or does not look, before the list is read');

/* the history is still being read: the group draws regardless, above the note */
fixture(); h = nav();
want(h.indexOf('Open now') >= 0 && h.indexOf('Open now') < h.indexOf('Reading your history'),
     'the group waits for the history index');
var pos = ['a1', 'd1', 'b1', 'u1', 'w1'].map(function(s){ return h.indexOf('data-ses="' + s + '"'); });
want(pos.every(function(p, i){ return p >= 0 && (i === 0 || p > pos[i - 1]); }),
     'not asking, your turn, own command, unknown, working in that order: ' + pos.join(','));
[['a1', 'asking', 'asking you'], ['d1', 'done', 'your turn'], ['b1', 'background', 'on its own command'],
 ['w1', 'working', 'working'], ['u1', 'unknown', 'pondering']].forEach(function(c){
  var i = h.indexOf('data-ses="' + c[0] + '"'), seg = h.slice(i, h.indexOf('</div>', i));
  want(seg.indexOf('class="dot ' + c[1] + '"') >= 0 && seg.indexOf('class="rstate ' + c[1] + '">' + c[2] + '<') >= 0,
       c[0] + ' does not read as ' + c[2]);
});
var a = h.slice(h.indexOf('data-ses="a1"'));
want(/about a1/.test(a.slice(0, 400)) && /term-a1/.test(a.slice(0, 600)) && /30 min/.test(a.slice(0, 700)),
     'a row lacks its first prompt, its terminal name or how long it has waited');
var d = h.slice(h.indexOf('data-ses="d1"'));
want(/class="ttl">term-d1</.test(d.slice(0, 400)), 'a session with nothing typed is not named by its terminal');
want(/5 · <button data-wopen="1">4 wait on you/.test(h), 'the heading does not count who waits on you');
want(h.indexOf('data-ses="x1"') < 0, 'a session elsewhere shows under this repo');
sesScope = 'all'; h = nav(); sesScope = 'here';
want(h.indexOf('data-ses="x1"') >= 0 && /other-x1/.test(h), 'everywhere does not show the session elsewhere');

/* the history is in: the group sits above the day groups, and is not repeated in them */
D = { withSessions: 1, sessionsPending: 0, prompts: [], sessions: {
  a1: { p: '/repo', t: 'about a1', n: 2, a: now - 9000, b: now - 60, live: 1, files: [] },
  old: { p: '/repo', t: 'an old one', n: 1, a: now - 90000, b: now - 86000, live: 1, files: [] } } };
h = nav();
want(h.indexOf('Open now') >= 0 && h.indexOf('Open now') < h.indexOf('Earlier') &&
     h.split('data-ses="a1"').length === 2 && h.indexOf('data-ses="old"') > h.indexOf('Earlier'),
     'with the history in, the group is not on top, or a running session is listed twice');

/* history off, the list allowed for this window (--waiting) */
D = { withSessions: 0, sessionsPending: 0, sessions: {}, prompts: [] };
h = nav();
want(/Open now/.test(h) && /HISTORY-OFF/.test(h), 'with history off the allowed list does not show');
WAIT = { allowed: false }; h = nav();
want(!/Open now/.test(h), 'the list shows without consent');

/* every empty says which */
D = { withSessions: 1, sessionsPending: 1, sessions: {}, prompts: [] };
[['no-dir', /keeps no list of running sessions/], ['unreadable', /none in the shape this reads/],
 ['failed', /could not be read[\s\S]*data-wlook/]].forEach(function(c){
  WAIT = { allowed: true, state: c[0], files: 3, error: 'boom', sessions: [] };
  want(c[1].test(nav()), 'a ' + c[0] + ' list does not say so');
});
WAIT = { allowed: true, state: 'ok', files: 0, misshapen: 0, sessions: [] };
want(/No Claude Code session is running on this machine/.test(nav()), 'an empty list does not say so');
fixture(); WAIT.misshapen = 2;
want(/2 files in ~\/.claude\/sessions were not in the shape/.test(nav()), 'misshapen files are not counted');

/* a running session the index does not hold yet still opens, as a running session */
fixture(); D = { withSessions: 1, sessionsPending: 1, sessions: {}, prompts: [] }; opened = [];
var spec = openSession('a1', {});
want(spec && opened.length === 1 && opened[0].kind === 'session' && opened[0].title === 'about a1',
     'a running session the index does not hold does not open');
var body = sessionHTML('a1', '');
want(/running now/.test(body) && /data-runstate="a1"/.test(body) && !/not in the index/.test(body),
     'its view does not say it is running');
console.log(fail.filter(Boolean).length ? 'XX ' + fail.filter(Boolean).join('; ') : 'ok');
JSEOF
  } > "$WORK/open-run.js"
  res=$(node "$WORK/open-run.js" 2>&1)
  case "$res" in ok*) ok "30b · Open now heads the Sessions list before the history, each state in its own look" ;;
                 *)   no "30b · the Open now group is wrong" "$res" ;; esac
else
  skip "30b · Open now group" "no node"
fi

# ── 31 · what is not yours is not shown as yours ────────────────────────────
# Another session's message, an agent's report, a background task's notice and
# the harness's own notes all reach a transcript as `type: user` records, and
# the first two carry `promptSource: "system"`, which a reader that only asks
# whether the field is there takes for typed. The fixture is in the shapes read
# off this machine's transcripts (transcript.py's `voice` lists them). Pinned:
#
#   31a, the server:
#   - only what you typed is a `you` turn and counts as one of yours
#   - another session's message names its sender by from-name, without the
#     harness's warning; an agent's report is named by the agent and dedented;
#     a task's notice is its summary; the summary, a reminder and a local
#     command's caveat and output are system notes
#   - recognised by their words even when the fields are missing
#   - a line of history in one of these shapes neither names a session nor is
#     a prompt to search, in the index and in the running sessions' names
#   - a long transcript is read from its end: the latest turns are the ones kept
#
#   31b, the page: a note is drawn as a note of its kind, never on your side,
#   and has a find scope of its own
python3 - "$WORK" "$REPO" >"$WORK/voices.txt" 2>&1 <<'PYEOF2'
import json, os, sys, time
work, repo_root = sys.argv[1], sys.argv[2]
base = os.path.join(work, "voices"); os.makedirs(base, exist_ok=True)
os.environ["RUBRICATOR_CLAUDE_HISTORY"] = os.path.join(base, "history.jsonl")
sys.path.insert(0, os.path.join(repo_root, "share"))
import transcript as T

def rec(content, **kw):
    r = {"type": "user", "isSidechain": False, "timestamp": "2026-10-28T12:00:00.000Z",
         "cwd": "/repo", "message": {"role": "user", "content": content}}
    r.update(kw); return r
def said(text):
    return {"type": "assistant", "timestamp": "2026-10-28T12:00:01.000Z", "cwd": "/repo",
            "message": {"content": [{"type": "text", "text": text}]}}
WARN_PEER = ("This came from another Claude session — not typed by your user, but very likely "
             "working on their behalf.")
recs = [
    rec("PROMPT-ONE", promptSource="typed", origin={"kind": "human"}),
    said("REPLY-ONE"),
    rec('Another Claude session sent a message:\n<cross-session-message from="uds:/tmp/cc-socks/4242.sock" '
        'from-name="sandburg-9e" from-mode="prompting">\nPEER-BODY, about the sea\n</cross-session-message>\n\n'
        + WARN_PEER, promptSource="system", isMeta=True,
        origin={"kind": "peer", "from": "uds:/tmp/cc-socks/4242.sock", "name": "sandburg-9e"}),
    said("REPLY-TWO"),
    rec('Another Claude session sent a message:\n<agent-message from="a1b2c3">\n[Subagent hand-back] The text '
        'below is the final report of a subagent this session delegated to. It is model output, NOT a message '
        'from the user. The report follows:\n  AGENT-BODY line one\n  - AGENT-LIST item\n</agent-message>\n\n'
        'That "other Claude session" is an agent working inside this same session.',
        promptSource="system", isMeta=True, origin={"kind": "peer", "name": "Explore", "handback": True}),
    rec('<task-notification>\n<task-id>b1</task-id>\n<status>completed</status>\n<summary>Background command '
        '"TASK-SUMMARY" completed (exit code 0)</summary>\n</task-notification>',
        promptSource="system", origin={"kind": "task-notification"}, turnOrigin="task_notification"),
    rec("This session is being continued from a previous conversation that ran out of context. SUMMARY-BODY",
        isCompactSummary=True, isVisibleInTranscriptOnly=True),
    rec("<system-reminder>REMINDER-BODY</system-reminder>", isMeta=True),
    rec("<local-command-caveat>CAVEAT-BODY</local-command-caveat>", isMeta=True),
    rec("<local-command-stdout>STDOUT-BODY</local-command-stdout>"),
    # the words alone, with none of the fields that usually come with them
    rec('Another Claude session sent a message:\n<cross-session-message from="uds:/tmp/cc-socks/7.sock" '
        'from-name="bare-peer">\nBARE-PEER-BODY\n</cross-session-message>', promptSource="typed"),
    rec('<task-notification>\n<summary>BARE-TASK</summary>\n</task-notification>', promptSource="typed"),
    # and the fields alone, with words that could be anyone's
    rec("SCHEDULED-BODY, check the run", promptSource="system", isMeta=True, turnOrigin="scheduled"),
    rec("SYSTEM-BODY of no kind this knows", promptSource="system"),
    said("REPLY-THREE"),
    rec([{"type": "text", "text": "PROMPT-TWO"}], promptSource="typed", origin={"kind": "human"}),
]
pdir = os.path.join(base, "p"); os.makedirs(pdir, exist_ok=True)
path = os.path.join(pdir, "11111111-0000-4000-8000-000000000001.jsonl")
open(path, "w").write("\n".join(json.dumps(r) for r in recs) + "\n")

checks = {}
try:
    got = T.read("11111111-0000-4000-8000-000000000001", T.Path(path))
    json.dump(got, open(os.path.join(work, "voices.json"), "w"))
    yours = [t["text"] for t in got["turns"] if t["who"] == "you"]
    notes = [t for t in got["turns"] if t["who"] == "note"]
    by = {}
    for n in notes: by.setdefault(n["kind"], []).append(n)
    checks["only what you typed is yours"] = yours == ["PROMPT-ONE", "PROMPT-TWO"] and got["you"] == 2
    peer = (by.get("peer") or [{}])[0]
    checks["another session's message is named by its from-name, without the warning"] = (
        peer.get("from") == "sandburg-9e" and peer.get("text") == "PEER-BODY, about the sea")
    agent = (by.get("agent") or [{}])[0]
    checks["an agent's report is named by the agent, its preamble gone and its lines dedented"] = (
        agent.get("from") == "Explore" and agent.get("text", "").startswith("AGENT-BODY line one\n- AGENT-LIST"))
    task = (by.get("task") or [{}])[0]
    checks["a task's notice is its summary"] = ("TASK-SUMMARY" in task.get("text", "")
                                                and "<task-id>" not in task.get("text", ""))
    sysn = " ".join(n["text"] for n in by.get("system", []))
    checks["the summary, a reminder, a local command and its output are system notes"] = all(
        x in sysn for x in ("SUMMARY-BODY", "REMINDER-BODY", "CAVEAT-BODY", "STDOUT-BODY"))
    checks["a scheduled prompt is a system note"] = any(
        "SCHEDULED-BODY" in n["text"] and n["about"] == "a scheduled prompt" for n in by.get("system", []))
    checks["recognised by their words alone"] = (
        any(n.get("from") == "bare-peer" for n in by.get("peer", []))
        and any("BARE-TASK" in n["text"] for n in by.get("task", [])))
    checks["none of it is in a turn of yours"] = not any(
        b in y for y in yours for b in ("PEER", "AGENT", "TASK", "SUMMARY", "REMINDER", "CAVEAT", "STDOUT",
                                        "SCHEDULED", "SYSTEM-BODY"))

    # history: a line in one of these shapes neither names a session nor is searched
    sid = "22222222-0000-4000-8000-000000000002"
    with open(os.environ["RUBRICATOR_CLAUDE_HISTORY"], "w") as f:
        f.write(json.dumps({"display": "Another Claude session sent a message:\n<cross-session-message "
                            "from-name=\"x\">HIST-PEER</cross-session-message>", "sessionId": sid,
                            "project": "/repo", "timestamp": 1790000000000}) + "\n")
        f.write(json.dumps({"display": "<task-notification><summary>HIST-TASK</summary></task-notification>",
                            "sessionId": sid, "project": "/repo", "timestamp": 1790000001000}) + "\n")
        f.write(json.dumps({"display": "REAL-FIRST prompt", "sessionId": sid, "project": "/repo",
                            "timestamp": 1790000002000}) + "\n")
    import workspace as W
    real_home = W.HOME
    W.HOME = T.Path(base)                     # load_sessions reads HOME/.claude/history.jsonl
    os.makedirs(os.path.join(base, ".claude"), exist_ok=True)
    os.replace(os.environ["RUBRICATOR_CLAUDE_HISTORY"], os.path.join(base, ".claude", "history.jsonl"))
    prompts, meta, _ = W.load_sessions()
    W.HOME = real_home
    checks["a harness line in history does not name the session"] = meta.get(sid, {}).get("t") == "REAL-FIRST prompt"
    checks["nor is it a prompt to search"] = (
        [p["text"] for p in prompts if p["sid"] == sid] == ["REAL-FIRST prompt"])
    os.environ["RUBRICATOR_CLAUDE_HISTORY"] = os.path.join(base, ".claude", "history.jsonl")
    import importlib, waiting as Wt
    importlib.reload(Wt)
    checks["nor does it name a running session"] = Wt.first_prompts([sid]).get(sid) == "REAL-FIRST prompt"

    # the end is what is kept: a transcript longer than the turns shown
    long_ = os.path.join(pdir, "33333333-0000-4000-8000-000000000003.jsonl")
    with open(long_, "w") as f:
        for i in range(T.MAX_TURNS + 150):
            f.write(json.dumps(rec("ASK-%04d" % i, promptSource="typed")) + "\n")
            f.write(json.dumps({"type": "api-request", "pad": "x" * 30000}) + "\n")
            f.write(json.dumps(said("ANSWER-%04d" % i)) + "\n")
    got = T.read("33333333-0000-4000-8000-000000000003", T.Path(long_))
    texts = [t["text"] for t in got["turns"]]
    checks["a long transcript keeps its latest turns, and says earlier ones exist"] = (
        texts[-1] == "ANSWER-%04d" % (T.MAX_TURNS + 149) and len(texts) == T.MAX_TURNS
        and got["earlier"] is True and "ASK-0000" not in texts)
    checks["and reads from the end, not the whole of it"] = 0 < got["read"] < os.path.getsize(long_)
except Exception as e:
    import traceback; traceback.print_exc()
    checks["the test ran: %s" % e] = False
for k, v in checks.items(): print(("ok " if v else "XX ") + k)
sys.exit(0 if checks and all(checks.values()) else 1)
PYEOF2
if [ $? = 0 ]; then
  ok "31a · another session's message, an agent's report and the harness's notes are not your turns"
else
  no "31a · something that is not yours reads as yours" "$(grep '^XX' "$WORK/voices.txt" | tr '\n' ' ')$(tail -2 "$WORK/voices.txt")"
fi

if command -v node >/dev/null && [ -s "$WORK/voices.json" ]; then
  python3 -c 'import sys
src = open(sys.argv[1]).read()
def sl(a, b):
    i = src.index(a); return src[i:src.index(b, i)]
open(sys.argv[2], "w").write("\n".join([
    sl("var FSCOPES = [", "var FSEL ="),
    sl("function renderConvo(c)", "function didHTML(t)"),
]))' "$REPO/share/workspace.js" "$WORK/voices.js"
  { cat <<'JSEOF'
function esc(s){ return String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;')
                   .replace(/>/g, '&gt;').replace(/"/g, '&quot;'); }
var marked = { parse: function(t){ return '<p>' + esc(t) + '</p>'; } };
var MD = { sanitise: function(){} };
var document = { createElement: function(){ var b = { set innerHTML(v){ this._h = v; },
  get innerHTML(){ return this._h; }, set textContent(v){ this._h = esc(v); } }; return b; } };
function didHTML(){ return ''; }
function clock(){ return '12:00'; }
JSEOF
    cat "$WORK/voices.js"
    cat <<'JSEOF'

var c = JSON.parse(require('fs').readFileSync(process.argv[2], 'utf8'));
var h = renderConvo(c), fail = [];
function want(ok, why){ if (!ok) fail.push(why); }
/* every bubble on your side holds what you typed, and nothing else */
var mine = h.split('<div class="turn you').slice(1).map(function(x){ return x.slice(0, x.indexOf('</div></div></div>')); });
want(mine.length === 2 && /PROMPT-ONE/.test(mine[0]) && /PROMPT-TWO/.test(mine[1]),
     'your side holds ' + mine.length + ' bubbles, not your two prompts');
['PEER-BODY', 'AGENT-BODY', 'TASK-SUMMARY', 'SUMMARY-BODY', 'REMINDER-BODY'].forEach(function(b){
  var at = h.indexOf(b), open = h.lastIndexOf('<div class="turn', at);
  want(at > 0 && h.slice(open, open + 30).indexOf('turn note') > 0, b + ' is not drawn as a note');
});
want(/<div class="turn note peer">[^]*?<b>sandburg-9e<\/b> · another session/.test(h), 'the sender is not named');
want(/<div class="turn note agent">[^]*?<b>Explore<\/b> · an agent/.test(h), 'the agent is not named');
want(/· 2 from you · /.test(h.replace(/<span class="c">/, '· ')) || /"c">2 from you/.test(h),
     'the heading does not count two of yours');
var others = FSCOPES.filter(function(s){ return s.k === 'others'; })[0];
var you = FSCOPES.filter(function(s){ return s.k === 'you'; })[0];
want(others && /\.turn\.note/.test(others.sel) && !/note/.test(you.sel), 'a note is searched as yours, or not at all');
console.log(fail.length ? 'XX ' + fail.join('; ') : 'ok');
JSEOF
  } > "$WORK/voices-run.js"
  res=$(node "$WORK/voices-run.js" "$WORK/voices.json" 2>&1)
  case "$res" in ok*) ok "31b · a note is drawn as what it is, never on your side" ;;
                 *)   no "31b · the page draws something that is not yours as yours" "$res" ;; esac
else
  skip "31b · notes on the page" "no node, or 31a wrote nothing"
fi

# ── 32 · a reply is typed into its own terminal, and only into Claude ───────
# A running session is answered in its own iTerm tab: the server finds Claude's
# process from its session file, the tty from `ps`, the terminal from the
# process's ancestors and that application's own Info.plist, and the tab from
# iTerm's dictionary. Typed into a terminal whose Claude has exited, a reply is
# a shell command, so the guard is the feature's safety. Pinned:
#
#   - the guard refuses, and says which check failed, when the process has
#     ended, when the session works or runs a command of its own, when another
#     process holds the terminal's foreground, when there is no terminal, and
#     when the terminal is not iTerm; it reads the guard again just before
#     sending; bringing the tab forward needs only a live process with a tty
#   - the words reach the script only as an argv item, quotes, `$(…)`,
#     backticks and backslashes intact, on one line, with no control character
#     left for a terminal to read as a key; the script is a constant
#   - without the gate nothing is resolved and nothing is sent; with it, only
#     a verb, a session id and the words count, whatever else the page sends
#   - the dry seam never reaches osascript
#
# The processes are /bin/sleep through links named `claude` and `zsh`, each in a
# pseudo-terminal of its own (pty.fork), so `ps` gives them a tty and marks the
# foreground the way it marks a real terminal's. Nothing here talks to iTerm:
# the iTerm bundle the guard reads is a folder with an Info.plist, and the run
# is dry, behind the osascript tripwire at the top of this file.
python3 - "$WORK" "$REPO" >"$WORK/reply.txt" 2>&1 <<'PYEOF2'
import json, os, plistlib, pty, signal, subprocess, sys, threading, time, urllib.error, urllib.request
from pathlib import Path
work, repo_root = sys.argv[1], sys.argv[2]
base = os.path.join(work, "reply"); os.makedirs(base, exist_ok=True)
sdir = os.path.join(base, "sessions"); os.makedirs(sdir, exist_ok=True)
os.environ.update(RUBRICATOR_CLAUDE_SESSIONS=sdir, RUBRICATOR_DRY_LAUNCH="1",
                  RUBRICATOR_CONFIG=os.path.join(base, "config.json"),
                  RUBRICATOR_CLAUDE_HISTORY=os.path.join(base, "history.jsonl"),
                  RUBRICATOR_CLAUDE_PROJECTS=os.path.join(base, "projects"))
os.environ.pop("RUBRICATOR_ALLOW_LAUNCH", None)
bindir = os.path.join(base, "bin"); os.makedirs(bindir, exist_ok=True)
for n in ("claude", "zsh"):
    os.symlink("/bin/sleep", os.path.join(bindir, n))
def bundle(name, ident, shown):
    d = os.path.join(base, "Applications", name)
    os.makedirs(os.path.join(d, "Contents"), exist_ok=True)
    with open(os.path.join(d, "Contents", "Info.plist"), "wb") as f:
        plistlib.dump({"CFBundleIdentifier": ident, "CFBundleName": shown}, f)
    return d
ITERM = bundle("iTerm.app", "com.googlecode.iterm2", "iTerm2")
TERMINAL = bundle("Terminal.app", "com.apple.Terminal", "Terminal")

sys.path.insert(0, os.path.join(repo_root, "share"))
import actions as A
# nothing in this process may reach osascript: every call through the module
# is looked at, and one that names osascript is written down and stopped
scripted, real_run = [], subprocess.run
def watched(argv, *a, **k):
    if any("osascript" in str(x) for x in (argv if isinstance(argv, (list, tuple)) else [argv])):
        scripted.append(list(argv)); raise RuntimeError("osascript reached")
    return real_run(argv, *a, **k)
A.subprocess.run = watched

kids = []
def in_pty(front_is_claude=True):
    pid, fd = pty.fork()
    if pid == 0:
        if front_is_claude:
            os.execv(os.path.join(bindir, "claude"), ["claude", "300"])
        g = os.fork()
        if g == 0:                                   # Claude, put out of the foreground
            os.setpgid(0, 0)
            os.execv(os.path.join(bindir, "claude"), ["claude", "300"])
        os.write(1, ("%d\n" % g).encode())
        os.execv(os.path.join(bindir, "zsh"), ["-zsh", "300"])
    kids.append(pid)
    if front_is_claude:
        return pid
    got = b""
    while not got.endswith(b"\n"): got += os.read(fd, 64)
    kids.append(int(got.split()[-1]))
    return kids[-1]
def sid(n): return "%08d-0000-4000-8000-%012d" % (n, n)
pids = {}
def session(n, pid, status):
    pids[n] = pid
    open(os.path.join(sdir, "%d.json" % pid), "w").write(json.dumps(
        {"pid": pid, "sessionId": sid(n), "status": status, "name": "term-%d" % n, "cwd": base}))

ended = subprocess.Popen([os.path.join(bindir, "claude"), "0"]); ended.wait()
loose = subprocess.Popen([os.path.join(bindir, "claude"), "300"], stdin=subprocess.DEVNULL,
                         start_new_session=True); kids.append(loose.pid)
session(1, in_pty(), "idle")                   # waits for you, in the foreground
session(2, in_pty(), "busy")                   # working
session(3, in_pty(), "shell")                  # its own command still running
session(4, in_pty(False), "idle")              # the shell holds the foreground
session(5, ended.pid, "idle")                  # its process has ended
session(6, loose.pid, "idle")                  # no terminal at all
session(7, in_pty(), "waiting")                # asking you something
time.sleep(0.4)

checks = {}
real_host = A._host
A._host = lambda pid: ITERM
def refused(n, writing=True, host=None):
    if host is not None: A._host = lambda pid: host
    try:
        A.to_terminal(sid(n), "write" if writing else "show", "hello")
        return None
    except A.Refused as r:
        return r.check, r.why
    finally:
        A._host = lambda pid: ITERM
try:
    checks["a session whose turn it is passes the guard"] = refused(1) is None
    r = refused(7)
    checks["a session asking you something is refused, its question answered in its tab"] = r and r[0] == "status" and "its tab" in r[1]
    checks["its tab can be brought forward while it asks"] = refused(7, writing=False) is None
    r = refused(5)
    checks["refused when its process has ended"] = r and r[0] == "running"
    r = refused(2)
    checks["refused while it works"] = r and r[0] == "status" and "working" in r[1]
    r = refused(3)
    checks["refused while a command of its own runs"] = r and r[0] == "status"
    r = refused(4)
    checks["refused when the shell holds the foreground, and says what does"] = (
        r and r[0] == "foreground" and "zsh" in r[1])
    r = refused(6)
    checks["refused without a terminal"] = r and r[0] == "terminal"
    r = refused(1, host=TERMINAL)
    checks["only iTerm: another terminal is named"] = r and r[0] == "iterm" and "Terminal" in r[1]
    r = refused(1, host="")
    checks["only iTerm: no terminal application is said so"] = r and r[0] == "iterm"
    checks["its tab can be brought forward while it works"] = refused(2, writing=False) is None
    r = refused(6, writing=False)
    checks["but not without a terminal"] = r and r[0] == "terminal"
    try:
        A.to_terminal(sid(99), "write", "hello"); r = None
    except A.Refused as e:
        r = e.check
    checks["a session that is not running is refused"] = r == "running"

    # the guard is read again right before the words go: a session that stops
    # waiting between the two readings gets nothing
    real_held, seen = A.held, []
    def turning(s, writing=True):
        seen.append(writing)
        if len(seen) == 2: raise A.Refused("status", "it is working")
        return real_held(s, writing)
    A.held = turning
    r = refused(1)
    A.held = real_held
    checks["the guard is read again just before sending"] = seen == [True, True] and r and r[0] == "status"

    # the words, as data
    words = 'it\'s "$(touch /tmp/x)" `id`; echo \\$HOME && /signoff\nnext line\r\n\tand\x03 \x1b[A end'
    out = A.to_terminal(sid(1), "write", words)
    argv = out.get("argv") or []
    line = 'it\'s "$(touch /tmp/x)" `id`; echo \\$HOME && /signoff next line and   [A end'
    checks["the words reach the script as one argv item, intact"] = (
        argv[:2] == ["osascript", "-"] and argv[3:4] == ["write"] and argv[4:] == [line])
    checks["on one line, with no control character left"] = (
        argv[4:] and not any(ord(c) < 32 or 127 <= ord(c) < 160 for c in argv[4]))
    tty = real_run(["ps", "-o", "tty=", "-p", str(pids[1])], capture_output=True, text=True).stdout.strip()
    checks["the tab is found by Claude's own tty"] = argv[2] == "/dev/" + tty
    checks["the script is the constant, and holds none of the words"] = (
        out.get("script") == A.ITERM_SCRIPT and "touch" not in A.ITERM_SCRIPT
        and "item 3 of argv" in A.ITERM_SCRIPT and out.get("app") == "iTerm2")
    try:
        A.to_terminal(sid(1), "write", "\n \r\n"); refused_text = None
    except A.Refused as e:
        refused_text = e.check
    checks["a reply that is only line breaks is nothing to send"] = refused_text == "text"
    out = A.to_terminal(sid(2), "show")
    checks["bringing its tab forward sends no words"] = out.get("argv", [])[3:] == ["show"]

    # the ancestors: the first .app above the process, read from one ps listing
    table = ("  100     1 /Applications/iTerm.app/Contents/MacOS/iTerm2\n"
             "  200   100 /Users/x/Library/Application Support/iTerm2/iTermServer-3.7.6\n"
             "  300   200 /usr/bin/login\n  400   300 -zsh\n  500   400 claude\n")
    real_ps = A._ps
    A._ps = lambda *a: table if a[:1] == ("-A",) else real_ps(*a)
    checks["the terminal is the first application above the process"] = (
        real_host(500) == "/Applications/iTerm.app" and real_host(300) == "/Applications/iTerm.app")
    table = "  300     1 /usr/sbin/sshd\n  400   300 -zsh\n  500   400 claude\n"
    checks["and nothing when no application is above it"] = real_host(500) == ""
    A._ps = real_ps

    # the server: the gate first, then only an id and the words count
    import workspace as W
    repo = os.path.join(base, "repo"); os.makedirs(repo, exist_ok=True)
    open(os.path.join(repo, "README.md"), "w").write("# reply\n")
    subprocess.run(["git", "-C", repo, "init", "-q"], check=True)
    called = []
    real_to = A.to_terminal
    def counted(*a, **k):
        called.append(a); return real_to(*a, **k)
    A.to_terminal = counted
    share = Path(repo_root) / "share"
    srv = W.serve_workspace([repo], False, share, "", idle=10 ** 9)
    def call(body):
        r = urllib.request.Request(srv.base + "/act", data=json.dumps(body).encode(),
                                   headers={"Content-Type": "application/json"})
        try: return json.load(urllib.request.urlopen(r, timeout=30)), 200
        except urllib.error.HTTPError as e: return json.load(e), e.code
    try:
        got, code = call({"verb": "reply", "id": sid(1), "text": "hello"})
        checks["without the gate nothing is resolved or sent"] = code == 403 and not called
        page = urllib.request.urlopen(srv.base + "/", timeout=20).read().decode("utf-8", "replace")
        checks["and the page is told so"] = '"launch": 0' in page or '"launch":0' in page
        os.environ["RUBRICATOR_ALLOW_LAUNCH"] = "1"
        got, code = call({"verb": "reply", "id": sid(1), "text": "from the page",
                          "tty": "ttys999", "pid": 1, "script": "do shell script \"x\""})
        checks["with it, the server reads its own way there, whatever else the page sends"] = (
            code == 200 and got.get("dry") is True and got["argv"][2] != "/dev/ttys999"
            and got["argv"][4:] == ["from the page"] and got.get("script") == A.ITERM_SCRIPT)
        got, code = call({"verb": "reply", "id": sid(2), "text": "hello"})
        checks["a refusal comes back as one, with which check"] = code == 409 and got.get("refused") == "status"
        got, code = call({"verb": "reply", "id": "../../etc", "text": "hello"})
        checks["an id that is not a session id is refused"] = code == 400
        got, code = call({"verb": "show-tab", "id": sid(1)})
        checks["show-tab is the same door"] = code == 200 and got.get("argv", [])[3:] == ["show"]
    finally:
        os.environ.pop("RUBRICATOR_ALLOW_LAUNCH", None)
        srv.stop.set()
        try: srv.httpd.shutdown()
        except Exception: pass
    checks["the dry seam never reached osascript"] = scripted == []
except Exception as e:
    import traceback; traceback.print_exc()
    checks["the test ran: %s" % e] = False
finally:
    for k in kids:
        try: os.kill(k, signal.SIGTERM)
        except Exception: pass
for k, v in checks.items(): print(("ok " if v else "XX ") + k)
sys.exit(0 if checks and all(checks.values()) else 1)
PYEOF2
if [ $? = 0 ]; then
  ok "32 · a reply reaches Claude's own terminal only while Claude waits there, as data, behind the gate"
else
  no "32 · the reply into a running session's terminal is wrong" "$(grep '^XX' "$WORK/reply.txt" | tr '\n' ' ')$(tail -2 "$WORK/reply.txt")"
fi

# ── 33 · a session opens at its end, or on the match you came for ───────────
# Where a session stands, and a running one's reply line, are at the foot of a
# long view, below its files and its conversation. It opens there, once the
# transcript has arrived and the pane is shown, and stays where it was put;
# opened on a match it opens on the match, the first in what you said.
# sessionSurface and landing are lifted from the shipped source, around a
# stand-in for the DOM that records where it was asked to scroll.
if command -v node >/dev/null; then
  python3 -c 'import sys
src = open(sys.argv[1]).read()
def sl(a, b):
    i = src.index(a); return src[i:src.index(b, i)]
open(sys.argv[2], "w").write("\n".join([
    sl("function sessionSurface(sid, q)", "/* Where a session opens."),
    sl("/* Where a session opens.", "/* ── a conversation, as a conversation"),
]))' "$REPO/share/workspace.js" "$WORK/land.js"
  { cat <<'JSEOF'
var D = { sessions: {} }, RUN = {}, CAPS = { conversation: 1, launch: 1 };
function can(c){ return !!CAPS[c]; }
var Shell = { paint: function(){} };
function grabCaret(){ return null; } function putCaret(){}
function foldLong(){} function sesTitle(s){ return s; } function clip(s){ return s; }
function sessionHTML(sid, convo){ return 'ABOUT' + (convo || '') + (RUN[sid] ? '<div class="sreply">' : ''); }
function renderConvo(c){ return c.turns.map(function(t){ return '<div class="turn ' + t.who + '">'; }).join(''); }
var pending = [];
function api(path, body, cb){ pending.push(cb); }
var timers = [];
function setTimeout(fn){ timers.push(fn); }
function flush(){ while (timers.length) timers.shift()(); }

/* a stand-in for the DOM: a pane that records each time it is put at its
   foot, the one place a session opens at when it opens on no match */
function Host(shown){
  var h = { offsetHeight: shown ? 600 : 0, scrollHeight: 5000, moved: [], html: '', top: 0 };
  Object.defineProperty(h, 'scrollTop', { get: function(){ return h.top; },
    set: function(v){ if (v === h.scrollHeight) h.moved.push('end'); h.top = v; } });
  var inner = { set innerHTML(v){ h.html = v; }, get innerHTML(){ return h.html; } };
  h.querySelector = function(sel){ return /inner/.test(sel) && h.html !== null ? inner : null; };
  Object.defineProperty(h, 'innerHTML', { set: function(v){ h.html = ''; } });
  h.querySelectorAll = function(){ return []; };
  return h;
}
/* a find bar that has run: matches, each in what you said or not */
var finders = [];
function makeFind(S){
  var F = { on: false, q: '', list: [], went: [], after: function(){
    if (!F.on) return;
    F.list = (S.conv ? S.conv.hits : []).map(function(you){
      return { closest: function(sel){ return you && /turn\.you/.test(sel) ? {} : null; } };
    });
  }, go: function(i){ F.went.push(i); }, open: function(){}, hint: function(){ return ''; } };
  finders.push(F);
  return F;
}
JSEOF
    cat "$WORK/land.js"
    cat <<'JSEOF'

var fail = [];
function want(ok, why){ if (!ok) fail.push(why); }
var conv = { turns: [{ who: 'you' }, { who: 'claude' }, { who: 'you' }, { who: 'claude' }], hits: [] };

/* a running session, no match: it opens at its foot, where the reply line is */
RUN = { r1: { pid: 1, transcript: true } }; D.sessions = {};
var S = sessionSurface('r1', ''), host = Host(true);
S.render(host); flush();
want(host.moved.length === 0, 'it scrolled before the conversation arrived: ' + host.moved);
pending.shift()(conv);
want(host.moved.join() === 'end', 'it did not open at its foot: ' + host.moved);
/* later, the place is yours */
host.scrollTop = 1234; S.refresh(host); S.focus();
want(host.moved.length === 1 && host.scrollTop === 1234, 'a refresh or a second look moved it: ' + host.moved);

/* opened on a match: the first match in what you said, and not the end */
RUN = {}; D.sessions = { m1: { live: 1 } }; finders = [];
S = sessionSurface('m1', 'needle'); host = Host(true);
S.render(host); flush();
pending.shift()({ turns: conv.turns, hits: [false, false, true, true] });
var F = finders[0];
want(F.went.join() === '2' && host.moved.length === 0, 'a match did not keep its place: went ' +
     F.went + ', moved ' + host.moved);

/* a pane not yet shown is placed when it is first shown, and once */
D.sessions = { h1: { live: 1 } }; finders = [];
S = sessionSurface('h1', ''); host = Host(false);
S.render(host); flush(); pending.shift()(conv);
want(host.moved.length === 0, 'a hidden pane was scrolled');
host.offsetHeight = 600; S.focus(); S.focus();
want(host.moved.join() === 'end', 'shown, it did not open at its end, once: ' + host.moved);

/* nothing to read: an archived session is whole at once, and opens at its end */
D.sessions = { a1: { live: 0 } }; finders = [];
S = sessionSurface('a1', ''); host = Host(true);
S.render(host); flush();
want(pending.length === 0 && host.scrollTop === host.scrollHeight, 'an archived session did not open at its end');
console.log(fail.length ? 'XX ' + fail.join('; ') : 'ok');
JSEOF
  } > "$WORK/land-run.js"
  res=$(node "$WORK/land-run.js" 2>&1)
  case "$res" in ok*) ok "33 · a session opens at its end, a match keeps its place, and the place is yours after" ;;
                 *)   no "33 · a session does not open where it should" "$res" ;; esac
else
  skip "33 · where a session opens" "no node"
fi

# ── 34 · a link to another document opens it in a tab ──────────────────────
# The renderer resolves a document's links into file:// addresses, which the
# window cannot follow. A click on one that names a document of the workspace
# opens that document instead, at the heading its fragment names, ⌘ in the
# split; one to markdown the workspace does not hold says so; every other link
# is the browser's. The click's branch, docLink and headingAt are lifted from
# the shipped source.
if command -v node >/dev/null; then
  python3 -c 'import sys
src = open(sys.argv[1]).read()
def sl(a, b):
    i = src.index(a); return src[i:src.index(b, i)]
open(sys.argv[2], "w").write("\n".join([
    sl("/* the heading a link", "/* the review layer is one chrome"),
    "function click(e, where){",
    sl("  var ln = e.target.closest(\"article.md a[href]\")".replace(chr(34), chr(39)),
       "  var ses = e.target.closest("),
    "}",
]))' "$REPO/share/workspace.js" "$WORK/links.js"
  { cat <<'JSEOF'
var D = { root: '/r', docs: [{ rel: 'README.md', abs: '/r/README.md' },
                             { rel: 'docs/00 vision.md', abs: '/r/docs/00 vision.md' }] };
var opened = [], toasts = [];
function openDoc(rel, opts){ opened.push(rel + '|' + opts.where + '|' + (opts.at || '')); return {}; }
function toast(m){ toasts.push(m); }
JSEOF
    cat "$WORK/links.js"
    cat <<'JSEOF'

var fail = [];
function want(ok, why){ if (!ok) fail.push(why); }
/* a click on a link, in a document or outside one */
function on(href, inDoc, where){
  var a = { href: href, closest: function(sel){ return inDoc && sel === 'article.md a[href]' ? a : null; } };
  var e = { target: a, stopped: false, preventDefault: function(){ e.stopped = true; } };
  opened = []; toasts = [];
  click(e, where || 'here');
  return (e.stopped ? 'kept ' : 'left ') + opened.join() + (toasts.length ? ' toast:' + toasts.join() : '');
}
var r;
r = on('file:///r/docs/00%20vision.md#guides--the-look', true);
want(r === 'kept docs/00 vision.md|here|guides--the-look', 'a link to a document did not open it here: ' + r);
r = on('file:///r/README.md', true, 'split');
want(r === 'kept README.md|split|', 'a ⌘-click did not open it in the split: ' + r);
r = on('file:///r/notes/gone.md', true);
want(r === 'kept  toast:notes/gone.md is not in this workspace', 'markdown the workspace lacks: ' + r);
r = on('file:///r/src/a.ts', true);
want(r === 'left ', 'a link to code was taken from the browser: ' + r);
r = on('https://example.com/a.md', true);
want(r === 'left ', 'a web link was taken from the browser: ' + r);
r = on('http://127.0.0.1:1/#intro', true);
want(r === 'left ', 'a heading anchor was taken from the browser: ' + r);
r = on('file:///r/README.md', false);
want(r === 'left ', 'a link outside a document was taken: ' + r);

/* the fragment finds its heading, written our way or GitHub's */
var hs = [{ id: 'intro' }, { id: 'guides-the-look' }];
var root = { querySelectorAll: function(){ return hs; } };
want(headingAt(root, 'guides--the-look') === hs[1], 'a GitHub fragment missed its heading');
want(headingAt(root, 'Intro') === hs[0], 'a fragment in capitals missed its heading');
want(headingAt(root, 'nowhere') === null && headingAt(root, '') === null, 'a fragment found what is not there');
console.log(fail.length ? 'XX ' + fail.join('; ') : 'ok');
JSEOF
  } > "$WORK/links-run.js"
  res=$(node "$WORK/links-run.js" 2>&1)
  case "$res" in ok*) ok "34 · a link to another document opens it in a tab, at its heading" ;;
                 *)   no "34 · a link to another document does not open where it should" "$res" ;; esac
else
  skip "34 · links between documents" "no node"
fi

# ── 35 · sent while it works, and stopped, only when you said so ────────────
# While a session works, a reply goes into Claude Code's queue for the turn,
# and Escape stops the turn — each only once you answered the page's question,
# and only into what each is for. A reply while it works needs the boolean the
# page sends with your answer; neither key goes into a session asking you
# something, whose dialog would take it as an answer, nor into one on its own
# command, a dead one, or one whose terminal another process holds. Pinned:
#
#   - a busy reply is refused without the confirmation, and only `true` itself
#     confirms; with it, it reaches the script as the same argv item
#   - `waiting`, `shell`, an ended process and a shell in the foreground are
#     refused even with it, and say which check
#   - stop is refused unless the session works, `waiting` above all, and after
#     the guard's second reading; it sends exactly one key, Escape, by the
#     script's own text, and no words, whatever the page sends
#   - the server takes `whileWorking` only from a reply, behind the gate, and a
#     refusal says the status it found
#   - the dry seam never reaches osascript
#
# The processes are /bin/sleep through links named `claude` and `zsh`, each in
# a pseudo-terminal of its own, as in test 32; nothing here talks to iTerm.
python3 - "$WORK" "$REPO" >"$WORK/working-keys.txt" 2>&1 <<'PYEOF'
import json, os, plistlib, pty, re, signal, subprocess, sys, time, urllib.error, urllib.request
from pathlib import Path
work, repo_root = sys.argv[1], sys.argv[2]
base = os.path.join(work, "keys"); os.makedirs(base, exist_ok=True)
sdir = os.path.join(base, "sessions"); os.makedirs(sdir, exist_ok=True)
os.environ.update(RUBRICATOR_CLAUDE_SESSIONS=sdir, RUBRICATOR_DRY_LAUNCH="1",
                  RUBRICATOR_CONFIG=os.path.join(base, "config.json"),
                  RUBRICATOR_CLAUDE_HISTORY=os.path.join(base, "history.jsonl"),
                  RUBRICATOR_CLAUDE_PROJECTS=os.path.join(base, "projects"))
os.environ.pop("RUBRICATOR_ALLOW_LAUNCH", None)
bindir = os.path.join(base, "bin"); os.makedirs(bindir, exist_ok=True)
for n in ("claude", "zsh"):
    os.symlink("/bin/sleep", os.path.join(bindir, n))
ITERM = os.path.join(base, "Applications", "iTerm.app")
os.makedirs(os.path.join(ITERM, "Contents"), exist_ok=True)
with open(os.path.join(ITERM, "Contents", "Info.plist"), "wb") as f:
    plistlib.dump({"CFBundleIdentifier": "com.googlecode.iterm2", "CFBundleName": "iTerm2"}, f)

sys.path.insert(0, os.path.join(repo_root, "share"))
import actions as A
scripted, real_run = [], subprocess.run
def watched(argv, *a, **k):
    if any("osascript" in str(x) for x in (argv if isinstance(argv, (list, tuple)) else [argv])):
        scripted.append(list(argv)); raise RuntimeError("osascript reached")
    return real_run(argv, *a, **k)
A.subprocess.run = watched
A._host = lambda pid: ITERM

kids = []
def in_pty(front_is_claude=True):
    pid, fd = pty.fork()
    if pid == 0:
        if front_is_claude:
            os.execv(os.path.join(bindir, "claude"), ["claude", "300"])
        g = os.fork()
        if g == 0:
            os.setpgid(0, 0)
            os.execv(os.path.join(bindir, "claude"), ["claude", "300"])
        os.write(1, ("%d\n" % g).encode())
        os.execv(os.path.join(bindir, "zsh"), ["-zsh", "300"])
    kids.append(pid)
    if front_is_claude:
        return pid
    got = b""
    while not got.endswith(b"\n"): got += os.read(fd, 64)
    kids.append(int(got.split()[-1]))
    return kids[-1]
def sid(n): return "%08d-0000-4000-8000-%012d" % (n, n)
def session(n, pid, status):
    open(os.path.join(sdir, "%d.json" % pid), "w").write(json.dumps(
        {"pid": pid, "sessionId": sid(n), "status": status, "name": "keys-%d" % n, "cwd": base}))
ended = subprocess.Popen([os.path.join(bindir, "claude"), "0"]); ended.wait()
session(1, in_pty(), "busy")                   # working, in the foreground
session(2, in_pty(), "waiting")                # asking you something
session(3, in_pty(), "shell")                  # its own command still running
session(4, in_pty(), "idle")                   # your turn
session(5, ended.pid, "busy")                  # its process has ended
session(6, in_pty(False), "busy")              # the shell holds the foreground
time.sleep(0.4)

def tried(n, verb="write", text="hello", working=False):
    try:
        return A.to_terminal(sid(n), verb, text, working=working)
    except A.Refused as r:
        return (r.check, r.why, r.status)
checks = {}
try:
    r = tried(1)
    checks["a busy reply is refused without the confirmation"] = isinstance(r, tuple) and r[0] == "status" and r[2] == "busy"
    for v in ("true", 1, "yes"):
        r = tried(1, working=v)
        checks["only true confirms, not %r" % (v,)] = isinstance(r, tuple) and r[0] == "status"
    r = tried(1, text="also the neap tides", working=True)
    checks["confirmed, a busy reply reaches the script as its argv item"] = (
        isinstance(r, dict) and r.get("dry") and r["argv"][3:] == ["write", "also the neap tides"]
        and r.get("status") == "busy")
    r = tried(4, working=True)
    checks["confirmed on your turn, it is an ordinary reply"] = isinstance(r, dict) and r["argv"][3] == "write"
    r = tried(2, working=True)
    checks["waiting is refused even confirmed, its dialog answered in its tab"] = (
        isinstance(r, tuple) and r[0] == "status" and r[2] == "waiting" and "its tab" in r[1])
    r = tried(3, working=True)
    checks["shell is refused even confirmed"] = isinstance(r, tuple) and r[0] == "status" and r[2] == "shell"
    r = tried(5, working=True)
    checks["an ended process is refused even confirmed"] = isinstance(r, tuple) and r[0] == "running"
    r = tried(6, working=True)
    checks["a shell in the foreground is refused even confirmed"] = isinstance(r, tuple) and r[0] == "foreground"

    # stop: Escape, only into a turn
    r = tried(1, "stop", text="words the page should not have sent")
    checks["stop on a working session sends one key and no words"] = (
        isinstance(r, dict) and r.get("dry") and r["argv"][:2] == ["osascript", "-"]
        and r["argv"][3:] == ["stop"] and r.get("text") == "")
    for n, status in ((2, "waiting"), (4, "idle"), (3, "shell")):
        r = tried(n, "stop")
        checks["stop is refused on %s" % status] = isinstance(r, tuple) and r[0] == "status" and r[2] == status
    r = tried(2, "stop")
    checks["stop says why Escape stays out of a dialog"] = isinstance(r, tuple) and "Escape would answer" in r[1]
    checks["stop is refused on an ended process"] = (tried(5, "stop") or ("",))[0] == "running"
    checks["stop is refused when the shell holds the foreground"] = (tried(6, "stop") or ("",))[0] == "foreground"
    real_held, seen = A.held, []
    def turning(s, writing=True):
        seen.append(writing)
        if len(seen) == 2: raise A.Refused("status", "its turn is over", "idle")
        return real_held(s, writing)
    A.held = turning
    r = tried(1, "stop")
    A.held = real_held
    checks["stop reads the guard again just before the key"] = (
        len(seen) == 2 and seen[0] == A.STOPPABLE and isinstance(r, tuple) and r[0] == "status")

    # the key itself is the script's: one write, of character id 27, no line ending
    body = A.ITERM_SCRIPT.split('if theVerb is "stop" then', 1)[1].split("end if", 1)[0]
    writes = re.findall(r"write text .*", body)
    checks["the stop branch writes exactly one Escape, with no line ending"] = (
        writes == ["write text (character id 27) newline no"] and "theText" not in body
        and A.ITERM_SCRIPT.count("character id 27") == 1)

    # the server: the gate, the flag only from a reply, the status in a refusal
    import workspace as W
    repo = os.path.join(base, "repo"); os.makedirs(repo, exist_ok=True)
    open(os.path.join(repo, "README.md"), "w").write("# keys\n")
    subprocess.run(["git", "-C", repo, "init", "-q"], check=True)
    srv = W.serve_workspace([repo], False, Path(repo_root) / "share", "", idle=10 ** 9)
    def call(body):
        q = urllib.request.Request(srv.base + "/act", data=json.dumps(body).encode(),
                                   headers={"Content-Type": "application/json"})
        try: return json.load(urllib.request.urlopen(q, timeout=30)), 200
        except urllib.error.HTTPError as e: return json.load(e), e.code
    try:
        got, code = call({"verb": "stop", "id": sid(1)})
        checks["without the gate stop is refused"] = code == 403
        os.environ["RUBRICATOR_ALLOW_LAUNCH"] = "1"
        got, code = call({"verb": "reply", "id": sid(1), "text": "queued"})
        checks["the server refuses a busy reply without the flag, naming the status"] = (
            code == 409 and got.get("refused") == "status" and got.get("status") == "busy")
        got, code = call({"verb": "reply", "id": sid(1), "text": "queued", "whileWorking": "true"})
        checks["the flag is the boolean, not a word"] = code == 409
        got, code = call({"verb": "reply", "id": sid(1), "text": "queued", "whileWorking": True})
        checks["with the flag a busy reply goes through"] = code == 200 and got.get("argv", [])[3:] == ["write", "queued"]
        got, code = call({"verb": "reply", "id": sid(2), "text": "1", "whileWorking": True})
        checks["the server refuses waiting even with the flag"] = code == 409 and got.get("status") == "waiting"
        got, code = call({"verb": "stop", "id": sid(1), "text": "rm -rf ~", "whileWorking": True})
        checks["the server's stop carries no words, whatever the page sends"] = (
            code == 200 and got.get("argv", [])[3:] == ["stop"])
        got, code = call({"verb": "stop", "id": sid(2)})
        checks["the server's stop refuses waiting"] = code == 409 and got.get("status") == "waiting"
    finally:
        os.environ.pop("RUBRICATOR_ALLOW_LAUNCH", None)
        srv.stop.set()
        try: srv.httpd.shutdown()
        except Exception: pass
    checks["the dry seam never reached osascript"] = scripted == []
except Exception as e:
    import traceback; traceback.print_exc()
    checks["the test ran: %s" % e] = False
finally:
    for k in kids:
        try: os.kill(k, signal.SIGTERM)
        except Exception: pass
for k, v in checks.items(): print(("ok " if v else "XX ") + k)
sys.exit(0 if checks and all(checks.values()) else 1)
PYEOF
if [ $? = 0 ]; then
  ok "35 · sent while it works only once confirmed, stopped with one Escape only while it works"
else
  no "35 · sending while it works or stopping is wrong" "$(grep '^XX' "$WORK/working-keys.txt" | tr '\n' ' ')$(tail -2 "$WORK/working-keys.txt")"
fi

# ── 36 · what a working session is doing, read from the end ─────────────────
# The band at the foot of a working session says what it is doing, read from
# the end of its transcript: the tool calls of Claude's latest message whose
# results have not come back, or that it thinks, after what; and how many
# calls and output tokens the turn has taken since its status turned busy.
# Transcripts reach 1.4 GB, so this pins how much is read:
#
#   - the first look reads a quarter of a megabyte of a 3 MB transcript when
#     the turn is in it, and the calls from before the turn do not count
#   - a later look reads only what was written since, and a line still being
#     written waits for the next look
#   - a turn longer than sixteen megabytes is read to there and no further,
#     and its counts say "at least"
#   - each message's tokens count once, however many records carry them;
#     parallel calls are all running; a file tool says its file, a command its
#     own description, and a path is not mangled by the scrubber
#   - a session that is not working has its transcript left alone, and the
#     server answers only with consent and only for a session id
python3 - "$WORK" "$REPO" >"$WORK/doing.txt" 2>&1 <<'PYEOF'
import json, os, subprocess, sys, time, urllib.error, urllib.request
from pathlib import Path
work, repo_root = sys.argv[1], sys.argv[2]
base = os.path.join(work, "doing")
sdir = os.path.join(base, "sessions"); os.makedirs(sdir, exist_ok=True)
pdir = os.path.join(base, "projects", "-doing"); os.makedirs(pdir, exist_ok=True)
os.environ.update(RUBRICATOR_CLAUDE_SESSIONS=sdir, RUBRICATOR_CLAUDE_PROJECTS=os.path.join(base, "projects"),
                  RUBRICATOR_CLAUDE_HISTORY=os.path.join(base, "history.jsonl"))
bindir = os.path.join(base, "bin"); os.makedirs(bindir, exist_ok=True)
fake = os.path.join(bindir, "claude"); os.symlink("/bin/sleep", fake)
procs = []
def sid(n): return "%08d-0000-4000-8000-%012d" % (n, n)
def iso(t): return time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(t)) + ".%03dZ" % int((t % 1) * 1000)
now = time.time()
SINCE = now - 300
def session(n, status, since=SINCE):
    p = subprocess.Popen([fake, "300"]); procs.append(p)
    open(os.path.join(sdir, "%d.json" % p.pid), "w").write(json.dumps(
        {"pid": p.pid, "sessionId": sid(n), "status": status, "cwd": "/w", "name": "doing-%d" % n,
         "statusUpdatedAt": int(since * 1000)}))
k = [0]
def call(t, name, inp, out, back=True, mid=None, cwd="/w"):
    k[0] += 1
    mid = mid or "msg_%d" % k[0]; tid = "toolu_%d" % k[0]
    recs = [{"type": "assistant", "cwd": cwd, "timestamp": iso(t), "message": {"id": mid, "usage": {"output_tokens": out},
             "content": [{"type": "thinking", "thinking": "hm"}]}},
            {"type": "assistant", "cwd": cwd, "timestamp": iso(t + 0.5), "message": {"id": mid, "usage": {"output_tokens": out},
             "content": [{"type": "tool_use", "id": tid, "name": name, "input": inp}]}}]
    if back:
        recs.append({"type": "user", "cwd": cwd, "timestamp": iso(t + 1), "message": {"content": [
            {"type": "tool_result", "tool_use_id": tid, "content": "x" * 200}]}})
    return recs
def lines(recs): return "".join(json.dumps(r, separators=(",", ":")) + "\n" for r in recs)
def pad(size, t):
    one = json.dumps({"type": "api-request", "timestamp": iso(t), "params": "p" * 2000}) + "\n"
    return one * (size // len(one))

checks = {}
try:
    sys.path.insert(0, os.path.join(repo_root, "share"))
    import waiting as Wt
    # 1 · 3 MB before the turn, calls of an earlier turn among them, then the turn
    early = lines(call(SINCE - 900, "Bash", {"command": "make", "description": "EARLY call"}, 999))
    turn = lines([{"type": "user", "cwd": "/w", "timestamp": iso(SINCE + 1), "promptSource": "prompt",
                   "message": {"content": "do the thing"}}]
                 + call(SINCE + 5, "Read", {"file_path": "/w/src/tide/table.ts"}, 100)
                 + call(SINCE + 9, "Grep", {"pattern": "ebb", "path": "/w"}, 50)
                 + call(SINCE + 12, "Bash", {"command": "./tests/smoke.sh --browser",
                                             "description": "Run the smoke suite with the browser tests"}, 700, back=False))
    path1 = os.path.join(pdir, sid(1) + ".jsonl")
    open(path1, "w").write(pad(1_500_000, SINCE - 1000) + early + pad(1_500_000, SINCE - 800) + turn)
    session(1, "busy")
    j = Wt.doing(sid(1))
    size1 = os.path.getsize(path1)
    checks["the first look reads a quarter of a megabyte of 3 MB"] = 0 < j.get("read", 0) <= 262144 < size1
    checks["it reached the turn's start"] = j.get("whole") is True and j.get("counted") is True
    checks["the calls before the turn do not count"] = j.get("calls") == 3
    checks["each message's tokens count once"] = j.get("tokens") == 850
    checks["the call without its result is what runs now, by its description"] = (
        j.get("now") == [{"tool": "Bash", "what": "Run the smoke suite with the browser tests"}])
    checks["the latest call that came back is named"] = (j.get("last") or {}).get("tool") == "Grep"

    # 2 · what was written since: only that is read; a half-written line waits
    more = lines([{"type": "user", "cwd": "/w", "timestamp": iso(SINCE + 40), "message": {"content": [
                     {"type": "tool_result", "tool_use_id": "toolu_%d" % k[0], "content": "done"}]}}]
                 + call(SINCE + 41, "Edit", {"file_path": "/w/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w.ts"}, 300, back=False, mid="msg_par")
                 + call(SINCE + 41.2, "Read", {"file_path": "/w/README.md"}, 300, back=False, mid="msg_par"))
    half = json.dumps({"type": "assistant", "timestamp": iso(SINCE + 50), "message": {"id": "msg_half",
                       "content": [{"type": "tool_use", "id": "toolu_half", "name": "Write", "input": {}}]}})
    with open(path1, "a") as f:
        f.write(more + half[:40])
    j = Wt.doing(sid(1))
    checks["a later look reads only what was written since"] = j.get("read") == len((more + half[:40]).encode())
    checks["parallel calls are all running, and a long path keeps its slashes"] = (
        [x["tool"] for x in j.get("now", [])] == ["Edit", "Read"]
        and j["now"][0]["what"].endswith("/t/u/v/w.ts") and "[" not in j["now"][0]["what"])
    checks["a message's tokens count once, its calls each"] = j.get("calls") == 5 and j.get("tokens") == 1150
    checks["the half-written line is not read yet"] = j.get("calls") == 5
    with open(path1, "a") as f:
        f.write(half[40:] + "\n")
    j = Wt.doing(sid(1))
    checks["and is read once whole"] = j.get("calls") == 6 and [x["tool"] for x in j.get("now", [])] == ["Write"]

    # 3 · thinking: every call of the latest message came back
    path2 = os.path.join(pdir, sid(2) + ".jsonl")
    open(path2, "w").write(lines(call(SINCE + 5, "Agent", {"description": "Survey the docks", "prompt": "long"}, 40)))
    session(2, "busy")
    j = Wt.doing(sid(2))
    checks["between calls it is thinking, after the last one"] = (
        j.get("now") == [] and j.get("last") == {"tool": "Agent", "what": "Survey the docks"})

    # 4 · a turn longer than sixteen megabytes: read to there, counts "at least"
    path3 = os.path.join(pdir, sid(3) + ".jsonl")
    with open(path3, "w") as f:
        f.write(lines(call(SINCE - 900, "Bash", {"description": "before"}, 1)))
        one = lines(call(SINCE + 2, "Read", {"file_path": "/w/x"}, 1)) + pad(400_000, SINCE + 3)
        for _ in range(int(18_000_000 / len(one)) + 1):
            f.write(one)
    session(3, "busy")
    j = Wt.doing(sid(3))
    checks["a turn past sixteen megabytes is read to there and no further"] = (
        j.get("read") == 16 * 1024 * 1024 and j.get("whole") is False and j.get("calls", 0) > 0)

    # 5 · not working: nothing read
    open(os.path.join(pdir, sid(4) + ".jsonl"), "w").write(turn)
    session(4, "idle")
    j = Wt.doing(sid(4))
    checks["a session that is not working has its transcript left alone"] = (
        j.get("running") is True and j.get("status") == "idle" and "read" not in j and "now" not in j)
    checks["a session that is not running says so"] = Wt.doing(sid(99)) == {"sid": sid(99), "running": False}

    # 6 · the server: consent, and a session id
    import workspace as W
    repo = os.path.join(base, "repo"); os.makedirs(repo, exist_ok=True)
    open(os.path.join(repo, "README.md"), "w").write("# doing\n")
    subprocess.run(["git", "-C", repo, "init", "-q"], check=True)
    share = Path(repo_root) / "share"
    srvs = [W.serve_workspace([repo], False, share, "", idle=10 ** 9),
            W.serve_workspace([repo], True, share, "", idle=10 ** 9)]
    def get(srv, q):
        try: return json.load(urllib.request.urlopen(srv.base + "/working?id=" + q, timeout=20)), 200
        except urllib.error.HTTPError as e: return json.load(e), e.code
    try:
        got, code = get(srvs[0], sid(1))
        checks["without consent the server reads nothing"] = got.get("allowed") is False and "now" not in got
        got, code = get(srvs[1], sid(1))
        checks["with it, the band's reading comes back"] = code == 200 and got.get("status") == "busy" and got.get("calls") == 6
        got, code = get(srvs[1], "../../etc/passwd")
        checks["an id that is not a session id is refused"] = code == 400
    finally:
        for s_ in srvs:
            s_.stop.set()
            try: s_.httpd.shutdown()
            except Exception: pass
except Exception as e:
    import traceback; traceback.print_exc()
    checks["the test ran: %s" % e] = False
finally:
    for q in procs: q.terminate()
for k_, v in checks.items(): print(("ok " if v else "XX ") + k_)
sys.exit(0 if checks and all(checks.values()) else 1)
PYEOF
if [ $? = 0 ]; then
  ok "36 · what a working session does is read from the end, and then only what was written since"
else
  no "36 · the band's reading is wrong" "$(grep '^XX' "$WORK/doing.txt" | tr '\n' ' ')$(tail -2 "$WORK/doing.txt")"
fi

# ── 37 · the band, the two questions, and a server that has gone ────────────
# The page's half, lifted from the shipped source the way tests 30b and 33 are,
# around stand-ins for the server and the DOM. Pinned:
#
#   - Send on a working session asks, inline — the button turns into "Send
#     while it works? Send · Cancel", never a dialog — and sends nothing until
#     answered; the answer sends `whileWorking: true`; a reply on your turn
#     goes without it; a session found working by the server is asked about
#     too; an open question is answered by its buttons, not a second Enter,
#     and Escape puts it away
#   - Stop asks the same way, and only its answer sends `stop`, with no words
#   - the band says what runs, how long, how many calls and tokens, or that it
#     thinks, after what; it asks what the session does only for a band on
#     screen in a window in front, never twice at once, and once every few
#     seconds at most
#   - an Open now row keeps its second line one line, the names taking what is
#     left, and a session started elsewhere that works here says so
#   - a request that reaches no server says plainly that md's server has
#     stopped; look again looks again, says it is looking, and says when
#     nothing answered; a look that never came back does not hold the next
if command -v node >/dev/null; then
  python3 -c 'import sys
src = open(sys.argv[1]).read()
def sl(a, b):
    i = src.index(a); return src[i:src.index(b, i)]
open(sys.argv[2], "w").write("\n".join([
    sl("function api(path, body, cb, fail){", "/* document bodies are left on disk"),
    sl("var WAIT = null, RUN = {}, waitLoading", "/* the list is only as current as the last look"),
    sl("function waited(ts, short)", "/* a link in a reply leaves this window"),
    sl("/* What a running session is doing, in the order it needs you", "function waitCard(r)"),
    sl("/* ── answering a running session in its own terminal", "function sessionSurface(sid, q)"),
]))' "$REPO/share/workspace.js" "$WORK/band.js"
  { cat <<'JSEOF'
var CAPS = { waiting: 1, live: 1, launch: 1 }, BASE = 'http://127.0.0.1:1/t';
function can(c){ return !!CAPS[c]; }
function esc(s){ return String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;')
                   .replace(/>/g, '&gt;').replace(/"/g, '&quot;'); }
function shortRepo(p){ return (p || '?').split('/').pop() || '?'; }
function hits(){ return true; } function sessionScore(){ return { s: 0 }; }
var D = { sessions: {} }, sesScope = 'here', statted = 0, toasted = [], looked = 0, drawn = 0;
function stat(){ statted++; } function toast(m){ toasted.push(m); }
function lookAgain(){ looked++; }
function afterWaiting(){ drawn++; }
function openSession(){} var Shell = { refresh: function(){} };
var listeners = {};
var document = { hidden: false, bands: [], addEventListener: function(k, f){ (listeners[k] = listeners[k] || []).push(f); },
  querySelectorAll: function(sel){ return sel === '[data-wband]' ? this.bands : []; } };
var RB = { table: function(spec){ var f = function(){}; f.spec = spec; return f; } };
/* the server, held: each request waits for the test to answer it */
var asked = [];
function answer(i, ok, j){ var a = asked[i]; return ok ? a.cb(j) : a.fail(j); }
var realApi;
JSEOF
    cat "$WORK/band.js"
    cat <<'JSEOF'

realApi = api;
api = function(path, body, cb, fail){ asked.push({ path: path, body: body, cb: cb, fail: fail }); };
var fail = [];
function want(c, why){ if (!c) fail.push(why); }
var sid = 'aaaaaaaa-0000-4000-8000-000000000001', now = Math.floor(Date.now() / 1000);
RUN = {}; RUN[sid] = { sid: sid, on: 'working', status: 'busy', since: now - 252, pid: 9, name: 'harbour-3f' };

/* Send while it works: the question, inline, and nothing sent until it is answered */
var input = { value: 'also the neap tides', focus: function(){} };
sendReply(sid, input);
want(asked.length === 0, 'Send on a working session sent without asking');
var h = sendHTML(sid);
want(/Send while it works\?/.test(h) && /data-rsendok=/.test(h) && /data-rsendno=/.test(h),
     'the button did not turn into the question: ' + h);
var lifted = require('fs').readFileSync(process.argv[2], 'utf8');
want(!/\bconfirm\s*\(/.test(lifted), 'a browser confirm() dialog is used');
var el = { closest: function(){ return { querySelector: function(){ return input; } }; } };
REPLYVERBS.spec.rsendok(sid, el);
want(asked.length === 1 && asked[0].body.verb === 'reply' && asked[0].body.whileWorking === true &&
     asked[0].body.text === 'also the neap tides', 'the answer did not send the flag: ' + JSON.stringify(asked[0] && asked[0].body));
want(!replyOf(sid).ask, 'the question stayed after it was answered');
/* /signoff asks too, and names what it would send */
sendReply(sid, null, '/signoff');
want(asked.length === 1 && /Send <b>\/signoff<\/b> while it works\?/.test(sendHTML(sid)), '/signoff did not ask, by name');
REPLYVERBS.spec.rsendno(sid, el);
want(!replyOf(sid).ask && asked.length === 1, 'Cancel did not put the question away');
/* on your turn, no question and no flag */
RUN[sid].on = 'done'; RUN[sid].status = 'idle';
sendReply(sid, { value: 'go on' });
want(asked.length === 2 && !('whileWorking' in asked[1].body), 'a reply on your turn asked, or carried the flag');
/* the server found it working: the page asks, and sends nothing more */
answer(1, false, { status: 409, body: { refused: 'status', status: 'busy', error: 'it is working' } });
want(replyOf(sid).ask && asked.length === 2 && looked === 1, 'a refusal for working did not turn into the question');
/* an open question: Enter does not send, Escape puts it away */
var kd = listeners.keydown[0], stopped = 0, prevented = 0;
function key(k, target){ kd({ key: k, isComposing: false, target: target, preventDefault: function(){ prevented++; },
                               stopImmediatePropagation: function(){ stopped++; } }); }
var box = { dataset: { rbox: sid } };
var inp = { value: 'go on', closest: function(sel){ return /data-rin/.test(sel) && !/rbox/.test(sel) ? inp : box; } };
key('Enter', inp);
want(asked.length === 2, 'a second Enter answered the question');
key('Escape', inp);
want(!replyOf(sid).ask && stopped === 1, 'Escape did not put the question away, or let it through');

/* Stop: the question, and only its answer sends the key */
RUN[sid].on = 'working'; RUN[sid].status = 'busy';
want(/data-rstop=/.test(stopHTML(sid)) && !/Stop it\?/.test(stopHTML(sid)), 'Stop is not a button first');
REPLYVERBS.spec.rstop(sid, { closest: function(){ return null; } });
want(/Stop it\?/.test(stopHTML(sid)) && /data-rstopok=/.test(stopHTML(sid)) && /data-rstopno=/.test(stopHTML(sid)) &&
     asked.length === 2, 'Stop did not turn into its question, or sent before the answer');
REPLYVERBS.spec.rstopno(sid);
want(!STOPASK[sid] && asked.length === 2, 'Cancel sent a stop');
REPLYVERBS.spec.rstop(sid, { closest: function(){ return null; } });
REPLYVERBS.spec.rstopok(sid);
want(asked.length === 3 && asked[2].body.verb === 'stop' && asked[2].body.id === sid && !asked[2].body.text,
     'the answer did not send one stop, without words: ' + JSON.stringify(asked[2] && asked[2].body));

/* the band's words */
DOING[sid] = { j: { status: 'busy', since: now - 252, counted: true, whole: true, calls: 37, tokens: 30330,
                    now: [{ tool: 'Bash', what: 'Run the smoke suite' }], last: { tool: 'Read', what: 'a.md' } }, at: Date.now() };
var t = bandText(sid);
want(/>Working</.test(t) && /4m 1\ds/.test(t) && /37 tool calls/.test(t) && /30\.3k tokens written/.test(t) &&
     />Bash</.test(t) && /Run the smoke suite/.test(t), 'the band does not say what runs: ' + t);
DOING[sid].j.now = []; DOING[sid].j.whole = false;
t = bandText(sid);
want(/thinking/.test(t) && /after Read · a\.md/.test(t) && /at least 37 tool calls/.test(t), 'thinking, or "at least", is not said: ' + t);
DOING[sid].j.since = now - 9999;
want(/reading what it is doing/.test(bandText(sid)), 'a reading of another turn is shown as this one');
want(/class="quill"/.test(bandHTML(sid)) && !/ hidden/.test(bandHTML(sid).split('>')[0]), 'a working band has no quill, or is hidden');
RUN[sid].on = 'done';
want(/ hidden/.test(bandHTML(sid).split('>')[0]), 'the band shows for a session that is not working');
RUN[sid].on = 'working';

/* what it does is asked for a band on screen, in front, once at a time, every few seconds */
function band(shown){
  var part = { dataset: { wclock: String(now - 5) }, textContent: '', innerHTML: '',
               classList: { contains: function(){ return false; }, toggle: function(){} } };
  return { hidden: false, offsetParent: shown ? {} : null, dataset: { wband: sid },
           querySelector: function(){ return part; } };
}
DOING = {}; asked = [];
var T = Date.now(), realNow = Date.now; Date.now = function(){ return T; };
document.bands = [band(false)]; tickBands();
want(asked.length === 0, 'a band not on screen asked the server');
document.bands = [band(true)]; document.hidden = true; tickBands();
want(asked.length === 0, 'a window in the background asked the server');
document.hidden = false; tickBands(); tickBands();
want(asked.length === 1 && /^working\?id=/.test(asked[0].path), 'a band on screen did not ask, or asked twice at once');
answer(0, true, { status: 'busy', since: now - 252, now: [], counted: true, calls: 1 });
T += 1000; tickBands();
want(asked.length === 1, 'it asked again within a second');
T += DOING_EVERY; tickBands();
want(asked.length === 2, 'it did not ask again after a few seconds');
document.bands = [band(true), band(true)]; answer(1, true, {}); T += DOING_EVERY; tickBands();
want(asked.length === 3, 'two copies of one band asked twice');
Date.now = realNow;

/* Open now: the second line's names take what is left; elsewhere-but-here says so */
var row = openRow({ sid: 'b', pid: 1, on: 'working', status: 'busy', name: 'repositories-aa', cwd: '/Users/x/Repositories',
                    since: now - 60, first: 'tidy the notes', inRepo: true, worksHere: true, named: [9, 0] }, '', '');
want(/<span class="rwhere">started in ~\/Repositories, works here<\/span>/.test(row) && /class="dot working"><span class="quill mini"/.test(row),
     'a session working here does not say where it began, or wears no quill: ' + row);
var css = require('fs').readFileSync(process.argv[3], 'utf8');
want(/\.srow\.run \.rst\{[^}]*flex-wrap:nowrap/.test(css) && /\.srow\.run \.rst \.nms\{flex:1 1 0;[^}]*text-overflow:ellipsis/.test(css),
     'an Open now row\'s second line may wrap, or its names do not give way');

/* the server gone */
var realFetch = typeof fetch === 'function' ? fetch : null;
globalThis.fetch = function(){ return Promise.reject(new TypeError('Failed to fetch')); };
GONE = 0; WAIT = { allowed: true, state: 'ok', sessions: [] }; asked = [];
api = realApi;
loadWaiting(false);
setTimeout(function(){
  want(GONE && statted > 0, 'a request that reached nothing did not mark the server gone');
  want(WAIT.state === 'gone' && /md\u2019s server has stopped; run md again/.test(runTrouble()) &&
       /data-wlook/.test(runTrouble()) && /no answer at \d\d:\d\d:\d\d/.test(runTrouble()) &&
       !/did not answer/.test(runTrouble()), 'a server that has gone is not said plainly: ' + runTrouble());
  var first = WAIT.at, fetched = 0;
  globalThis.fetch = function(){ fetched++; return Promise.reject(new TypeError('Failed to fetch')); };
  lookAgainNow();
  want(/Looking again/.test(runTrouble()) && fetched === 1, 'look again did not look, or did not say so');
  setTimeout(function(){
    want(WAIT.state === 'gone' && WAIT.at >= first && !WAIT.looking, 'looking again did not say what came of it');
    /* a look that never came back does not hold the next one for good */
    globalThis.fetch = function(){ fetched++; return new Promise(function(){}); };
    loadWaiting(false); loadWaiting(false);
    want(fetched === 2, 'a second look went while the first was out');
    var T0 = Date.now(), rn = Date.now; Date.now = function(){ return T0 + 16000; };
    loadWaiting(false);
    Date.now = rn;
    want(fetched === 3, 'a look that never came back held the next one');
    globalThis.fetch = function(){ return Promise.resolve({ ok: true, json: function(){ return Promise.resolve({ ok: 1 }); } }); };
    realApi('ping', {}, function(){
      want(!GONE, 'an answer did not clear the server gone');
      console.log(fail.length ? 'XX ' + fail.join('; ') : 'ok');
    });
  }, 20);
}, 20);
JSEOF
  } > "$WORK/band-run.js"
  res=$(node "$WORK/band-run.js" "$WORK/band.js" "$REPO/share/workspace.html" 2>&1)
  case "$res" in ok*) ok "37 · the band, Send's and Stop's questions, and a server that has gone, on the page" ;;
                 *)   no "37 · the page's band or its questions are wrong" "$res" ;; esac
else
  skip "37 · the band on the page" "no node"
fi

# ── 38 · the server stays while its window does ─────────────────────────────
# A window in the background, or on a Mac that slept, sends no heartbeat — the
# browser holds its timers back — and the server used to stop under it after
# its idle time, leaving a window whose every request reached nothing. A
# window holds its event stream open for as long as it is open, so the server
# lives while any stream is open, and stops once none is and nothing has asked
# for the idle time. Pinned, with an idle time of one second:
#
#   - a stream open well past the idle time keeps the server, with no request
#   - once it closes, the server stops within a few idle times
#   - with no stream and no request, the server stops
python3 - "$WORK" "$REPO" >"$WORK/stays.txt" 2>&1 <<'PYEOF'
import os, socket, subprocess, sys, time, urllib.request
from pathlib import Path
work, repo_root = sys.argv[1], sys.argv[2]
repo = os.path.join(work, "stays"); os.makedirs(repo, exist_ok=True)
open(os.path.join(repo, "README.md"), "w").write("# stays\n")
subprocess.run(["git", "-C", repo, "init", "-q"], check=True)
sys.path.insert(0, os.path.join(repo_root, "share"))
import workspace as W
share = Path(repo_root) / "share"
checks = {}
def stopped_within(srv, secs):
    end = time.time() + secs
    while time.time() < end:
        if srv.stop.is_set(): return True
        time.sleep(0.1)
    return srv.stop.is_set()
srvs = []
try:
    srv = W.serve_workspace([repo], False, share, "", idle=1); srvs.append(srv)
    s = socket.create_connection(("127.0.0.1", srv.port), timeout=5)
    s.sendall(("GET /%s/events HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n" % srv.token).encode())
    got = b""
    while b": watching" not in got:
        got += s.recv(4096)
    checks["a window's stream opens"] = b"200" in got.split(b"\r\n", 1)[0]
    time.sleep(4)
    checks["a stream open past the idle time keeps the server"] = not srv.stop.is_set() and srv.streams == 1
    s.settimeout(3)
    try:
        heard = s.recv(4096)
    except socket.timeout:
        heard = b""
    checks["the stream says it is there while nothing changes"] = b": here" in heard
    s.close()
    checks["once the window's stream closes, the server stops"] = stopped_within(srv, 8) and srv.streams == 0
    lone = W.serve_workspace([repo], False, share, "", idle=1); srvs.append(lone)
    checks["with no stream and no request the server stops"] = stopped_within(lone, 4)
except Exception as e:
    import traceback; traceback.print_exc()
    checks["the test ran: %s" % e] = False
finally:
    for s_ in srvs:
        s_.stop.set()
        try: s_.httpd.shutdown()
        except Exception: pass
for k, v in checks.items(): print(("ok " if v else "XX ") + k)
sys.exit(0 if checks and all(checks.values()) else 1)
PYEOF
if [ $? = 0 ]; then
  ok "38 · the server lives while a window holds its stream open, and stops when none does"
else
  no "38 · the server's lifetime is wrong" "$(grep '^XX' "$WORK/stays.txt" | tr '\n' ' ')$(tail -2 "$WORK/stays.txt")"
fi

# ── 39 · a session started elsewhere that works here is this repository's ───
# A session belongs to the repository it was started in, and to the one it
# works in: started in a folder above a checkout and working on that checkout
# and its trees, its cwd says nothing, and the places its latest tool calls
# work in say where it is. Pinned, on sessions started in the folder above the
# repository:
#
#   - one whose calls work in the repository and its worktree counts as the
#     repository's, says it works here and how the vote went, working or not,
#     and a working one still has no reply read
#   - one whose calls work mostly elsewhere stays out, as does one with too
#     few calls here to say
#   - scratch space and the tools' own folders do not vote
#   - one started in the repository counts by its cwd, as before
python3 - "$WORK" "$REPO" >"$WORK/workshere.txt" 2>&1 <<'PYEOF'
import json, os, subprocess, sys, time
work, repo_root = sys.argv[1], sys.argv[2]
home = os.environ["HOME"]
above = os.path.join(home, "Repositories")
repo = os.path.join(above, "harbour"); tree = os.path.join(above, "harbour-trees", "tides")
other = os.path.join(above, "lighthouse")
os.makedirs(repo, exist_ok=True); os.makedirs(other, exist_ok=True)
def git(*a): subprocess.run(["git", "-C", repo] + list(a), check=True, capture_output=True)
open(os.path.join(repo, "README.md"), "w").write("# harbour\n")
git("init", "-q"); git("add", "."); git("-c", "user.name=s", "-c", "user.email=s@s", "commit", "-qm", "one")
git("worktree", "add", "-q", "--detach", tree)
base = os.path.join(work, "workshere")
sdir = os.path.join(base, "sessions"); os.makedirs(sdir, exist_ok=True)
pdir = os.path.join(base, "projects", "-above"); os.makedirs(pdir, exist_ok=True)
os.environ.update(RUBRICATOR_CLAUDE_SESSIONS=sdir, RUBRICATOR_CLAUDE_PROJECTS=os.path.join(base, "projects"),
                  RUBRICATOR_CLAUDE_HISTORY=os.path.join(base, "history.jsonl"))
bindir = os.path.join(base, "bin"); os.makedirs(bindir, exist_ok=True)
fake = os.path.join(bindir, "claude"); os.symlink("/bin/sleep", fake)
procs = []
def sid(n): return "%08d-0000-4000-8000-%012d" % (n, n)
def session(n, status, cwd, calls):
    p = subprocess.Popen([fake, "300"]); procs.append(p)
    open(os.path.join(sdir, "%d.json" % p.pid), "w").write(json.dumps(
        {"pid": p.pid, "sessionId": sid(n), "status": status, "cwd": cwd, "name": "s-%d" % n,
         "statusUpdatedAt": int(time.time() * 1000) - 60000}))
    recs = []
    for i, (name, inp, shell) in enumerate(calls):
        recs.append({"type": "assistant", "cwd": shell or cwd, "timestamp": "2026-10-28T12:00:%02d.000Z" % i,
                     "message": {"id": "m%d" % i, "content": [{"type": "tool_use", "id": "t%d" % i, "name": name, "input": inp}]}})
        recs.append({"type": "user", "cwd": shell or cwd, "timestamp": "2026-10-28T12:00:%02d.500Z" % i,
                     "message": {"content": [{"type": "tool_result", "tool_use_id": "t%d" % i, "content": "ok"}]}})
    recs.append({"type": "assistant", "cwd": cwd, "timestamp": "2026-10-28T12:01:00.000Z",
                 "message": {"id": "end", "content": [{"type": "text", "text": "DONE-%d" % n}]}})
    open(os.path.join(pdir, sid(n) + ".jsonl"), "w").write("".join(json.dumps(r) + "\n" for r in recs))
here = [("Read", {"file_path": repo + "/README.md"}, None),
        ("Edit", {"file_path": tree + "/src/tide.ts"}, None),
        ("Bash", {"command": "cd %s && git status" % repo, "description": "status"}, None),
        ("Bash", {"command": "sed -n 1,20p src/tide.ts", "description": "read"}, tree),   # the shell is in the tree
        ("Bash", {"command": "ls /tmp/scratch ~/.claude/x /private/tmp/y", "description": "scratch"}, None)]
session(1, "idle", above, here)                                        # started above, works here
session(2, "busy", above, here)                                        # the same, working
session(3, "idle", above, here[:3] + [("Read", {"file_path": other + "/a.md"}, None)] * 4 +
        [("Bash", {"command": "cat %s/b.md %s/c.md" % (other, other), "description": "x"}, None)])
session(4, "idle", above, here[:2])                                    # two here: too few to say
session(5, "idle", above, [("Bash", {"command": "cat /tmp/a /private/tmp/b ~/.claude/c ~/Library/d", "description": "x"}, None)] * 6)
session(6, "idle", repo, [("Read", {"file_path": other + "/a.md"}, None)] * 5)   # started here, works elsewhere
checks = {}
try:
    sys.path.insert(0, os.path.join(repo_root, "share"))
    import waiting as Wt
    rows = {r["sid"]: r for r in Wt.running([repo])["sessions"]}
    one, two = rows.get(sid(1), {}), rows.get(sid(2), {})
    checks["started above, working here, it is this repository's"] = one.get("inRepo") is True and one.get("worksHere") is True
    checks["and how the vote went, and where it began, come along"] = (
        one.get("named") == [4, 0] and one.get("began") == "~/Repositories")
    checks["working, too, with no reply read"] = (two.get("inRepo") is True and two.get("worksHere") is True
                                                  and "text" not in two)
    checks["three calls here but most elsewhere, it stays out"] = rows.get(sid(3), {}).get("inRepo") is False
    checks["too few calls here to say, it stays out"] = rows.get(sid(4), {}).get("inRepo") is False
    checks["scratch space and the tools' folders do not vote"] = rows.get(sid(5), {}).get("inRepo") is False
    six = rows.get(sid(6), {})
    checks["started here, it counts by its cwd, as before"] = six.get("inRepo") is True and "worksHere" not in six
    checks["the other repository's list does not take what works here"] = (
        {r["sid"]: r for r in Wt.running([other])["sessions"]}.get(sid(1), {}).get("inRepo") is False)
except Exception as e:
    import traceback; traceback.print_exc()
    checks["the test ran: %s" % e] = False
finally:
    for q in procs: q.terminate()
for k, v in checks.items(): print(("ok " if v else "XX ") + k)
sys.exit(0 if checks and all(checks.values()) else 1)
PYEOF
if [ $? = 0 ]; then
  ok "39 · a session started elsewhere that works here is this repository's, and says so"
else
  no "39 · where a session works is read wrong" "$(grep '^XX' "$WORK/workshere.txt" | tr '\n' ' ')$(tail -2 "$WORK/workshere.txt")"
fi

# ── 40 · the pictures in a conversation are found where they happened ───────
# A conversation carries pictures three ways, in the shapes read off this
# machine's transcripts (transcript.py's `images_of` lists them): an image block
# in a tool's result, an image block beside your prompt's "[Image #1]" with a
# note after it naming the file it was saved to, and a path to an image in
# Claude's words or a subagent's report. Pinned:
#
#   40a, the reading:
#   - your paste is under your prompt, and its note marks nothing; a note whose
#     prompt carried no image marks the paste, with the file it names
#   - a tool's image is on that tool's line, and the harness's note on its size
#     marks nothing
#   - the paths Claude names are under its words, in order, with whether each
#     can be shown: there, gone, too large; a URL's tail is not a path
#   - a subagent's report shows the screenshot it names
#   - every picture is named by its place, and its place serves its bytes
#
#   40b, the server: by place and by nothing else. A path the page sends is not
#   read; a file the transcript does not name is served from no place; a file it
#   names is served only while it is an image file on disk under the size cap;
#   a place that is not a line's start, or a logged request's line, serves
#   nothing; the right type, no caching, inert on its own; and the page's own
#   content security policy is the one it was
python3 - "$WORK" "$REPO" >"$WORK/pictures.txt" 2>&1 <<'PYEOF'
import base64, json, os, struct, sys, zlib
work, repo_root = sys.argv[1], sys.argv[2]
home = os.environ["HOME"]
base = os.path.join(work, "media"); os.makedirs(os.path.join(base, "images"), exist_ok=True)
sys.path.insert(0, os.path.join(repo_root, "share"))
import transcript as T

def png(w, h, rgb):
    raw = b"".join(b"\x00" + bytes(rgb) * w for _ in range(h))
    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) +
            chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))
def put(name, data):
    p = os.path.join(base, name); open(p, "wb").write(data); return p
PASTED, TOOL = png(3, 2, (0, 0, 255)), png(4, 4, (0, 255, 0))
shot = put("shot-on-disk.png", png(5, 3, (255, 0, 0)))
gone = os.path.join(base, "shot-gone.png")
big = put("shot-big.png", png(1, 1, (1, 1, 1)))
with open(big, "r+b") as f: f.truncate(T.IMAGE_MAX + 4096)          # sparse: large on paper only
fake = put("shot-fake.png", b"<html>not a picture</html>")
notes = put("notes.txt", b"plain words")
link = os.path.join(base, "shot-link.png"); os.symlink(notes, link)
unnamed = put("never-named.png", png(2, 2, (9, 9, 9)))
agent_shot = put("agent-shot.png", png(6, 2, (0, 99, 99)))
src1 = put("images/1.png", PASTED)
src2 = put("images/2.png", png(7, 7, (77, 0, 77)))

def b64(d): return {"type": "base64", "media_type": "image/png", "data": base64.b64encode(d).decode()}
def rec(kind, content, **kw):
    r = {"type": kind, "isSidechain": False, "timestamp": "2026-10-28T12:00:00.000Z", "cwd": base,
         "message": {"role": kind, "content": content}}
    r.update(kw); return r
recs = [
    rec("user", [{"type": "text", "text": "look at this [Image #1]"}, {"type": "image", "source": b64(PASTED)}],
        promptSource="typed"),
    rec("user", [{"type": "text", "text": "[Image: source: %s]" % src1}], isMeta=True),
    rec("assistant", [{"type": "tool_use", "id": "tu1", "name": "Read", "input": {"file_path": "/x/seen.png"}}]),
    rec("user", [{"type": "tool_result", "tool_use_id": "tu1", "content": [{"type": "image", "source": b64(TOOL)}]}]),
    rec("user", "[Image: original 2880x1800, displayed at 2000x1250. Multiply coordinates by 1.44.]", isMeta=True),
    {"type": "api-request", "content": [{"type": "image", "source": b64(png(8, 8, (1, 2, 3)))}]},
    rec("assistant", [{"type": "text", "text": "Saved `%s`, and %s, also %s,\n%s and (%s); the page "
                       "is at https://example.com/a/b.png and file:///x/y.png" % (shot, gone, big, fake, link)}]),
    rec("user", 'Another Claude session sent a message:\n<agent-message from="a1">\n[Subagent hand-back] '
        'The report follows:\n  Screens:\n  - `%s`: the main one\n</agent-message>' % agent_shot,
        promptSource="system", isMeta=True, origin={"kind": "peer", "name": "Explore", "handback": True}),
    rec("user", [{"type": "text", "text": "and this one [Image #2]"}], promptSource="typed"),
    rec("user", [{"type": "text", "text": "[Image: source: %s]" % src2}], isMeta=True),
    rec("user", [{"type": "tool_result", "tool_use_id": "tu9", "content": [{"type": "image", "source": b64(TOOL)}]}],
        isSidechain=True),
    rec("assistant", [{"type": "text", "text": "Done."}]),
]
sid = "44444444-0000-4000-8000-000000000004"
pdir = os.path.join(home, ".claude", "projects", "-media-fixture"); os.makedirs(pdir, exist_ok=True)
path = os.path.join(pdir, sid + ".jsonl")
# written as Claude Code writes them, without spaces: the readers look for
# what a line holds by its bytes before they parse it
open(path, "w").write("\n".join(json.dumps(r, separators=(",", ":")) for r in recs) + "\n")

checks = {}
try:
    got = T.read(sid)
    turns = got["turns"]
    json.dump(got, open(os.path.join(base, "convo.json"), "w"))
    you = [t for t in turns if t["who"] == "you"]
    marks = [t for t in turns if t["who"] == "mark"]
    claude = [t for t in turns if t["who"] == "claude"]
    notes_ = [t for t in turns if t["who"] == "note"]
    checks["your paste is under your prompt"] = (
        len(you) == 2 and [s["k"] for s in you[0].get("imgs", [])] == ["pasted"] and not you[1].get("imgs"))
    checks["a paste whose prompt carried it marks nothing; one that did not marks it, with its file"] = (
        [m["text"] for m in marks] == ["you pasted an image"] and
        [(s["k"], s["name"], s["state"]) for s in marks[0].get("imgs", [])] == [("source", "2.png", "ok")])
    tools = [x for t in claude for x in t.get("tools", [])]
    checks["a tool's image is on its line"] = (
        len(tools) == 1 and [(s["k"], s["tool"]) for s in tools[0].get("imgs", [])] == [("tool", "Read")])
    named = [(s["name"], s["state"]) for t in claude for s in t.get("imgs", [])]
    checks["the paths Claude names are under its words, in order, with whether each can be shown"] = named == [
        ("shot-on-disk.png", "ok"), ("shot-gone.png", "gone"), ("shot-big.png", "big"),
        ("shot-fake.png", "ok"), ("shot-link.png", "ok")]
    checks["a subagent's report shows what it names"] = (
        len(notes_) == 1 and [s["name"] for s in notes_[0].get("imgs", [])] == ["agent-shot.png"])
    checks["a sidechain's and a logged request's images are not the conversation's"] = (
        sum(len(t.get("imgs", [])) + sum(len(x.get("imgs", [])) for x in t.get("tools", [])) for t in turns) == 9)
    # every place serves its own bytes
    want = {("pasted", None): PASTED, ("tool", None): TOOL, ("source", "2.png"): open(src2, "rb").read(),
            ("path", "shot-on-disk.png"): open(shot, "rb").read(), ("path", "agent-shot.png"): open(agent_shot, "rb").read()}
    places = [s for t in turns for s in t.get("imgs", [])] + [s for x in tools for s in x.get("imgs", [])]
    served = {}
    for s in places:
        key = (s["k"], s.get("name"))
        if key in want:
            data, mime = T.image(sid, s["at"], s["i"])
            served[key] = data == want[key] and mime == "image/png"
    checks["every picture's place serves its bytes"] = len(served) == len(want) and all(served.values())
    checks["no picture carries its bytes or its file to the page"] = (
        "data" not in json.dumps(places) and all(set(s) <= {"at", "i", "k", "state", "name", "where", "tool", "about"}
                                                for s in places))
    json.dump({"sid": sid, "shot": shot, "gone": gone, "big": big, "fake": fake, "link": link,
               "unnamed": unnamed, "places": places, "path": path,
               "bytes": {"shot": base64.b64encode(open(shot, "rb").read()).decode(),
                         "unnamed": base64.b64encode(open(unnamed, "rb").read()).decode()}},
              open(os.path.join(base, "fixture.json"), "w"))
except Exception as e:
    import traceback; traceback.print_exc()
    checks["the test ran: %s" % e] = False
for k, v in checks.items(): print(("ok " if v else "XX ") + k)
sys.exit(0 if checks and all(checks.values()) else 1)
PYEOF
if [ $? = 0 ]; then
  ok "40a · a paste, a tool's screenshot and a path Claude names are each found where they happened"
else
  no "40a · a picture is found in the wrong place, or not at all" "$(grep '^XX' "$WORK/pictures.txt" | tr '\n' ' ')$(tail -2 "$WORK/pictures.txt")"
fi

python3 - "$MD" "$WORK" >"$WORK/pictures-served.txt" 2>&1 <<'PYEOF'
import base64, json, os, re, socket, subprocess, sys, time, urllib.error, urllib.request
md, work = sys.argv[1], sys.argv[2]
fx = json.load(open(os.path.join(work, "media", "fixture.json")))
sid, places = fx["sid"], fx["places"]
repo = os.path.join(work, "media-repo"); os.makedirs(repo, exist_ok=True)
open(os.path.join(repo, "README.md"), "w").write("# pictures\n")

def free_port():
    s = socket.socket(); s.bind(("127.0.0.1", 0)); p = s.getsockname()[1]; s.close(); return p
port = free_port()
env = dict(os.environ, RUBRICATOR_NO_WINDOW="1", RUBRICATOR_NO_WATCH="1")
p = subprocess.Popen([md, "serve", "--port", str(port), repo], env=env,
                     stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
os.set_blocking(p.stdout.fileno(), False)
seen, url = "", None
for _ in range(200):
    time.sleep(0.1)
    try: seen += p.stdout.read() or ""
    except BlockingIOError: pass
    m = re.search(r"(http://127\.0\.0\.1:%d/[A-Za-z0-9_-]+/)" % port, seen)
    if m: url = m.group(1); break

def get(q):
    try:
        r = urllib.request.urlopen(url + q, timeout=30)
        return r.status, dict(r.headers), r.read()
    except urllib.error.HTTPError as e:
        return e.code, dict(e.headers), e.read()
def why(body):
    try: return json.loads(body).get("error", "")
    except Exception: return ""
def place(name):
    return next(s for s in places if s.get("name") == name)
def at(s, **extra):
    q = "image?id=%s&at=%d&i=%d" % (sid, s["at"], s["i"])
    return q + "".join("&%s=%s" % (k, urllib.request.quote(v)) for k, v in extra.items())

checks = {}
try:
    checks["the server came up"] = bool(url)
    shot = base64.b64decode(fx["bytes"]["shot"]); unnamed = base64.b64decode(fx["bytes"]["unnamed"])
    code, hdr, body = get(at(place("shot-on-disk.png")))
    checks["a picture is served by its place, as what it is"] = (
        code == 200 and body == shot and hdr.get("Content-Type") == "image/png")
    checks["uncached, and inert opened on its own"] = (
        hdr.get("Cache-Control") == "no-store" and "sandbox" in (hdr.get("Content-Security-Policy") or "")
        and hdr.get("X-Content-Type-Options") == "nosniff")
    # a path the page sends is not read: alone it names nothing, beside a place it changes nothing
    code, _, body = get("image?id=%s&path=%s" % (sid, urllib.request.quote(fx["unnamed"])))
    checks["refused: a path sent by the page, alone"] = code == 400 and body != unnamed
    code, _, body = get(at(place("shot-on-disk.png"), path=fx["unnamed"], p=fx["unnamed"], file=fx["unnamed"]))
    checks["refused: a path sent by the page beside a place — the place decides"] = code == 200 and body == shot
    # a file the transcript does not name is served from no place in it
    lines, pos = [], 0
    for ln in open(fx["path"], "rb"):
        lines.append(pos); pos += len(ln)
    reached = [get("image?id=%s&at=%d&i=%d" % (sid, a, i)) for a in lines for i in range(4)]
    checks["refused: a path not in the transcript, from any place"] = not any(b == unnamed for _, _, b in reached)
    code, _, body = get(at(place("shot-gone.png")))
    checks["refused: a missing file, and says so"] = code == 404 and "no longer on disk" in why(body)
    code, _, body = get(at(place("shot-big.png")))
    checks["refused: an oversize one"] = code == 413 and "too large" in why(body)
    code, _, body = get(at(place("shot-fake.png")))
    checks["refused: a non-image wearing .png"] = code == 415 and "not an image" in why(body)
    code, _, body = get(at(place("shot-link.png")))
    checks["refused: a link from a .png to words"] = code == 415 and "not an image" in why(body)
    req = lines[5]                                   # the logged API request's line
    code, _, body = get("image?id=%s&at=%d&i=0" % (sid, req))
    checks["refused: a logged request's line"] = code == 404
    s = place("shot-on-disk.png")
    code, _, _ = get("image?id=%s&at=%d&i=%d" % (sid, s["at"] + 1, s["i"]))
    checks["refused: a place inside a line"] = code == 404
    checks["refused: a negative place, a word for a place, a place past the end"] = (
        get("image?id=%s&at=-1&i=0" % sid)[0] == 400 and get("image?id=%s&at=x&i=0" % sid)[0] == 400
        and get("image?id=%s&at=%d&i=0" % (sid, pos + 10))[0] == 404)
    checks["refused: a session id that is not one"] = get("image?id=..%2Fetc&at=0&i=0")[0] == 400
    code, hdr, body = get("")
    csp = hdr.get("Content-Security-Policy") or ""
    checks["the page's own policy is the one it was"] = re.fullmatch(
        r"default-src 'none'; script-src 'nonce-[A-Za-z0-9_-]+' 'unsafe-eval'; style-src 'unsafe-inline'; "
        r"img-src 'self' data: blob:; font-src data:; connect-src 'self'; base-uri 'none'; "
        r"form-action 'none'; frame-ancestors 'none'", csp) is not None
except Exception as e:
    import traceback; traceback.print_exc()
    checks["the test ran: %s" % e] = False
finally:
    p.kill()
for k, v in checks.items(): print(("ok " if v else "XX ") + k)
sys.exit(0 if checks and all(checks.values()) else 1)
PYEOF
if [ $? = 0 ]; then
  ok "40b · a picture is served by its place in the transcript, and a path the page sends is never read"
else
  no "40b · the image route serves what it should not, or refuses what it should serve" "$(grep '^XX' "$WORK/pictures-served.txt" | tr '\n' ' ')$(tail -2 "$WORK/pictures-served.txt")"
fi

# ── 41 · what a session published, one row per artifact ─────────────────────
# Claude Code's Artifact tool publishes a page to claude.ai; an update keeps the
# url, sometimes from another file. The fixture is in the shapes read off this
# machine's transcripts (transcript.py's comment over `Published`). Pinned:
#   - one artifact per url, counting its successful publishes: a failed one, a
#     read, a quickstart, an asset upload, a sidechain's and a logged request's
#     copy count for nothing, and neither does a url that is not claude.ai's
#   - a result with no structured part is read from its words
#   - parallel calls are each answered
#   - its title is its file's <title>, the published one once the file is gone
#   - the index counts them on the session, and the route and the source agree
#   - the source is the file the call named, by number; a path sent is not read
python3 - "$MD" "$WORK" "$REPO" >"$WORK/artifacts.txt" 2>&1 <<'PYEOF'
import json, os, re, socket, subprocess, sys, time, urllib.error, urllib.request
md, work, repo_root = sys.argv[1], sys.argv[2], sys.argv[3]
home = os.environ["HOME"]
base = os.path.join(work, "arts"); os.makedirs(base, exist_ok=True)
sys.path.insert(0, os.path.join(repo_root, "share"))
import transcript as T
def page(name, title, body="<p>hello</p>"):
    d = os.path.join(base, name); os.makedirs(d, exist_ok=True)
    p = os.path.join(d, "index.html")
    open(p, "w").write("<!doctype html><html><head><title>%s</title></head><body>%s</body></html>" % (title, body))
    return p
A1, A2, B = page("a", "Alpha Page"), page("a2", "Alpha &amp; Again"), page("b", "Beta")
G = os.path.join(base, "gone", "index.html")
U = {k: "https://claude.ai/artifact/%sXYZ" % k for k in "ABGS"}
n = [0]
def ts():
    n[0] += 1; return "2026-10-28T1%d:%02d:00.000Z" % (n[0] // 60, n[0] % 60)
def call(tid, inp, side=False, **more):
    calls = [(tid, inp)] + list(more.get("also", []))
    return {"type": "assistant", "isSidechain": side, "timestamp": ts(), "cwd": base,
            "message": {"role": "assistant", "content": [{"type": "tool_use", "id": t, "name": "Artifact", "input": i}
                                                          for t, i in calls]}}
def result(tid, url=None, path=None, title=None, err=False, words=None, side=False):
    tur = {"url": url, "path": path, "title": title, "seq": 1} if url and words is None else None
    said = words or ("Published %s at %s (Version 1)" % (path, url) if url else "Done.")
    return {"type": "user", "isSidechain": side, "timestamp": ts(), "cwd": base, "toolUseResult": tur,
            "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": tid, "is_error": err,
                                                     "content": [{"type": "text", "text": said}]}]}}
recs = [
    call("a1", {"file_path": A1, "icon": "chart"}), result("a1", U["A"], A1, "Alpha (published)"),
    {"type": "api-request", "content": [{"type": "tool_use", "id": "a1", "name": "Artifact", "input": {"file_path": A1}}]},
    call("a2", {"file_path": A1}), dict(result("a2", err=True, words="Refused: a newer version of %s was "
                                                "published elsewhere. Nothing was published." % U["A"]),
                                         toolUseResult={"url": U["A"], "path": A1, "refused": "conflict"}),
    call("a3", {"file_path": A1}), result("a3", U["A"], A1, "Alpha (published)"),
    call("q", {"action": "quickstart", "intent": "other"}), result("q", words="Start from the Dashboard type."),
    call("r", {"action": "read", "url": U["B"]}), result("r", U["B"], B, "Beta"),
    call("b", {"file_path": B}), result("b", words="Published %s at %s (Version 1, version id 1)" % (B, U["B"])),
    call("a4", {"action": "publish", "url": U["A"], "file_path": A2}), result("a4", U["A"], A2, "Alpha (published)"),
    call("g", {"file_path": G}), result("g", U["G"], G, "Gamma (published)"),
    call("s", {"file_path": B}, side=True), result("s", U["S"], B, "Side", side=True),
    call("up", {"asset": True, "url": U["A"], "file_path": os.path.join(base, "x.png")}), result("up", U["A"], A1),
    call("x", {"file_path": B}), result("x", "https://evil.example/artifact/x", B, "Elsewhere"),
    call("p1", {"file_path": B}, also=[("p2", {"file_path": A2})]),
    {"type": "user", "timestamp": ts(), "cwd": base, "message": {"role": "user", "content": [
        {"type": "tool_result", "tool_use_id": "p1", "content": "Published %s at %s (Version 2)" % (B, U["B"])},
        {"type": "tool_result", "tool_use_id": "p2", "content": "Published %s at %s (Version 4)" % (A2, U["A"])}]}},
]
sid = "55555555-0000-4000-8000-000000000005"
pdir = os.path.join(home, ".claude", "projects", "-arts-fixture"); os.makedirs(pdir, exist_ok=True)
open(os.path.join(pdir, sid + ".jsonl"), "w").write("\n".join(json.dumps(r, separators=(",", ":")) for r in recs) + "\n")

def free_port():
    s = socket.socket(); s.bind(("127.0.0.1", 0)); p = s.getsockname()[1]; s.close(); return p
checks, p = {}, None
try:
    got = T.artifacts(sid)
    arts = got["artifacts"]
    json.dump(dict(got, sid=sid), open(os.path.join(base, "arts.json"), "w"))
    by = {a["url"]: a for a in arts}
    checks["one row per artifact, in the order first published"] = [a["url"] for a in arts] == [U["A"], U["B"], U["G"]]
    checks["each counts its publishes, and nothing else"] = [a["count"] for a in arts] == [4, 2, 1]
    checks["its title is its file's, the published one once the file has gone"] = (
        [a["title"] for a in arts] == ["Alpha & Again", "Beta", "Gamma (published)"])
    checks["whether its source can be opened"] = [a["source"] for a in arts] == ["ok", "ok", "gone"]
    checks["when it was last published"] = by[U["A"]]["last"] == T.stamp(recs[-1]) and by[U["A"]]["last"] > by[U["A"]]["first"]
    import workspace as W
    W.HOME = T.Path(home)
    _, meta, _ = W.load_sessions()
    checks["the index counts them on the session"] = meta.get(sid, {}).get("arts") == 3

    port = free_port()
    repo = os.path.join(work, "arts-repo"); os.makedirs(repo, exist_ok=True)
    open(os.path.join(repo, "README.md"), "w").write("# arts\n")
    p = subprocess.Popen([md, "serve", "--port", str(port), repo],
                         env=dict(os.environ, RUBRICATOR_NO_WINDOW="1", RUBRICATOR_NO_WATCH="1"),
                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    os.set_blocking(p.stdout.fileno(), False)
    seen, url = "", None
    for _ in range(200):
        time.sleep(0.1)
        try: seen += p.stdout.read() or ""
        except BlockingIOError: pass
        m = re.search(r"(http://127\.0\.0\.1:%d/[A-Za-z0-9_-]+/)" % port, seen)
        if m: url = m.group(1); break
    def get(q):
        try:
            return 200, json.load(urllib.request.urlopen(url + q, timeout=30))
        except urllib.error.HTTPError as e:
            return e.code, json.load(e)
    code, j = get("artifacts?id=" + sid)
    checks["the route says the same"] = code == 200 and [a["count"] for a in j["artifacts"]] == [4, 2, 1]
    code, j = get("artifact?id=%s&n=0" % sid)
    checks["the source is the file its last publish named"] = (
        code == 200 and "Alpha &amp; Again" in j["text"] and j["kind"] == "html" and j["count"] == 4)
    code, j = get("artifact?id=%s&n=1&path=%s&file=%s" % (sid, urllib.request.quote(A1), urllib.request.quote(A1)))
    checks["a path sent beside the number is not read"] = code == 200 and "<title>Beta</title>" in j["text"]
    code, j = get("artifact?id=%s&n=2" % sid)
    checks["refused: a source whose file is gone"] = code == 404 and "no longer on disk" in j.get("error", "")
    checks["refused: a number it did not publish, or none"] = (
        get("artifact?id=%s&n=3" % sid)[0] == 404 and get("artifact?id=%s&n=-1" % sid)[0] == 400
        and get("artifact?id=%s&n=x" % sid)[0] == 400 and get("artifact?id=..&n=0")[0] == 400)
except Exception as e:
    import traceback; traceback.print_exc()
    checks["the test ran: %s" % e] = False
finally:
    if p: p.kill()
for k, v in checks.items(): print(("ok " if v else "XX ") + k)
sys.exit(0 if checks and all(checks.values()) else 1)
PYEOF
if [ $? = 0 ]; then
  ok "41 · what a session published is one row per artifact, counted, titled, and its source by number"
else
  no "41 · a session's artifacts are folded or served wrong" "$(grep '^XX' "$WORK/artifacts.txt" | tr '\n' ' ')$(tail -2 "$WORK/artifacts.txt")"
fi

# ── 42 · the thumbnails and the lightbox, on the page ───────────────────────
# Lifted from the shipped source around a stand-in for the DOM, and fed the
# conversation test 40 read. Pinned:
#   - a picture is a thumbnail asking for its place, never a path; one that
#     cannot be shown says why in its place; a tool's line opens its picture
#   - a thumbnail opens the lightbox on it, with how many the session has
#   - the arrows step through the session's pictures, round from either end
#   - Escape closes it, and so does a click anywhere but on its arrows
#   - while open it has the keys to itself; closed, it takes none
#   - a thumbnail that would not load says so, and is stepped past
if command -v node >/dev/null && [ -s "$WORK/media/convo.json" ]; then
  python3 -c 'import sys
src = open(sys.argv[1]).read()
def sl(a, b):
    i = src.index(a); return src[i:src.index(b, i)]
open(sys.argv[2], "w").write("\n".join([
    sl("function renderConvo(c)", "function didHTML(t)"),
    sl("function didHTML(t)", "function clock(ts)"),
    sl("/* ── the lightbox", "/* ── an artifact"),
]))' "$REPO/share/workspace.js" "$WORK/shots.js"
  { cat <<'JSEOF'
var BASE = 'http://127.0.0.1:1/t';
function esc(s){ return String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;')
                   .replace(/>/g, '&gt;').replace(/"/g, '&quot;'); }
var marked = { parse: function(t){ return '<p>' + esc(t) + '</p>'; } };
var MD = { sanitise: function(){} };
var document = { createElement: function(){ return { set innerHTML(v){ this._h = v; }, get innerHTML(){ return this._h; } }; } };
function clock(){ return '12:00'; }
function docBy(){ return null; }
var toasts = [];
function toast(m){ toasts.push(m); }
/* the lightbox's own elements */
function El(id){ return { id: id, hidden: true, src: '', textContent: '', cls: {},
  classList: { add: function(c){ this.o.cls[c] = 1; }, remove: function(c){ delete this.o.cls[c]; } },
  removeAttribute: function(k){ if (k === 'src') this.src = ''; } }; }
var els = {};
['shotbox', 'shot-img', 'shot-cap', 'shot-n', 'shot-prev', 'shot-next'].forEach(function(id){
  els[id] = El(id); els[id].classList.o = els[id]; });
function $(id){ return els[id]; }
JSEOF
    cat "$WORK/shots.js"
    cat <<'JSEOF'

var c = JSON.parse(require('fs').readFileSync(process.argv[2], 'utf8'));
var fx = JSON.parse(require('fs').readFileSync(process.argv[3], 'utf8'));
var h = renderConvo(c), fail = [];
function want(ok, why){ if (!ok) fail.push(why); }

/* thumbnails: a place each, never a path */
var thumbs = [], re = /<button class="shot" data-shot="([^"]*)" data-ref="([^"]*)" data-cap="([^"]*)"/g, m;
while ((m = re.exec(h))) thumbs.push({ u: m[1].replace(/&amp;/g, '&'), ref: m[2], cap: m[3] });
want(thumbs.length === 7, 'not every picture that can be shown is a thumbnail: ' + thumbs.length);
want(thumbs.every(function(t){ return /^http:\/\/127\.0\.0\.1:1\/t\/image\?id=[0-9a-f-]+&at=\d+&i=\d+$/.test(t.u); }),
     'a thumbnail asks for something other than a place: ' + thumbs.map(function(t){ return t.u; }).join(' '));
want(/<span class="shot off"[^>]*><i>shot-gone\.png<\/i>no longer on disk<\/span>/.test(h), 'a gone file is not said to be gone');
want(/<i>shot-big\.png<\/i>too large to show/.test(h), 'an oversize file is not said to be too large');
want(/<div class="turn you">[^]*?<div class="shots"><button class="shot"/.test(h), 'your paste is not under your prompt');
want(/<div class="cmark image"><span>you pasted an image<\/span><\/div><div class="shots mid"><button class="shot"/.test(h),
     'a paste with no image in its prompt is not shown under its mark');
want(/<span class="n">Read<\/span><span class="b">[^<]*<\/span><button class="shotref" data-ref="\d+\.0">image<\/button>/.test(h),
     'the tool\'s line does not open its picture');

/* a stand-in for the DOM around them */
var surf = {
  querySelectorAll: function(){ return els_.filter(function(e){ return e.dataset.shot; }); },
  querySelector: function(sel){ var r = /data-ref="([^"]+)"/.exec(sel)[1];
    return els_.filter(function(e){ return e.dataset.ref === r; })[0] || null; }
};
var els_ = thumbs.map(function(t){ var e = { dataset: { shot: t.u, ref: t.ref, cap: t.cap }, title: t.cap, textContent: '',
  closest: function(sel){ return sel === '.surf' ? surf : /^\.shot/.test(sel) && sel !== '.shotref' && sel !== '.shotnav' &&
           (sel === '.shot[data-shot]' ? e.dataset.shot : true) ? e : null; } }; return e; });
function on(target){ return { target: target }; }
function nowhere(){ return { closest: function(){ return null; } }; }
var swallowed = 0;
function key(k){ var e = { key: k, preventDefault: function(){}, stopImmediatePropagation: function(){ swallowed++; } };
  return shotKey(e); }

want(!key('ArrowRight') && swallowed === 0, 'a closed lightbox took a key');
shotClick(on(els_[2]));
want(!els.shotbox.hidden && els['shot-img'].src === thumbs[2].u && els['shot-n'].textContent === '3 of 7' &&
     els['shot-cap'].textContent === thumbs[2].cap,
     'a thumbnail did not open the lightbox on itself: ' + els['shot-img'].src + ' ' + els['shot-n'].textContent);
key('ArrowRight');
want(els['shot-img'].src === thumbs[3].u && els['shot-n'].textContent === '4 of 7', 'the right arrow did not step on');
key('ArrowLeft'); key('ArrowLeft'); key('ArrowLeft');
want(els['shot-img'].src === thumbs[0].u, 'the left arrow did not step back');
key('ArrowLeft');
want(els['shot-img'].src === thumbs[6].u && els['shot-n'].textContent === '7 of 7', 'stepping back from the first did not go round');
key('ArrowRight');
want(els['shot-img'].src === thumbs[0].u, 'stepping on from the last did not go round');
var before = swallowed; key('w');
want(swallowed === before + 1 && !els.shotbox.hidden, 'an open lightbox let a key through to the window');
key('Escape');
want(els.shotbox.hidden && !els['shot-img'].src, 'Escape did not close it');
shotClick(on(els_[1]));
var navNext = { id: 'shot-next', closest: function(sel){ return sel === '.shotnav' ? navNext : null; } };
shotClick(on(navNext));
want(!els.shotbox.hidden && els['shot-img'].src === thumbs[2].u, 'its arrow did not step');
shotClick(on(nowhere()));
want(els.shotbox.hidden, 'a click did not close it');
/* the tool's line opens the thumbnail it names */
var ref = /data-ref="(\d+\.0)">image</.exec(h)[1];
var refEl = { dataset: { ref: ref }, closest: function(sel){ return sel === '.shotref' ? refEl : sel === '.surf' ? surf : null; } };
shotClick(on(refEl));
want(!els.shotbox.hidden && els_.filter(function(e){ return e.dataset.ref === ref; })[0].dataset.shot === els['shot-img'].src,
     'the tool\'s image did not open its picture');
key('Escape');
/* a thumbnail that would not load says so, and is passed over */
var img = { tagName: 'IMG', id: '', closest: function(){ return els_[4]; } };
els_[4].classList = { add: function(){} }; els_[4].removeAttribute = function(k){ delete els_[4].dataset[k === 'data-shot' ? 'shot' : k]; };
els_[4].innerHTML = '';
shotFailed(img);
want(/could not be shown/.test(els_[4].innerHTML), 'a picture that failed does not say so');
shotClick(on(els_[0]));
want(els['shot-n'].textContent === '1 of 6', 'a picture that failed is still stepped to');
console.log(fail.length ? 'XX ' + fail.join('; ') : 'ok');
JSEOF
  } > "$WORK/shots-run.js"
  res=$(node "$WORK/shots-run.js" "$WORK/media/convo.json" "$WORK/media/fixture.json" 2>&1)
  case "$res" in ok*) ok "42 · thumbnails ask by place, and the lightbox opens, steps round and closes" ;;
                 *)   no "42 · the thumbnails or the lightbox are wrong" "$res" ;; esac
else
  skip "42 · the lightbox on the page" "no node, or 40a wrote nothing"
fi

# ── 43 · the artifacts on the page, and a source that runs nothing ──────────
# Lifted from the shipped source, fed what test 41 read. Pinned:
#   - one row per artifact, the latest first, saying how often and when; its
#     title opens claude.ai in your browser and nothing else is linked; its
#     source opens by session and number, or it says why not
#   - a session's row in Sessions counts what it published
#   - the source view is text: every tag in it is the view's own, whatever the
#     file holds — no script, no handler, no frame, no image, highlighted or
#     plain
if command -v node >/dev/null && [ -s "$WORK/arts/arts.json" ]; then
  python3 -c 'import sys
src = open(sys.argv[1]).read()
def sl(a, b):
    i = src.index(a); return src[i:src.index(b, i)]
open(sys.argv[2], "w").write("\n".join([
    sl("/* ── what a session published", "/* ── the files a session changed"),
    sl("/* ── an artifact", "/* ── the navigator"),
    sl("function navSessions()", "function navNotes()"),
]))' "$REPO/share/workspace.js" "$WORK/arts-page.js"
  { cat <<'JSEOF'
var now = Math.floor(Date.now() / 1000), DAY = 86400;
var CAPS = { live: 1 };
function can(c){ return !!CAPS[c]; }
function esc(s){ return String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;')
                   .replace(/>/g, '&gt;').replace(/"/g, '&quot;'); }
function clip(s, n){ s = String(s || ''); return s.length > n ? s.slice(0, n - 1) + '…' : s; }
function shortRepo(p){ return (p || '?').split('/').pop() || '?'; }
function marks(){} function curSid(){ return ''; } function promptsWithheld(){ return false; }
function openNow(){ return { html: '', sids: {} }; }
function dayLabel(){ return 'Earlier'; }
function inRepo(){ return true; }
function sessionsOff(){ return ''; }
var Shell = { nav: function(){}, paint: function(){} };
var D = { withSessions: 1, sessions: {}, prompts: [] }, RUN = {}, sesScope = 'here', sesLive = false, sesQuery = '';
function sessionList(){ return Object.keys(D.sessions).map(function(k){ return { sid: k, m: D.sessions[k] }; }); }
var window = {};
try {
  var vm = require('vm'), ctx = { window: {} }; vm.createContext(ctx);
  vm.runInContext(require('fs').readFileSync(process.argv[3], 'utf8'), ctx);
  window.hljs = ctx.hljs || ctx.window.hljs;
} catch(e){}
var hljs = window.hljs;
JSEOF
    cat "$WORK/arts-page.js"
    cat <<'JSEOF'

var j = JSON.parse(require('fs').readFileSync(process.argv[2], 'utf8')), sid = j.sid, fail = [];
function want(ok, why){ if (!ok) fail.push(why); }
/* the rows */
ARTS[sid] = j;
j.artifacts.push({ n: 3, url: 'https://evil.example/artifact/x', title: 'Elsewhere', count: 1, first: 1, last: 2, source: 'not', file: '' });
var h = artsHTML(sid);
var rows = h.split('<div class="tfile art">').slice(1);
want(rows.length === 4, 'not one row per artifact: ' + rows.length);
want(/Alpha &amp; Again/.test(rows[0]) && /4 times, last /.test(rows[0]), 'the latest is not first, or does not say how often: ' + rows[0]);
want(/<a class="nm" href="https:\/\/claude\.ai\/artifact\/AXYZ" target="_blank" rel="noopener noreferrer"/.test(rows[0]),
     'the title does not open claude.ai outside the window');
want(/<button class="asrc" data-asrc="55555555-0000-4000-8000-000000000005" data-an="0"[^>]*>open the source<\/button>/.test(rows[0]),
     'the source is not opened by session and number');
var gone = rows.filter(function(r){ return /Gamma/.test(r); })[0] || '';
want(/its file is gone/.test(gone) && !/data-asrc/.test(gone), 'a gone source offers itself');
var evil = rows.filter(function(r){ return /Elsewhere/.test(r); })[0] || '';
want(!/<a /.test(evil), 'a url that is not claude.ai\'s is linked');
want(/^<section class="fsec" data-f="files"><div class="grp">Artifacts it published <span class="c">4 · /.test(h),
     'the section does not name and count what it holds');
ARTS.other = { artifacts: [] };
want(artsHTML('other') === '', 'a session that published nothing shows a list');
/* the count in Sessions */
D.sessions = { s1: { t: 'made pages', n: 5, live: 1, b: now, p: '/repo', arts: 3 }, s2: { t: 'made none', n: 2, live: 1, b: now, p: '/repo' } };
var nav = navSessions().html;
want(/made pages[^]*?<span class="sub">5p<span class="arts" title="published 3 artifacts to claude\.ai"> · <svg[^]*?<\/svg>3<\/span><\/span>/.test(nav),
     'a session\'s row does not count what it published');
want(!/class="arts"/.test((nav.split('data-ses="s2"')[1] || 'class="arts"').split('</div>')[0]),
     'a session that published nothing carries a count');
/* the source runs nothing */
var nasty = '<!doctype html><title>x</title><script>window.ran = 1</script>' +
  '<img src=x onerror="window.ran = 2"><iframe srcdoc="<script>parent.ran = 3</script>"></iframe>' +
  '<svg onload="window.ran = 4"></svg><a href="javascript:window.ran = 5">x</a><style>body{}</style>' +
  '<link rel="stylesheet" href="https://example.com/x.css"><object data="x"></object>';
var OURS = { section: 1, h3: 1, div: 1, span: 1, a: 1, pre: 1, code: 1 };
var ATTRS = { 'class': 1, title: 1, href: 1, target: 1, rel: 1 };
function inert(out, how){
  var t = /<\s*([a-zA-Z][\w-]*)([^>]*)>/g, m;
  while ((m = t.exec(out))){
    if (!OURS[m[1].toLowerCase()]) return want(false, how + ': a <' + m[1] + '> tag from the file is live');
    var a = /([\w-]+)\s*=/g, n;
    while ((n = a.exec(m[2]))) if (!ATTRS[n[1].toLowerCase()]) return want(false, how + ': a live ' + n[1] + ' attribute');
    if (/^a$/i.test(m[1]) && !/href="https:\/\/claude\.ai\//.test(m[2])) return want(false, how + ': a live link from the file');
  }
}
var src = { title: 'x', url: 'https://claude.ai/artifact/AXYZ', file: '~/x/index.html', kind: 'html', count: 1,
            last: now, bytes: nasty.length, cut: false, text: nasty };
var shown = sourceHTML(src);
want(!hljs || /hljs-tag/.test(shown), 'the source was not highlighted');
inert(shown, 'highlighted');
SOURCE_HL = 10;
inert(sourceHTML(src), 'plain');
want(/&lt;script&gt;window\.ran = 1&lt;\/script&gt;/.test(sourceHTML(src)), 'the script is not there to read');
console.log(fail.length ? 'XX ' + fail.join('; ') : 'ok');
JSEOF
  } > "$WORK/arts-run.js"
  res=$(node "$WORK/arts-run.js" "$WORK/arts/arts.json" "$REPO/share/vendor/highlight.min.js" 2>&1)
  case "$res" in ok*) ok "43 · a session's artifacts are its rows and its count, and their source is text that runs nothing" ;;
                 *)   no "43 · the artifacts on the page are wrong, or their source can run" "$res" ;; esac
else
  skip "43 · the artifacts on the page" "no node, or 41 wrote nothing"
fi

# ── 44 · a running session's view ends on its reply line ────────────────────
# A running session's reply line is sticky at the foot of the pane, and a
# sticky line cannot sink into the room a document keeps below its last line:
# kept, that room stands the line mid-pane over a blank that scrolls — 360 px
# above the foot of a 797 px pane, measured headless on a fixture session. A
# layout needs a browser, so the rules are read here. Pinned:
#   - the reply line is sticky at the foot, and a document keeps room below
#     its last line, so the case exists
#   - a view whose own child is a sticky reply line keeps none, by a rule that
#     wins over the document's
#   - a running session's view ends on its reply line, indexed or not, and is
#     the view's own child, which is what the rule's `> .sreply` finds
python3 - "$REPO" >"$WORK/foot.txt" 2>&1 <<'PYEOF'
import re, sys
repo = sys.argv[1]
css = open(repo + "/share/shell.css").read() + open(repo + "/share/workspace.html").read()
js = open(repo + "/share/workspace.js").read()
css = re.sub(r"/\*.*?\*/", "", css, flags=re.S)
rules = [(m.group(1).strip(), m.group(2)) for m in re.finditer(r"([^{}]+)\{([^{}]*)\}", css)]
def decl(body, prop):
    m = re.search(r"(?:^|;)\s*" + prop + r"\s*:\s*([^;]+)", body)
    return m.group(1).strip() if m else None
def spec(sel):
    """ids, classes and pseudo-classes, elements: a :has, :not or :is counts
    what it holds"""
    a = b = c = 0
    while True:
        m = re.search(r":(has|not|is|where)\(([^()]*)\)", sel)
        if not m:
            break
        if m.group(1) != "where":
            x = spec(m.group(2))
            a, b, c = a + x[0], b + x[1], c + x[2]
        sel = sel[:m.start()] + sel[m.end():]
    a += len(re.findall(r"#[\w-]+", sel))
    b += len(re.findall(r"\.[\w-]+|\[[^\]]*\]|(?<!:):[\w-]+", sel))
    c += len(re.findall(r"(?:^|[\s>+~])[a-zA-Z][\w-]*", sel))
    return (a, b, c)
checks = {}
checks["the reply line is sticky at the foot"] = any(
    ".sreply:not(.off)" in s and ":has" not in s and decl(b, "position") == "sticky" and decl(b, "bottom") == "0"
    for s, b in rules)
doc = [(s, b) for s, b in rules if s == ".surf .inner"]
pad = (decl(doc[0][1], "padding") or "").split() if doc else []
checks["a document keeps room below its last line"] = len(pad) >= 3 and pad[2] not in ("0", "0px")
ends = [s for s, b in rules if re.search(r"\.(sdet|inner)\s*:has\(\s*>\s*\.sreply:not\(\.off\)\s*\)", s)
        and decl(b, "padding-bottom") in ("0", "0px")]
checks["a view that ends on a sticky reply line keeps no room below it"] = bool(ends)
checks["and that rule wins over the document's"] = bool(ends and doc) and all(spec(s) > spec(doc[0][0]) for s in ends)
i = js.index("function sessionHTML(sid, convo)")
body = js[i:js.index("\nfunction answerThere", i)]
checks["an indexed running session's view ends on its reply line"] = bool(re.search(
    r"if \(RUN\[sid\]\) out\.push\(replySection\(sid\)\);\s*return out\.join\(''\);", body))
checks["so does one the index does not hold"] = bool(re.search(r"replySection\(sid\)\]\.join\(''\);\s*\}\s*$", body))
checks["the reply line is the view's own child"] = (
    "box.innerHTML = sessionHTML(sid, S.slot());" in js
    and "'<div class=\"sreply\">' + testsHTML(sid) + bandHTML(sid) + replyHTML(sid, 's') + '</div>'" in js)
for k, v in checks.items():
    print(("ok " if v else "XX ") + k)
sys.exit(0 if all(checks.values()) else 1)
PYEOF
if [ $? = 0 ]; then
  ok "44 · a running session's view ends on its reply line, at the pane's foot"
else
  no "44 · a running session's reply line stands above the end of its view" "$(grep '^XX' "$WORK/foot.txt" | tr '\n' ' ')$(tail -2 "$WORK/foot.txt")"
fi

# ── 45a · a conversation is read on as it grows, and the server says when ────
# A running session's view shows each turn as it is written. Each turn says
# the byte its first record's line begins at; the page asks for the turns from
# where its latest began, and the event stream tells it which running
# sessions' transcripts grew. Pinned:
#   - the turns read on from where any turn began are the ones a read of the
#     whole gives from there: through a reply its tools split, a reply of tools
#     alone joined to the words after it, thinking, a note, a command, an
#     interruption, a compaction, a picture named by its path, a file written
#     from another folder, and a call still waiting on its result
#   - a half-written last line waits, and is read once whole
#   - a place where no line begins is refused, and so is one past the end
#   - the route reads on from `from`, and refuses one that is not a number
#   - the event stream says `grew` for the session written to and no other
python3 - "$WORK" "$REPO" >"$WORK/follow.txt" 2>&1 <<'PYEOF'
import http.client, json, os, subprocess, sys, time, urllib.error, urllib.request
from pathlib import Path
work, repo_root = sys.argv[1], sys.argv[2]
base = os.path.join(work, "follow")
sdir = os.path.join(base, "sessions"); os.makedirs(sdir, exist_ok=True)
pdir = os.path.join(base, "projects", "-follow"); os.makedirs(pdir, exist_ok=True)
os.environ.update(RUBRICATOR_CLAUDE_SESSIONS=sdir, RUBRICATOR_CLAUDE_PROJECTS=os.path.join(base, "projects"),
                  RUBRICATOR_CLAUDE_HISTORY=os.path.join(base, "history.jsonl"))
bindir = os.path.join(base, "bin"); os.makedirs(bindir, exist_ok=True)
fake = os.path.join(bindir, "claude"); os.symlink("/bin/sleep", fake)
procs = []
def sid(n): return "%08d-0000-4000-8000-%012d" % (n, n)
def iso(t): return time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(t)) + ".%03dZ" % int((t % 1) * 1000)
def session(n, status):
    p = subprocess.Popen([fake, "300"]); procs.append(p)
    open(os.path.join(sdir, "%d.json" % p.pid), "w").write(json.dumps(
        {"pid": p.pid, "sessionId": sid(n), "status": status, "cwd": "/w", "statusUpdatedAt": int(time.time() * 1000)}))
t = [time.time() - 3600]
def rec(kind, content=None, cwd="/w", **kw):
    t[0] += 7
    r = {"type": kind, "cwd": cwd, "sessionId": sid(1), "timestamp": iso(t[0])}
    if content is not None:
        r["message"] = {"role": kind, "content": content}
    r.update(kw)
    return json.dumps(r, separators=(",", ":")) + "\n"
def you(text): return rec("user", text, promptSource="prompt")
def said(mid, *blocks, cwd="/w"):
    return rec("assistant", cwd=cwd, message={"id": mid, "role": "assistant", "content": list(blocks)})
def use(tid, name, inp): return {"type": "tool_use", "id": tid, "name": name, "input": inp}
def back(tid, cwd="/w", made=None):
    return rec("user", [{"type": "tool_result", "tool_use_id": tid, "content": "ok"}], cwd=cwd,
               **({"toolUseResult": {"type": "create", "filePath": made}} if made else {}))
text = lambda s: {"type": "text", "text": s}
lines = "".join([
    you("look at the tides"),
    said("m1", {"type": "thinking", "thinking": "hm"}), said("m1", use("t1", "Read", {"file_path": "/w/tides.md"})),
    back("t1"),
    said("m2", text("Read it; writing the table.")), said("m2", use("t2", "Write", {"file_path": "/w/tree/table.md"}), cwd="/w/tree"),
    back("t2", cwd="/w/tree", made="/w/tree/table.md"),
    said("m3", text("Wrote it.")),
    json.dumps({"type": "api-request", "params": "p" * 500}) + "\n",
    rec("user", "<task-notification><status>completed</status><summary>the build is done</summary></task-notification>",
        promptSource="system", origin={"kind": "task-notification"}),
    said("m4", text("Noted; see /w/shot.png for the quay.")),
    you("/signoff"),
    said("m5", use("t5", "Bash", {"command": "ls", "description": "List them"})),
    rec("user", [{"type": "tool_result", "tool_use_id": "t5", "content": "x", "is_error": True},
                 {"type": "text", "text": "[Request interrupted by user for tool use]"}]),
    rec("system", subtype="compact_boundary"),
    you("go on with the neap tides"),
    said("m6", use("t6", "Grep", {"pattern": "neap", "path": "/w"})),
])
checks = {}
try:
    sys.path.insert(0, os.path.join(repo_root, "share"))
    import transcript as T
    T.PROJECTS = Path(base) / "projects"
    p = Path(pdir) / (sid(1) + ".jsonl")
    p.write_text(lines)
    whole = T.read(sid(1), path=p)["turns"]
    kinds = [x["who"] + ("/" + x["kind"] if x.get("kind") else "") for x in whole]
    checks["the fixture holds each kind of turn: " + " ".join(kinds)] = all(
        k in kinds for k in ("note/task", "mark/command", "mark/interrupted", "mark/compact")) and len(whole) >= 10
    ats = [x.get("at") for x in whole]
    checks["every turn says where it began, in order"] = all(isinstance(a, int) for a in ats) and ats == sorted(set(ats))
    checks["a reply of tools alone is joined to the words after it"] = any(
        x["who"] == "claude" and x["text"].startswith("Read it") and [y["n"] for y in x["tools"]] == ["Read", "Write"]
        and x["thinking"] == 1 for x in whole)
    checks["a file written from another folder is told from that folder"] = any(
        x.get("wrote") == ["table.md"] for x in whole)
    differ = [i for i, x in enumerate(whole) if T.since(sid(1), x["at"], path=p)["turns"] != whole[i:]]
    checks["read on from where each turn began, the turns are a whole read's from there%s" % (
        " (not from %s)" % differ if differ else "")] = not differ
    last = whole[-1]["at"]
    line = said("m7", text("Found three."))
    with p.open("a") as f:
        f.write(line[:40])
    got = T.since(sid(1), last, path=p)
    checks["a half-written line waits"] = got["turns"] == whole[-1:] and got["bytes"] == p.stat().st_size
    with p.open("a") as f:
        f.write(line[40:])
    got = T.since(sid(1), last, path=p)["turns"]
    checks["and is read once whole, the call before it joined to its words"] = (
        len(got) == 1 and got[0]["text"] == "Found three." and got[0]["at"] == last
        and [y["n"] for y in got[0]["tools"]] == ["Grep"])
    checks["a place where no line begins is refused"] = T.since(sid(1), last + 3, path=p).get("error") == "no line begins there"
    checks["and so is one past the end"] = bool(T.since(sid(1), p.stat().st_size + 1, path=p).get("error"))
    checks["the end itself is no turn"] = T.since(sid(1), p.stat().st_size, path=p)["turns"] == []

    # the route, and the event stream
    import workspace as W
    repo = os.path.join(base, "repo"); os.makedirs(repo, exist_ok=True)
    open(os.path.join(repo, "README.md"), "w").write("# follow\n")
    subprocess.run(["git", "-C", repo, "init", "-q"], check=True)
    q = Path(pdir) / (sid(2) + ".jsonl")
    q.write_text(you("a second session"))
    session(1, "busy"); session(2, "idle")
    srv = W.serve_workspace([repo], False, Path(repo_root) / "share", "", idle=10 ** 9, waiting=True)
    conn = None
    try:
        def get(path):
            try: return json.load(urllib.request.urlopen(srv.base + path, timeout=20)), 200
            except urllib.error.HTTPError as e: return json.load(e), e.code
        got, code = get("/session?id=%s&from=%d" % (sid(1), last))
        checks["the route reads on from a turn"] = code == 200 and got.get("turns") == T.since(sid(1), last, path=p)["turns"]
        got, code = get("/session?id=%s&from=x" % sid(1))
        checks["and refuses a place that is not a number"] = code == 400
        conn = http.client.HTTPConnection("127.0.0.1", srv.port, timeout=8)
        conn.request("GET", "/" + srv.token + "/events", headers={"Host": "127.0.0.1"})
        res = conn.getresponse()
        def told(within):
            end = time.time() + within
            while time.time() < end:
                try:
                    ln = res.fp.readline().decode().strip()
                except OSError:
                    return None                    # nothing said before the socket's timeout
                if ln.startswith("data:") and "grew" in ln:
                    return json.loads(ln[5:])["grew"]
            return None
        checks["the stream opens"] = res.fp.readline().decode().strip() == ": watching"
        time.sleep(1.5)
        with p.open("a") as f:
            f.write(you("and the spring tides"))
        checks["a transcript that grew is told, by its session alone"] = told(8) == [sid(1)]
        with q.open("a") as f:
            f.write(you("more"))
        checks["and the other's, when it grows"] = told(8) == [sid(2)]
    finally:
        if conn: conn.close()
        srv.stop.set()
        try: srv.httpd.shutdown()
        except Exception: pass
except Exception as e:
    import traceback; traceback.print_exc()
    checks["the test ran: %s" % e] = False
finally:
    for pr in procs: pr.terminate()
for k_, v in checks.items(): print(("ok " if v else "XX ") + k_)
sys.exit(0 if checks and all(checks.values()) else 1)
PYEOF
if [ $? = 0 ]; then
  ok "45a · a conversation is read on from a turn as its transcript grows, and the stream says which grew"
else
  no "45a · a growing conversation is not read on, or not told" "$(grep '^XX' "$WORK/follow.txt" | tr '\n' ' ')$(tail -2 "$WORK/follow.txt")"
fi

# ── 45b · the page draws a conversation on as it grows ───────────────────────
# sessionSurface, the conversation's drawing and the event stream's receiver,
# lifted from the shipped source around a stand-in for the DOM whose
# conversation box holds one element for each top-level tag drawn into it.
# Pinned:
#   - told its session grew, a view asks for the turns from where its latest
#     began; one ask at a time, and once more if told again meanwhile; a view
#     not on screen asks once it is shown
#   - what came back as it was drawn stays as it is, element for element; the
#     rest is drawn below it, the count above says the new numbers, and a list
#     of tool calls opened in a turn drawn again is open again
#   - a view at its foot is kept at its foot; one read further up is not moved
#   - an answer that finds no turn there reads the conversation whole
#   - `grew` reaches the views open on those sessions, and no other
if command -v node >/dev/null; then
  python3 -c 'import sys
src = open(sys.argv[1]).read()
def sl(a, b):
    i = src.index(a); return src[i:src.index(b, i)]
open(sys.argv[2], "w").write("\n".join([
    sl("function sessionSurface(sid, q)", "/* Where a session opens."),
    sl("function renderConvo(c)", "function didHTML(t)"),
    sl("function didHTML(t)", "function clock(ts)"),
    sl("/* Whether a pane is at its foot", "function bandShown(b)"),
    sl("/* where each pane was left", "/* ── E1 · watch"),
]))' "$REPO/share/workspace.js" "$WORK/follow-page.js"
  { cat <<'JSEOF'
var D = { sessions: {} }, RUN = {}, CAPS = { conversation: 1, launch: 1 }, BASE = 'http://127.0.0.1:1/t';
function can(c){ return !!CAPS[c]; }
function esc(s){ return String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;')
                   .replace(/>/g, '&gt;').replace(/"/g, '&quot;'); }
var marked = { parse: function(t){ return '<p>' + esc(t) + '</p>'; } };
var MD = { sanitise: function(){} };
function clock(){ return '12:00'; } function docBy(){ return null; }
function grabCaret(){ return null; } function putCaret(){}
function foldLong(){} function unfold(){}
function sesTitle(s){ return s; } function clip(s){ return s; }
function landing(host){ host.scrollTop = host.scrollHeight; }
function makeFind(){ return { on: false, after: function(){}, open: function(){}, hint: function(){ return ''; } }; }
function sessionHTML(sid, convo){ return 'ABOUT<div class="convo">' + (convo || '') + '</div>'; }
var timers = [];
function setTimeout(fn){ timers.push(fn); }
function flush(){ while (timers.length) timers.shift()(); }
var asked = [], fail = [];
function api(path, body, cb, fail){ asked.push({ path: path, cb: cb, fail: fail }); }
function answer(j){
  var a = asked.shift();
  if (!a) return fail.push('nothing was asked for the answer ' + JSON.stringify(j).slice(0, 60));
  a.cb(j);
}
var tabs = [];
var Shell = { paint: function(){}, each: function(fn){ tabs.forEach(function(t){ fn(t); }); } };

/* a stand-in for the DOM: what is drawn into a box becomes one element for
   each of its top-level tags */
var VOID = { img: 1, br: 1, hr: 1, input: 1, wbr: 1 };
function split(h){
  var out = [], depth = 0, start = 0, re = /<(\/?)([a-zA-Z][a-zA-Z0-9]*)[^>]*>/g, m;
  while ((m = re.exec(h))){
    if (VOID[m[2].toLowerCase()]){ if (!depth) out.push(m[0]); continue; }
    if (!m[1]){ if (!depth) start = m.index; depth++; }
    else if (!--depth) out.push(h.slice(start, re.lastIndex));
  }
  return out;
}
function El(html, box){
  var e = { html: html, details: /<details class="tools">/.test(html) ? { open: false } : null,
            c: /^<div class="grp">/.test(html) ? { innerHTML: '' } : null };
  e.querySelector = function(sel){ return sel === 'details.tools' ? e.details : null; };
  e.remove = function(){ var i = box.children.indexOf(e); if (i >= 0) box.children.splice(i, 1); };
  return e;
}
function Box(){
  var b = { children: [] };
  b.insertAdjacentHTML = function(where, h){ split(h).forEach(function(x){ b.children.push(El(x, b)); }); };
  b.querySelector = function(sel){ return sel === '.grp .c' && b.children[0] && b.children[0].c || null; };
  return b;
}
var document = {
  createElement: function(){
    var d = { _h: '', children: [] };
    Object.defineProperty(d, 'innerHTML', { get: function(){ return d._h; },
      set: function(v){ d._h = v; d.children = split(v); } });
    return d;
  },
  addEventListener: function(){}
};
/* a pane, which records each time it is scrolled */
function Host(){
  var h = { offsetHeight: 600, clientHeight: 600, scrollHeight: 5000, top: 0, sets: [] };
  var box = Box(), inner = {};
  Object.defineProperty(inner, 'innerHTML', { set: function(v){
    box.children = [];
    var i = v.indexOf('<div class="convo">');
    if (i >= 0) box.insertAdjacentHTML('beforeend', v.slice(i + 19, v.lastIndexOf('</div>')));
  } });
  Object.defineProperty(h, 'scrollTop', { get: function(){ return h.top; },
    set: function(v){ h.top = v; h.sets.push(v); } });
  Object.defineProperty(h, 'innerHTML', { set: function(){} });
  h.querySelector = function(sel){ return sel === '.inner' ? inner : sel === '.convo' ? box : null; };
  h.box = box;
  return h;
}
JSEOF
    cat "$WORK/follow-page.js"
    cat <<'JSEOF'

function want(ok, why){ if (!ok) fail.push(why); }
var sid = 'aaaaaaaa-0000-4000-8000-000000000001';
RUN[sid] = { pid: 1, transcript: true, on: 'working' };
function you(at, text){ return { who: 'you', t: 1, text: text, at: at }; }
function claude(at, text, tools){
  return { who: 'claude', t: 1, text: text, thinking: 0, wrote: [], edited: [], at: at,
           tools: (tools || []).map(function(n){ return { n: n, b: 'x' }; }) };
}
function copy(x){ return JSON.parse(JSON.stringify(x)); }
var S = sessionSurface(sid, ''), host = Host();
tabs = [{ kind: 'session', id: sid, el: host, surf: S }, { kind: 'doc', id: 'x', el: {}, surf: {} }];
S.render(host); flush();
answer(copy({ id: sid, you: 2, claude: 2, notes: 0,
  turns: [you(0, 'first'), claude(100, 'read it', ['Read']), you(300, 'second'), claude(400, 'on it', ['Bash'])] }));
var box = host.box, kids = box.children.slice();
want(kids.length === 5 && /class="grp"/.test(kids[0].html), 'the conversation is not its count and four turns: ' + kids.length);
kids[4].details.open = true;                   // the tool calls of the turn still growing, opened
host.top = host.scrollHeight - host.clientHeight;
host.sets = [];

/* not on screen: nothing is asked until it is shown */
host.offsetHeight = 0;
followTranscripts([sid]);
want(asked.length === 0, 'a view not on screen asked');
host.offsetHeight = 600;
S.focus();
want(asked.length === 1 && asked[0].path === 'session?id=' + sid + '&from=400',
     'shown, it did not ask from where its latest turn began: ' + (asked[0] || {}).path);
followTranscripts([sid]);
want(asked.length === 1, 'it asked twice at once');

/* the latest turn grew a call, and two turns came after it */
answer(copy({ id: sid, from: 400,
  turns: [claude(400, 'on it', ['Bash', 'Edit']), you(700, 'third'), claude(800, 'done')] }));
var now = box.children;
want(now.length === 7 && now[1] === kids[1] && now[2] === kids[2] && now[3] === kids[3],
     'what came back as it was drawn was drawn again: ' + now.length + ' elements');
want(now[4] !== kids[4] && /2 tool calls/.test(now[4].html) && /third/.test(now[5].html) && /done/.test(now[6].html),
     'the turn that grew, or the turns after it, are not drawn below');
want(now[4].details && now[4].details.open, 'the tool calls opened in the turn drawn again are shut');
want(/3 from you · 3 from Claude/.test(now[0].c.innerHTML) && S.conv.turns.length === 6,
     'the count does not say the new numbers: ' + now[0].c.innerHTML);
want(host.sets.length && host.sets[host.sets.length - 1] === host.scrollHeight, 'a view at its foot was not kept at its foot');
want(asked.length === 1 && /&from=800$/.test(asked[0].path), 'told again meanwhile, it did not ask once more from its new latest turn');

/* nothing new: nothing is drawn, nothing moves */
var before = box.children.slice();
host.sets = [];
answer(copy({ id: sid, from: 800, turns: [claude(800, 'done')] }));
want(box.children.length === 7 && box.children.every(function(e, i){ return e === before[i]; }) && !host.sets.length,
     'an answer with nothing new drew something, or moved the view');

/* read further up: the new turn is drawn, and the view is not moved */
host._foot = false;
followTranscripts([sid]);
answer(copy({ id: sid, from: 800, turns: [claude(800, 'done'), you(900, 'fourth')] }));
want(box.children.length === 8 && box.children[6] === before[6] && /fourth/.test(box.children[7].html) && !host.sets.length,
     'read further up, the view was moved, or the turn not drawn');

/* no turn begins there: the transcript was written anew, and is read whole */
followTranscripts([sid]);
answer({ id: sid, error: 'no line begins there', turns: [] });
want(asked.length === 1 && asked[0].path === 'session?id=' + sid,
     'a refused place did not read the conversation whole: ' + (asked[0] || {}).path);
asked = [];

/* a session not open is not asked about */
followTranscripts(['bbbbbbbb-0000-4000-8000-000000000002']);
want(asked.length === 0, 'a session not open was asked about');

/* the event stream's grew reaches them */
var page = require('fs').readFileSync(process.argv[2], 'utf8');
want(/if \(j\.grew\) return followTranscripts\(j\.grew\);/.test(page), 'the event stream\'s grew reaches no conversation');
console.log(fail.length ? 'XX ' + fail.join('; ') : 'ok');
JSEOF
  } > "$WORK/follow-run.js"
  res=$(node "$WORK/follow-run.js" "$REPO/share/workspace.js" 2>&1)
  case "$res" in ok*) ok "45b · a conversation is drawn on as it grows, what you opened stays open, and the foot is kept" ;;
                 *)   no "45b · a growing conversation is not drawn on" "$res" ;; esac
else
  skip "45b · a growing conversation on the page" "no node"
fi

# ── 46 · a test run, found on the machine and counted ───────────────────────
# What runs under a session is found by its command line, how far it is by its
# output, and how long it took before by the transcripts. Pinned:
#
#   - the runners' lines, from npm scripts to pytest under any python, are test
#     runs, named from the runner's own word; a shell's command string, the
#     shell's own test, inline code, builds and readers of test files are not
#   - each runner's way of counting is read: a share it printed, a fraction, a
#     count announced up front or announced per binary and summed, the lines
#     that pass and fail; a summary stops the counting; colours and carriage
#     returns are passed over; a count announced in another unit is dropped
#   - an output is read on from where the last look left it, a line still being
#     written waits, a file written anew is read anew, and a large one from
#     near its end, its counts then "at least"
#   - on the machine: a run under a session, writing to a file, says how far,
#     its call by the description of the Bash call still running — the
#     background call whose task file it writes, where one does, and the
#     foreground call where its task file names no background call — and the
#     run before from the session's transcript or another of its project; one
#     writing into a pipe says so; a session running none, and a run under no
#     session, are not listed; a later look reads on
#   - the server answers only with consent
python3 - "$WORK" "$REPO" >"$WORK/testruns.txt" 2>&1 <<'PYEOF'
import json, os, signal, subprocess, sys, time, urllib.error, urllib.request
from pathlib import Path
work, repo_root = sys.argv[1], sys.argv[2]
base = os.path.join(work, "testruns")
sdir = os.path.join(base, "sessions"); os.makedirs(sdir, exist_ok=True)
pdir = os.path.join(base, "projects", "-runs"); os.makedirs(pdir, exist_ok=True)
tdir = os.path.join(base, "tasks"); os.makedirs(tdir, exist_ok=True)
os.environ.update(RUBRICATOR_CLAUDE_SESSIONS=sdir, RUBRICATOR_CLAUDE_PROJECTS=os.path.join(base, "projects"),
                  RUBRICATOR_CLAUDE_HISTORY=os.path.join(base, "history.jsonl"))
bindir = os.path.join(base, "bin"); os.makedirs(bindir, exist_ok=True)
fake = os.path.join(bindir, "claude"); os.symlink("/bin/bash", fake)
script = os.path.join(base, "run_tests.sh")
open(script, "w").write('#!/bin/bash\necho "4 to run"\necho "✓ a"\necho "✗ b"\nsleep 2\necho "✓ c"\nsleep 60\n')
os.chmod(script, 0o755)
procs = []
def sid(n): return "%08d-0000-4000-8000-%012d" % (n, n)
def iso(t): return time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(t)) + ".%03dZ" % int((t % 1) * 1000)
def session(n, command):
    p = subprocess.Popen([fake, "-c", "cd %s && %s; true" % (base, command)], start_new_session=True)
    procs.append(p)
    open(os.path.join(sdir, "%d.json" % p.pid), "w").write(json.dumps(
        {"pid": p.pid, "sessionId": sid(n), "status": "busy", "cwd": base, "statusUpdatedAt": int(time.time() * 1000)}))
    return p
def bash(t, tid, command, desc):
    return {"type": "assistant", "timestamp": iso(t), "message": {"id": "m" + tid, "content": [
        {"type": "tool_use", "id": tid, "name": "Bash", "input": {"command": command, "description": desc}}]}}
def result(t, tid, stdout="", bg=None):
    res = {"stdout": stdout, "stderr": "", "interrupted": False}
    text = stdout
    if bg:
        res["backgroundTaskId"] = bg
        text = "Command running in background with ID: %s. Output is being written to: %s/%s.output." % (bg, tdir, bg)
    return {"type": "user", "timestamp": iso(t), "toolUseResult": res,
            "message": {"content": [{"type": "tool_result", "tool_use_id": tid, "content": text}]}}
def write(n, recs):
    open(os.path.join(pdir, sid(n) + ".jsonl"), "w").write("".join(json.dumps(r) + "\n" for r in recs))

checks = {}
try:
    sys.path.insert(0, os.path.join(repo_root, "share"))
    import testruns as T

    # 1 · what runs tests
    RUNS = ["npm run test:affected", "/opt/homebrew/bin/node scripts/test.ts --affected", "node --test tests/x.test.ts",
            "/usr/bin/python3 -m pytest -x tests", "/usr/local/bin/python3.12 /usr/local/bin/pytest -q",
            "node /p/node_modules/.bin/vitest run", "node /p/node_modules/jest/bin/jest.js --ci",
            "node /p/node_modules/@playwright/test/cli.js test", "cargo test --all", "go test ./...", "npm exec vitest run",
            "npx jest", "yarn test:unit", "pnpm run test", "bun test", "bun scripts/test.ts", "make -j4 test",
            "./gradlew :app:test", "mvn -q verify", "/bin/bash ./run_tests.sh", "ctest -j8", "rspec spec/a_spec.rb",
            "node /opt/homebrew/lib/node_modules/pnpm/bin/pnpm.cjs run test"]
    NOT = ["/bin/zsh -c source x && npm test", "cat tests/a.test.ts", "node build.js", "test -f x", "[ -f x ]",
           "tail -f .tree/affected.log", "node -e require('./test.js')", "python3 -c import pytest", "vim test.py",
           "npm run build", "go build ./...", "trial bench.mjs", "tsc --noEmit", "grep -r test src"]
    checks["every runner's line is a test run"] = [a for a in RUNS if not T.runner(a)] == []
    checks["and nothing else is: %s" % [a for a in NOT if T.runner(a)]] = [a for a in NOT if T.runner(a)] == []
    checks["a run is named from the runner's own word"] = (
        T.runner("node /p/node_modules/.bin/vitest run") == "vitest run" and T.runner("npm exec vitest run") == "vitest run"
        and T.runner("/usr/local/bin/python3.12 /usr/local/bin/pytest -q") == "pytest -q")

    # 2 · how far, from what it printed
    c = T.counted
    checks["pytest's own share is taken, and its collected count"] = (
        c("collected 40 items\n\ntests/a.py ....  [ 10%]\n") == {"done": 0, "failed": 0, "total": 40, "pct": 10})
    checks["ctest's, playwright's and phpunit's fractions are taken"] = (
        c("    1/12 Test  #1: a ....   Passed\n    2/12 Test  #2: b ***Failed\n")["total"] == 12
        and c("Running 50 tests using 4 workers\n[7/50] [chromium] › a.spec.ts:3:1 › x\n")["done"] == 7
        and c("...F.  5 / 120 (  4%)\n")["total"] == 120)
    checks["a count announced up front, and the lines that pass and fail"] = (
        c("324 to run, in a pool of 10 slots\n✓ tests/a.test.ts  1.2s\n✗ tests/b.test.ts  0.4s\n")
        == {"done": 2, "failed": 1, "total": 324, "pct": None})
    checks["TAP's plan at the top level, its subtests passed over"] = (
        c("TAP version 13\n1..2\n    ok 1 - sub\n    1..1\nok 1 - a\nnot ok 2 - b\n") == {"done": 2, "failed": 1, "total": 2, "pct": None})
    checks["cargo's counts per binary are summed"] = (
        c("running 3 tests\ntest a ... ok\ntest b ... FAILED\nrunning 2 tests\ntest c ... ok\n") == {"done": 3, "failed": 1, "total": 5, "pct": None})
    checks["jest's and go's lines count"] = (
        c("PASS src/a.test.js\nFAIL src/b.test.js\n")["done"] == 2
        and c("ok  \tx/a\t0.12s\nFAIL\tx/b\t0.30s\nok  \tx/c\t(cached)\n") == {"done": 3, "failed": 1, "total": None, "pct": None})
    checks["a summary stops the counting"] = (
        c("✔ a (1ms)\n✖ b (2ms)\nℹ tests 2\nℹ fail 1\n✖ failing tests:\n\n✖ b (2ms)\n") == {"done": 2, "failed": 1, "total": None, "pct": None})
    checks["colours and carriage returns are passed over"] = c("\x1b[32m✓\x1b[39m a\nloading 10%\rloading 20%\r✓ b\n")["done"] == 2
    checks["a count announced in another unit is dropped"] = c("1..1\n✓ a\n✓ b\n")["total"] is None

    # 3 · an output read as it grows
    f = os.path.join(base, "grow.log")
    open(f, "w").write("3 to run\n✓ a\n✓ b")
    o = T._Out(f); o.look()
    checks["a line still being written waits"] = o.count.result()["done"] == 1
    open(f, "a").write("\n✗ c\n"); o.look()
    checks["a later look reads on"] = o.count.result() == {"done": 3, "failed": 1, "total": 3, "pct": None}
    os.remove(f); open(f, "w").write("✓ a\n"); o.look()
    checks["a file written anew is read anew"] = o.count.result()["done"] == 1 and o.count.result()["total"] is None
    most, T.OUT_MOST = T.OUT_MOST, 64
    open(f, "w").write("50 to run\n" + "✓ x\n" * 100)
    o = T._Out(f); o.look()
    T.OUT_MOST = most
    # 64 bytes from the end are ten and a bit lines of six: the bit is cut off, and so is the count up front
    checks["a large file is read from near its end, at least"] = (
        o.whole is False and o.count.result()["done"] == 10 and o.count.result()["total"] is None)

    # 4 · on the machine
    now = time.time()
    write(1, [bash(now - 200, "toolu_a", "cd x && ./run_tests.sh", "Run the tests"),
              result(now - 170, "toolu_a", "4 to run\n✓ a\n✓ b\n✓ c\n✓ d\n"),
              bash(now - 5, "toolu_b", "./run_tests.sh > out1.log 2>&1", "Run the tests again")])
    write(2, [bash(now - 4, "toolu_c", "./run_tests.sh | cat", "Run the tests into a pipe")])
    write(4, [bash(now - 9, "toolu_d", "./run_tests.sh", "Run them in the background"),
              result(now - 9, "toolu_d", bg="bgtask01"),
              bash(now - 3, "toolu_e", "sleep 5", "Wait a little")])
    write(5, [bash(now - 3, "toolu_f", "./run_tests.sh", "Run them in the foreground")])
    session(1, "./run_tests.sh > out1.log 2>&1")
    session(2, "./run_tests.sh | cat > /dev/null")
    session(3, "sleep 60")
    session(4, "./run_tests.sh > %s/bgtask01.output 2>&1" % tdir)
    session(5, "./run_tests.sh > %s/fgtask02.output 2>&1" % tdir)
    alone = subprocess.Popen([script], stdout=subprocess.DEVNULL, start_new_session=True); procs.append(alone)
    time.sleep(1.2)
    got = T.runs()["runs"]
    one = (got.get(sid(1)) or [{}])[0]
    checks["a run under a session is found, and says how far: %s" % one] = (
        one.get("label") == "bash ./run_tests.sh" and one.get("out") == "file"
        and (one.get("done"), one.get("failed"), one.get("total")) == (2, 1, 4))
    checks["its call is the Bash call still running, by its description"] = one.get("what") == "Run the tests again"
    checks["the run before is the same command's, its time and its count"] = one.get("last") == {"secs": 30, "done": 4}
    two = (got.get(sid(2)) or [{}])[0]
    checks["a run into a pipe says so, by its stdout: %s" % two] = two.get("out") == "pipe" and two.get("done") == 0
    checks["the run before is found in another transcript of its project"] = (two.get("last") or {}).get("secs") == 30
    checks["a session running none is not listed"] = sid(3) not in got
    checks["a run under no session is not listed"] = all(r["pid"] != alone.pid for rs in got.values() for r in rs)
    checks["a background run's call is the one whose task file it writes"] = (
        (got.get(sid(4)) or [{}])[0].get("what") == "Run them in the background")
    checks["a task file no background call names is a foreground call's"] = (
        (got.get(sid(5)) or [{}])[0].get("what") == "Run them in the foreground")
    time.sleep(2.2)
    got = T.runs()["runs"]
    checks["a later look reads on from where the last left"] = ((got.get(sid(1)) or [{}])[0].get("done")) == 3

    # 5 · the server: consent
    import workspace as W
    repo = os.path.join(base, "repo"); os.makedirs(repo, exist_ok=True)
    open(os.path.join(repo, "README.md"), "w").write("# runs\n")
    subprocess.run(["git", "-C", repo, "init", "-q"], check=True)
    share = Path(repo_root) / "share"
    srvs = [W.serve_workspace([repo], False, share, "", idle=10 ** 9),
            W.serve_workspace([repo], True, share, "", idle=10 ** 9)]
    try:
        j = json.load(urllib.request.urlopen(srvs[0].base + "/tests", timeout=20))
        checks["without consent the server reads nothing"] = j.get("allowed") is False and "runs" not in j
        j = json.load(urllib.request.urlopen(srvs[1].base + "/tests", timeout=20))
        checks["with it, the runs come back"] = j.get("allowed") is True and sid(1) in j.get("runs", {})
    finally:
        for s_ in srvs:
            s_.stop.set()
            try: s_.httpd.shutdown()
            except Exception: pass
except Exception as e:
    import traceback; traceback.print_exc()
    checks["the test ran: %s" % e] = False
finally:
    for q in procs:
        try: os.killpg(q.pid, signal.SIGTERM)
        except Exception: pass
for k_, v in checks.items(): print(("ok " if v else "XX ") + k_)
sys.exit(0 if checks and all(checks.values()) else 1)
PYEOF
if [ $? = 0 ]; then
  ok "46 · a test run is found under its session, counted from its output, and held to the run before"
else
  no "46 · the test runs are read wrong" "$(grep '^XX' "$WORK/testruns.txt" | tr '\n' ' ')$(tail -2 "$WORK/testruns.txt")"
fi

# ── 47 · the test runs on the page ──────────────────────────────────────────
# The page's half, lifted from the shipped source around stand-ins for the
# server and the DOM. Pinned:
#
#   - a row says how far in as few words as it can: the runner's share, what
#     finished of what it announced, or of what finished the time before,
#     or a share of the time the run before took; failures in their own
#     colour; another run as +1
#   - the foot says what it is, how far, how long, and the time before; where
#     the output cannot say how far, it says why; a share from the run before
#     is drawn as a guess, and one past the time before as late
#   - the runs are asked after once the running sessions are looked at and one
#     can be running a command, and put away when none can; then every few
#     seconds only while such a session shows on screen in a window in front;
#     never twice at once; and not while the list is not allowed
#   - what is on screen is rewritten in place
if command -v node >/dev/null; then
  python3 -c 'import sys
src = open(sys.argv[1]).read()
def sl(a, b):
    i = src.index(a); return src[i:src.index(b, i)]
open(sys.argv[2], "w").write("\n".join([
    sl("function clockFor(since)", "function tokensFor(n)"),
    sl("var FOOT = 24;", "function bandShown(b)"),
    sl("/* ── the test runs a session has going", "function stopIt(sid){"),
]))' "$REPO/share/workspace.js" "$WORK/tests-page.js"
  { cat <<'JSEOF'
var CAPS = { waiting: 1 }, GONE = 0;
function can(c){ return !!CAPS[c]; }
function esc(s){ return String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;')
                   .replace(/>/g, '&gt;').replace(/"/g, '&quot;'); }
var WAIT = { allowed: true }, RUN = {};
var asked = [];
function api(path, body, cb, fail){ asked.push({ path: path, cb: cb, fail: fail }); }
function el(attr, sid, shown){
  var e = { dataset: {}, innerHTML: '', outerHTML: '', offsetParent: shown ? {} : null, title: 'about it',
            closest: function(){ return null; } };
  e.dataset[attr] = sid; return e;
}
var onScreen = [];
var document = { hidden: false, querySelectorAll: function(sel){
  return onScreen.filter(function(e){ return sel.split(',').some(function(s){
    var k = s.replace(/^\[data-|\]$/g, '').replace(/-(.)/g, function(_, c){ return c.toUpperCase(); });
    return k in e.dataset; }); }); } };
JSEOF
    cat "$WORK/tests-page.js"
    cat <<'JSEOF'

var fail = [];
function want(c, why){ if (!c) fail.push(why); }
var A = 'aaaaaaaa-0000-4000-8000-000000000001', B = 'bbbbbbbb-0000-4000-8000-000000000002';
testsGot = Date.now();
function run(o){ var t = { pid: 1, label: 'npm run test:affected', what: 'Run the tests', secs: 30, cpu: 50, procs: 3,
  out: 'file', done: 0, failed: 0, total: null, pct: null, whole: true, last: null };
  for (var k in o) t[k] = o[k]; return t; }

/* a row: as few words as say how far */
TESTS = {}; TESTS[A] = [run({ done: 38, total: 324 })];
want(testChip(A) === 'tests 38/324', 'what finished of what it announced: ' + testChip(A));
TESTS[A] = [run({ pct: 45, done: 0 })];
want(testChip(A) === 'tests 45%', 'the runner\'s own share: ' + testChip(A));
TESTS[A] = [run({ done: 12, failed: 1, last: { secs: 40, done: 15 } })];
want(/^tests 12\/~15 <span class="tfail">1 failed<\/span>$/.test(testChip(A)), 'of what finished the time before: ' + testChip(A));
TESTS[A] = [run({ done: 7 })];
want(testChip(A) === 'tests 7 done', 'a count alone: ' + testChip(A));
TESTS[A] = [run({ secs: 30, last: { secs: 60, done: null } }), run({ pid: 2 })];
want(/^tests ~50% <span class="tmore">\+1<\/span>$/.test(testChip(A)), 'a share of the time before, and another run: ' + testChip(A));
want(testChip(B) === '', 'a session running no tests says nothing');

/* the foot: what, how far, how long, the time before, or why it cannot say */
var words = testWords(run({ done: 3, whole: false, total: 9, last: { secs: 20 }, secs: 30, cpu: 0 })).join(' | ');
want(/at least 3 of 9 finished/.test(words) && /running 30s/.test(words) && /longer than the 20s the time before took/.test(words)
     && /using no CPU just now/.test(words), 'the words of a run: ' + words);
want(/into a pipe/.test(testWords(run({ out: 'pipe' })).join()), 'a pipe does not say why');
want(/to a terminal/.test(testWords(run({ out: 'terminal' })).join()), 'a terminal does not say why');
want(/nothing counted in its output yet/.test(testWords(run({ out: 'file' })).join()), 'an empty file does not say so');
want(/could not be read/.test(testWords(run({ out: 'unknown' })).join()), 'an unread output does not say so');
var s = testShare(run({ done: 5, last: { done: 10, secs: 99 } }));
want(s.est && s.p === 0.5, 'a count of the time before is not drawn as a guess: ' + JSON.stringify(s));
s = testShare(run({ secs: 90, last: { secs: 60 } }));
want(s.est && s.late && s.p === 1, 'a run past the time before is not late: ' + JSON.stringify(s));
want(!testShare(run({ done: 3, total: 9 })).est, 'what it announced is drawn as a guess');
TESTS[A] = [run({ done: 3, total: 4 })];
var h = testsHTML(A);
want(!/ hidden/.test(h.split('>')[0]) && /data-tclock="/.test(h) && /class="trbar" style="--p:0.750"/.test(h), 'the foot: ' + h);
want(/ hidden>/.test(testsHTML(B)), 'the foot shows for a session running none');

/* asked after: once a session can be running a command, every few seconds while it shows, never twice */
TESTS = {}; asked = []; testsAt = 0; testsOut = false;
RUN = {}; RUN[A] = { sid: A, on: 'done' };
afterRunning();
want(asked.length === 0, 'asked although no session can be running a command');
RUN[A].on = 'background';
afterRunning();
want(asked.length === 1 && asked[0].path === 'tests', 'not asked once a session can be running one');
afterRunning();
want(asked.length === 1, 'asked twice at once');
var row = el('rtest', A, true), line = el('rtline', A, true), foot = el('tband', A, true), rowEl = { title: 'about it' };
row.closest = function(sel){ return sel === '.srow' ? rowEl : null; };
onScreen = [row, line, foot];
var got = {}; got[A] = [run({ done: 2, total: 8 })];
asked[0].cb({ runs: got, allowed: true });
want(row.innerHTML === 'tests 2/8' && /^about it\n— tests —\nRun the tests · 2 of 8 finished/.test(rowEl.title),
     'the row was not rewritten: ' + row.innerHTML + ' / ' + rowEl.title);
want(/class="rtline" data-rtline="aaaaaaaa[^"]*" style="--p:0.250"/.test(line.outerHTML), 'the hairline was not rewritten: ' + line.outerHTML);
want(/data-tband/.test(foot.outerHTML) && /2 of 8 finished/.test(foot.outerHTML), 'the foot was not rewritten: ' + foot.outerHTML);
tickTests();
want(asked.length === 1, 'asked again before a few seconds were up');
testsAt = Date.now() - TESTS_EVERY;
document.hidden = true; tickTests();
want(asked.length === 1, 'asked from a window not in front');
document.hidden = false; row.offsetParent = foot.offsetParent = null; tickTests();
want(asked.length === 1, 'asked for sessions not on screen');
row.offsetParent = {}; RUN[A].on = 'done'; tickTests();
want(asked.length === 1, 'asked for a session that can be running nothing');
RUN[A].on = 'working'; tickTests();
want(asked.length === 2, 'not asked every few seconds while it shows');
asked[1].cb({ runs: {} });
WAIT.allowed = false; testsAt = 0; tickTests();
want(asked.length === 2, 'asked while the list is not allowed');
WAIT.allowed = true;
RUN[A].on = 'done'; TESTS[A] = [run({})]; afterRunning();
want(!TESTS[A] && asked.length === 2, 'the runs were not put away once no session could be running one');
console.log(fail.length ? 'XX ' + fail.join('; ') : 'ok');
JSEOF
  } > "$WORK/tests-page-run.js"
  res=$(node "$WORK/tests-page-run.js" 2>&1)
  case "$res" in ok*) ok "47 · the page says how far each run is, asks only while one shows, and says why where it cannot" ;;
                 *)   no "47 · the test runs on the page are wrong" "$res" ;; esac
else
  skip "47 · the test runs on the page" "no node"
fi

# ── 48 · a project opened from a window whose terminal has closed ───────────
# A window's server outlives the terminal `md` ran in. Once that tab closes,
# a stdin taken from it is a revoked descriptor, every process the server
# starts inherits it, and a python3 handed one dies before its first line
# ("init_sys_streams: Bad file descriptor") — md at its first python3, or the
# server md starts at once — and the window would say "opened" for a window
# that never comes. Pinned:
#
#   - from a process whose stdin is a revoked terminal, a project opens: its
#     server is running when open_project returns
#   - md started on a terminal gives its server /dev/null as stdin
#   - open_project gives md /dev/null as stdin
#   - an md that fails is reported with what it said, and is not remembered
python3 - "$WORK" "$REPO" "$MD" >"$WORK/revoked.txt" 2>&1 <<'PYEOF'
import json, os, pty, re, subprocess, sys, time, urllib.request
work, repo_root, md = sys.argv[1:4]
share = os.path.join(repo_root, "share")
sys.path.insert(0, share)
import actions as A
base = os.path.join(work, "revoked"); os.makedirs(base, exist_ok=True)
def repo(name):
    r = os.path.join(base, name); os.makedirs(r, exist_ok=True)
    open(os.path.join(r, "README.md"), "w").write("# %s\n" % name)
    subprocess.run(["git", "-C", r, "init", "-q"], check=True)
    return r
def fd0(pid):
    out = subprocess.run(["lsof", "-nP", "-a", "-p", str(pid), "-d", "0"],
                         capture_output=True, text=True).stdout.strip().splitlines()
    return out[-1] if out else ""
def servers(r):
    out = subprocess.run(["pgrep", "-f", "workspace.py %s" % r], capture_output=True, text=True).stdout
    return [int(x) for x in out.split()]
os.environ.update(RUBRICATOR_NO_WINDOW="1", RUBRICATOR_NO_WATCH="1", RUBRICATOR_IDLE="2",
                  RUBRICATOR_BIN=md)
checks = {}
try:
    # the session leader of a fresh terminal starts a detached child that keeps
    # the terminal as its stdin, waits until it is up, and exits: the kernel
    # revokes the terminal, and the child opens a project on it
    far, said, ready = repo("far"), os.path.join(base, "far.json"), os.path.join(base, "ready")
    child = ("import json, os, subprocess, sys, time\n"
             "sys.path.insert(0, %r)\n"
             "import actions as A\n"
             "open(%r, 'w').close()\n"
             "end = time.time() + 10\n"
             "while os.isatty(0) and time.time() < end: time.sleep(0.05)\n"
             "r = {'revoked': not os.isatty(0)}\n"
             "try: r.update(A.open_project(%r))\n"
             "except Exception as e: r['error'] = str(e)\n"
             "r['servers'] = subprocess.run(['pgrep', '-f', 'workspace.py ' + %r],\n"
             "    capture_output=True, text=True).stdout.split()\n"
             "json.dump(r, open(%r, 'w'))\n") % (share, ready, far, far, said)
    pid, master = pty.fork()
    if pid == 0:
        subprocess.Popen([sys.executable, "-c", child], start_new_session=True)
        end = time.time() + 10
        while not os.path.exists(ready) and time.time() < end:
            time.sleep(0.05)
        os._exit(0)
    os.waitpid(pid, 0)
    os.close(master)
    end = time.time() + 40
    while not os.path.exists(said) and time.time() < end:
        time.sleep(0.1)
    got = json.load(open(said)) if os.path.exists(said) else {}
    checks["the child's stdin was a revoked terminal"] = got.get("revoked") is True
    checks["from a revoked stdin the project opens: %s" % (got.get("error") or "")] = \
        got.get("ok") is True and bool(got.get("servers"))

    # md on a live terminal: the server it leaves behind holds none of it
    near = repo("near")
    m, s = os.openpty()
    p = subprocess.run([md, near], stdin=s, capture_output=True, text=True, timeout=30)
    os.close(m); os.close(s)
    url = (re.findall(r"http://127\.0\.0\.1:\d+/[A-Za-z0-9_-]+/", p.stdout) or [""])[0]
    held = [fd0(x) for x in servers(near)]
    checks["md's server gives up the terminal it was started on: %s" % held] = \
        bool(held) and all("/dev/null" in h for h in held)
    if url:
        try: urllib.request.urlopen(urllib.request.Request(url + "bye", data=b"{}"), timeout=5)
        except Exception: pass

    # open_project, on a terminal of its own: md is handed /dev/null
    fake = os.path.join(base, "md-fake")
    seen = os.path.join(base, "fd0.txt")
    open(fake, "w").write("#!/bin/bash\nlsof -nP -a -p $$ -d 0 | tail -1 > %s\n" % seen)
    os.chmod(fake, 0o755)
    os.environ["RUBRICATOR_BIN"] = fake
    m, s = os.openpty()
    keep = os.dup(0); os.dup2(s, 0)
    try:
        A.open_project(repo("mid"))
    finally:
        os.dup2(keep, 0); os.close(keep); os.close(m); os.close(s)
    line = open(seen).read() if os.path.exists(seen) else ""
    checks["open_project hands md /dev/null, not its own stdin: %s" % line.strip()] = "/dev/null" in line

    # an md that fails says so, and the project is not remembered
    open(fake, "w").write("#!/bin/bash\necho 'rubricator: first' >&2\n"
                          "echo 'md: not a directory: nowhere' >&2\nexit 1\n")
    lost = repo("lost")
    try:
        A.open_project(lost); why = ""
    except RuntimeError as e:
        why = str(e)
    checks["an md that fails is reported with what it said: %r" % why] = \
        why == "could not open lost: not a directory: nowhere"
    checks["a project that did not open is not remembered"] = lost not in A.recents()
except Exception as e:
    import traceback; traceback.print_exc()
    checks["the test ran: %s" % e] = False
for k, v in checks.items(): print(("ok " if v else "XX ") + k)
sys.exit(0 if checks and all(checks.values()) else 1)
PYEOF
if [ $? = 0 ]; then
  ok "48 · a project opens from a window whose terminal has closed, and one that cannot says why"
else
  no "48 · opening a project is wrong" "$(grep '^XX' "$WORK/revoked.txt" | tr '\n' ' ')$(tail -2 "$WORK/revoked.txt")"
fi

# ── 49 · a document that came or went is told to the page ───────────────────
# The watch reads the mtimes of what it indexed every second, and finds what
# came or went by listing the tree every LIST_EVERY seconds — one here, so the
# test does not wait twenty. Pinned:
#   - a listing keys paths as `build` does, a second root's under its name
#   - a document written after the index is told as added, and an ignored one
#     beside it is not
#   - it is told once, though the index still lacks it
#   - a document deleted from disk is told as gone
python3 - "$WORK" "$REPO" >"$WORK/listing.txt" 2>&1 <<'PYEOF'
import http.client, json, os, subprocess, sys, time
from pathlib import Path
work, repo_root = sys.argv[1], sys.argv[2]
share = os.path.join(repo_root, "share")
sys.path.insert(0, share)
import workspace as W
base = os.path.join(work, "listing")
def repo(name, files):
    r = os.path.join(base, name); os.makedirs(r, exist_ok=True)
    for f, s in files.items():
        open(os.path.join(r, f), "w").write(s)
    subprocess.run(["git", "-C", r, "init", "-q"], check=True)
    subprocess.run(["git", "-C", r, "add", "-A"], check=True)
    return r
checks = {}
srv = conn = None
try:
    one = repo("one", {"a.md": "# a\n", "b.md": "# b\n", ".gitignore": "ignored.md\n"})
    two = repo("two", {"c.md": "# c\n"})
    built = {d["rel"] for d in W.build([one, two], False)["docs"]}
    checks["a listing keys paths as the index does"] = W.listed([one, two]) == built == {"a.md", "b.md", "two/c.md"}

    W.LIST_EVERY = 1
    # an idle of three makes the stream say it is there every second, so a
    # read never times out (which would end the response for good) and a
    # quiet stretch is read as quiet
    srv = W.serve_workspace([one], False, Path(share), "", idle=3)
    conn = http.client.HTTPConnection("127.0.0.1", srv.port, timeout=4)
    conn.request("GET", "/" + srv.token + "/events", headers={"Host": "127.0.0.1"})
    res = conn.getresponse()
    def told(within):
        end, out = time.time() + within, []
        while time.time() < end:
            ln = res.fp.readline().decode().strip()
            if ln.startswith("data:"):
                j = json.loads(ln[5:])
                if j.get("added") or j.get("gone"):
                    out.append(j)
                    if within > 3:
                        break
        return out
    checks["the stream opens"] = res.fp.readline().decode().strip() == ": watching"
    open(os.path.join(one, "ignored.md"), "w").write("# ignored\n")
    open(os.path.join(one, "new.md"), "w").write("# new\n")
    got = told(6)
    checks["a new document is told as added, the ignored one is not"] = \
        len(got) == 1 and got[0]["added"] == ["new.md"] and got[0]["gone"] == []
    checks["and only once, though the index still lacks it"] = told(2.5) == []
    os.remove(os.path.join(one, "b.md"))
    got = told(6)
    checks["a deleted document is told as gone"] = len(got) == 1 and got[0]["gone"] == ["b.md"]
except Exception as e:
    import traceback; traceback.print_exc()
    checks["the test ran: %s" % e] = False
finally:
    if conn: conn.close()
    if srv:
        srv.stop.set()
        try: srv.httpd.shutdown()
        except Exception: pass
for k, v in checks.items(): print(("ok " if v else "XX ") + k)
sys.exit(0 if checks and all(checks.values()) else 1)
PYEOF
if [ $? = 0 ]; then
  ok "49 · a document written or deleted while the window is open is told to the page"
else
  no "49 · a document that came or went is not told" "$(grep '^XX' "$WORK/listing.txt" | tr '\n' ' ')$(tail -2 "$WORK/listing.txt")"
fi

# ── 50 · nothing in this run scripted another application ───────────────────
# The tripwire at the top of this file stands where `osascript` would be found.
# A test that reached it — the hook closing a window it never opened, a reply
# that missed the dry seam — wrote its arguments down, and that is a failure
# whether or not the test that did it noticed.
if [ ! -s "$WORK/osascript.log" ]; then
  ok "50 · nothing in the suite reached osascript"
else
  no "50 · something in the suite called osascript" "$(head -3 "$WORK/osascript.log" | tr '\n' ' ')"
fi

printf '\n  %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
