#!/usr/bin/env bash
# scripts/bastion/post-install-host.sh
set -euo pipefail
set -o errtrace

# ----------------------------------------
# post-install-host.sh (version simplifiée)
# - Prépare le bastion fraîchement créé
# - Lit l'inventory pour récupérer IP/clé/user
# - Installe Bitwarden CLI sur le bastion si nécessaire via APT
# ----------------------------------------

# ----- Config -----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INVENTORY="${INVENTORY:-$REPO_ROOT/infra/k8s_ansible/inventory.ini}"

# ----- Helpers -----
die(){ echo "❌ $*" >&2; exit 1; }
info(){ echo "👉 $*"; }
ok(){ echo "✅ $*"; }

trap 'die "Échec à la ligne $LINENO (cmd: ${BASH_COMMAND:-?})"' ERR

# ----- Préchecks -----
info "Vérification des prérequis..."

# Vérifier l'existence de l'inventaire
[[ -f "$INVENTORY" ]] || die "Inventory introuvable: $INVENTORY"

# Vérifier que les commandes nécessaires sont présentes
for bin in ssh scp awk ssh-keygen bw; do
  command -v "$bin" >/dev/null 2>&1 || die "Commande requise introuvable: $bin"
done
ok "Tous les prérequis sont installés."

# ----- Lire bastion dans inventory -----
# Extraction des informations du bastion depuis l'inventaire
BASTION_LINE="$(awk '
  $0 ~ /^\[bastion\]/ { inb=1; next }
  inb && NF && $1 !~ /^\[/ { print; exit }
' "$INVENTORY")"

[[ -n "${BASTION_LINE:-}" ]] || die "Entrée [bastion] introuvable ou vide dans $INVENTORY"
ok "Informations sur le bastion lues avec succès."

# Fonction pour récupérer les valeurs à partir de l'inventaire
get_kv(){ echo "$BASTION_LINE" | tr ' ' '\n' | awk -F= -v k="$1" '$1==k{print $2; found=1} END{exit !found}'; }

# Récupération des valeurs depuis l'inventaire
BASTION_HOST="${BASTION_HOST:-$(get_kv ansible_host 2>/dev/null || true)}"
BASTION_USER="${BASTION_USER:-$(get_kv ansible_user 2>/dev/null || echo root)}"
BASTION_KEY="${BASTION_KEY:-$(get_kv ansible_ssh_private_key_file 2>/dev/null || echo "$HOME/.ssh/hetzner-bastion")}"

# Vérification que les informations du bastion sont bien présentes
[[ -n "$BASTION_HOST" ]] || die "ansible_host absent dans [bastion]"
[[ -f "$BASTION_KEY" ]] || die "Clé privée absente: $BASTION_KEY"

# Configuration SSH
SSH_OPTS=(-o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$BASTION_KEY")

info "Préparation du bastion: ${BASTION_USER}@${BASTION_HOST}"

# ----- Test SSH -----
info "Test de connexion SSH..."
# Nettoyer la clé existante si elle existe dans le fichier known_hosts
ssh-keygen -R "$BASTION_HOST" >/dev/null 2>&1 || true
# Essayer de se connecter via SSH
ssh "${SSH_OPTS[@]}" "${BASTION_USER}@${BASTION_HOST}" 'echo "Connexion OK"'
ok "Connexion SSH fonctionnelle"
info "Copie des clés SSH sur le bastion..."
scp "${SSH_OPTS[@]}" "$HOME/.ssh/hetzner-bastion.pub" "${BASTION_USER}@${BASTION_HOST}:/root/.ssh/hetzner-bastion.pub"
scp "${SSH_OPTS[@]}" "$HOME/.ssh/hetzner-bastion" "${BASTION_USER}@${BASTION_HOST}:/root/.ssh/hetzner-bastion"
ssh "${SSH_OPTS[@]}" "${BASTION_USER}@${BASTION_HOST}" 'chmod 600 /root/.ssh/hetzner-bastion && chmod 644 /root/.ssh/hetzner-bastion.pub'
ok "Clés SSH copiées sur le bastion."

# ----- Fin -----
ok "Bastion prêt."
echo
info "Connexion SSH :"
echo "ssh ${SSH_OPTS[*]} ${BASTION_USER}@${BASTION_HOST}"
export GITHUB_TOKEN=$(bw get item "github-token-v2" | jq -r '.login.username')
echo "Commande à executer sur bastion"
echo "git clone https://$GITHUB_TOKEN@github.com/logo-solutions/nudger-vm"
