#!/usr/bin/env bash
set -euo pipefail

ID_SSH="${ID_SSH:-id_vm_ed25519}"
NAME="${1:-bastion}"
USER="root"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIRHOME="$(cd "$SCRIPT_DIR/../.." && pwd)"

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

# GitHub App secret
echo "ssh -i ~/.ssh/${ID_SSH} $USER@$VM_IP \"mkdir -p /etc/github-app && chmod 700 /etc/github-app\""
echo "scp -i ~/.ssh/${ID_SSH} ~/Downloads/nudger-vm-003.2025-09-27.private-key.pem \
  $USER@$VM_IP:/etc/github-app/nudger-vm.private-key.pem"
echo "ssh -i ~/.ssh/${ID_SSH} $USER@$VM_IP \"chown root:root /etc/github-app/nudger-vm.private-key.pem && chmod 600 /etc/github-app/nudger-vm.private-key.pem\""

# Post-install
echo "👉 Connexion: ssh -i ~/.ssh/${ID_SSH} $USER@$VM_IP"
echo "PAT=<patdepuisbitwarden>"
echo "👉 Depuis la VM :git clone https://\$PAT@github.com/logo-solutions/nudger-vm.git"
echo "👉 Puis : ~/nudger-vm/scripts/bastion/install-ansible.sh"
echo "👉 Ensuite : source ~/ansible_venv/bin/activate && cd ~/nudger-vm/infra/k8s_ansible"
echo " ansible-playbook -i inventory.ini playbooks/bastion/site.bastion.yml"
echo "export VAULT_ADDR=http://127.0.0.1:8200"
echo "export VAULT_TOKEN=\$(jq -r .root_token /root/.ansible/artifacts/bastion/vault-init.json)"
echo "vault kv put secret/users/kubernetes-admin password="changeme123""
echo "vault kv put secret/users/ops-loic password="changeme123""
echo "vault kv put secret/users/dev-loic password="changeme123""


echo " ansible-playbook -i inventory.ini playbooks/bastion/007-init-vault.yml"
