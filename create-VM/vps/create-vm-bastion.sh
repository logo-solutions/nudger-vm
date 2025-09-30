#!/usr/bin/env bash
set -euo pipefail
set -o errtrace

# ── Defaults ──────────────────────────────────────────────────────────────
NAME="${NAME:-bastion}"
TYPE="${TYPE:-cpx31}"
LOCATION="${LOCATION:-hel1}"
IMAGE="${IMAGE:-ubuntu-22.04}"
CONTEXT="${CONTEXT:-nudger}"
AUTO_COMMIT="${AUTO_COMMIT:-0}"   # 1 pour activer

SSH_KEY_ID="${SSH_KEY_ID:-}"
KEY_NAME="${KEY_NAME:-hetzner-bastion}"
KEY_PATH="${KEY_PATH:-$HOME/.ssh/hetzner-bastion}"
KEY_PUB="${KEY_PUB:-${KEY_PATH}.pub}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CI_TMPL="${CI_TMPL:-$REPO_ROOT/create-VM/vps/cloud-init-template.yaml}"
CI_REND="${CI_REND:-$REPO_ROOT/create-VM/vps/cloud-init.yaml}"
INV_FILE="$REPO_ROOT/infra/k8s_ansible/inventory.ini"

# ── Helpers ───────────────────────────────────────────────────────────────
log(){ printf "\n\033[1;36m👉 %s\033[0m\n" "$*"; }
ok(){  printf "\033[1;32m✅ %s\033[0m\n" "$*"; }
err(){ printf "\033[1;31m❌ %s\033[0m\n" "$*" >&2; }
trap 'err "Échec à la ligne $LINENO (cmd: ${BASH_COMMAND:-?})"' ERR
need(){ command -v "$1" >/dev/null 2>&1 || { err "Commande requise introuvable: $1"; exit 1; }; }
finger_md5(){ ssh-keygen -lf "$1" -E md5 | awk '{print $2}' | sed 's/^MD5://'; }

wait_ssh(){
  local ip="$1" key="$2" tries=40
  log "Attente SSH disponible sur $ip (ssh -i $key)…"
  ssh-keygen -R "$ip" >/dev/null 2>&1 || true
  for i in $(seq 1 $tries); do
    if ssh -o BatchMode=yes -o ConnectTimeout=4 \
         -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
         -i "$key" root@"$ip" true 2>/dev/null; then
      ok "SSH opérationnel sur $ip"
      return 0
    fi
    sleep 3
  done
  err "SSH non disponible sur $ip"
  return 1
}

usage(){
cat <<EOF
Usage: $(basename "$0") [options]
  -t, --token TOKEN       Fournit HCLOUD_TOKEN si pas de contexte actif
  -n, --name NAME         Nom (def: $NAME)
  --type TYPE             Type (def: $TYPE)
  --location LOC          Localisation (def: $LOCATION)
  --image IMAGE           Image (def: $IMAGE)
  --ssh-key-id ID         ID clé Hetzner
  --key-name NAME         Nom clé Hetzner à assurer (def: $KEY_NAME)
  --key-path PATH         Chemin clé privée locale (def: $KEY_PATH)
  --ci-template FILE      Template cloud-init (def: $CI_TMPL)
  --ci-render FILE        Fichier rendu (def: $CI_REND)
  --recreate              Supprime et recrée si le serveur existe
  -h, --help              Aide
EOF
}

RECREATE=0
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
    --ci-template) CI_TMPL="${2:?}"; shift 2;;
    --ci-render)   CI_REND="${2:?}"; shift 2;;
    --recreate) RECREATE=1; shift;;
    -h|--help) usage; exit 0;;
    *) err "Option inconnue: $1"; usage; exit 2;;
  esac
done

# ── Prechecks ──────────────────────────────────────────────────────────────
need hcloud; need jq; need ssh-keygen; need awk; need envsubst
[[ -f "$KEY_PATH" && -f "$KEY_PUB" ]] || { err "Clé locale manquante: $KEY_PATH(.pub)"; exit 1; }
[[ -f "$CI_TMPL" ]] || { err "Template cloud-init introuvable: $CI_TMPL"; exit 1; }

# Contexte Hetzner
if ! hcloud context active >/dev/null 2>&1; then
  [[ -n "${HCLOUD_TOKEN:-}" ]] || { err "Pas de contexte et HCLOUD_TOKEN absent"; exit 1; }
  log "Création du contexte '$CONTEXT'"
  echo y | hcloud context create "$CONTEXT" >/dev/null 2>&1 || true
  hcloud context use "$CONTEXT"
fi
ok "Contexte actif: $(hcloud context active || echo 'n/a')"

