#!/usr/bin/env bash
set -euo pipefail

# Repo root (calc depuis ce script: create-VM/vps/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIRHOME="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ========== Réglages ==========
SSH_OPTS="-o StrictHostKeyChecking=accept-new"
ID_SSH="${ID_SSH:-id_vm_ed25519}"     # clé pour se connecter à la VM (locale)

# ========== Vérifications prérequis ==========
for cmd in hcloud envsubst nc ssh ssh-keygen scp git awk tee; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "❌ $cmd manquant."; exit 1; }
done

[[ -f "$DIRHOME/create-VM/vps/cloud-init-template.yaml" ]] || { echo "❌ cloud-init-template.yaml manquant."; exit 1; }
[[ -f "$HOME/.ssh/${ID_SSH}" ]] || { echo "❌ Clé privée VM ~/.ssh/${ID_SSH} manquante."; exit 1; }

echo "✅ Tous les prérequis sont présents"

# --- ARGUMENTS ---
if [[ $# -ne 3 ]]; then
    echo "Usage: $0 <VM_NAME> <USER> <DEPOT_GIT>"
    exit 1
fi

NAME="$1"
USER="$2"
DEPOT_GIT="$3"
ID_SSH_PUB="$(cat "$HOME/.ssh/${ID_SSH}.pub")"

#========= Cloud-init ==========
echo "➡️ Génération du cloud-init.yaml pour $USER"
export USER DEPOT_GIT ID_SSH_PUB
envsubst < "$DIRHOME/create-VM/vps/cloud-init-template.yaml" > "$DIRHOME/create-VM/vps/cloud-init.yaml"
echo "✅ cloud-init.yaml généré"

# ========== (Re)création serveur ==========
if hcloud server describe "$NAME" >/dev/null 2>&1; then
  echo "Suppression du serveur $NAME existant..."
  hcloud server delete "$NAME"
fi

echo "➡️ Création de la VM $NAME..."
OUTPUT="$(hcloud server create \
  --name "$NAME" \
  --image ubuntu-22.04 \
  --type cpx21 \
  --user-data-from-file "$DIRHOME/create-VM/vps/cloud-init.yaml" \
  --ssh-key loic-vm-key)"
echo "$OUTPUT"

VM_IP="$(echo "$OUTPUT" | awk '/IPv4:/ {print $2}')"
[[ -n "$VM_IP" ]] || { echo "❌ Impossible de récupérer l'adresse IPv4"; exit 1; }
echo "✅ VM IP: $VM_IP"

# ========== Attente SSH ==========
ssh-keygen -R "$VM_IP" >/dev/null 2>&1 || true
echo "⏳ Attente de SSH..."
for i in {1..30}; do
  if nc -z -w2 "$VM_IP" 22; then
    echo "✅ SSH up"
    break
  fi
  sleep 2
done || { echo "❌ Timeout: SSH indisponible"; exit 1; }

echo "✅ VM $NAME prête sur $VM_IP"
