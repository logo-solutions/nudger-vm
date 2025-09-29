#!/usr/bin/env bash
set -euo pipefail
set -o errtrace

### ───────── Helpers
log() { printf "\n\033[1;36m👉 %s\033[0m\n" "$*"; }
ok()  { printf "\033[1;32m✅ %s\033[0m\n" "$*"; }
err() { printf "\033[1;31m❌ %s\033[0m\n" "$*" >&2; }
trap 'err "Échec à la ligne $LINENO (cmd: ${BASH_COMMAND:-?})"' ERR

require_cmd() { command -v "$1" >/dev/null 2>&1 || { err "Commande requise introuvable: $1"; exit 1; }; }

as_root() {
  if [ "$(id -u)" -ne 0 ]; then
    err "Ce script doit être lancé en root."; exit 1
  fi
}

### ───────── Préambule
as_root
export DEBIAN_FRONTEND=noninteractive
export LC_ALL=C.UTF-8 LANG=C.UTF-8

### ───────── APT de base
log "Mise à jour des paquets système"
apt-get update -y -qq
apt-get upgrade -y -qq

log "Installation des dépendances système"
apt-get install -y -qq --no-install-recommends \
  zsh git curl wget jq tree unzip bash-completion make tar gzip \
  python3 python3-venv python3-pip python3-dev build-essential \
  ruby ruby-dev ca-certificates

ok "Paquets système OK"

### ───────── Hetzner hcloud CLI (idempotent)
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

### ───────── Virtualenv Ansible (contrôleur)
ANSIBLE_VENV="/root/ansible_venv"
if [ ! -d "$ANSIBLE_VENV" ] || [ ! -x "$ANSIBLE_VENV/bin/activate" ]; then
  log "Création / reconstruction du venv Ansible"
  rm -rf "$ANSIBLE_VENV"
  python3 -m venv "$ANSIBLE_VENV"
fi

# venv activé pour installer ansible et ses deps (contrôleur)
# shellcheck disable=SC1091
source "$ANSIBLE_VENV/bin/activate"

log "Mise à jour pip (venv)"
pip install -q --upgrade pip

log "Installation Ansible (venv contrôleur)"
# Version bornée et stable d’ansible-core
pip install -q "ansible-core>=2.16,<2.18" ansible-lint openshift kubernetes pyyaml passlib

# hvac dans le venv (facultatif mais utile si des scripts l’utilisent en local)
pip install -q --upgrade "hvac>=2.3"

# Collections Ansible dans des chemins standards
log "Installation des collections Ansible"
ansible-galaxy collection install -p ~/.ansible/collections \
  kubernetes.core ansible.posix community.general community.crypto community.hashi_vault --force -q

# Depuis requirements.yml si présent
REQ="$HOME/nudger-vm/infra/k8s_ansible/requirements.yml"
if [ -f "$REQ" ]; then
  ansible-galaxy collection install -r "$REQ" -p ~/.ansible/collections --force -q
fi

# S’assure qu’Ansible voit les collections utilisateur
export ANSIBLE_COLLECTIONS_PATHS="$HOME/.ansible/collections:/usr/share/ansible/collections"
ok "Ansible + collections OK"

### ───────── hvac sur Python système (Option B)
# IMPORTANT: pour que les modules community.hashi_vault (vault_kv2_*) côté cible
# puissent importer hvac lorsque ansible_python_interpreter=/usr/bin/python3
log "Installation/upgrade de hvac sur Python système"
python3 -m pip install -q --upgrade pip
python3 -m pip install -q --upgrade "hvac>=2.3"
ok "hvac système OK"

### ───────── Outils confort: fzf / lazygit
# fzf (idempotent, non interactif)
if [ ! -d "$HOME/.fzf" ]; then
  log "Installation fzf"
  git clone -q --depth 1 https://github.com/junegunn/fzf.git "$HOME/.fzf"
  "$HOME/.fzf/install" --all >/dev/null
  ok "fzf installé"
else
  ok "fzf déjà présent"
fi

# lazygit (installe binaire dans ~/bin)
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

### ───────── Affichage versions clés
log "Vérifications versions"
ansible --version || true
python3 -c 'import importlib.metadata as m; print("hvac (system)", m.version("hvac"))' || true
"$ANSIBLE_VENV/bin/python" -c 'import importlib.metadata as m; print("hvac (venv)", m.version("hvac"))' || true

ok "Installation terminée !"
