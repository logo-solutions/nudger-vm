#!/usr/bin/env bash
set -euo pipefail

PROFILE_PATH="${PROFILE_PATH:-$HOME/nudger-vm/scripts/profile-bashrc/profile_logo.sh}"
BLOCK_TAG="# >>> logo-bashrc >>>"
BLOCK_END="# <<< logo-bashrc <<<"

# .inputrc
cat > "$HOME/.inputrc" <<'EOF'
set show-all-if-ambiguous on
set completion-ignore-case on
TAB: menu-complete
"\e[Z": menu-complete-backward
EOF
chmod 0644 "$HOME/.inputrc"

# Bloc idempotent dans .bashrc
if ! grep -q "$BLOCK_TAG" "$HOME/.bashrc" 2>/dev/null; then
  cat >> "$HOME/.bashrc" <<EOF
$BLOCK_TAG
case \$- in
  *i*) ;;
  *) return;;
esac

# bash-completion
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi

# kubectl
if command -v kubectl >/dev/null 2>&1; then
  source <(kubectl completion bash)
  alias k='kubectl'
  complete -o default -F __start_kubectl k
fi

# profile logo
if [ -f "$PROFILE_PATH" ]; then
  . "$PROFILE_PATH"
fi
$BLOCK_END
EOF
fi

echo "Done. Recharger avec: exec bash -l"
