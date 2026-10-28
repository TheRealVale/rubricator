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
# was called, and fails. Test 34 reads what it wrote, which has to be nothing.
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
   payload. A new one belongs here only if nothing is meant to click it. */
var PAYLOAD = ['copy-note','f','fg','id','line','n','q','sid','t','val'];

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
    checks["a session that waits for you passes the guard"] = refused(1) is None and refused(7) is None
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

/* a stand-in for the DOM: the elements landing can ask for are made from the
   markup the surface wrote, and each records where it was scrolled to */
function Host(shown){
  var h = { offsetHeight: shown ? 600 : 0, scrollTop: 0, scrollHeight: 5000, moved: [], html: '' };
  var inner = { set innerHTML(v){ h.html = v; }, get innerHTML(){ return h.html; } };
  h.querySelector = function(sel){ return /inner/.test(sel) && h.html !== null ? inner : null; };
  Object.defineProperty(h, 'innerHTML', { set: function(v){ h.html = ''; } });
  h.querySelectorAll = function(){
    var out = [], re = /<div class="(turn [a-z]+|sreply)"/g, m, i = 0;
    while ((m = re.exec(h.html))){
      (function(name, k){
        out.push({ name: name, scrollIntoView: function(o){ h.moved.push(name + '#' + k + ':' + o.block); h.scrollTop = 4000; } });
      })(m[1], i++);
    }
    return out;
  };
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
want(host.moved.join() === 'sreply#4:end', 'it did not open at its foot: ' + host.moved);
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
want(host.moved.join() === 'turn claude#3:end', 'shown, it did not open at its last turn, once: ' + host.moved);

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

# ── 34 · nothing in this run scripted another application ───────────────────
# The tripwire at the top of this file stands where `osascript` would be found.
# A test that reached it — the hook closing a window it never opened, a reply
# that missed the dry seam — wrote its arguments down, and that is a failure
# whether or not the test that did it noticed.
if [ ! -s "$WORK/osascript.log" ]; then
  ok "34 · nothing in the suite reached osascript"
else
  no "34 · something in the suite called osascript" "$(head -3 "$WORK/osascript.log" | tr '\n' ' ')"
fi

printf '\n  %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
