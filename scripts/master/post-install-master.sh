#!/usr/bin/env bash
set -euo pipefail
# Activer le venv Ansible de bastion
if ! command -v jq >/dev/null 2>&1; then
  echo "🔹 Installation jq (manquant)"
  apt-get update -y
  apt-get install -y jq
fi
if [ -f ~/ansible_venv/bin/activate ]; then
  source ~/ansible_venv/bin/activate
else
  echo "❌ Virtualenv Ansible absent sur bastion. Lance d'abord install-ansible-bastion.sh"
  exit 1
fi
echo "👉 Chargement du profil bash"
source ~/nudger-vm/config-vm/profile_logo.sh

echo "👉 Installation Ansible sur master1 via bastion"
ansible master1 -i ~/nudger-vm/infra/k8s_ansible/inventory.ini \
  -m script -a "~/nudger-vm/scripts/master/install-ansible-master.sh"

echo "👉 Activation venv + lancement des playbooks depuis bastion"
source ~/ansible_venv/bin/activate
cd ~/nudger-vm/infra/k8s_ansible

ansible-playbook -i inventory.ini playbooks/master/nudger.yml

echo "✅ Post-install master terminé depuis bastion."
