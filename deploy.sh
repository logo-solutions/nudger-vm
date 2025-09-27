#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

VM_NAME="master1"
USER="root"
DEPOT_GIT="https://github.com/logo-solutions/nudger-vm.git"
ID_SSH="id_vm_ed25519"
HOME_DIR="/root"
ANSIBLE_VENV="$HOME_DIR/ansible_venv"

# --- 1️⃣ Créer la VM et récupérer l'IP ---
IP=$("$SCRIPT_DIR/create-VM/vps/create-vm.sh" "$VM_NAME" "$USER" "$DEPOT_GIT" \
  | tee /dev/tty \
  | awk -F' ' '/VM IP:/ {print $NF}')

# --- 2️⃣ Générer l’inventaire ---
export VM_NAME USER IP ID_SSH ANSIBLE_VENV
envsubst < "$SCRIPT_DIR/infra/k8s_ansible/inventory.ini.j2" \
  > "$SCRIPT_DIR/infra/k8s_ansible/inventory.ini"

chmod 0600 "$SCRIPT_DIR/infra/k8s_ansible/inventory.ini"
echo "✅ Inventory généré avec IP $IP"

# --- 3️⃣ Bootstrap Ansible ---
echo "➡️ Bootstrap Ansible sur $VM_NAME..."
cd "$SCRIPT_DIR/infra/k8s_ansible"

if [ ! -d ".venv" ]; then
  python3 -m venv .venv
fi
# shellcheck disable=SC1091
source .venv/bin/activate

python -m pip -q install --upgrade pip
python -m pip -q install 'ansible-core>=2.16,<2.18' cryptography

export ANSIBLE_COLLECTIONS_PATH="$PWD/collections:$HOME/.ansible/collections"
ansible-galaxy collection install -r requirements.yml -p ./collections

export ANSIBLE_ROLES_PATH="$PWD/roles"
export ANSIBLE_CONFIG="$PWD/ansible.cfg"



echo "✅ VM $VM_NAME prête sur $IP"
echo ""
echo "👉 Connecte-toi avec :"
echo "   ssh -i ~/.ssh/$ID_SSH $USER@$IP"
echo ""
echo "👉 Clone le dépôt (avec ton PAT GitHub) :"
echo "   git clone https://<PAT>@github.com/logo-solutions/nudger-vm.git"
