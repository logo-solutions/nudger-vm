# ~/.bashrc

# Charger les alias
if [ -f ~/.bash_aliases ]; then
    . ~/.bash_aliases
fi

# Charger le profil Kubernetes si dispo
if [ -f ~/nudger/config-vm/profile_logo.sh ]; then
    source ~/nudger/config-vm/profile_logo.sh
fi

if command -v kubectl &> /dev/null; then
    # Définit le fichier où stocker la complétion
    COMPLETION_DIR="$HOME/.local/share/bash-completion/completions"
    KUBE_COMPLETION_FILE="$COMPLETION_DIR/kubectl"

    # Génère la complétion seulement si le binaire existe et que le fichier de complétion est plus ancien ou manquant
    if [[ ! -f "$KUBE_COMPLETION_FILE" || "$(which kubectl)" -nt "$KUBE_COMPLETION_FILE" ]]; then
        mkdir -p "$COMPLETION_DIR"
        kubectl completion bash > "$KUBE_COMPLETION_FILE" 2>/dev/null || echo "Warning: Échec de génération de la complétion kubectl" >&2
    fi

    # Charge la complétion
    if [[ -f "$KUBE_COMPLETION_FILE" ]]; then
        source "$KUBE_COMPLETION_FILE"
        # Configure la complétion pour l'alias 'k'
        complete -o default -F __start_kubectl k
    fi
fi
# --- fzf + Ctrl-R pour BASH ---
# Ne s'applique qu'à Bash
[ -n "$BASH_VERSION" ] || return 0

# Charge les bindings fournis par le paquet fzf (Ubuntu/Debian)
if [ -f /usr/share/doc/fzf/examples/key-bindings.bash ]; then
  . /usr/share/doc/fzf/examples/key-bindings.bash
fi

# Variante installateur (si ~/.fzf.bash existe)
[ -f ~/.fzf.bash ] && . ~/.fzf.bash

