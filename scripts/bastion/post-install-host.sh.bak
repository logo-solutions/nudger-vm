#!/usr/bin/env bash
set -euo pipefail

# --- Config ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INVENTORY="${INVENTORY:-$REPO_ROOT/infra/k8s_ansible/inventory.ini}"

# Paramètres optionnels
#   GITHUB_APP_KEY_PATH : chemin de la clé privée GitHub App à copier
#   BASTION_HOST/USER/KEY : forcer manuellement (sinon auto depuis inventory)
GITHUB_APP_KEY_PATH="${GITHUB_APP_KEY_PATH:-${1:-}}"

# --- Helpers ---
die(){ echo "❌ $*" >&2; exit 1; }
info(){ echo "👉 $*"; }
ok(){ echo "✅ $*"; }

[[ -f "$INVENTORY" ]] || die "Inventory introuvable: $INVENTORY"

# --- Lire la ligne 'bastion' depuis [bastion] dans l'inventory ---
# Exemple attendu :
# [bastion]
# bastion ansible_host=157.180.42.146 ansible_user=root ansible_ssh_private_key_file=/Users/loicgourmelon/.ssh/hetzner-bastion ansible_python_interpreter=/usr/bin/python3
BASTION_LINE="$(awk '
  $0 ~ /^\[bastion\]/ { inb=1; next }
  inb && NF && $1 !~ /^\[/ { print; exit }
' "$INVENTORY")"

[[ -n "${BASTION_LINE:-}" ]] || die "Entrée [bastion] introuvable ou vide dans $INVENTORY"

# Extraire paramètres avec fallback
get_kv(){ echo "$BASTION_LINE" | tr ' ' '\n' | awk -F= -v k="$1" '$1==k{print $2; found=1} END{exit !found}'; }
BASTION_HOST="${BASTION_HOST:-$(get_kv ansible_host 2>/dev/null || true)}"
BASTION_USER="${BASTION_USER:-$(get_kv ansible_user 2>/dev/null || echo root)}"
BASTION_KEY="${BASTION_KEY:-$(get_kv ansible_ssh_private_key_file 2>/dev/null || echo "$HOME/.ssh/hetzner-bastion")}"

[[ -n "$BASTION_HOST" ]] || die "ansible_host absent dans l’inventory [bastion]"
[[ -f "$BASTION_KEY" ]] || die "Clé privée absente: $BASTION_KEY"

SSH_OPTS=(-o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$BASTION_KEY")

info "Préparation côté hôte pour ${BASTION_USER}@${BASTION_HOST}"
# Éviter le warning “host key changed” en cas de recréations fréquentes
ssh-keygen -R "$BASTION_HOST" >/dev/null 2>&1 || true

# 1) Créer le répertoire sécurisé
ssh "${SSH_OPTS[@]}" "${BASTION_USER}@${BASTION_HOST}" 'sudo mkdir -p /etc/github-app && sudo chmod 700 /etc/github-app'

# 2) Copier la clé privée GitHub App si fournie
if [[ -n "${GITHUB_APP_KEY_PATH}" ]]; then
  [[ -f "$GITHUB_APP_KEY_PATH" ]] || die "Fichier clé GitHub App introuvable: $GITHUB_APP_KEY_PATH"
  scp "${SSH_OPTS[@]}" "$GITHUB_APP_KEY_PATH" "${BASTION_USER}@${BASTION_HOST}:/tmp/nudger-vm.private-key.pem"
  ssh "${SSH_OPTS[@]}" "${BASTION_USER}@${BASTION_HOST}" 'sudo mv /tmp/nudger-vm.private-key.pem /etc/github-app/nudger-vm.private-key.pem && sudo chown root:root /etc/github-app/nudger-vm.private-key.pem && sudo chmod 600 /etc/github-app/nudger-vm.private-key.pem'
  ok "Clé GitHub App déployée dans /etc/github-app/nudger-vm.private-key.pem"
else
  info "Aucune clé GitHub App fournie (paramètre GITHUB_APP_KEY_PATH). Skipping copy."
fi

ok "Bastion prêt. Connexion :"
echo "ssh ${SSH_OPTS[*]} ${BASTION_USER}@${BASTION_HOST}"
