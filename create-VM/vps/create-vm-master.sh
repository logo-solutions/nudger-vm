#!/usr/bin/env bash
set -euo pipefail
set -o errtrace

# ─── Defaults ────────────────────────────────────────────────────────────────
NAME="${NAME:-master1}"
TYPE="${TYPE:-cpx21}"
LOCATION="${LOCATION:-nbg1}"
IMAGE="${IMAGE:-ubuntu-22.04}"
CONTEXT="${CONTEXT:-nudger}"

# Clé Hetzner : soit tu fournis l'ID, soit on fabrique/récupère depuis ta pub locale
SSH_KEY_ID="${SSH_KEY_ID:-}"                 # ex: export SSH_KEY_ID=102793911
KEY_NAME="${KEY_NAME:-nudger-vm-default}"    # nom de la clé côté Hetzner si on doit l'uploader
KEY_PATH="${KEY_PATH:-/root/.ssh/id_vm_ed25519}"
KEY_PUB="${KEY_PUB:-${KEY_PATH}.pub}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INV_FILE="$SCRIPT_DIR/../../infra/k8s_ansible/inventory.ini"

# ─── Helpers ────────────────────────────────────────────────────────────────
log(){ printf "\n\033[1;36m👉 %s\033[0m\n" "$*"; }
ok(){  printf "\033[1;32m✅ %s\033[0m\n" "$*"; }
err(){ printf "\033[1;31m❌ %s\033[0m\n" "$*" >&2; }
trap 'err "Échec à la ligne $LINENO (cmd: ${BASH_COMMAND:-?})"' ERR

need(){ command -v "$1" >/dev/null 2>&1 || { err "Commande requise introuvable: $1"; exit 1; }; }

confirm() {
  local prompt="${1:-Confirmer ?} [y/N] "
  read -r -p "$prompt" ans || true
  case "$ans" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  -t, --token TOKEN     Passer HCLOUD_TOKEN (sinon utiliser celui déjà exporté)
  -n, --name NAME       Nom du serveur (défaut: $NAME)
  --type TYPE           Type Hetzner (défaut: $TYPE)
  --location LOC        Localisation (défaut: $LOCATION)
  --image IMAGE         Image (défaut: $IMAGE)
  --ssh-key-id ID       ID d'une clé Hetzner existante (sinon on crée depuis ~/.ssh/id_vm_ed25519.pub)
  --key-name NAME       Nom à utiliser côté Hetzner pour la clé (défaut: $KEY_NAME)
  --key-path PATH       Chemin de ta clé privée locale (défaut: $KEY_PATH)
  -h, --help            Aide
EOF
}

# ─── Args ───────────────────────────────────────────────────────────────────
if [[ $# -gt 0 ]]; then
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -t|--token) export HCLOUD_TOKEN="${2:?}"; shift 2 ;;
      -n|--name)  NAME="${2:?}"; shift 2 ;;
      --type)     TYPE="${2:?}"; shift 2 ;;
      --location) LOCATION="${2:?}"; shift 2 ;;
      --image)    IMAGE="${2:?}"; shift 2 ;;
      --ssh-key-id) SSH_KEY_ID="${2:?}"; shift 2 ;;
      --key-name) KEY_NAME="${2:?}"; shift 2 ;;
      --key-path) KEY_PATH="${2:?}"; KEY_PUB="${KEY_PATH}.pub"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) err "Option inconnue: $1"; usage; exit 2 ;;
    esac
  done
fi

# ─── Prechecks ──────────────────────────────────────────────────────────────
need hcloud
need jq
need ssh-keygen
need awk

# Contexte Hetzner
if ! hcloud context active >/dev/null 2>&1; then
  [[ -n "${HCLOUD_TOKEN:-}" ]] || { err "Aucun contexte actif et HCLOUD_TOKEN non défini. Fournis -t TOKEN ou exporte HCLOUD_TOKEN."; exit 1; }
  log "Création du contexte '$CONTEXT' (non-interactif) avec HCLOUD_TOKEN"
  echo y | hcloud context create "$CONTEXT" >/dev/null 2>&1 || true
  hcloud context use "$CONTEXT"
fi
ok "Contexte actif: $(hcloud context active)"

# Clé locale présente ?
if [[ ! -f "$KEY_PATH" || ! -f "$KEY_PUB" ]]; then
  log "Clé locale absente — génération: $KEY_PATH"
  mkdir -p "$(dirname "$KEY_PATH")"
  ssh-keygen -t ed25519 -N "" -f "$KEY_PATH" -C "hetzner-$NAME" -q
  chmod 600 "$KEY_PATH"; chmod 644 "$KEY_PUB"
