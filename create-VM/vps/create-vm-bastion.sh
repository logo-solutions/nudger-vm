#!/usr/bin/env bash
set -euo pipefail

ID_SSH="${ID_SSH:-id_vm_ed25519}"
NAME="${1:-bastion}"
HOSTNAME="${NAME}_host"   # éviter conflit groupe/host
USER="root"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIRHOME="$(cd "$SCRIPT_DIR/../.." && pwd)"
INVENTORY="$DIRHOME/infra/k8s_ansible/inventory.ini"

# Prérequis
for cmd in hcloud envsubst nc ssh ssh-keygen; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "❌ $cmd manquant"; exit 1; }
done
[[ -f "$HOME/.ssh/${ID_SSH}" ]] || { echo "❌ clé privée SSH absente"; exit 1; }

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
  --type cpx31 \
  --user-data-from-file "$DIRHOME/create-VM/vps/cloud-init.yaml" \
  --ssh-key loic-vm-key)"

VM_IP="$(echo "$OUTPUT" | awk '/IPv4:/ {print $2}')"
echo "✅ VM $NAME IP: $VM_IP"

# Attente SSH
for i in {1..30}; do
  if nc -z -w2 "$VM_IP" 22; then break; fi
  sleep 2
done || { echo "❌ Timeout SSH"; exit 1; }

ssh-keygen -R "$VM_IP" >/dev/null 2>&1 || true
export bastion=$VM_IP
echo "✅ SSH up"

# --- Mise à jour inventaire ---
# --- Fallback: synthesize inventory.ini if missing ---
if [[ ! -f "inventory.ini" ]]; then
  echo "⚠️ inventory.ini absent — création minimale (bastion en local)"
  cat > inventory.ini <<'EOF'
[bastion]
bastion_host ansible_host=127.0.0.1 ansible_connection=local ansible_user=root ansible_python_interpreter=/usr/bin/python3

[k8s_masters]

[master:children]
k8s_masters
EOF
fi

echo "✅ Inventaire mis à jour"

# Instructions post-install
echo "👉 Test SSH: ssh -i ~/.ssh/${ID_SSH} $USER@$VM_IP"
echo "👉 Test Ansible: ansible -i $INVENTORY $HOSTNAME -m ping"
