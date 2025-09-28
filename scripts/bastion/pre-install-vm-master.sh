#!/usr/bin/env bash
set -euo pipefail

KEY_NAME="bastion-vm-key-hetzner"
KEY_FILE="/root/.ssh/$KEY_NAME"

# --- Supprimer la clé Hetzner existante si présente ---
EXIST_ID=$(hcloud ssh-key list -o noheader | awk -v k="$KEY_NAME" '$2 == k {print $1}')
if [[ -n "${EXIST_ID:-}" ]]; then
  echo "⚠️  Suppression clé Hetzner ID=$EXIST_ID ($KEY_NAME)..."
  hcloud ssh-key delete "$EXIST_ID"
fi

# --- Générer nouvelle paire de clés ---
echo "👉 Génération de la nouvelle clé SSH : $KEY_FILE"
rm -f "$KEY_FILE" "$KEY_FILE.pub"
ssh-keygen -t ed25519 -f "$KEY_FILE" -C "$KEY_NAME" -N "" -q

# --- Ajouter dans Hetzner ---
echo "👉 Ajout de la clé publique dans Hetzner..."
hcloud ssh-key create \
  --name "$KEY_NAME" \
  --public-key-from-file "$KEY_FILE.pub"

# --- Récupérer l’ID via describe ---
SSH_KEY_ID=$(hcloud ssh-key describe "$KEY_NAME" -o json | jq -r '.id')

echo "✅ Clé créée dans Hetzner :"
echo "   Nom    : $KEY_NAME"
echo "   ID     : $SSH_KEY_ID"
echo "   Privée : $KEY_FILE"

echo
echo "👉 Pour créer une VM avec cette clé :"
echo "   SSH_KEY_ID=$SSH_KEY_ID ./create-vm-master.sh"
