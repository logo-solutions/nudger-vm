#!/usr/bin/env bash
set -euo pipefail
set -o errtrace

# ── Defaults ──────────────────────────────────────────────────────────────
NAME="${NAME:-master1}"
TYPE="${TYPE:-cpx21}"
LOCATION="${LOCATION:-nbg1}"
IMAGE="${IMAGE:-ubuntu-22.04}"
CONTEXT="${CONTEXT:-nudger}"

# Clé SSH durable (celle qui est déjà côté Hetzner + présente en local)
SSH_KEY_ID="${SSH_KEY_ID:-}"                     # ex: --ssh-key-id 102768386 (recommandé)
KEY_NAME="${KEY_NAME:-hetzner-bastion}"         # si on doit assurer côté Hetzner
KEY_PATH="${KEY_PATH:-/root/.ssh/hetzner-bastion}"
KEY_PUB="${KEY_PUB:-${KEY_PATH}.pub}"

# Cloud-init (optionnel)
CLOUD_INIT="${CLOUD_INIT:-}"

# Repo + inventory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INV_FILE="$REPO_ROOT/infra/k8s_ansible/inventory.ini"

# ── Helpers ───────────────────────────────────────────────────────────────
log(){ printf "\n\033[1;36m👉 %s\033[0m\n" "$*"; }
ok(){  printf "\033[1;32m✅ %s\033[0m\n" "$*"; }
err(){ printf "\033[1;31m❌ %s\033[0m\n" "$*" >&2; }
trap 'err "Échec à la ligne $LINENO (cmd: ${BASH_COMMAND:-?})"' ERR
need(){ command -v "$1" >/dev/null 2>&1 || { err "Commande requise introuvable: $1"; exit 1; }; }
finger_md5(){ ssh-keygen -lf "$1" -E md5 | awk '{print $2}' | sed 's/^MD5://'; }

usage(){
cat <<EOF
Usage: $(basename "$0") [options]
  -t, --token TOKEN       Fournit HCLOUD_TOKEN si pas de contexte actif
  -n, --name NAME         Nom (def: $NAME)
  --type TYPE             Type (def: $TYPE)
  --location LOC          Localisation (def: $LOCATION)
  --image IMAGE           Image (def: $IMAGE)
  --ssh-key-id ID         ID clé Hetzner (recommandé)
  --key-name NAME         Nom clé Hetzner à créer/assurer (def: $KEY_NAME)
  --key-path PATH         Chemin de la clé privée locale (def: $KEY_PATH)
  --cloud-init FILE       Fichier cloud-init (optionnel)
  --recreate              Supprime et recrée si le serveur existe
  -h, --help              Aide
EOF
}

RECREATE=0
# ── Args ───────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--token) export HCLOUD_TOKEN="${2:?}"; shift 2;;
    -n|--name)  NAME="${2:?}"; shift 2;;
    --type)     TYPE="${2:?}"; shift 2;;
    --location) LOCATION="${2:?}"; shift 2;;
    --image)    IMAGE="${2:?}"; shift 2;;
    --ssh-key-id) SSH_KEY_ID="${2:?}"; shift 2;;
    --key-name) KEY_NAME="${2:?}"; shift 2;;
    --key-path) KEY_PATH="${2:?}"; KEY_PUB="${KEY_PATH}.pub"; shift 2;;
    --cloud-init) CLOUD_INIT="${2:?}"; shift 2;;
    --recreate) RECREATE=1; shift;;
    -h|--help) usage; exit 0;;
    *) err "Option inconnue: $1"; usage; exit 2;;
  esac
done

