#!/usr/bin/env bash
set -euo pipefail

NAME="master1"
TYPE="cpx21"
LOCATION="nbg1"
IMAGE="ubuntu-22.04"
SSH_KEY="id_vm_ed25519"
INVENTORY="infra/k8s_ansible/inventory.ini"

echo "👉 Création de la VM $NAME..."
hcloud server create --name "$NAME" \
  --type "$TYPE" \
  --location "$LOCATION" \
  --image "$IMAGE" \
  --ssh-key "$SSH_KEY" \
  --label role=k8s,env=lab \
  --wait

IP=$(hcloud server describe "$NAME" -o json | jq -r '.public_net.ipv4.ip')
echo "✅ VM $NAME créée avec IP $IP"

# Mise à jour inventaire
echo "👉 Mise à jour de $INVENTORY"
grep -v "^$NAME " "$INVENTORY" > "$INVENTORY.tmp" || true
cat >> "$INVENTORY.tmp" <<EOF

[k8s_masters]
$NAME ansible_host=$IP ansible_user=root ansible_ssh_private_key_file=~/.ssh/id_vm_ed25519
EOF
mv "$INVENTORY.tmp" "$INVENTORY"

echo "✅ Inventaire mis à jour"
echo "👉 Test SSH: ssh -i ~/.ssh/id_vm_ed25519 root@$IP"
echo "👉 Test Ansible: ansible -i $INVENTORY $NAME -m ping"
