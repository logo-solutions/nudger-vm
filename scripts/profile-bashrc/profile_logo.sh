export LOGO_DIR="/root"
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
source .bash_aliases
# --- git minimal  helpers
if command -v git >/dev/null 2>&1; then
  gpup() { git push -u origin "$(git branch --show-current)"; }

  # protected branches for force push / delete
  _git_protected_regex='^(main|master|prod|production|release/.+)$'
  gpf() {
    local cur; cur="$(git branch --show-current 2>/dev/null)"
    [[ "$cur" =~ $_git_protected_regex ]] && { echo "⛔ no force on $cur"; return 1; }
    git push --force-with-lease "$@"
  }
  gbD() {
    local b="$1"
    [ -n "$b" ] || { echo "usage: gbD <branch>"; return 1; }
    [[ "$b" =~ $_git_protected_regex ]] && { echo "⛔ protected: $b"; return 1; }
    git branch -D "$b"
  }

  # Quick check identity
  gitwho() { 
    echo "user.name=$(git config user.name) | user.email=$(git config user.email)"
  }
fi
# --- Prompt personnalisé (texte + couleurs)
parse_git_branch() {
  git branch --show-current 2>/dev/null
}

# Couleurs
RED="\[\033[0;31m\]"
GREEN="\[\033[0;32m\]"
YELLOW="\[\033[0;33m\]"
BLUE="\[\033[0;34m\]"
MAGENTA="\[\033[0;35m\]"
CYAN="\[\033[0;36m\]"
RESET="\[\033[0m\]"

# Prompt : user@host chemin [branche]
PS1="${GREEN}\u${RESET}@${CYAN}\h ${YELLOW}\w${RESET}\
\$(branch=\$(parse_git_branch); if [ -n \"\$branch\" ]; then echo \" [${MAGENTA}\$branch${RESET}]\"; fi)\n\$ "

  git config --global user.email "loic@logo-solutions.fr"
  git config --global user.name "logo"
