#!/usr/bin/env bash
# Remove markside.  Leaves your annotations (they live in the browser) alone.
set -euo pipefail
PREFIX="${PREFIX:-$HOME/.local}"
KEEP_CACHE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --prefix) shift; PREFIX="${1:?}" ;;
    --keep-cache) KEEP_CACHE=1 ;;
    -h|--help) sed -n '2,3p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac; shift
done
say() { printf '  %s\n' "$*"; }

[ -e "$PREFIX/bin/md" ] && { rm -f "$PREFIX/bin/md"; say "removed $PREFIX/bin/md"; }
[ -d "$PREFIX/share/markside" ] && { rm -rf "$PREFIX/share/markside"; say "removed $PREFIX/share/markside"; }
if [ "$KEEP_CACHE" = 0 ] && [ -d "$HOME/.cache/markside" ]; then
  rm -rf "$HOME/.cache/markside"; say "removed the render cache"
fi
RC="$HOME/.zshrc"
if [ -f "$RC" ] && grep -q '>>> markside >>>' "$RC"; then
  tmp="$(mktemp)"
  awk 'BEGIN{skip=0} /^# >>> markside >>>$/{skip=1} skip==0{print} /^# <<< markside <<<$/{skip=0}' "$RC" > "$tmp"
  # drop the blank line the installer added, so the file is byte-identical again
  awk 'NF{last=NR}{l[NR]=$0}END{for(i=1;i<=last;i++)print l[i]}' "$tmp" > "$tmp.2" && mv "$tmp.2" "$tmp"
  mv "$tmp" "$RC"; say "removed the markside block from ~/.zshrc"
fi
echo
say "If you installed the Claude Code hook, remove it with: ./install-hook.sh --remove"
say "A checkout of this repo is untouched — delete it if you want it gone."
