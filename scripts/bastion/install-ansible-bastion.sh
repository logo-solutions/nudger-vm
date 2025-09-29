#!/usr/bin/env bash
set -euo pipefail
set -o errtrace

log() { printf "\n\033[1;36m👉 %s\033[0m\n" "$*"; }
ok()  { printf "\033[1;32m✅ %s\033[0m\n" "$*"; }
err() { printf "\033[1;31m❌ %s\033[0m\n" "$*" >&2; }
trap 'err "Échec à la ligne $LINENO (cmd: ${BASH_COMMAND:-?})"' ERR

as_root() { [ "$(id -u)" -eq 0 ] || { err "Ce script doit être lancé en root."; exit 1; }; }
as_root

export DEBIAN_FRONTEND=noninteractive
export LC_ALL=C.UTF-8 LANG=C.UTF-8

log "Mise à jour des paquets système"
apt-get update -y
apt-get upgrade -y

log "Installation des dépendances système"
apt-get install -y --no-install-recommends \
  zsh git curl wget jq tree unzip bash-completion make tar gzip \
  python3 python3-venv python3-pip python3-dev build-essential \
  ruby ruby-dev ca-certificates

# --- hcloud CLI (idempotent)
if ! command -v hcloud >/dev/null 2>&1; then
  log "Installation hcloud CLI"
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT
  curl -fsSL "https://github.com/hetznercloud/cli/releases/latest/download/hcloud-linux-amd64.tar.gz" -o "$tmpdir/hcloud.tar.gz"
  tar -xzf "$tmpdir/hcloud.tar.gz" -C "$tmpdir"
  install -m 0755 "$tmpdir/hcloud" /usr/local/bin/hcloud
  ok "hcloud installé"
else
  ok "hcloud déjà présent"
fi

# --- Virtualenv Ansible (contrôleur)
ANSIBLE_VENV="/root/ansible_venv"
if [ ! -d "$ANSIBLE_VENV" ] || [ ! -x "$ANSIBLE_VENV/bin/activate" ]; then
  log "Création / reconstruction du venv Ansible"
  rm -rf "$ANSIBLE_VENV"
  python3 -m venv "$ANSIBLE_VENV"
fi
# shellcheck disable=SC1091
source "$ANSIBLE_VENV/bin/activate"

log "Mise à jour pip (venv)"
pip install --upgrade pip

log "Installation Ansible (venv contrôleur)"
pip install "ansible-core>=2.16,<2.18" ansible-lint openshift kubernetes pyyaml passlib
# hvac aussi dans le venv (utile côté contrôleur)
pip install --upgrade "hvac>=2.3"

# --- Collections Ansible (sans -q)
log "Installation des collections Ansible"
ansible-galaxy collection install \
  kubernetes.core \
  ansible.posix \
  community.general \
  community.crypto \
  community.hashi_vault \
  --force

# Depuis requirements.yml si présent
REQ="$HOME/nudger-vm/infra/k8s_ansible/requirements.yml"
if [ -f "$REQ" ]; then
  ansible-galaxy collection install -r "$REQ" --force
fi

# S’assure qu’Ansible voit les collections utilisateur
export ANSIBLE_COLLECTIONS_PATHS="$HOME/.ansible/collections:/usr/share/ansible/collections"
ok "Ansible + collections OK"

# --- Option B : hvac sur Python système (pour modules vault_kv2_* côté cible)
log "Installation/upgrade de hvac sur Python système"
python3 -m pip install --upgrade pip
python3 -m pip install --upgrade "hvac>=2.3"
ok "hvac système OK"

# --- Outils confort: fzf / lazygit
if [ ! -d "$HOME/.fzf" ]; then
  log "Installation fzf"
  git clone --depth 1 https://github.com/junegunn/fzf.git "$HOME/.fzf"
  "$HOME/.fzf/install" --all >/dev/null
  ok "fzf installé"
else
  ok "fzf déjà présent"
fi

if ! command -v "$HOME/bin/lazygit" >/dev/null 2>&1 && ! command -v lazygit >/dev/null 2>&1; then
  log "Installation lazygit"
  LG_VER="$(curl -fsSL https://api.github.com/repos/jesseduffield/lazygit/releases/latest | jq -r '.tag_name' | sed 's/^v//')"
  curl -fsSL -o /tmp/lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${LG_VER}_Linux_x86_64.tar.gz"
  tar -xzf /tmp/lazygit.tar.gz -C /tmp lazygit
  install -D -m 0755 /tmp/lazygit "$HOME/bin/lazygit"
  rm -f /tmp/lazygit /tmp/lazygit.tar.gz
  grep -q 'export PATH=\$HOME/bin:\$PATH' "$HOME/.bashrc" || echo 'export PATH=$HOME/bin:$PATH' >> "$HOME/.bashrc"
  ok "lazygit installé"
else
  ok "lazygit déjà présent"
fi

# --- Affichage versions clés
log "Vérifications versions"
ansible --version || true
python3 - <<'PY' || true
import importlib.metadata as m, sys
def ver(p): 
    try: print(p, m.version(p))
    except Exception as e: print(p, "N/A:", e)
ver("hvac")
print("python:", sys.executable)
PY

ok "Installation terminée !"