# ── Prechecks ──────────────────────────────────────────────────────────────
need hcloud; need jq; need ssh-keygen; need awk
# ── Clé SSH locale : récupération depuis Bitwarden si absente ──────────────
if [[ ! -f "$KEY_PATH" || ! -f "$KEY_PUB" ]]; then
  log "Clé SSH absente, tentative de récupération depuis Bitwarden…"
  export BW_SESSION="${BW_SESSION:-$(bw unlock --raw 2>/dev/null)}"

  # Récupérer la clé privée
  PRIV_KEY=$(bw get item cle_privee_hetzner | jq -r '.login.password' 2>/dev/null)
  if [[ -z "$PRIV_KEY" || "$PRIV_KEY" == "null" ]]; then
    err "Impossible de récupérer la clé privée dans Bitwarden (item: cle_privee_hetzner)"
    exit 1
  fi

  # Création du dossier ~/.ssh si besoin
  mkdir -p "$(dirname "$KEY_PATH")"
  chmod 700 "$(dirname "$KEY_PATH")"

  # Sauvegarde et permissions
  echo "$PRIV_KEY" > "$KEY_PATH"
  chmod 600 "$KEY_PATH"

  # Génération de la clé publique si absente
  if [[ ! -f "$KEY_PUB" ]]; then
    ssh-keygen -y -f "$KEY_PATH" > "$KEY_PUB"
  fi

  ok "Clé SSH restaurée depuis Bitwarden : $KEY_PATH"
fi
[[ -f "$KEY_PATH" && -f "$KEY_PUB" ]] || { err "Clé locale manquante: $KEY_PATH(.pub)"; exit 1; }

# Contexte Hetzner
if ! hcloud context active >/dev/null 2>&1; then
  # Si la variable HCLOUD_TOKEN n'est pas définie, on va la chercher dans Bitwarden
# ── Authentification Hetzner via Bitwarden ───────────────
if [[ -z "${HCLOUD_TOKEN:-}" ]]; then
  log "HCLOUD_TOKEN absent, tentative de récupération depuis Bitwarden..."
  export BW_SESSION="${BW_SESSION:-$(bw unlock --raw 2>/dev/null)}"
  HCLOUD_TOKEN=$(bw get item token_hcloud_bastion | jq -r '.login.password' 2>/dev/null)
  if [[ -z "$HCLOUD_TOKEN" || "$HCLOUD_TOKEN" == "null" ]]; then
    err "Impossible de récupérer le token dans Bitwarden (item: token_hcloud_bastion)"
    exit 1
  fi
  export HCLOUD_TOKEN
fi

ok "Authentification Hetzner OK (token chargé depuis Bitwarden)"
  log "Création du contexte '$CONTEXT' (non-interactif)"
  # Supprime si existe déjà pour éviter doublons silencieux
  hcloud context delete "$CONTEXT" -f >/dev/null 2>&1 || true
  echo y | hcloud context create "$CONTEXT" --token "$HCLOUD_TOKEN" >/dev/null 2>&1 || true
  hcloud context use "$CONTEXT" >/dev/null 2>&1 || true

  # 🧠 Force le token pour le process courant (certaines versions du CLI ne relisent pas immédiatement la config)
  export HCLOUD_TOKEN
fi

