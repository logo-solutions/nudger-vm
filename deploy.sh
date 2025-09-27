#!/usr/bin/env bash
set -euo pipefail

echo "➡️ Installation Ansible sur bastion (localhost)..."

# Venv Ansible
if [ ! -d "$HOME/ansible_venv" ]; then
  python3 -m venv "$HOME/ansible_venv"
fi
source "$HOME/ansible_venv/bin/activate"

pip install --upgrade pip
pip install 'ansible-core>=2.16,<2.18' cryptography hvac

# Collections Ansible
ansible-galaxy collection install -r infra/k8s_ansible/requirements.yml

# Inventory → bastion = localhost
cat > infra/k8s_ansible/inventory.ini <<'EOF'
[bastion]
localhost ansible_connection=local ansible_python_interpreter=/usr/bin/python3
EOF
chmod 0600 infra/k8s_ansible/inventory.ini

echo "✅ Inventory bastion localhost généré"
echo "👉 Active ton venv avec : source ~/ansible_venv/bin/activate"
