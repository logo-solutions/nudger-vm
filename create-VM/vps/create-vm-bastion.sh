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

BASTION_KEY="${BASTION_KEY:-$HOME/.ssh/id_ed25519}"   # <-- ajuste si besoin

SSH_OPTS="-o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -i $BASTION_KEY"

# 🔎 Attente SSH bastion
echo "👉 Attente SSH sur $VM_IP"
for i in {1..30}; do
  if nc -z -w2 "$VM_IP" 22 >/dev/null 2>&1; then
    if ssh $SSH_OPTS root@"$VM_IP" true 2>/dev/null; then
      echo "✅ SSH up"
      break
    fi
  fi
  sleep 2
  if [ "$i" -eq 30 ]; then echo "❌ Timeout SSH"; exit 1; fi
done

# 📦 Chemin distant de l'inventaire SUR LE BASTION
REMOTE_INV="/root/nudger-vm/infra/k8s_ansible/inventory.ini"

echo "👉 Mise à jour de l’inventaire sur le bastion: $REMOTE_INV"
ssh $SSH_OPTS root@"$VM_IP" bash -s <<'EOSSH'
set -euo pipefail
mkdir -p /root/nudger-vm/infra/k8s_ansible
# Si un template existe et que tu veux l'utiliser, tu peux faire:
# test -f /root/nudger-vm/infra/k8s_ansible/inventory.ini.j2 && \
#   envsubst < /root/nudger-vm/infra/k8s_ansible/inventory.ini.j2 > /root/nudger-vm/infra/k8s_ansible/inventory.ini

# Inventaire minimal idempotent pour exécuter les playbooks bastion depuis le bastion
cat > /root/nudger-vm/infra/k8s_ansible/inventory.ini <<'EOF'
[bastion]
bastion_host ansible_host=127.0.0.1 ansible_connection=local ansible_user=root ansible_python_interpreter=/usr/bin/python3

[k8s_masters]

[master:children]
k8s_masters
EOF
chmod 640 /root/nudger-vm/infra/k8s_ansible/inventory.ini
EOSSH

echo "✅ Inventaire mis à jour sur le bastion"

echo "👉 Rappels utiles (à lancer SUR le bastion) :"
echo "   source ~/ansible_venv/bin/activate"
echo "   cd ~/nudger-vm/infra/k8s_ansible"
echo "   ansible -i inventory.ini bastion_host -m ping"
