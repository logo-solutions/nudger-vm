#!/usr/bin/env bash
set -euo pipefail
set -o errtrace

# ── Defaults ──────────────────────────────────────────────────────────────
NAME="${NAME:-bastion}"
TYPE="${TYPE:-cpx31}"
LOCATION="${LOCATION:-hel1}"
IMAGE="${IMAGE:-ubuntu-22.04}"
CONTEXT="${CONTEXT:-nudger}"
# Auto commit/push de l'inventaire (opt-in)
AUTO_COMMIT="${AUTO_COMMIT:-0}"   # 1 pour activer

# Clé SSH Durable
SSH_KEY_ID="${SSH_KEY_ID:-}"                   # si tu veux forcer l'ID
KEY_NAME="${KEY_NAME:-hetzner-bastion}"        # nom côté Hetzner (durable)
KEY_PATH="${KEY_PATH:-/root/.ssh/hetzner-bastion}"
KEY_PUB="${KEY_PUB:-${KEY_PATH}.pub}"

# Cloud-init (template → rendu)
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
  --ssh-key-id ID         ID clé Hetzner (sinon auto-ensure via KEY_NAME+KEY_PATH(.pub))
  --key-name NAME         Nom clé Hetzner à assurer (def: $KEY_NAME)
  --key-path PATH         Chemin clé privée locale (def: $KEY_PATH)
  --ci-template FILE      Template cloud-init (def: $CI_TMPL)
  --ci-render FILE        Fichier cloud-init rendu (def: $CI_REND)
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
  [[ -n "${HCLOUD_TOKEN:-}" ]] || { err "Pas de contexte et HCLOUD_TOKEN absent (-t TOKEN)."; exit 1; }
  log "Création du contexte '$CONTEXT' (non-interactif)"
  echo y | hcloud context create "$CONTEXT" >/dev/null 2>&1 || true
  hcloud context use "$CONTEXT"
fi
ok "Contexte actif: $(hcloud context active || echo 'n/a')"

# Assurer la clé côté Hetzner (si ID non fourni)
if [[ -z "$SSH_KEY_ID" ]]; then
  log "Assurance clé Hetzner depuis la pub locale ($KEY_PUB)"
  LOCAL_MD5="$(finger_md5 "$KEY_PUB")"
  if hcloud ssh-key describe "$KEY_NAME" -o json >/dev/null 2>&1; then
    HC_MD5="$(hcloud ssh-key describe "$KEY_NAME" -o json | jq -r .fingerprint)"
    if [[ "$HC_MD5" != "$LOCAL_MD5" ]]; then
      log "Clé '$KEY_NAME' existe mais fingerprint différent → nouveau nom unique"
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

# Serveur existe ?
if hcloud server describe "$NAME" >/dev/null 2>&1; then
  if [[ "$RECREATE" -eq 1 ]]; then
    log "Suppression de '$NAME' (recreate)…"
    hcloud server delete "$NAME"
    ok "Serveur supprimé."
  else
    ok "VM déjà présente, pas de création."
  fi
fi

# Créer
if ! hcloud server describe "$NAME" >/dev/null 2>&1; then
  log "Création de $NAME (type=$TYPE, image=$IMAGE, loc=$LOCATION, key=$SSH_KEY_ID)"
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

# known_hosts
ssh-keygen -R "$IP" >/dev/null 2>&1 || true
ssh-keyscan -H "$IP" >> ~/.ssh/known_hosts 2>/dev/null || true

# Inventaire Ansible local (groupe [bastion])
log "Mise à jour inventaire: $INV_FILE"
if [[ -f "$INV_FILE" ]]; then
  sed -i'' -e "/^bastion /d" "$INV_FILE" 2>/dev/null || sed -i "/^bastion /d" "$INV_FILE"
  if ! grep -q "^\[bastion\]" "$INV_FILE"; then
    printf "\n[bastion]\n" >> "$INV_FILE"
  fi
  awk -v ip="$IP" -v key="$KEY_PATH" '
    BEGIN{printed=0}
    /^\[bastion\]/{print; print "bastion ansible_host=" ip " ansible_user=root ansible_ssh_private_key_file=" key " ansible_python_interpreter=/usr/bin/python3"; printed=1; next}
    {print}
    END{if(!printed) print "bastion ansible_host=" ip " ansible_user=root ansible_ssh_private_key_file=" key " ansible_python_interpreter=/usr/bin/python3"}
  ' "$INV_FILE" > "$INV_FILE.tmp" && mv "$INV_FILE.tmp" "$INV_FILE"
else
  cat > "$INV_FILE" <<EOF
[bastion]
bastion ansible_host=$IP ansible_user=root ansible_ssh_private_key_file=$KEY_PATH ansible_python_interpreter=/usr/bin/python3
EOF
fi
ok "Inventaire local mis à jour"
# ====== AUTO COMMIT / PUSH (opt-in) ======
if [[ "$AUTO_COMMIT" == "1" ]]; then
  REPO_ROOT="$(cd "$DIRHOME" && git rev-parse --show-toplevel 2>/dev/null || echo "")"
  if [[ -z "$REPO_ROOT" ]]; then
    LOG "🛈 AUTO_COMMIT=1 ignoré (pas un repo git sous $DIRHOME)"
  else
    (
      cd "$REPO_ROOT"

      # Branche courante + remote
      BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"
      ORIGIN_URL="$(git remote get-url origin 2>/dev/null || echo "")"

      # Config auteur locale, non intrusive si déjà définie
      git config user.name  >/dev/null || git config user.name  "nudger-bot"
      git config user.email >/div/null || git config user.email "devops@logo-solutions"

      # Assure-toi d’être à jour pour éviter les non-fast-forward
      git pull --rebase --autostash || true

      # Ne stage QUE l’inventaire
      FILE="infra/k8s_ansible/inventory.ini"

      # Commit seulement s’il y a un vrai diff
      if ! git diff --quiet -- "$FILE"; then
        git add "$FILE"
        MSG="chore(inventory): update bastion IP ${VM_IP}"
        git commit -m "$MSG"

        # Push :
        # - si remote HTTPS et GITHUB_TOKEN présent → pousse avec header Auth (pas d’URL à encoder)
        # - sinon push standard (SSH ou HTTPS déjà authentifié)
        if [[ -n "$GITHUB_TOKEN" && "$ORIGIN_URL" == https://* ]]; then
          git -c http.extraheader="Authorization: Bearer ${GITHUB_TOKEN}" \
              push origin "$BRANCH"
        else
          git push origin "$BRANCH"
        fi
        LOG "✅ Inventory poussé: $FILE → $BRANCH"
      else
        LOG "🛈 Aucun changement à committer dans $FILE"
      fi
    )
  fi
fi

# Attendre SSH + test
wait_ssh "$IP" "$KEY_PATH"
log "Test SSH : ssh -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -i $KEY_PATH root@$IP true"
ssh -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -i "$KEY_PATH" root@"$IP" true

ok "Bastion prêt: $NAME ($IP)"
echo "Astuce: ansible -i $INV_FILE bastion -m ping -u root"
