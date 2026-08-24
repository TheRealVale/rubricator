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
  # Every file in share/, asked of git rather than listed here. The list this
  # replaced named eight of eighteen: it was correct when it was written, then
  # render.js was lifted out of template.html and nobody updated it, so every
  # install but the maintainer's rendered a blank page and exited 0. A
  # hand-kept list has no way to learn about a new file. git ls-files already
  # knows, and vendor/ and __pycache__/ are already ignored, so this loop
  # carries no inventory of its own to drift.
  git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1 || die \
    "install.sh reads the file list from git ls-files, so it needs a checkout.
    Clone rather than downloading an archive:
      git clone https://github.com/TheRealVale/rubricator.git"
  n=0
  while IFS= read -r rel; do
    [ -f "$REPO/$rel" ] || continue
    install -m "$(stat -f '%Lp' "$REPO/$rel" 2>/dev/null || echo 0644)" \
      "$REPO/$rel" "$PREFIX/share/rubricator/${rel#share/}"
    n=$((n + 1))
  done < <(git -C "$REPO" ls-files share/)
  [ "$n" -gt 0 ] || die "git ls-files share/ returned nothing — incomplete checkout?"
  say "installed $PREFIX/bin/md and $n files in $PREFIX/share/rubricator"
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
    # strip ANY previous block of ours, including ones written under an older
    # name — otherwise a rename leaves a dead source line behind
    # `|| true`: grep exits 1 when it emits no lines, and a zero-length ~/.zshrc
    # made that abort the whole script under `set -e` — no block, no banner, no
    # hook, and no error. An rc containing only our own markers survived,
    # because it still emitted two lines, which is why this went unnoticed.
    { grep -v '/md\.zsh"' "$RC" || true; } \
      | awk 'BEGIN{skip=0}
             /^# >>> (rubricator|markside|md-render) >>>$/{skip=1}
             skip==0{print}
             /^# <<< (rubricator|markside|md-render) <<<$/{skip=0}' > "$tmp"
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

# ── prove it works before saying it does ─────────────────────────────────────
# The old script printed "Done." having never rendered anything, then told the
# reader to run `md README.md` — which, on this install, produced a blank page.
# A self-check cannot drift the way a list can, because it exercises the
# artefact instead of describing it.
selfcheck() {
  local d out
  "$PREFIX/bin/md" --version >/dev/null 2>&1 || { say "self-check: md --version failed"; return 1; }
  d="$(mktemp -d)"; trap 'rm -rf "$d"' RETURN
  printf '# rubricator self-check\n\nIf you can read this heading, the renderer is installed.\n' > "$d/check.md"
  out="$d/check.html"
  "$PREFIX/bin/md" -o "$out" "$d/check.md" >/dev/null 2>&1 \
    || { say "self-check: md -o exited non-zero"; return 1; }
  [ -s "$out" ] || { say "self-check: md -o wrote nothing"; return 1; }
  # 'md renderer' is the first line of share/render.js and appears nowhere else
  # in bin/ or share/. Do NOT grep for 'window.MD': review.js defines
  # window.MDReview, so that string is present on the broken page too and the
  # check would pass on the exact bug it exists to catch.
  grep -q 'md renderer' "$out" \
    || { say "self-check: the page has no renderer in it — $PREFIX/share/rubricator is incomplete"; return 1; }
  grep -q '<title>check.md</title>' "$out" \
    || { say "self-check: the page was built without the document"; return 1; }
  # the document itself rides in the payload as base64, so assert on that
  # rather than on its text, which never appears literally
  b64="$(base64 < "$d/check.md" | tr -d '\n' | cut -c1-32)"
  grep -q "$b64" "$out" \
    || { say "self-check: the document did not reach the payload"; return 1; }
  return 0
}
if selfcheck; then
  READY=1
else
  READY=0
  say ""
  say "The install did not verify. Do not expect 'md' to render anything yet."
  say "Re-run with a full checkout, or open an issue with the line above."
fi

# ── optional: the Claude Code hook ───────────────────────────────────────────
if [ "$WITH_HOOK" = 1 ]; then
  "$REPO/install-hook.sh"
fi

[ "$READY" = 1 ] || exit 1

cat <<EOF

  Done — rendered a test page to prove it. Open a new terminal (or: exec zsh), then:

    md README.md          render and open
    md                    README.md in the current directory
    md --help             everything else

  oh-my-zsh binds 'md' to 'mkdir -p'; rubricator takes the name and gives you 'mkd' instead.
EOF
[ "$WITH_HOOK" = 1 ] || cat <<'EOF'
  Claude Code users: ./install-hook.sh wires up plan review (see the README).

EOF
