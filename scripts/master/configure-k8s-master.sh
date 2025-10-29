#!/usr/bin/env bash
set -euo pipefail
# Activer le venv Ansible de bastion
if [ -f ~/ansible_venv/bin/activate ]; then
  source ~/ansible_venv/bin/activate
else
  echo "❌ Virtualenv Ansible absent sur bastion. Lance d'abord install-ansible-bastion.sh"
  exit 1
fi

echo "👉 Installation Ansible sur master1 via bastion"
ansible master1 -i ~/nudger-vm/infra/k8s_ansible/inventory.ini \
  -m script -a "~/nudger-vm/scripts/master/bootstrap-ansible-control-plane.sh"

echo "👉 Activation venv + lancement des playbooks depuis bastion"
source ~/ansible_venv/bin/activate
cd ~/nudger-vm/infra/k8s_ansible

ansible-playbook -i inventory.ini playbooks/master/nudger.yml

echo "✅ Post-install master terminé depuis bastion."
