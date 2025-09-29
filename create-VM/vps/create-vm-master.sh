#!/usr/bin/env bash
set -euo pipefail
set -o errtrace

# -------- Defaults --------
NAME="${NAME:-master1}"
TYPE="${TYPE:-cpx21}"
LOCATION="${LOCATION:-nbg1}"
IMAGE="${IMAGE:-ubuntu-22.04}"
CONTEXT="${CONTEXT:-nudger}"

# IMPORTANT: clé Hetzner à utiliser (ID côté Hetzner)
SSH_KEY_ID="${SSH_KEY_ID:-}"   # export SSH_KEY_ID=xxxx
# Chemin de la clé privée qui servira pour SSH vers la VM
KEY_PATH="${KEY_PATH:-/root/.ssh/id_vm_ed25519}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INV_FILE="$SCRIPT_DIR/../../infra/k8s_ansible/inventory.ini"

# -------- Helpers --------
log(){ printf "\n\033[1;36m👉 %s\033[0m\n" "$*"; }
ok(){  printf "\033[1;32m✅ %s\033[0m\n" "$*"; }
err(){ printf "\033[1;31m❌ %s\033[0m\n" "$*" >&2; }
trap 'err "Échec à la ligne $LINENO (cmd: ${BASH_COMMAND:-?})"' ERR

need(){ command -v "$1" >/dev/null 2>&1 || { err "Commande requise introuvable: $1"; exit 1; }; }

confirm() {
  # usage: confirm "message" -> 0 si yes
  local prompt="${1:-Confirmer ?} [y/N] "
  read -r -p "$prompt" ans || true
  case "$ans" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  -t, --token TOKEN     Passer HCLOUD_TOKEN via paramètre (au lieu d'un export externe)
  -n, --name NAME       Nom du serveur (défaut: $NAME)
  --type TYPE           Type Hetzner (défaut: $TYPE)
  --location LOC        Localisation Hetzner (défaut: $LOCATION)
  --image IMAGE         Image (défaut: $IMAGE)
  --ssh-key-id ID       ID de la clé SSH Hetzner à injecter (obligatoire si pas déjà exporté)
  --key-path PATH       Chemin clé privée locale pour SSH (défaut: $KEY_PATH)
  -h, --help            Afficher cette aide

Exemples:
  $(basename "$0") -t "\$HCLOUD_TOKEN" --ssh-key-id 102768386
  NAME=master2 $(basename "$0") --ssh-key-id 102768386
EOF
}

# -------- Args parsing --------
if [[ $# -gt 0 ]]; then
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -t|--token) export HCLOUD_TOKEN="${2:?}"; shift 2 ;;
      -n|--name)  NAME="${2:?}"; shift 2 ;;
      --type)     TYPE="${2:?}"; shift 2 ;;
      --location) LOCATION="${2:?}"; shift 2 ;;
      --image)    IMAGE="${2:?}"; shift 2 ;;
      --ssh-key-id) SSH_KEY_ID="${2:?}"; shift 2 ;;
      --key-path) KEY_PATH="${2:?}"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) err "Option inconnue: $1"; usage; exit 2 ;;
    esac
  done
fi

need hcloud
need jq
need ssh-keygen
need awk

# -------- Contexte Hetzner --------
if ! hcloud context active >/dev/null 2>&1; then
  [[ -n "${HCLOUD_TOKEN:-}" ]] || { err "Aucun contexte hcloud actif et HCLOUD_TOKEN non défini. Fournis -t TOKEN ou exporte HCLOUD_TOKEN."; exit 1; }
  log "Création du contexte '$CONTEXT' avec HCLOUD_TOKEN (non-interactif)"
  echo y | hcloud context create "$CONTEXT" >/dev/null 2>&1 || true
  hcloud context use "$CONTEXT"
fi
ok "Contexte actif: $(hcloud context active)"

# -------- Préchecks clés --------
if [[ -z "$SSH_KEY_ID" ]]; then
  err "SSH_KEY_ID requis (ex: --ssh-key-id 102768386 ou export SSH_KEY_ID=...)"
  exit 1
fi
if [[ ! -f "$KEY_PATH" ]]; then
  err "Clé privée locale introuvable: $KEY_PATH (ajuste --key-path ou crée la clé)"
  exit 1
fi

# -------- Existe déjà ? --------
EXISTS=0
if hcloud server describe "$NAME" >/dev/null 2>&1; then
  EXISTS=1
fi

if (( EXISTS )); then
  log "Le serveur '$NAME' existe déjà."
  if confirm "Souhaites-tu le supprimer et le recréer ?"; then
    log "Suppression de '$NAME'…"
    hcloud server delete "$NAME"
    ok "Serveur supprimé."
  else
    log "Réutilisation de '$NAME' existant (pas de recréation)."
  fi
fi

# -------- Création si nécessaire --------
if ! hcloud server describe "$NAME" >/dev/null 2>&1; then
  log "Création de la VM $NAME (type=$TYPE, image=$IMAGE, location=$LOCATION) avec clé SSH ID=$SSH_KEY_ID"
  # On ne parse pas la sortie texte: on décrit après pour récupérer l'IP proprement
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

# -------- Récupération IP --------
# Petite attente pour être sûr que l'IP est publiée
sleep 2
IP="$(hcloud server describe "$NAME" -o json | jq -r '.public_net.ipv4.ip')"
[[ -n "$IP" && "$IP" != "null" ]] || { err "Impossible de récupérer l'IP publique pour $NAME"; exit 1; }
ok "IP publique: $IP"

# -------- known_hosts cleanup --------
log "Nettoyage known_hosts pour $IP"
ssh-keygen -R "$IP" >/dev/null 2>&1 || true

# -------- Inventaire Ansible --------
log "Mise à jour de l’inventaire $INV_FILE"
if [[ -f "$INV_FILE" ]]; then
  # supprime les anciennes lignes du serveur
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

echo "👉 Test SSH : ssh -i $KEY_PATH root@$IP"
