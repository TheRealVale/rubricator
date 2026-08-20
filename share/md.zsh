# rubricator — the `md` command: alias fix + completion.  Sourced from ~/.zshrc.

# oh-my-zsh's lib/directories.zsh binds md='mkdir -p'; hand the name to the renderer
# and keep the mkdir shortcut as `mkd`.
unalias md 2>/dev/null
alias mkd='mkdir -p'

_md() {
  _arguments -s -S \
    '(-b --browser -t --tab)'{-b,--browser,-t,--tab}'[open in a normal browser tab]' \
    '(-n --no-open)'{-n,--no-open}'[only generate; print the path]' \
    '(-p --print)'{-p,--print}'[print the HTML to stdout]' \
    '(-o --out)'{-o,--out}'[write standalone HTML to FILE]:output file:_files -g "*.html"' \
    '--light[start in light mode]' \
    '(- *)'{-h,--help}'[show help]' \
    '(- *)'{-v,--version}'[show version]' \
    '*:markdown file:_files -g "*.(md|markdown|mdown|mkd|mdx|mdc|qmd|rmd|txt|MD|Markdown)"'
}
compdef _md md
