#!/usr/bin/env bash
set -euo pipefail
set -o errtrace

###############################################################################
#  Script : create-vm-master.sh
#  Auteur : Loïc Bourmelon
#  Description :
#    - Récupère le token Hetzner et la clé SSH depuis Bitwarden
#    - Supprime la VM master1 si elle existe déjà
#    - Crée la VM master1 sur Hetzner
#    - Met à jour l’inventaire Ansible
#    - Teste la connexion SSH
###############################################################################

NAME="master1"
TYPE="cpx32"
LOCATION="nbg1"
IMAGE="ubuntu-22.04"

KEY_NAME="hetzner-bastion"
KEY_PATH="/root/.ssh/hetzner-bastion"
KEY_PUB="${KEY_PATH}.pub"
INV_FILE="/root/nudger-vm/infra/k8s_ansible/inventory.ini"

HCLOUD_BIN="/usr/local/bin/hcloud"

# ──────────────────────────────
# Helpers
# ──────────────────────────────
log()  { printf "\n\033[1;36m👉 %s\033[0m\n" "$*"; }
ok()   { printf "\033[1;32m✅ %s\033[0m\n" "$*"; }
warn() { printf "\033[1;33m⚠️  %s\033[0m\n" "$*"; }
err()  { printf "\033[1;31m❌ %s\033[0m\n" "$*" >&2; exit 1; }

trap 'err "Échec à la ligne $LINENO (cmd: ${BASH_COMMAND:-?})"' ERR
need() { command -v "$1" >/dev/null 2>&1 || err "Outil manquant: $1"; }

# ──────────────────────────────
# Pré-vérifications
# ──────────────────────────────
log "Vérification des outils requis..."
for cmd in $HCLOUD_BIN jq ssh-keygen bw nc; do need "$cmd"; done
ok "Tous les outils requis sont disponibles."

# ──────────────────────────────
# Authentification Hetzner
# ──────────────────────────────
log "Chargement du token Hetzner depuis Bitwarden..."
export BW_SESSION="${BW_SESSION:-$(bw unlock --raw)}"
HCLOUD_TOKEN=$(bw get item token_hcloud_bastion | jq -r '.login.password')
[[ -z "$HCLOUD_TOKEN" || "$HCLOUD_TOKEN" == "null" ]] && err "Token Hetzner introuvable."
ok "Token Hetzner récupéré."

export HCLOUD_TOKEN

# ──────────────────────────────
# Clé SSH
# ──────────────────────────────
if [[ ! -f "$KEY_PATH" ]]; then
  log "Restauration de la clé SSH depuis Bitwarden..."
  PRIV_KEY=$(bw get item cle_privee_hetzner | jq -r '.login.password')
  [[ -z "$PRIV_KEY" || "$PRIV_KEY" == "null" ]] && err "Clé SSH non trouvée dans Bitwarden."
  mkdir -p "$(dirname "$KEY_PATH")"
  echo "$PRIV_KEY" > "$KEY_PATH"
  chmod 600 "$KEY_PATH"
  ssh-keygen -y -f "$KEY_PATH" > "$KEY_PUB"
fi
ok "Clé SSH prête."

# ──────────────────────────────
# Vérification clé Hetzner
# ──────────────────────────────
log "Assurance clé Hetzner..."
if ! $HCLOUD_BIN ssh-key describe "$KEY_NAME" >/dev/null 2>&1; then
  $HCLOUD_BIN ssh-key create --name "$KEY_NAME" --public-key "$(cat "$KEY_PUB")" >/dev/null
  ok "Clé Hetzner créée."
else
  ok "Clé Hetzner déjà existante."
fi

SSH_KEY_ID="$($HCLOUD_BIN ssh-key describe "$KEY_NAME" -o json | jq -r .id)"
ok "SSH_KEY_ID=$SSH_KEY_ID"

# ──────────────────────────────
# Suppression éventuelle de la VM
# ──────────────────────────────
if $HCLOUD_BIN server describe "$NAME" >/dev/null 2>&1; then
  warn "VM existante détectée → suppression..."
  $HCLOUD_BIN server delete "$NAME"
  ok "VM supprimée."
  sleep 5
fi

# ──────────────────────────────
# Création de la VM
# ──────────────────────────────
log "Création de la VM $NAME..."
$HCLOUD_BIN server create \
  --name "$NAME" \
  --type "$TYPE" \
  --image "$IMAGE" \
  --location "$LOCATION" \
  --ssh-key "$SSH_KEY_ID" >/dev/null
ok "VM créée."

# ──────────────────────────────
# Récupération IP publique
# ──────────────────────────────
sleep 5
IP="$($HCLOUD_BIN server describe "$NAME" -o json | jq -r '.public_net.ipv4.ip')"
[[ -z "$IP" || "$IP" == "null" ]] && err "Impossible de récupérer l’IP publique."
ok "IP publique: $IP"

# ──────────────────────────────
# Mise à jour inventaire Ansible
# ──────────────────────────────
log "Mise à jour de l’inventaire Ansible..."
cat > "$INV_FILE" <<EOF
[bastion]
bastion_host ansible_host=127.0.0.1 ansible_connection=local ansible_user=root

[k8s_masters]
$NAME ansible_host=$IP ansible_user=root ansible_ssh_private_key_file=$KEY_PATH ansible_python_interpreter=/usr/bin/python3

[master:children]
k8s_masters
EOF
ok "Inventaire mis à jour: $INV_FILE"

# ──────────────────────────────
# Test de connexion SSH
# ──────────────────────────────
log "Test SSH vers $IP..."
for i in {1..30}; do
  if nc -z "$IP" 22 2>/dev/null; then
    ssh -o StrictHostKeyChecking=no -i "$KEY_PATH" root@"$IP" true && ok "Connexion SSH OK."
    break
  fi
  sleep 3
done

# ──────────────────────────────
# Résumé final
# ──────────────────────────────
log "Résumé final"
echo "🌍 Nom VM       : $NAME"
echo "📍 IP Publique  : $IP"
echo "🔑 Clé Hetzner  : $KEY_NAME (ID: $SSH_KEY_ID)"
echo "📘 Inventaire   : $INV_FILE"
ok "Création complète."

echo "💡 Commande test : ansible -i $INV_FILE k8s_masters -m ping -u root"