# Fallback : si Ctrl-R n'est pas lié, on crée un widget fzf pour l'historique
if ! bind -P 2>/dev/null | grep -q '"\C-r"'; then
  __fzf_history__() {
    local cmd
    cmd="$(HISTTIMEFORMAT= history | sed 's/^ *[0-9]\+ *//' | tac | fzf +s --height=40% --reverse)"
    [[ -n "$cmd" ]] || return
    READLINE_LINE="$cmd"
    READLINE_POINT=${#READLINE_LINE}
  }
  bind -x '"\C-r": __fzf_history__'
fi

##### ── Git: Best Practices (safe, idempotent) ──────────────────────────────

# 1) Complétion Git (si dispo)
if command -v git >/dev/null 2>&1; then
  # Paquets Debian/Ubuntu (git + bash-completion)
  if [ -f /usr/share/bash-completion/completions/git ]; then
    . /usr/share/bash-completion/completions/git
  elif [ -f /etc/bash_completion.d/git ]; then
    . /etc/bash_completion.d/git
  fi
fi

# 2) Bootstrap config Git globale (exécuté 1 seule fois)
_git_bootstrap_file="$HOME/.config/bash/.git_bootstrap_done"
if command -v git >/dev/null 2>&1 && [ ! -f "$_git_bootstrap_file" ]; then
  mkdir -p "$(dirname "$_git_bootstrap_file")"

  # Sécurité & hygiène
  git config --global pull.ff only                 # pas de merges implicites
  git config --global fetch.prune true             # nettoie les branches distantes supprimées
  git config --global init.defaultBranch main      # branche par défaut
  git config --global rebase.autosquash true       # facilite les fixup!/squash
  git config --global rebase.autoStash true        # stash auto avant rebase/pull --rebase
  git config --global push.autoSetupRemote true    # crée l'upstream au premier push (git ≥ 2.37)
  git config --global branch.sort -committerdate   # branches triées par activité récente
  git config --global color.ui auto                # couleurs
  git config --global rerere.enabled true          # réutilise les résolutions de conflits
  # Optionnel: pager amélioré (si delta installé)
  if command -v delta >/dev/null 2>&1; then
    git config --global core.pager delta
    git config --global interactive.diffFilter "delta --color-only"
    git config --global delta.navigate true
    git config --global delta.line-numbers true
  fi

  date > "$_git_bootstrap_file"
fi

# 3) Alias & fonctions “safe”
# - Pull sans merge accidentel; variante rebase dispo
# --- Git: set minimal sans doublon ---

# Politique de pull : choisir l'UNE des deux lignes suivantes
alias gpl='git pull --ff-only'                 # (A) jamais de merge implicite
# alias gpl='git pull --rebase --autostash'    # (B) toujours rebase

alias g='git'
alias gs='git status -sb'
alias glg='git log --oneline --graph --decorate --date=relative'
alias gfa='git fetch --all --prune'

# Modernes (remplacent checkout)
alias gsw='git switch'
alias gswc='git switch -c'
alias grs='git restore'
alias grst='git restore --staged'

# Commits rapides
alias gcm='git commit -m'
alias gca='git add -A && git commit -m'

# Push avec upstream auto
gpup() { git push -u origin "$(git branch --show-current)"; }

# Sync propre (fetch + prune + pull selon ta politique)
gsync() { git fetch --all --prune && gpl; }

# Protections basiques
_git_protected_regex='^(main|master|prod|production|release\/.+)$'
gpf() {  # force push protégé
  local cur; cur="$(git branch --show-current 2>/dev/null)"
  [[ "$cur" =~ $_git_protected_regex ]] && { echo "Refusé: force-push sur $cur"; return 1; }
  git push --force-with-lease "$@"
}
gclean-branches() {
  git fetch --prune
  git branch --merged | grep -vE '^\*' | grep -Ev "$_git_protected_regex" | xargs -r -n1 git branch -d
}

# Push avec création d'upstream si besoin
gpup() {
  local cur; cur="$(git branch --show-current 2>/dev/null)" || return
  [ -n "$cur" ] || { echo "Pas sur une branche."; return 1; }
  git push -u origin "$cur"
}

# Sync propre: fetch + prune + rebase (ou ff-only si propre)
gsync() {
  local target="${1:-origin/$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null | awk -F/ '{print $2}')}"
  git fetch --all --prune || return
  if git merge-base --is-ancestor "$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null | cut -d/ -f2-)" HEAD 2>/dev/null; then
    git pull --ff-only
  else
    git pull --rebase --autostash
  fi
}

# Fixup → autosquash
gfixup() {
  # Usage: gfixup <commit-ish>  (ex: gfixup HEAD~1)
  [ -n "$1" ] || { echo "Usage: gfixup <commit-ish>"; return 1; }
  git commit --fixup "$1" && git rebase -i --autosquash "$1"^
}

# Branches récentes (locales)
grecent() {
  git for-each-ref --count="${1:-15}" --sort=-committerdate refs/heads/ \
    --format='%(committerdate:relative) %(refname:short)'
}

# Protections simples contre les bêtises sur branches critiques
_git_protected_regex='^(main|master|prod|production|release\/.+)$'
gpf() {
  # push --force “protégé”
  local cur; cur="$(git branch --show-current 2>/dev/null)"
  if [[ "$cur" =~ $_git_protected_regex ]]; then
    echo "Refusé: force-push sur branche protégée ($cur)."
    return 1
  fi
  git push --force-with-lease "$@"
}

gbD() {
  # delete local branch (protégé)
  local b="$1"
  [ -n "$b" ] || { echo "Usage: gbD <branch>"; return 1; }
  if [[ "$b" =~ $_git_protected_regex ]]; then
    echo "Refusé: suppression d'une branche protégée ($b)."
    return 1
  fi
  git branch -D "$b"
}

# Nettoyage des branches locales déjà mergées (hors protégées)
gclean-branches() {
  git fetch --prune
  git branch --merged \
    | grep -vE '^\*' \
    | grep -Ev "$_git_protected_regex" \
    | xargs -r -n1 git branch -d
}

# 4) Prompt Bash avec statut Git (facultatif, léger)
# Nécessite git-prompt (souvent dans /usr/share/git/completion/)
if [ -z "$PROMPT_COMMAND" ]; then
  if [ -f /usr/share/git/completion/git-prompt.sh ]; then
    . /usr/share/git/completion/git-prompt.sh
  elif [ -f /etc/bash_completion.d/git-prompt ]; then
    . /etc/bash_completion.d/git-prompt
  fi
  # Ajoute (branche + état) à PS1 si git-prompt dispo
  if type __git_ps1 >/dev/null 2>&1; then
    export GIT_PS1_SHOWDIRTYSTATE=1
    export GIT_PS1_SHOWSTASHSTATE=1
    export GIT_PS1_SHOWUPSTREAM="auto"
    PROMPT_COMMAND='__git_ps1 "\u@\h:\w" " \n$ "'
  fi
fi
##### ─────────────────────────────────────────────────────────────────────────

