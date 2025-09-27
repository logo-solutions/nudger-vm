#!/usr/bin/env bash
set -euo pipefail

echo "➡️ Installation d'Ansible et préparation de l'environnement..."

# 1. Pré-requis système
apt-get update -y
apt-get install -y python3-venv git curl unzip
apt-get install -y ruby-full
apt-get install -y ruby-full build-essential
gem install jwt -v "~> 2.7"
apt-get install -y jq


# 2. Créer un venv dédié à Ansible
ANSIBLE_VENV="$HOME/ansible_venv"
if [ ! -d "$ANSIBLE_VENV" ]; then
  python3 -m venv "$ANSIBLE_VENV"
fi
source "$ANSIBLE_VENV/bin/activate"

# 3. Installer Ansible et dépendances Vault
python -m pip install --upgrade pip
pip install 'ansible-core>=2.16,<2.19' hvac requests

# 4. Installer la collection community.hashi_vault
ansible-galaxy collection install community.hashi_vault
ansible-galaxy collection install ansible.posix
ansible-galaxy collection install community.crypto

# 5. Cloner ton dépôt nudger-vm si absent
if [ ! -d "$HOME/nudger-vm" ]; then
  git clone https://github.com/logo-solutions/nudger-vm.git "$HOME/nudger-vm"
fi

cd "$HOME/nudger-vm/infra/k8s_ansible"

# 6. Variables d’environnement (fix macOS / Vault)
echo "➡️ Ajout des variables d’environnement (fork safety / proxy)"
export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES
export no_proxy="*"
# 7. Créer un placeholder pour Ansible Vault si absent
VAULT_PASS_FILE="$HOME/nudger-vm/infra/k8s_ansible/.vault_pass.txt"
if [ ! -f "$VAULT_PASS_FILE" ]; then
  echo "changeme" > "$VAULT_PASS_FILE"
  chmod 600 "$VAULT_PASS_FILE"
fi
echo "✅ Ansible installé et prêt. Active ton venv avec :"

echo "   source ~/ansible_venv/bin/activate"
