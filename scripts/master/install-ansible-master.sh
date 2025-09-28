#!/bin/bash
set -euo pipefail

echo "🔹 Mise à jour et installation des paquets système"
sudo -E apt update && sudo -E apt upgrade -y
sudo apt install -y \
  zsh git curl wget jq tree unzip bash-completion make tar gzip python3-venv \
  python3-pip python3-dev build-essential \
  ruby ruby-dev

# 🔹 Hetzner hcloud CLI
if ! command -v hcloud >/dev/null 2>&1; then
  echo "🔹 Installation du client Hetzner Cloud (hcloud)"
  curl -L https://github.com/hetznercloud/cli/releases/latest/download/hcloud-linux-amd64.tar.gz -o hcloud.tar.gz
  tar -xvzf hcloud.tar.gz
  mv hcloud /usr/local/bin/
  chmod +x /usr/local/bin/hcloud
  rm -f hcloud.tar.gz
fi

# 🔹 Virtualenv Ansible
ANSIBLE_VENV="$HOME/ansible_venv"
if [ ! -d "$ANSIBLE_VENV" ] || [ ! -f "$ANSIBLE_VENV/bin/activate" ]; then
    echo "⚠️  Virtualenv manquant ou incomplet. Reconstruction..."
    rm -rf "$ANSIBLE_VENV"
    python3 -m venv "$ANSIBLE_VENV"
fi
source "$ANSIBLE_VENV/bin/activate"

# 🔹 Paquets Python
pip install --upgrade pip
pip install \
  "ansible-core>=2.16,<2.18" ansible-lint \
  openshift kubernetes pyyaml passlib hvac

# 🔹 Collections Ansible de base
ansible-galaxy collection install \
  kubernetes.core ansible.posix community.general \
  community.crypto community.hashi_vault --force

# 🔹 Collections depuis requirements.yml (si présent)
REQ_VM="$HOME/nudger-vm/infra/k8s_ansible/requirements.yml"
REQ="$HOME/nudger/infra/k8s-ansible/requirements.yml"
for REQ_FILE in "$REQ_VM" "$REQ"; do
  if [ -f "$REQ_FILE" ]; then
      echo "🔹 Installation des collections depuis $REQ_FILE"
      ansible-galaxy collection install -r "$REQ_FILE" --force
  fi
done

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
    if ! grep -q 'export PATH=$HOME/bin:$PATH' ~/.bashrc; then
        echo 'export PATH=$HOME/bin:$PATH' >> ~/.bashrc
    fi
fi

echo "✅ Installation terminée !"
