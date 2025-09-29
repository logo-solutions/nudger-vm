#!/usr/bin/env bash
set -euo pipefail

echo "👉 Chargement du profil bash"
source ~/nudger-vm/config-vm/profile_logo.sh
echo "👉 génération clé de déploiement"
ssh-keygen -t ed25519 -f /root/.ssh/id_ansible_vm -C "ansible@bastion"
echo "👉 Installation Ansible"
~/nudger-vm/scripts/bastion/install-ansible-bastion.sh

echo "👉 Activation venv + lancement des playbooks"
source ~/ansible_venv/bin/activate
cd ~/nudger-vm/infra/k8s_ansible

ansible-playbook -i inventory.ini playbooks/bastion/site.bastion.yml
ansible-playbook -i inventory.ini playbooks/bastion/007a-install-init-vault.yml

export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN=$(jq -r .root_token /root/.ansible/artifacts/bastion/vault-init.json)

vault kv put secret/users/kubernetes-admin password="changeme123"
vault kv put secret/users/ops-loic password="changeme123"
vault kv put secret/users/dev-loic password="changeme123"

ansible-playbook -i inventory.ini playbooks/bastion/007b-seed-vault.yml

echo "✅ Post-install terminé."
