# ── Defaults ──────────────────────────────────────────────────────────────
NAME="${NAME:-master1}"
TYPE="${TYPE:-cpx21}"
LOCATION="${LOCATION:-nbg1}"
IMAGE="${IMAGE:-ubuntu-22.04}"
CONTEXT="${CONTEXT:-nudger}"

# Clé SSH Durable (remplace id_vm_ed25519)
SSH_KEY_ID="${SSH_KEY_ID:-}"
KEY_NAME="${KEY_NAME:-hetzner-bastion}"
KEY_PATH="${KEY_PATH:-/root/.ssh/hetzner-bastion}"
KEY_PUB="${KEY_PUB:-${KEY_PATH}.pub}"
CLOUD_INIT="${CLOUD_INIT:-}"

# … (le reste inchangé jusqu’aux prechecks)

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

# … (création VM inchangée)

# Inventaire Ansible  (écrit la clé durable)
log "Mise à jour inventaire: $INV_FILE"
# ── Inventory (mode simple : on réécrit proprement) ──
INV_FILE="$SCRIPT_DIR/../../infra/k8s_ansible/inventory.ini"
install -d "$(dirname "$INV_FILE")"

# Si tu veux garder l'IP du bastion existant (au lieu de tout perdre),
# on tente de la relire AVANT d’écraser le fichier.
BASTION_LINE=""
if [[ -f "$INV_FILE" ]]; then
  BASTION_LINE="$(awk '
    $0 ~ /^\[bastion\]/ { inb=1; next }
    inb && NF && $1 !~ /^\[/ { print; exit }
  ' "$INV_FILE")"
fi

# Si on a trouvé une ligne bastion déjà valable, on la réutilise,
# sinon on met un placeholder pour ne rien bloquer.
if [[ -z "$BASTION_LINE" ]]; then
  BASTION_LINE="bastion ansible_host=CHANGE_ME ansible_user=root ansible_ssh_private_key_file=$KEY_PATH ansible_python_interpreter=/usr/bin/python3"
fi

cat > "$INV_FILE" <<EOF
# =========================
# INVENTORY.ANSIBLE
# =========================

[k8s_masters]
$NAME ansible_host=$IP ansible_user=root ansible_ssh_private_key_file=$KEY_PATH ansible_python_interpreter=/usr/bin/python3

# groupe logique pour faciliter les playbooks
[master:children]
k8s_masters

[bastion]
$BASTION_LINE
EOF

ok "Inventaire mis à jour"
