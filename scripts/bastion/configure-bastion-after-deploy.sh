#!/usr/bin/env bash
set -euo pipefail
set -o errtrace

###############################################################################
# post-install-vm-bastion.sh
# Auteur : Loïc Bourmelon
#
# Objectif :
#   - Vérifier la clé SSH durable (hetzner-bastion)
#   - Normaliser l’inventaire Ansible ([bastion] en local)
#   - (Optionnel) Copier la clé GitHub App
#   - Installer Ansible et exécuter le playbook bastion
###############################################################################

### -------- Helpers --------
log() { printf "\n\033[1;36m👉 %s\033[0m\n" "$*"; }
ok()  { printf "\033[1;32m✅ %s\033[0m\n" "$*"; }
err() { printf "\033[1;31m❌ %s\033[0m\n" "$*" >&2; exit 1; }

trap 'err "Échec à la ligne $LINENO (commande: ${BASH_COMMAND:-?})"' ERR
require_cmd(){ command -v "$1" >/dev/null 2>&1 || err "Commande requise introuvable: $1"; }
ensure_file(){ local f="$1"; local why="${2:-fichier requis manquant}"; [[ -f "$f" ]] || err "$why: $f"; }

### -------- Config --------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INVENTORY="${INVENTORY:-$REPO_ROOT/infra/k8s_ansible/inventory.ini}"

# Clé SSH durable utilisée pour le bastion et les VMs
BASTION_KEY_PATH="${BASTION_KEY_PATH:-/root/.ssh/hetzner-bastion}"
BASTION_KEY_PUB="${BASTION_KEY_PUB:-${BASTION_KEY_PATH}.pub}"

# (Optionnel) Clé GitHub App à copier
GITHUB_APP_KEY_PATH="${GITHUB_APP_KEY_PATH:-${1:-}}"

### -------- Vérification des outils --------
for cmd in jq ssh-keygen git python3; do require_cmd "$cmd"; done

### -------- Vérification clé SSH durable --------
log "Vérification clé durable (doit être installée par l’admin)"
install -d -m 700 /root/.ssh
if [[ ! -f "$BASTION_KEY_PATH" || ! -f "$BASTION_KEY_PUB" ]]; then
  err "Clé Hetzner absente : $BASTION_KEY_PATH(.pub).
Merci de l’installer avant de lancer ce script (ex: scp depuis ton Mac)."
fi
ok "Clé durable présente : $BASTION_KEY_PATH"

### -------- Normalisation inventory.ini : [bastion] en local --------
log "Normalisation de l'inventory: $INVENTORY"
touch "$INVENTORY"

# Supprime toute ancienne ligne 'bastion ' sous [bastion]
sed -i '/^\[bastion\]/,$!b;/^bastion /d' "$INVENTORY" 2>/dev/null || true

# S’assure de la présence du header [bastion]
grep -q '^\[bastion\]' "$INVENTORY" || printf "\n[bastion]\n" >> "$INVENTORY"

# Écrit l’entrée locale
awk '
  BEGIN{printed=0}
  /^\[bastion1\]/{print; print "bastion ansible_host=127.0.0.1 ansible_connection=local ansible_user=root ansible_python_interpreter=/usr/bin/python3"; printed=1; next}
  {print}
  END{if(!printed) print "bastion ansible_host=127.0.0.1 ansible_connection=local ansible_user=root ansible_python_interpreter=/usr/bin/python3"}
' "$INVENTORY" > "$INVENTORY.tmp" && mv "$INVENTORY.tmp" "$INVENTORY"
ok "[bastion] → local OK"

### -------- (optionnel) Copier la clé GitHub App --------
if [[ -n "${GITHUB_APP_KEY_PATH}" ]]; then
  ensure_file "$GITHUB_APP_KEY_PATH" "Fichier clé GitHub App introuvable"
  install -d -m 700 /etc/github-app
  install -m 600 "$GITHUB_APP_KEY_PATH" /etc/github-app/nudger-vm.private-key.pem
  chown root:root /etc/github-app/nudger-vm.private-key.pem
  ok "Clé GitHub App déployée."
else
  log "Aucune clé GitHub App fournie (GITHUB_APP_KEY_PATH). Skipping."
fi

### -------- Installation Ansible --------
log "Installation Ansible (script projet)"
ensure_file "$REPO_ROOT/scripts/bastion/install-ansible-bastion.sh" "Script Ansible manquant"
bash "$REPO_ROOT/scripts/bastion/install-ansible-bastion.sh"
ok "Ansible installé."

### -------- Activation venv + Playbooks --------
log "Activation venv et exécution playbooks..."
ensure_file "/root/ansible_venv/bin/activate" "Virtualenv ansible_venv introuvable"
# shellcheck disable=SC1091
source "/root/ansible_venv/bin/activate"
require_cmd ansible-playbook

cd "$REPO_ROOT/infra/k8s_ansible"
ensure_file "inventory.ini" "inventory.ini introuvable"
ansible-playbook -i inventory.ini playbooks/bastion/site.bastion.yml
ok "Playbook site.bastion.yml exécuté avec succès."

ok "Post-install Bastion terminée avec succès 🎉"
