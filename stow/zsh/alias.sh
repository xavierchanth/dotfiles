#!/bin/zsh

# you probably think this is dumb right?
# well... it actually does something really cool
# it makes it so that you can use sudo with other aliases
alias sudo='sudo '

if [ "$uname" = 'Darwin' ]; then
  alias x64='arch -x86_64'
fi
alias s='source $HOME/.zshenv && source $HOME/.zshrc'
alias q='exit'

alias v='nvim'
alias c='codex'
alias m='aerc'

alias clera='clear' # Mistakes happen ok... I make this one alot

alias ff='clear; fastfetch'

wrapped_man() {
  /usr/bin/man $1 ||
    if command -v $1 >/dev/null 2>&1; then
      $1 --help | $PAGER
    fi
}
alias man='wrapped_man'
# provides a fallback set of arguments for the command if no arguments are provided
wrapped_alias() {
  eval "function $1() { if [ \$# -gt 0 ]; then $2 \$@; else $2 $3; fi; }"
}
wrapped_alias "t" "tmux" "new -A -s 'main'"
wrapped_alias "z" "zed" "."

if [ "$(uname)" = 'Darwin' ]; then
  alias net='open "x-apple.systempreferences:com.apple.preference.network"'
fi

# Get a whole website recursively (-r), including css & js (-p)
# --no-parent ensures you only get this page and everything nested under it
# rather than the whole site
alias wgetsite='wget --no-parent -p -r'

alias y='yazi'
