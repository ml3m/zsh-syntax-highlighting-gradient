# Minimal stub to silence loader when directory exists but highlighter is unused.

_zsh_highlight_highlighter_lolcat_predicate() {
  # Never run; not enabled in ZSH_HIGHLIGHT_HIGHLIGHTERS
  return 1
}

_zsh_highlight_highlighter_lolcat_paint() {
  # No-op
  :
}

