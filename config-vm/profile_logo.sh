# --- optional aliases
[ -f ~/nudger/config-vm/.bash_aliases ] && . ~/nudger/config-vm/.bash_aliases

# --- bash-completion core (if installed)
if [ -f /usr/share/bash-completion/bash_completion ]; then
  . /usr/share/bash-completion/bash_completion
elif [ -f /etc/bash_completion ]; then
  . /etc/bash_completion
fi

# --- kubectl completion + alias k
if command -v kubectl >/dev/null 2>&1; then
  COMPLETION_DIR="$HOME/.local/share/bash-completion/completions"
  KUBE_COMPLETION_FILE="$COMPLETION_DIR/kubectl"
  mkdir -p "$COMPLETION_DIR"
  if [[ ! -f "$KUBE_COMPLETION_FILE" || "$(command -v kubectl)" -nt "$KUBE_COMPLETION_FILE" ]]; then
    kubectl completion bash > "$KUBE_COMPLETION_FILE" 2>/dev/null || true
  fi
  [ -f "$KUBE_COMPLETION_FILE" ] && . "$KUBE_COMPLETION_FILE"
  alias k='kubectl'
  complete -o default -F __start_kubectl k
fi

# --- fzf (single source)
if [ -f /usr/share/doc/fzf/examples/key-bindings.bash ]; then
  . /usr/share/doc/fzf/examples/key-bindings.bash
elif [ -f ~/.fzf.bash ]; then
  . ~/.fzf.bash
fi

# --- git minimal aliases + safe helpers
if command -v git >/dev/null 2>&1; then
  alias g='git'
  alias gs='git status -sb'
  alias glg='git log --oneline --graph --decorate --date=relative'
  alias gfa='git fetch --all --prune'
  alias gpl='git pull --ff-only'
  alias gsw='git switch'
  alias gswc='git switch -c'
  alias grs='git restore'
  alias grst='git restore --staged'
  alias gcm='git commit -m'
  alias gca='git add -A && git commit -m'
  gpup() { git push -u origin "$(git branch --show-current)"; }

  # protected branches for force push / delete
  _git_protected_regex='^(main|master|prod|production|release/.+)$'
  gpf() {
    local cur; cur="$(git branch --show-current 2>/dev/null)"
    [[ "$cur" =~ $_git_protected_regex ]] && { echo "no force on $cur"; return 1; }
    git push --force-with-lease "$@"
  }
  gbD() {
    local b="$1"
    [ -n "$b" ] || { echo "usage: gbD <branch>"; return 1; }
    [[ "$b" =~ $_git_protected_regex ]] && { echo "protected: $b"; return 1; }
    git branch -D "$b"
  }

  # completion for git aliases (if _git is available)
  if type _git >/dev/null 2>&1; then
    complete -o bashdefault -o default -F _git g
    complete -o bashdefault -o default -F _git gs
    complete -o bashdefault -o default -F _git glg
    complete -o bashdefault -o default -F _git gsw
    complete -o bashdefault -o default -F _git gswc
    complete -o bashdefault -o default -F _git grs
    complete -o bashdefault -o default -F _git grst
    complete -o bashdefault -o default -F _git gcm
    complete -o bashdefault -o default -F _git gca
  fi
fi

# --- Starship (prompt) ---
# --- Starship (prompt) ---
if command -v starship >/dev/null 2>&1; then
  # Ensure config dir exists
  mkdir -p "$HOME/.config"

  # Si le fichier n'existe pas encore, copie depuis ton repo
  if [ ! -f "$HOME/.config/starship.toml" ] && [ -f "$HOME/nudger/config-vm/starship.toml" ]; then
    cp "$HOME/nudger/config-vm/starship.toml" "$HOME/.config/starship.toml"
  fi

  # Utilise le starship.toml local s’il existe
  if [ -r "$HOME/.config/starship.toml" ]; then
    export STARSHIP_CONFIG="$HOME/.config/starship.toml"
  fi

  # Active starship uniquement en shell interactif
  case "$-" in
    *i*) eval "$(starship init bash)";;
  esac
fi
# --- Zoxide (no eval/init): cd wrapper + j/ji + completion
if command -v zoxide >/dev/null 2>&1; then
  export _ZO_DATA_DIR="$HOME/.local/share/zoxide"

  # feed DB on each cd (robust)
  cd() {
    if builtin cd "$@"; then
      zoxide add "$(pwd -L)" >/dev/null 2>&1 || true
      return 0
    else
      return $?
    fi
  }

  # jump commands
  j()  { local d; d="$(zoxide query -- "$@")"  || return; [ -d "$d" ] && builtin cd "$d"; }
  ji() { local d; d="$(zoxide query -i -- "$@")" || return; [ -d "$d" ] && builtin cd "$d"; }

  # completion for j/ji (list known paths)
  _j_complete() {
    local cur; COMPREPLY=(); cur="${COMP_WORDS[COMP_CWORD]}"
    mapfile -t COMPREPLY < <(zoxide query -l -- "$cur" 2>/dev/null)
  }
  complete -o dirnames -F _j_complete j
  complete -o dirnames -F _j_complete ji
fi
