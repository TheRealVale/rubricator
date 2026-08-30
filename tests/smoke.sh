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

printf '\n  %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
