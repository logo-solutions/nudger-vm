#!/usr/bin/env bash
set -euo pipefail
set -o errtrace

# ── Defaults ──────────────────────────────────────────────────────────────
NAME="${NAME:-master1}"
TYPE="${TYPE:-cpx21}"
LOCATION="${LOCATION:-nbg1}"
IMAGE="${IMAGE:-ubuntu-22.04}"
CONTEXT="${CONTEXT:-nudger}"

SSH_KEY_ID="${SSH_KEY_ID:-}"                 # ex: export SSH_KEY_ID=102804032
KEY_NAME="${KEY_NAME:-nudger-vm-default}"    # si on doit créer côté Hetzner
KEY_PATH="${KEY_PATH:-/root/.ssh/id_vm_ed25519}"
KEY_PUB="${KEY_PUB:-${KEY_PATH}.pub}"
CLOUD_INIT="${CLOUD_INIT:-}"                 # optionnel: chemin cloud-init à passer à hcloud

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INV_FILE="$SCRIPT_DIR/../../infra/k8s_ansible/inventory.ini"

# ── Helpers ───────────────────────────────────────────────────────────────
log(){ printf "\n\033[1;36m👉 %s\033[0m\n" "$*"; }
ok(){  printf "\033[1;32m✅ %s\033[0m\n" "$*"; }
err(){ printf "\033[1;31m❌ %s\033[0m\n" "$*" >&2; }
trap 'err "Échec à la ligne $LINENO (cmd: ${BASH_COMMAND:-?})"' ERR

need(){ command -v "$1" >/dev/null 2>&1 || { err "Commande requise introuvable: $1"; exit 1; }; }
confirm(){ read -r -p "${1:-Confirmer ?} [y/N] " a; case "$a" in y|Y|yes|YES) return 0;; *) return 1;; esac; }

finger_md5(){ ssh-keygen -lf "$1" -E md5 | awk '{print $2}' | sed 's/^MD5://'; }

