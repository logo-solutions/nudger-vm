#!/usr/bin/env bash
set -euo pipefail
set -o errtrace

### -------- Helpers --------
log() { printf "\n\033[1;36m👉 %s\033[0m\n" "$*"; }
ok()  { printf "\033[1;32m✅ %s\033[0m\n" "$*"; }
err() { printf "\033[1;31m❌ %s\033[0m\n" "$*" >&2; }

trap 'err "Échec à la ligne $LINENO (commande: ${BASH_COMMAND:-?})"; exit 1' ERR

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { err "Commande requise introuvable: $1"; exit 1; }
}

ensure_file() {
  local f="$1"; local why="${2:-fichier requis manquant}"
  [[ -f "$f" ]] || { err "$why: $f"; exit 1; }
}

kv_put() {
  local path="$1" key="$2" val="$3"
  log "Vault: kv put $path ($key=****)"
  VAULT_ADDR="$VAULT_ADDR" VAULT_TOKEN="$VAULT_TOKEN" \
    vault kv put "$path" "$key=$val" >/dev/null
  # validation lecture
  VAULT_ADDR="$VAULT_ADDR" VAULT_TOKEN="$VAULT_TOKEN" \
    vault kv get -format=json "$path" | jq -e --arg k "$key" '.data.data[$k] != null' >/dev/null
  ok "Secret écrit et vérifié: $path"
}

### -------- Préchecks --------
# Vérifie et installe jq si absent
if ! command -v jq >/dev/null 2>&1; then
  echo "🔹 Installation jq (manquant)"
  apt-get update -y
  apt-get install -y jq
fi
require_cmd jq
require_cmd ssh-keygen
require_cmd git
require_cmd python3

log "Chargement du profil bash"
# ne plante pas si le profil n'existe pas
if [[ -f "$HOME/nudger-vm/config-vm/profile_logo.sh" ]]; then
  # shellcheck disable=SC1091
  source "$HOME/nudger-vm/config-vm/profile_logo.sh"
else
  err "Profil $HOME/nudger-vm/config-vm/profile_logo.sh introuvable (ok pour continuer)."
fi

### -------- Clé de déploiement SSH --------
log "Génération clé de déploiement (idempotent)"
mkdir -p /root/.ssh && chmod 700 /root/.ssh
if [[ -f /root/.ssh/id_ansible_vm && -f /root/.ssh/id_ansible_vm.pub ]]; then
  ok "Clé /root/.ssh/id_ansible_vm déjà présente"
else
  ssh-keygen -t ed25519 -N "" -f /root/.ssh/id_ansible_vm -C "ansible@bastion" -q
  chmod 600 /root/.ssh/id_ansible_vm
  chmod 644 /root/.ssh/id_ansible_vm.pub
  ok "Clé SSH générée"
fi

### -------- Installation Ansible --------
log "Installation Ansible (script projet)"
ensure_file "$HOME/nudger-vm/scripts/bastion/install-ansible-bastion.sh" "Script Ansible manquant"
bash "$HOME/nudger-vm/scripts/bastion/install-ansible-bastion.sh"
ok "Ansible installé"

### -------- Activation venv + Playbooks --------
log "Activation venv"
ensure_file "$HOME/ansible_venv/bin/activate" "Virtualenv ansible_venv introuvable"
# shellcheck disable=SC1091
source "$HOME/ansible_venv/bin/activate"
require_cmd ansible-playbook

log "Lancement des playbooks bastion"
cd "$HOME/nudger-vm/infra/k8s_ansible"

ensure_file "inventory.ini" "inventory.ini introuvable"

ansible-playbook -i inventory.ini playbooks/bastion/site.bastion.yml
ok "site.bastion.yml OK"

ansible-playbook -i inventory.ini playbooks/bastion/007a-install-init-vault.yml
ok "007a-install-init-vault.yml OK"

### -------- Récupération du token Vault --------
log "Configuration VAULT_ADDR"
export VAULT_ADDR="http://127.0.0.1:8200"

# Chemins possibles d’artifacts (selon ta conf actuelle)
ART1="/root/.ansible/artifacts/bastion/vault-init.json"
ART2="/root/.ansible/artifacts/bastion_host/vault-init.json"

VAULT_INIT_JSON=""
if [[ -f "$ART1" ]]; then
  VAULT_INIT_JSON="$ART1"
elif [[ -f "$ART2" ]]; then
  VAULT_INIT_JSON="$ART2"
fi

if [[ -z "${VAULT_INIT_JSON:-}" ]]; then
  err "vault-init.json introuvable (cherché dans $ART1 et $ART2). Vérifie le play 007a."
  exit 1
fi
ok "vault-init.json trouvé: $VAULT_INIT_JSON"

log "Export du VAULT_TOKEN"
export VAULT_TOKEN
VAULT_TOKEN="$(jq -r '.root_token // empty' "$VAULT_INIT_JSON")"
if [[ -z "$VAULT_TOKEN" || "$VAULT_TOKEN" == "null" ]]; then
  err "root_token absent dans $VAULT_INIT_JSON"
  exit 1
fi
ok "Token chargé (******)"

# Vérification du token
VAULT_OK="$(VAULT_ADDR="$VAULT_ADDR" VAULT_TOKEN="$VAULT_TOKEN" vault token lookup >/dev/null && echo ok || echo ko)"
if [[ "$VAULT_OK" != "ok" ]]; then
  err "Échec validation du token Vault"
  exit 1
fi
ok "Token valide"

# S’assure que le moteur KV v2 est actif (idempotent)
log "Activation KV v2 sur 'secret' (idempotent)"
VAULT_ADDR="$VAULT_ADDR" VAULT_TOKEN="$VAULT_TOKEN" \
  vault secrets enable -path=secret kv-v2 >/dev/null 2>&1 || true
ok "KV v2 prêt"

### -------- Seed des secrets --------
kv_put "secret/users/kubernetes-admin" "password" "changeme123"
kv_put "secret/users/ops-loic"         "password" "changeme123"
kv_put "secret/users/dev-loic"         "password" "changeme123"

### -------- Playbook de seed additionnel --------
if [[ -f "playbooks/bastion/007b-seed-vault.yml" ]]; then
  log "Execution 007b-seed-vault.yml"
  ansible-playbook -i inventory.ini playbooks/bastion/007b-seed-vault.yml
  ok "007b-seed-vault.yml OK"
else
  err "playbooks/bastion/007b-seed-vault.yml introuvable (on continue)."
fi

ok "Post-install terminé."
