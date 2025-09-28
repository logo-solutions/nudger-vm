#!/usr/bin/env bash
set -euo pipefail

ID_SSH="${ID_SSH:-id_vm_ed25519}"   # clé SSH par défaut
NAME="${1:-bastion}"
USER="root"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIRHOME="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Vérif prérequis côté local
for cmd in hcloud envsubst nc ssh ssh-keygen scp; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "❌ $cmd manquant"; exit 1; }
done
[[ -f "$HOME/.ssh/${ID_SSH}" ]] || { echo "❌ clé privée SSH absente"; exit 1; }

# Générer cloud-init
envsubst < "$DIRHOME/create-VM/vps/cloud-init-template.yaml" \
  > "$DIRHOME/create-VM/vps/cloud-init.yaml"

# Supprimer VM si existante
if hcloud server describe "$NAME" >/dev/null 2>&1; then
  hcloud server delete "$NAME"
fi

# Créer VM Hetzner
OUTPUT="$(hcloud server create \
  --name "$NAME" \
  --image ubuntu-22.04 \
  --type cpx31 \
  --user-data-from-file "$DIRHOME/create-VM/vps/cloud-init.yaml" \
  --ssh-key loic-vm-key)"

VM_IP="$(echo "$OUTPUT" | awk '/IPv4:/ {print $2}')"
echo "✅ VM $NAME IP: $VM_IP"

# Attendre SSH up
for i in {1..30}; do
  if nc -z -w2 "$VM_IP" 22; then break; fi
  sleep 2
done || { echo "❌ Timeout SSH"; exit 1; }

ssh-keygen -R "$VM_IP" >/dev/null 2>&1 || true
echo "✅ SSH up"

# -------------------------------------------------------------------
# 🔹 Bootstrap bastion : paquets système + venv Ansible
# -------------------------------------------------------------------
ssh -i "$HOME/.ssh/${ID_SSH}" $USER@$VM_IP <<'EOF'
  set -e
  export DEBIAN_FRONTEND=noninteractive
  apt update && apt upgrade -y
  apt install -y git curl wget jq unzip bash-completion python3-venv tree

  # Virtualenv Ansible
  ANSIBLE_VENV="$HOME/ansible_venv"
  if [ ! -d "\$ANSIBLE_VENV" ]; then
    python3 -m venv "\$ANSIBLE_VENV"
    source "\$ANSIBLE_VENV/bin/activate"
    pip install --upgrade pip
    pip install "ansible-core>=2.16,<2.18" ansible-lint openshift kubernetes pyyaml passlib
    ansible-galaxy collection install \
      kubernetes.core ansible.posix community.general community.hashi_vault --force
  fi
EOF

# -------------------------------------------------------------------
# 🔹 Rappel : gestion secrets GitHub App
# -------------------------------------------------------------------
echo "⚠️  Copie ta clé privée GitHub App sur le bastion :"
echo "scp -i ~/.ssh/${ID_SSH} ~/Downloads/nudger-vm-003.2025-09-27.private-key.pem \\"
echo "    $USER@$VM_IP:/etc/github-app/nudger-vm.private-key.pem"
echo "ssh -i ~/.ssh/${ID_SSH} $USER@$VM_IP \\"
echo "    'chown root:root /etc/github-app/nudger-vm.private-key.pem && chmod 600 /etc/github-app/nudger-vm.private-key.pem'"

# -------------------------------------------------------------------
# 🔹 Infos de connexion et workflow
# -------------------------------------------------------------------
echo "👉 Connexion: ssh -i ~/.ssh/${ID_SSH} $USER@$VM_IP"
echo "👉 Ensuite :"
echo "   source ~/ansible_venv/bin/activate"
echo "   cd ~/nudger-vm/infra/k8s_ansible"
echo "   ansible-playbook -i inventory.ini playbooks/bastion/001-setup-github-deploykey.yml"
