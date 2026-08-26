#!/usr/bin/env bash
# Install (or remove) the Claude Code hook that opens rubricator's review window
# when Claude finishes a plan.   Usage:  ./install-hook.sh [--remove]
#
# P7. There is now a channel that does not need this script at all:
#
#   /plugin marketplace add TheRealVale/rubricator
#   /plugin install rubricator@rubricator
#
# which delivers hooks/hooks.json and needs no edit to your settings.json.
# Prefer it. This script stays for the people who install with ./install.sh and
# do not want a second mechanism, and because it is the only path that also
# works when rubricator lives somewhere the plugin loader will not look. It
# backs your settings up before touching them and is idempotent either way.
set -euo pipefail

SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"
REMOVE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --remove)   REMOVE=1 ;;
    --settings) shift; SETTINGS="${1:?--settings needs a path}" ;;
    -h|--help)  sed -n '2,3p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

REPO="$(cd -P "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
MD="$(command -v md 2>/dev/null || true)"
case "$MD" in "") MD="$HOME/.local/bin/md" ;; esac
[ -x "$MD" ] || MD="$REPO/bin/md"
[ -x "$MD" ] || { echo "rubricator: cannot find the md command — run ./install.sh first" >&2; exit 1; }

[ -f "$SETTINGS" ] || { echo "rubricator: no Claude Code settings at $SETTINGS" >&2; exit 1; }
command -v python3 >/dev/null || { echo "rubricator: python3 required" >&2; exit 1; }

BACKUP="$SETTINGS.bak-rubricator-$(date +%Y%m%d%H%M%S)"
cp "$SETTINGS" "$BACKUP"

python3 - "$SETTINGS" "$REMOVE" "$MD" <<'PY'
import collections, json, sys
path, remove, md = sys.argv[1], sys.argv[2] == "1", sys.argv[3]
with open(path, encoding="utf-8") as f:
    cfg = json.load(f, object_pairs_hook=collections.OrderedDict)

hooks = cfg.setdefault("hooks", collections.OrderedDict())
pre   = hooks.setdefault("PreToolUse", [])
had   = any(e.get("matcher") == "ExitPlanMode" for e in pre)
pre[:] = [e for e in pre if e.get("matcher") != "ExitPlanMode"]        # idempotent

if remove:
    if not pre:   hooks.pop("PreToolUse", None)
    if not hooks: cfg.pop("hooks", None)
    print("  plan-review hook " + ("removed" if had else "was not installed"))
else:
    pre.append(collections.OrderedDict([
        ("matcher", "ExitPlanMode"),
        ("hooks", [collections.OrderedDict([
            ("type", "command"),
            ("command", f"{md} --hook plan"),
            ("timeout", 600),
        ])]),
    ]))
    print("  plan-review hook " + ("updated" if had else "installed") + f" → {md} --hook plan")

with open(path, "w", encoding="utf-8") as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)
    f.write("\n")
PY

python3 -m json.tool < "$SETTINGS" > /dev/null && echo "  settings.json is valid JSON"
echo "  backup: $BACKUP"
echo
echo "  Restart Claude Code for it to take effect.   Undo: $0 --remove"
echo "  (Or skip this script entirely: /plugin marketplace add TheRealVale/rubricator)"
