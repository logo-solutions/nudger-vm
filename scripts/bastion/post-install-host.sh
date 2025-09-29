#!/usr/bin/env bash
set -euo pipefail

# Emplacement de l'inventory Ansible (même que dans create-vm-bastion.sh)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIRHOME="$(cd "$SCRIPT_DIR/../.." && pwd)"
INVENTORY="$DIRHOME/infra/k8s_ansible/inventory.ini"

# Récupère l'IP du bastion dans l'inventory
VM_IP="$(awk '/\[bastion\]/ {getline; print $2}' "$INVENTORY" | cut -d= -f2)"
USER="$(awk '/\[bastion\]/ {getline; for(i=1;i<=NF;i++){ if($i ~ /^ansible_user=/){split($i,a,"="); print a[2]}}}' "$INVENTORY")"

# Paramètres SSH
ID_SSH="${1:-id_vm_ed25519}"
KEY_PATH="${2:-$HOME/Downloads/nudger-vm-003.2025-09-27.private-key.pem}"

if [[ -z "$VM_IP" ]]; then
  echo "❌ Impossible de trouver l'IP du bastion dans $INVENTORY"
  exit 1
fi

echo "👉 Préparation côté hôte pour $USER@$VM_IP"

# Création du dossier sur la VM
ssh -i ~/.ssh/${ID_SSH} "$USER@$VM_IP" \
  "mkdir -p /etc/github-app && chmod 700 /etc/github-app"

# Copie de la clé privée GitHub App
scp -i ~/.ssh/${ID_SSH} "$KEY_PATH" \
  "$USER@$VM_IP:/etc/github-app/nudger-vm.private-key.pem"

# Permissions
ssh -i ~/.ssh/${ID_SSH} "$USER@$VM_IP" \
  "chown root:root /etc/github-app/nudger-vm.private-key.pem && chmod 600 /etc/github-app/nudger-vm.private-key.pem"

echo "✅ Clé GitHub App déployée."
echo
echo "👉 Connecte-toi ensuite : ssh -i ~/.ssh/${ID_SSH} $USER@$VM_IP"
echo "Puis lance : ~/nudger-vm/scripts/post-install-vm.sh"