wait_ssh(){
  local ip="$1" key="$2" tries=40
  log "Attente SSH disponible sur $ip (ssh -i $key)…"
  for i in $(seq 1 $tries); do
    if ssh -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=accept-new \
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
  --ssh-key-id ID         ID clé Hetzner (sinon auto-ensure via KEY_NAME+KEY_PATH)
  --key-name NAME         Nom clé Hetzner à créer/assurer (def: $KEY_NAME)
  --key-path PATH         Chemin de la clé privée locale (def: $KEY_PATH)
  --cloud-init FILE       Fichier cloud-init à passer à hcloud (optionnel)
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
[[ -f "$KEY_PATH" && -f "$KEY_PUB" ]] || { err "Clé locale manquante: $KEY_PATH(.pub)"; exit 1; }

# Contexte Hetzner
if ! hcloud context active >/dev/null 2>&1; then
  [[ -n "${HCLOUD_TOKEN:-}" ]] || { err "Pas de contexte et HCLOUD_TOKEN absent (-t TOKEN)."; exit 1; }
  log "Création du contexte '$CONTEXT' (non-interactif)"
  echo y | hcloud context create "$CONTEXT" >/dev/null 2>&1 || true
  hcloud context use "$CONTEXT"
fi
ok "Contexte actif: $(hcloud context active || echo 'n/a')"

# Assurer la clé Hetzner alignée avec la pub locale si SSH_KEY_ID absent
if [[ -z "$SSH_KEY_ID" ]]; then
  log "Assurance clé Hetzner depuis la pub locale ($KEY_PUB)"
  LOCAL_MD5="$(finger_md5 "$KEY_PUB")"
  if hcloud ssh-key describe "$KEY_NAME" -o json >/dev/null 2>&1; then
    HC_MD5="$(hcloud ssh-key describe "$KEY_NAME" -o json | jq -r .fingerprint)"
    if [[ "$HC_MD5" != "$LOCAL_MD5" ]]; then
      log "Clé '$KEY_NAME' existe mais ne matche pas (hc:$HC_MD5 != local:$LOCAL_MD5) → création d’un nouveau nom unique"
      KEY_NAME="${KEY_NAME}-$(date +%s)"
      hcloud ssh-key create --name "$KEY_NAME" --public-key "$(cat "$KEY_PUB")" >/dev/null
    fi
  else
    hcloud ssh-key create --name "$KEY_NAME" --public-key "$(cat "$KEY_PUB")" >/dev/null
  fi
  SSH_KEY_ID="$(hcloud ssh-key describe "$KEY_NAME" -o json | jq -r .id)"
fi
ok "SSH_KEY_ID=$SSH_KEY_ID"

# Serveur existe ?
EXISTS=0
if hcloud server describe "$NAME" >/dev/null 2>&1; then EXISTS=1; fi

if (( EXISTS )) && (( RECREATE )); then
  log "Suppression de '$NAME' (recreate demandé)…"
  hcloud server delete "$NAME"
  EXISTS=0
  ok "Serveur supprimé."
fi

# Création si nécessaire
if (( ! EXISTS )); then
  log "Création de $NAME (type=$TYPE, image=$IMAGE, loc=$LOCATION, key=$SSH_KEY_ID)"
  if [[ -n "$CLOUD_INIT" ]]; then
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
  ok "VM déjà présente, pas de création."
fi

# IP publique
sleep 2
IP="$(hcloud server describe "$NAME" -o json | jq -r '.public_net.ipv4.ip')"
[[ -n "$IP" && "$IP" != "null" ]] || { err "Impossible de récupérer l'IP publique"; exit 1; }
ok "IP publique: $IP"

# known_hosts
ssh-keygen -R "$IP" >/dev/null 2>&1 || true
ssh-keyscan -H "$IP" >> ~/.ssh/known_hosts 2>/dev/null || true

# Inventaire Ansible
log "Mise à jour inventaire: $INV_FILE"
if [[ -f "$INV_FILE" ]]; then
  sed -i "/^$NAME /d" "$INV_FILE"
  if ! grep -q "^\[k8s_masters\]" "$INV_FILE"; then
    printf "[k8s_masters]\n" | cat - "$INV_FILE" > "$INV_FILE.tmp" && mv "$INV_FILE.tmp" "$INV_FILE"
  fi
  awk -v name="$NAME" -v ip="$IP" -v key="$KEY_PATH" '
    BEGIN{printed=0}
    /^\[k8s_masters\]/{print; print name " ansible_host=" ip " ansible_user=root ansible_ssh_private_key_file=" key " ansible_python_interpreter=/usr/bin/python3"; printed=1; next}
    {print}
    END{if(!printed) print name " ansible_host=" ip " ansible_user=root ansible_ssh_private_key_file=" key " ansible_python_interpreter=/usr/bin/python3"}
  ' "$INV_FILE" > "$INV_FILE.tmp" && mv "$INV_FILE.tmp" "$INV_FILE"
else
  cat > "$INV_FILE" <<EOF
[k8s_masters]
$NAME ansible_host=$IP ansible_user=root ansible_ssh_private_key_file=$KEY_PATH ansible_python_interpreter=/usr/bin/python3

[bastion]
bastion_host ansible_host=127.0.0.1 ansible_connection=local ansible_python_interpreter=/usr/bin/python3

[master:children]
k8s_masters
EOF
fi
ok "Inventaire mis à jour"

# Attendre SSH et test court
wait_ssh "$IP" "$KEY_PATH"
log "Test SSH : ssh -o IdentitiesOnly=yes -i $KEY_PATH root@$IP true"
ssh -o IdentitiesOnly=yes -i "$KEY_PATH" root@"$IP" true

ok "Création + SSH OK pour $NAME ($IP)"
echo "Astuce: ansible -i $INV_FILE master -m ping -u root"
