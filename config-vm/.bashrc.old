#!/bin/bash

###############################################################
#  TITRE: Configuration DevOps Bash
#
#  AUTEUR:   Loic G.
#  VERSION:  1.0
#  CREATION: 2023
#  MODIFIE:  $(date +"%Y-%m-%d")
#
#  DESCRIPTION: Configuration optimisée pour DevOps
###############################################################

# ===== INITIAL SETUP =====
clear
echo -e '\033[0;32m
██╗░░░░░░█████╗░░██████╗░░█████╗░
██║░░░░░██╔══██╗██╔════╝░██╔══██╗
██║░░░░░██║░░██║██║░░██╗░██║░░██║
██║░░░░░██║░░██║██║░░╚██╗██║░░██║
███████╗╚█████╔╝╚██████╔╝╚█████╔╝
╚══════╝░╚════╝░░╚═════╝░░╚════╝░
'

# ===== HISTORY CONFIGURATION =====
# don't put duplicate lines or lines starting with space in the history.
HISTCONTROL=ignoreboth
# append to the history file, don't overwrite it
shopt -s histappend
# for setting history length see HISTSIZE and HISTFILESIZE in bash(1)
HISTSIZE=100000
HISTFILESIZE=200000

# ===== PATH UPDATES =====
export PATH="$PATH:$HOME/.local/bin"
export PATH="$PATH:$HOME/.krew/bin"
export PATH="$PATH:$HOME/.tfenv/bin"
export PATH="/opt/homebrew/bin:$PATH"
export PATH="/opt/homebrew/opt:$PATH"
export PATH="/Library/Frameworks/Python.framework/Versions/3.13/bin:$PATH"

# ===== TOOL CONFIGURATION =====
# Kubernetes
export KUBECONFIG=${KUBECONFIG:-$HOME/.k0s/kubeconfig}
export KUBE_EDITOR='code --wait'
if command -v kubectl &>/dev/null; then
    source <(kubectl completion bash)
fi

# Terraform
export TF_CLI_ARGS="-no-color"
export TF_PLUGIN_CACHE_DIR="$HOME/.terraform.d/plugin-cache"
mkdir -p "$TF_PLUGIN_CACHE_DIR"
if command -v terraform &>/dev/null; then
    complete -o nospace -C "$(which terraform)" terraform
fi

# AWS
export AWS_PAGER=""

# Ansible
export ANSIBLE_FORCE_COLOR=1
export ANSIBLE_INVENTORY=~/ansible/inventory

# ===== ALIASES =====
# System
alias ll='ls -laFh --color=auto'
alias la='ls -A'
alias l='ls -larth'
alias s='sudo -s'

# Git
alias gs='git status'
alias gc='git commit'
alias gp='git push'
alias gpl='git pull'
alias gco='git checkout'
alias gl='git log'
alias gst='git status'
alias gg='git log --oneline --all --graph --name-status'
alias lg="lazygit"

# Kubernetes
alias k='kubectl'
alias kctx='kubectx'
alias kns='kubens'
alias kcc='kubectl config current-context'
alias kg='kubectl get'
alias kga='kubectl get all --all-namespaces'
alias kgp='kubectl get pods'
alias kgs='kubectl get services'
alias kn='kubens'
alias ksgp='kubectl get pods -n kube-system'
alias kss='kubectl get services -n kube-system'
alias kuc='kubectl config use-context'
alias kx='kubectx'
alias kdump='kubectl get all --all-namespaces'
alias kdebug="kubectl run -it --rm debug --image=busybox --restart=Never -- sh"
alias kdump="kubectl get all,ingress,pvc -A"

# Docker
alias d='docker'
alias dc='docker-compose'
alias dps="docker ps --format 'table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Ports}}'"

# Terraform
alias tf='terraform'
alias tfi='terraform init'
alias tfp='terraform plan'
alias tfa='terraform apply'
alias tfd='terraform destroy'
alias tfplan="terraform plan -out=tfplan && terraform show -json tfplan | jq > plan.json"
alias tfw='terraform workspace list'

# AWS
alias awslogin='aws sso login'
alias awsroles='aws sts get-caller-identity'

# Utilities
alias json='jq .'                          # Pretty-print JSON
alias yaml='yq eval .'                     # Pretty-print YAML
alias cheats='tldr'                        # Quick docs
alias vu='vagrant up'

# ===== FUNCTIONS =====
# Kubernetes context info
kinfo() {
    if ! command -v kubectl &>/dev/null; then
        echo "kubectl not installed!"
        return 1
    fi
    echo "Current Context: $(kubectl config current-context 2>/dev/null || echo 'None')"
    echo "Namespace: $(kubectl config view --minify --output 'jsonpath={..namespace}' 2>/dev/null || echo 'default')"
    echo "Cluster Info:"
    kubectl cluster-info 2>/dev/null || echo "Unable to get cluster info"
}


# Docker clean
dclean() {
    if ! command -v docker &>/dev/null; then
        echo "docker not installed!"
        return 1
    fi
    docker system prune -af --volumes
}

# ===== ENHANCEMENTS =====
# FZF configuration
if [ -f ~/.fzf.bash ]; then
    source ~/.fzf.bash
    # Recherche de fichier + ouverture dans Vim
    alias vf='vim $(fzf)'
    # Recherche de dossier + cd dedans
    alias cdf='cd $(find * -type d | fzf)'
fi

# Let's Go !! #################################################
export KUBECONFIG=/etc/kubernetes/admin.conf
