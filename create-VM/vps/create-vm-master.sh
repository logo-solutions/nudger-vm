#!/usr/bin/env bash
set -euo pipefail

ID_SSH="${ID_SSH:-bastion-vm-key-hetzner}"  # Nom ou ID Hetzner
NAME="${1:-master1}"
USER="root"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIRHOME="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Prérequis
for cmd in hcloud envsubst nc ssh ssh-keygen; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "❌ $cmd manquant"; exit 1; }
done

# cloud-init
envsubst < "$DIRHOME/create-VM/vps/cloud-init-template.yaml" \
  > "$DIRHOME/create-VM/vps/cloud-init.yaml"

# Supprimer VM existante
if hcloud server describe "$NAME" >/dev/null 2>&1; then
  hcloud server delete "$NAME"
fi

# Créer VM
OUTPUT="$(hcloud server create \
  --name "$NAME" \
  --image ubuntu-22.04 \
  --type cpx21 \
  --user-data-from-file "$DIRHOME/create-VM/vps/cloud-init.yaml" \
  --ssh-key "$ID_SSH")"

VM_IP="$(echo "$OUTPUT" | awk '/IPv4:/ {print $2}')"
echo "✅ VM $NAME IP: $VM_IP"

# Attente SSH
for i in {1..30}; do
  if nc -z -w2 "$VM_IP" 22; then break; fi
  sleep 2
done || { echo "❌ Timeout SSH"; exit 1; }
ssh-keygen -R "$VM_IP" >/dev/null 2>&1 || true
export master1=$VM_IP
echo "✅ SSH up"
echo "./scripts/bastion/post-install-host.sh $VM_IP"
echo "## depuis la VM"
echo "ssh -i ~/.ssh/${ID_SSH} $USER@$VM_IP"
