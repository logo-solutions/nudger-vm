#!/usr/bin/env bash
set -euo pipefail
# Activer le venv Ansible de bastion
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

ansible-playbook -i inventory.ini playbooks/bastion/site.bastion.yml
ansible-playbook -i inventory.ini playbooks/bastion/007a-install-init-vault.yml

echo "👉 Configuration de Vault"
export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN=$(jq -r .root_token /root/.ansible/artifacts/bastion/vault-init.json)

vault kv put secret/users/kubernetes-admin password="changeme123"
vault kv put secret/users/ops-loic password="changeme123"
vault kv put secret/users/dev-loic password="changeme123"

ansible-playbook -i inventory.ini playbooks/bastion/007b-seed-vault.yml

echo "✅ Post-install master terminé depuis bastion."
