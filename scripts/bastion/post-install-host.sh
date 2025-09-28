#!/usr/bin/env bash
set -euo pipefail

USER="${USER:-root}"
VM_IP="${VM_IP:?VM_IP manquant (export VM_IP=...)}"
ID_SSH="${ID_SSH:-id_vm_ed25519}"
KEY_PATH="${KEY_PATH:-$HOME/Downloads/nudger-vm-003.2025-09-27.private-key.pem}"

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
echo "👉 Connecte-toi ensuite : ssh -i ~/.ssh/${ID_SSH} $USER@$VM_IP"
echo "Puis lance le script 'post-install-vm.sh' côté VM."
