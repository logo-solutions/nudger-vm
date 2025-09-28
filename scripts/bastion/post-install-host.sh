#!/usr/bin/env bash
set -euo pipefail

# Usage: ./post-install-host.sh <VM_IP> [USER] [ID_SSH] [KEY_PATH]
# Exemple: ./post-install-host.sh 91.98.16.184 root id_vm_ed25519 ~/Downloads/nudger-vm-003.2025-09-27.private-key.pem

VM_IP="${1:?IP de la VM manquant (ex: 91.98.16.184)}"
USER="${2:-root}"
ID_SSH="${3:-id_vm_ed25519}"
KEY_PATH="${4:-$HOME/Downloads/nudger-vm-003.2025-09-27.private-key.pem}"

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