# Double vérif : s'il reste vide, on recharge le token depuis le contexte actif
if [[ -z "${HCLOUD_TOKEN:-}" ]]; then
  HCLOUD_TOKEN=$(awk -v ctx="$CONTEXT" '
  $1 == "[context \""ctx"\"]" {found=1; next}
  found && $1 == "token" {print $3; exit}
' ~/.config/hcloud/cli.toml 2>/dev/null)
export HCLOUD_TOKEN
fi

# Validation
if ! hcloud context active >/dev/null 2>&1; then
  err "Le contexte Hetzner '$CONTEXT' n'a pas pu être activé. Vérifie ton token."
  exit 1
fi

ok "Contexte actif: $(hcloud context active)"


# Assurer la clé Hetzner si SSH_KEY_ID non fourni
if [[ -z "$SSH_KEY_ID" ]]; then
  log "Assurance clé Hetzner depuis la pub locale ($KEY_PUB)"
  LOCAL_MD5="$(finger_md5 "$KEY_PUB")"
  if hcloud ssh-key describe "$KEY_NAME" -o json >/dev/null 2>&1; then
    HC_MD5="$(hcloud ssh-key describe "$KEY_NAME" -o json | jq -r .fingerprint)"
    if [[ "$HC_MD5" != "$LOCAL_MD5" ]]; then
      log "Clé '$KEY_NAME' existe mais fingerprint différent → nouveau nom"
      KEY_NAME="${KEY_NAME}-$(date +%s)"
      hcloud ssh-key create --name "$KEY_NAME" --public-key "$(cat "$KEY_PUB")" >/dev/null
    fi
  else
    hcloud ssh-key create --name "$KEY_NAME" --public-key "$(cat "$KEY_PUB")" >/dev/null
  fi
  SSH_KEY_ID="$(hcloud ssh-key describe "$KEY_NAME" -o json | jq -r .id)"
fi
ok "SSH_KEY_ID=$SSH_KEY_ID"

# ── Création VM ────────────────────────────────────────────────────────────
EXISTS=0
if hcloud server describe "$NAME" >/dev/null 2>&1; then EXISTS=1; fi

if (( EXISTS )) && (( RECREATE )); then
  log "Suppression de '$NAME' (recreate)…"
  hcloud server delete "$NAME"
  EXISTS=0
  ok "Serveur supprimé."
fi

if (( ! EXISTS )); then
  log "Création de $NAME (type=$TYPE, image=$IMAGE, loc=$LOCATION, key=$SSH_KEY_ID)"
  if [[ -n "${CLOUD_INIT:-}" ]]; then
    hcloud server create \
      --name "$NAME" \
      --image "$IMAGE" \
      --type "$TYPE" \
      --location "$LOCATION" \
      --ssh-key "$SSH_KEY_ID" \
      --user-data-from-file "$CLOUD_INIT" >/dev/null
  else
    hcloud server create \
      --name "$NAME" \
      --image "$IMAGE" \
      --type "$TYPE" \
      --location "$LOCATION" \
      --ssh-key "$SSH_KEY_ID" >/dev/null
  fi
  ok "VM créée."
else
  ok "VM déjà présente."
fi

# IP publique
sleep 2
IP="$(hcloud server describe "$NAME" -o json | jq -r '.public_net.ipv4.ip')"
[[ -n "$IP" && "$IP" != "null" ]] || { err "Impossible de récupérer l'IP publique"; exit 1; }
ok "IP publique: $IP"

# known_hosts
ssh-keygen -R "$IP" >/dev/null 2>&1 || true
ssh-keyscan -H "$IP" >> ~/.ssh/known_hosts 2>/dev/null || true

# ── Inventory.ini : réécriture propre de deux sections ─────────────────────
log "Mise à jour inventaire: $INV_FILE"
mkdir -p "$(dirname "$INV_FILE")"
touch "$INV_FILE"

# 1) Purge ancienne section bastion
sed -i '/^\[bastion\]/,/^\[/ { /^\[bastion\]/! {/^\[/!d } }' "$INV_FILE"

# 2) Réécriture bastion (toujours propre, pas de backslash, pas de doublon)
{
  echo ""
  echo "[bastion]"
  echo "bastion_host ansible_host=127.0.0.1 ansible_connection=local ansible_user=root ansible_python_interpreter=/usr/bin/python3"
  echo ""
  echo "[k8s_masters]"
  echo "$NAME ansible_host=$IP ansible_user=root ansible_ssh_private_key_file=$KEY_PATH ansible_python_interpreter=/usr/bin/python3"
  echo ""
  echo "[master:children]"
  echo "k8s_masters"
} >> "$INV_FILE"
# ── Attente ouverture du port SSH ──────────────────────────────────────────
log "Attente d'ouverture du port 22 sur $IP…"
for i in $(seq 1 60); do  # ~3 minutes max
  if nc -z "$IP" 22 2>/dev/null; then
    ok "Port 22 ouvert"
    break
  fi
  sleep 3
done

# ── Test SSH ───────────────────────────────────────────────────────────────
log "Test SSH : ssh -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -i $KEY_PATH root@$IP true"
ssh -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -i "$KEY_PATH" root@"$IP" true

ok "Inventaire mis à jour"
log "Test SSH : ssh -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -i $KEY_PATH root@$IP true"
ssh -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -i "$KEY_PATH" root@"$IP" true

ok "Création + SSH OK pour $NAME ($IP)"
echo "Astuce: ansible -i $INV_FILE k8s_masters -m ping -u root"