fi
ok "Clé locale OK: $KEY_PUB"

# Si pas d'ID fourni, créer/récupérer la clé Hetzner depuis TA pub locale
if [[ -z "$SSH_KEY_ID" ]]; then
  log "Création/récupération d'une clé Hetzner depuis ta pub locale ($KEY_PUB)"
  # tente la création; si déjà présente avec ce nom, on ignore l'erreur
  hcloud ssh-key create --name "$KEY_NAME" --public-key "$(cat "$KEY_PUB")" >/dev/null 2>&1 || true
  SSH_KEY_ID="$(hcloud ssh-key describe "$KEY_NAME" -o json | jq -r '.id // empty')"
  [[ -n "$SSH_KEY_ID" ]] || { err "Impossible d'obtenir l'ID de la clé Hetzner '$KEY_NAME'"; exit 1; }
  ok "SSH_KEY_ID=$SSH_KEY_ID"
else
  ok "SSH_KEY_ID fourni: $SSH_KEY_ID"
fi

# ─── Serveur existant ? ─────────────────────────────────────────────────────
EXISTS=0
if hcloud server describe "$NAME" >/dev/null 2>&1; then EXISTS=1; fi

if (( EXISTS )); then
  log "Le serveur '$NAME' existe déjà."
  if confirm "Souhaites-tu le supprimer et le recréer ?"; then
    log "Suppression de '$NAME'…"
    hcloud server delete "$NAME"
    ok "Serveur supprimé."
  else
    log "Réutilisation de '$NAME' existant."
  fi
fi

# ─── Création si nécessaire ─────────────────────────────────────────────────
if ! hcloud server describe "$NAME" >/dev/null 2>&1; then
  log "Création de la VM $NAME (type=$TYPE, image=$IMAGE, location=$LOCATION) avec clé SSH ID=$SSH_KEY_ID"
  hcloud server create \
    --name "$NAME" \
    --image "$IMAGE" \
    --type "$TYPE" \
    --ssh-key "$SSH_KEY_ID" \
    --location "$LOCATION" >/dev/null
  ok "VM $NAME créée."
else
  ok "VM $NAME déjà présente (pas de création)."
fi

# ─── Récupération IP ────────────────────────────────────────────────────────
sleep 2
IP="$(hcloud server describe "$NAME" -o json | jq -r '.public_net.ipv4.ip')"
[[ -n "$IP" && "$IP" != "null" ]] || { err "Impossible de récupérer l'IP publique pour $NAME"; exit 1; }
ok "IP publique: $IP"

# ─── known_hosts ────────────────────────────────────────────────────────────
log "Nettoyage known_hosts pour $IP"
ssh-keygen -R "$IP" >/dev/null 2>&1 || true

# ─── Mise à jour inventaire ────────────────────────────────────────────────
log "Mise à jour de l’inventaire $INV_FILE"
if [[ -f "$INV_FILE" ]]; then
  sed -i "/^$NAME /d" "$INV_FILE"
  if grep -q "^\[k8s_masters\]" "$INV_FILE"; then
    awk -v name="$NAME" -v ip="$IP" -v key="$KEY_PATH" '
      BEGIN { added=0 }
      /^\[k8s_masters\]/ {
        print;
        print name " ansible_host=" ip " ansible_user=root ansible_ssh_private_key_file=" key " ansible_python_interpreter=/usr/bin/python3";
        added=1; next
      }
      { print }
      END {
        if (!added)
          print "[k8s_masters]\n" name " ansible_host=" ip " ansible_user=root ansible_ssh_private_key_file=" key " ansible_python_interpreter=/usr/bin/python3"
      }
    ' "$INV_FILE" > "$INV_FILE.tmp" && mv "$INV_FILE.tmp" "$INV_FILE"
  else
    { echo "[k8s_masters]"; echo "$NAME ansible_host=$IP ansible_user=root ansible_ssh_private_key_file=$KEY_PATH ansible_python_interpreter=/usr/bin/python3"; cat "$INV_FILE"; } > "$INV_FILE.tmp"
    mv "$INV_FILE.tmp" "$INV_FILE"
  fi
else
  cat > "$INV_FILE" <<EOF
[k8s_masters]
$NAME ansible_host=$IP ansible_user=root ansible_ssh_private_key_file=$KEY_PATH ansible_python_interpreter=/usr/bin/python3

[bastion]
bastion_host ansible_host=127.0.0.1 ansible_connection=local ansible_python_interpreter=/usr/bin/python3
EOF
fi
ok "Inventaire mis à jour"

echo "👉 Test SSH : ssh -o IdentitiesOnly=yes -i $KEY_PATH root@$IP"
