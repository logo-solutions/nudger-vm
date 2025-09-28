#!/bin/bash
set -e

# 🔹 Mise à jour système et installation des dépendances
echo "🔹 Mise à jour et installation des paquets système (sudo requis)"
sudo -E apt update && sudo -E apt upgrade -y
sudo apt install -y zsh git curl wget jq tree unzip bash-completion make tar gzip python3-venv

# 🔹 Virtualenv pour Ansible
ANSIBLE_VENV="$HOME/ansible_venv"

create_ansible_venv() {
    echo "🔹 Création du virtualenv Ansible dans $ANSIBLE_VENV"
    python3 -m venv "$ANSIBLE_VENV"
}

if [ ! -d "$ANSIBLE_VENV" ] || [ ! -f "$ANSIBLE_VENV/bin/activate" ]; then
    echo "⚠️  Virtualenv manquant ou incomplet. Reconstruction..."
    rm -rf "$ANSIBLE_VENV"
    create_ansible_venv
else
    echo "✅ Virtualenv Ansible déjà présent."
fi

# Activation et installation des packages Python
source "$ANSIBLE_VENV/bin/activate"
pip install --upgrade pip
pip install "ansible-core>=2.16,<2.18" ansible-lint openshift kubernetes pyyaml

# 🔹 Collections indispensables
ansible-galaxy collection install kubernetes.core ansible.posix community.general --force

# 🔹 Collections depuis requirements.yml (si présent)
REQUIREMENTS_FILE="$HOME/nudger/infra/k8s-ansible/requirements.yml"
if [ -f "$REQUIREMENTS_FILE" ]; then
    echo "🔹 Installation des collections depuis requirements.yml"
    ansible-galaxy collection install -r "$REQUIREMENTS_FILE" --force
fi

echo "🔹 Versions installées :"
ansible --version

# 🔹 fzf
if [ ! -d "$HOME/.fzf" ]; then
    echo "🔹 Installation de fzf"
    git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
    ~/.fzf/install --all
fi

# 🔹 lazygit
if ! command -v lazygit &> /dev/null; then
    echo "🔹 Installation de lazygit"
    LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" \
        | grep -Po '"tag_name": "v\K[^"]*')
    curl -Lo lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz"
    tar xf lazygit.tar.gz lazygit
    mkdir -p "$HOME/bin"
    mv lazygit "$HOME/bin/"
    rm -rf lazygit.tar.gz
    # Ajouter au PATH si nécessaire
    if ! grep -q 'export PATH=$HOME/bin:$PATH' ~/.bashrc; then
        echo 'export PATH=$HOME/bin:$PATH' >> ~/.bashrc
    fi
fi

echo "✅ Installation terminée !"
