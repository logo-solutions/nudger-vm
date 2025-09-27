#!/usr/bin/env bash
set -euo pipefail

# Absolutiser les chemins relativement à ce script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

VM_NAME="master1"
USER="root"
DEPOT_GIT="git@github.com:loicgo29/nudger.git"
ID_SSH="id_vm_ed25519"
HOME_DIR="/root"   # et pas /home/root
ANSIBLE_VENV="$HOME_DIR/ansible_venv"
# --- 1️⃣ Créer la VM et récupérer l'IP ---
IP=$("$SCRIPT_DIR/create-VM/vps/create-vm.sh" "$VM_NAME" "$USER" "$DEPOT_GIT" \
  | tee /dev/tty \
  | awk -F' ' '/VM IP:/ {print $NF}')

# --- 2️⃣ Générer l’inventaire ---
export VM_NAME USER IP ID_SSH ANSIBLE_VENV
envsubst < "$SCRIPT_DIR/infra/k8s_ansible/inventory.ini.j2" \
  > "$SCRIPT_DIR/infra/k8s_ansible/inventory.ini"

echo "✅ Inventory généré avec IP $IP"

# --- 3️⃣ Bootstrap Ansible ---
echo "➡️ Bootstrap Ansible sur $VM_NAME..."
cd "$SCRIPT_DIR/infra/k8s_ansible"

# 3.1 Venv projet (idempotent)
if [ ! -d ".venv" ]; then
  python3 -m venv .venv
fi
# shellcheck disable=SC1091
source .venv/bin/activate

python -m pip -q install --upgrade pip
python -m pip -q install 'ansible-core>=2.16,<2.18' cryptography

# 3.2 Collections locales (idempotent)
export ANSIBLE_COLLECTIONS_PATHS="$PWD/collections:$HOME/.ansible/collections"
ansible-galaxy collection install -r requirements.yml -p ./collections

# 3.3 Chemins Ansible (au cas où ansible.cfg ne serait pas pris)
export ANSIBLE_ROLES_PATH="$PWD/roles"
export ANSIBLE_CONFIG="$PWD/ansible.cfg"

# 3.4 Vault (choisis l’une des deux lignes)
# A) demander le pass à l’exécution :
VAULT_ARGS="--ask-vault-pass"
# B) ou fichier de pass (sécurise les droits 0600) :
# VAULT_ARGS="--vault-id @${HOME}/.vault-pass.txt"

# 3.5 Lancer le play principal
ansible-playbook -i ./inventory.ini ./playbooks/nudger.yml

echo "ssh -i ~/.ssh/id_vm_ed25519 dev-loic@$IP"
