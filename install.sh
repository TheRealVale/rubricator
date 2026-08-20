#!/usr/bin/env bash
# rubricator installer.  Safe to re-run; nothing here needs root.
set -euo pipefail

REPO="$(cd -P "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PREFIX="${PREFIX:-$HOME/.local}"
MODE="copy"
SHELL_RC=1
WITH_HOOK=0

usage() {
  cat <<'USAGE'
rubricator installer

  ./install.sh [options]

  --link         symlink the command at this checkout instead of copying,
                 so edits here take effect immediately (good for hacking on it)
  --prefix DIR   install under DIR (default: ~/.local)
  --no-shell     skip the zsh alias + completion block in ~/.zshrc
  --with-hook    also install the Claude Code plan-review hook
  -h, --help     this
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --link)      MODE="link" ;;
    --prefix)    shift; PREFIX="${1:?--prefix needs a directory}" ;;
    --no-shell)  SHELL_RC=0 ;;
    --with-hook) WITH_HOOK=1 ;;
    -h|--help)   usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage; exit 1 ;;
  esac
  shift
done

say() { printf '  %s\n' "$*"; }
die() { printf 'rubricator: %s\n' "$*" >&2; exit 1; }

echo "rubricator → $PREFIX"

# ── prerequisites ────────────────────────────────────────────────────────────
command -v curl >/dev/null || die "curl is required (to fetch the render libraries)"
if ! command -v python3 >/dev/null && [ ! -x /usr/bin/python3 ]; then
  say "note: python3 not found — 'md --review' and the Claude Code hook will be unavailable"
fi
[ "$(uname -s)" = "Darwin" ] || say "note: built for macOS; on other systems 'open' must exist to launch a browser"

# ── files ────────────────────────────────────────────────────────────────────
mkdir -p "$PREFIX/bin" "$PREFIX/share/rubricator"
if [ "$MODE" = "link" ]; then
  ln -sfn "$REPO/bin/md" "$PREFIX/bin/md"
  rm -rf "$PREFIX/share/rubricator"
  say "linked $PREFIX/bin/md → $REPO/bin/md"
  SHARE="$REPO/share"
else
  install -m 0755 "$REPO/bin/md" "$PREFIX/bin/md"
  for f in template.html review.css review.js ui.css ui.js md.zsh vendor.txt; do
    install -m 0644 "$REPO/share/$f" "$PREFIX/share/rubricator/$f"
  done
  install -m 0755 "$REPO/share/hook.py" "$PREFIX/share/rubricator/hook.py"
  say "installed $PREFIX/bin/md and $PREFIX/share/rubricator"
  SHARE="$PREFIX/share/rubricator"
fi

# ── render libraries (pinned + checksummed; see share/vendor.txt) ────────────
if ! "$PREFIX/bin/md" --vendor; then
  say "warning: could not fetch the render libraries — run 'md --vendor' once you are online"
fi

# ── shell integration ────────────────────────────────────────────────────────
if [ "$SHELL_RC" = 1 ] && [ -n "${HOME:-}" ]; then
  RC="$HOME/.zshrc"
  if [ -f "$RC" ]; then
    tmp="$(mktemp)"
    grep -v 'md-render/md\.zsh\|rubricator/md\.zsh\|rubricator/share/md\.zsh' "$RC" \
      | awk 'BEGIN{skip=0} /^# >>> rubricator >>>$/{skip=1} skip==0{print} /^# <<< rubricator <<<$/{skip=0}' > "$tmp"
    { echo ""
      echo "# >>> rubricator >>>"
      echo "[ -f \"$SHARE/md.zsh\" ] && source \"$SHARE/md.zsh\""
      echo "# <<< rubricator <<<"
    } >> "$tmp"
    mv "$tmp" "$RC"
    say "added the rubricator block to ~/.zshrc (alias fix + tab completion)"
  else
    say "no ~/.zshrc found — add:  source \"$SHARE/md.zsh\""
  fi
fi

case ":$PATH:" in
  *":$PREFIX/bin:"*) ;;
  *) say "note: $PREFIX/bin is not on your PATH — add it to your shell profile" ;;
esac

# ── optional: the Claude Code hook ───────────────────────────────────────────
if [ "$WITH_HOOK" = 1 ]; then
  "$REPO/install-hook.sh"
fi

cat <<EOF

  Done. Open a new terminal (or: exec zsh), then:

    md README.md          render and open
    md                    README.md in the current directory
    md --help             everything else

  oh-my-zsh binds 'md' to 'mkdir -p'; rubricator takes the name and gives you 'mkd' instead.
EOF
[ "$WITH_HOOK" = 1 ] || cat <<'EOF'
  Claude Code users: ./install-hook.sh wires up plan review (see the README).

EOF