# Assurer la clé Hetzner
if [[ -z "$SSH_KEY_ID" ]]; then
  log "Assurance clé Hetzner ($KEY_PUB)"
  LOCAL_MD5="$(finger_md5 "$KEY_PUB")"
  if hcloud ssh-key describe "$KEY_NAME" -o json >/dev/null 2>&1; then
    HC_MD5="$(hcloud ssh-key describe "$KEY_NAME" -o json | jq -r .fingerprint)"
    if [[ "$HC_MD5" != "$LOCAL_MD5" ]]; then
      KEY_NAME="${KEY_NAME}-$(date +%s)"
      hcloud ssh-key create --name "$KEY_NAME" --public-key "$(cat "$KEY_PUB")" >/dev/null
    fi
  else
    hcloud ssh-key create --name "$KEY_NAME" --public-key "$(cat "$KEY_PUB")" >/dev/null
  fi
  SSH_KEY_ID="$(hcloud ssh-key describe "$KEY_NAME" -o json | jq -r .id)"
fi
ok "SSH_KEY_ID=$SSH_KEY_ID"

# Rendu cloud-init
export HOSTNAME="$NAME"
log "Rendu cloud-init → $CI_REND (HOSTNAME=$HOSTNAME)"
envsubst < "$CI_TMPL" > "$CI_REND"

# Création serveur
if hcloud server describe "$NAME" >/dev/null 2>&1; then
  if [[ "$RECREATE" -eq 1 ]]; then
    log "Suppression de '$NAME' (recreate)…"
    hcloud server delete "$NAME"
    ok "Serveur supprimé."
  else
    ok "VM déjà présente"
  fi
fi

if ! hcloud server describe "$NAME" >/dev/null 2>&1; then
  log "Création de $NAME (type=$TYPE, image=$IMAGE, loc=$LOCATION)"
  hcloud server create \
    --name "$NAME" \
    --image "$IMAGE" \
    --type "$TYPE" \
    --location "$LOCATION" \
    --ssh-key "$SSH_KEY_ID" \
    --user-data-from-file "$CI_REND" >/dev/null
  ok "VM créée."
fi

# IP publique
sleep 2
IP="$(hcloud server describe "$NAME" -o json | jq -r '.public_net.ipv4.ip')"
[[ -n "$IP" && "$IP" != "null" ]] || { err "Impossible de récupérer l'IP publique"; exit 1; }
ok "IP publique: $IP"

ssh-keygen -R "$IP" >/dev/null 2>&1 || true
ssh-keyscan -H "$IP" >> ~/.ssh/known_hosts 2>/dev/null || true

# Inventaire Ansible : normaliser la section [bastion] en mode SSH depuis le host
# Inventaire Ansible local (groupe [bastion]) — FORCER FORMAT PROPRE
log "Mise à jour inventaire: $INV_FILE"
touch "$INV_FILE"

# Reconstruire le fichier en garantissant :
#  - une seule section [bastion]
#  - exactement UNE ligne 'bastion …' sans backslashes ni ansible_connection=local
#  - on ne modifie pas les autres sections
awk_prog='
# Inventaire Ansible local (section [bastion] propre)
log "Mise à jour inventaire: $INV_FILE"
touch "$INV_FILE"

awk_prog='
BEGIN { inb=0; injected=0; seen_header=0 }
# Toute entête de section
/^\[/ {
  # Si on sort de [bastion] sans avoir injecté la ligne propre
  if (inb && !injected) {
    print "bastion ansible_host=" ip " ansible_user=root ansible_ssh_private_key_file=" key " ansible_python_interpreter=/usr/bin/python3"
    injected=1
  }
  print
  if ($0 ~ /^\[bastion\]$/) { inb=1; seen_header=1; next } else { inb=0; next }
}
{
  if (inb) {
    # Supprimer toute ancienne ligne bastion et toute ligne finissant par un backslash
    if ($0 ~ /^bastion[[:space:]]/) next
    if ($0 ~ /\\[[:space:]]*$/)     next
    # Ne pas recopier le contenu ancien de la section bastion
    next
  }
  print
}
END {
  if (!seen_header) {
    print ""
    print "[bastion]"
  }
  if (!injected) {
    print "bastion ansible_host=" ip " ansible_user=root ansible_ssh_private_key_file=" key " ansible_python_interpreter=/usr/bin/python3"
  }
}'

awk -v ip="$IP" -v key="$KEY_PATH" "$awk_prog" "$INV_FILE" > "$INV_FILE.tmp" && mv "$INV_FILE.tmp" "$INV_FILE"

ok "Inventaire local mis à jour"
# SSH test
wait_ssh "$IP" "$KEY_PATH"
log "Test SSH : ssh -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -i $KEY_PATH root@$IP true"
ssh -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -i "$KEY_PATH" root@"$IP" true

ok "Bastion prêt: $NAME ($IP)"
echo "Astuce: ansible -i $INV_FILE bastion -m ping -u root"
