#!/bin/zsh

# Rebuild PATH once.  Home Manager and login programs can both add entries, so
# keep configured buckets deterministic and retain everything else at the end.
typeset -a _path_inherited _path_local _path_wrappers _path_nix _path_brew _path_darwin_d
typeset -a _path_darwin _path_misc _path_base
_path_inherited=( $path )
_path_misc=()
_path_local=(
  ${DOTFILES_HOST_BIN:+"$DOTFILES_HOST_BIN"}
  "$HOME/.dotfiles/bin/shared"
  "$HOME/.local/bin"
  ${ANDROID_HOME:+"$ANDROID_HOME/cmdline-tools/latest/bin"}
)

for _path_entry in $_path_inherited; do
  [[ -n $_path_entry ]] || continue
  if [[ -n $ANDROID_HOME && $_path_entry == "$ANDROID_HOME/cmdline-tools/latest/bin" ]]; then
    continue
  fi
  case $_path_entry in
    "$HOME/.dotfiles/bin/hosts/"*|"$HOME/.dotfiles/bin/shared"|"$HOME/.local/bin") ;;
    "$HOME/.local/share/mise/shims"|"$HOME/.local/share/mise/"*) ;; # rebuilt below; never inherit stale mise state
    "$HOME/.cargo/bin"|"$HOME/go/bin"|"$HOME/.dotnet/tools"|"$HOME/.bun/bin"|"$HOME/.pub-cache/bin"|"$HOME/.local/dev/flutter/"*|"$HOME/.local/share/gem/"*/bin) ;;
    /run/wrappers/bin) _path_wrappers+=( "$_path_entry" ) ;;
    "$HOME/.nix-profile/bin"|/etc/profiles/per-user/*/bin|/nix/var/nix/profiles/default/bin|/run/current-system/sw/bin) _path_nix+=( "$_path_entry" ) ;;
    /opt/homebrew/bin|/opt/homebrew/sbin|/home/linuxbrew/.linuxbrew/bin|/home/linuxbrew/.linuxbrew/sbin) _path_brew+=( "$_path_entry" ) ;;
    *) _path_misc+=( "$_path_entry" ) ;;
  esac
done

if [[ $OSTYPE == darwin* ]]; then
  for _path_file in /etc/paths.d/*(N); do
    while IFS= read -r _path_entry || [[ -n $_path_entry ]]; do
      [[ -n $_path_entry ]] && _path_darwin_d+=( "$_path_entry" )
    done < "$_path_file"
  done
  if [[ -r /etc/paths ]]; then
    while IFS= read -r _path_entry || [[ -n $_path_entry ]]; do
      [[ -n $_path_entry ]] && _path_darwin+=( "$_path_entry" )
    done < /etc/paths
  fi
fi

# mise receives a stable path without local prefixes.  Consequently every
# hook-env result can be fixed up by prepending a small, constant-size array.
_path_base=(
  "$HOME/.local/share/mise/shims"
  $_path_wrappers
  $_path_nix
  $_path_brew
  $_path_darwin_d
  $_path_darwin
  $_path_misc
)
typeset -gU path PATH
path=( $_path_base )
unset MANPATH

# Do not let activation inherited from an outer shell restore its old PATH.
unset MISE_SHELL __MISE_DIFF __MISE_SESSION __MISE_ORIG_PATH \
  __MISE_ZSH_PRECMD_RUN __MISE_ZSH_CHPWD_RAN

if (( $+commands[mise] )); then
  eval "$(mise activate zsh)"

  # Drop mise's per-prompt refresh.  Keep directory refreshes, followed by the
  # configured local prefix (config edits take effect after cd or a new shell).
  autoload -Uz add-zsh-hook
  add-zsh-hook -d precmd _mise_hook_precmd 2>/dev/null
  add-zsh-hook -d chpwd _mise_hook_chpwd 2>/dev/null
  _dotfiles_mise_chpwd() {
    (( $+functions[_mise_hook_chpwd] )) && _mise_hook_chpwd
    path=( $_path_local $path )
  }
  add-zsh-hook chpwd _dotfiles_mise_chpwd
fi
path=( $_path_local $path )

# clang
export CPATH="/usr/local/include${CPATH:+:$CPATH}"

# cmake
alias cmbs='cmake -G Ninja -B build -S . -DCMAKE_INSTALL_PREFIX="$HOME/.local/" -DCMAKE_EXPORT_COMPILE_COMMANDS=ON -DCMAKE_BUILD_TYPE=Debug -DCMAKE_C_COMPILER=gcc -DCMAKE_C_FLAGS="-std=c99 -Wno-error"'
alias cmbr='cmake -G Ninja -B build -S . -DCMAKE_INSTALL_PREFIX="$HOME/.local/" -DCMAKE_EXPORT_COMPILE_COMMANDS=ON -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=gcc -DCMAKE_C_FLAGS="-std=c99 -Wno-error"'
alias cmbb='cmake --build build'
alias cmcc='ln -s build/compile_commands.json .; [ -d "./tests" ] && ln -s build/compile_commands.json ./tests'
alias ctb='ctest --test-dir build --output-on-failure'
alias ccc='cmbs; cmbb; cmcc'

if (( $+commands[arduino-cli] )); then
  alias ard='arduino-cli'
  function ard-upload() {
    local p="$1"
    if [[ -z "$p" ]]; then
      echo "Usage: ard-upload <path>"
      return 1
    fi
    local selected="$(arduino-cli board list | tail -n +2 | fzf)"
    [[ -n "$selected" ]] || { echo Nothing selected; return 0; }
    arduino-cli upload "$p" -b "$(echo $selected | rev | cut -w -f2 | rev)" -p "$(echo $selected | cut -w -f1)"
  }
fi

unset _path_inherited _path_wrappers _path_nix _path_brew _path_darwin_d _path_darwin _path_misc _path_base _path_entry _path_file
