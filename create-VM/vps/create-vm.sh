#!/usr/bin/env bash
set -euo pipefail
DIRHOME=/Users/loicgourmelon/devops/nudger
SSH_OPTS="-o StrictHostKeyChecking=accept-new"

# --- PRÉREQUIS ---
# --- Vérification des prérequis ---
command -v hcloud >/dev/null 2>&1 || { echo "❌ hcloud CLI manquant. Installe-le avant de continuer."; exit 1; }
command -v envsubst >/dev/null 2>&1 || { echo "❌ envsubst manquant (paquet gettext)."; exit 1; }
command -v nc >/dev/null 2>&1 || { echo "❌ nc (netcat) manquant."; exit 1; }
command -v ssh >/dev/null 2>&1 || { echo "❌ ssh manquant."; exit 1; }
command -v ssh-keygen >/dev/null 2>&1 || { echo "❌ ssh-keygen manquant."; exit 1; }

# Vérification du fichier template
[[ -f $DIRHOME/create-VM/vps/cloud-init-template.yaml ]] || { echo "❌ $DIR/cloud-init-template.yaml manquant."; exit 1; }

# Vérification de la clé privée SSH
[[ -f ~/.ssh/id_vm_ed25519 ]] || { echo "❌ Clé privée SSH ~/.ssh/id_vm_ed25519 manquante."; exit 1; }

echo "✅ Tous les prérequis sont présents, le script peut démarrer..."


# ========== Réglages ==========
SSH_OPTS="-o StrictHostKeyChecking=accept-new"
ID_SSH="id_vm_ed25519"     # clé POUR SE CONNECTER À LA VM (locale)
BRANCH="main"

# Repo root (calc depuis ce script: create-VM/vps/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIRHOME="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ========== Prérequis ==========
for cmd in hcloud envsubst nc ssh ssh-keygen scp git awk tee; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "❌ $cmd manquant."; exit 1; }
done
[[ -f "$DIRHOME/create-VM/vps/cloud-init-template.yaml" ]] || { echo "❌ cloud-init-template.yaml manquant."; exit 1; }
[[ -f "$HOME/.ssh/${ID_SSH}" ]] || { echo "❌ Clé privée VM ~/.ssh/${ID_SSH} manquante."; exit 1; }
echo "✅ Tous les prérequis sont présents, le script peut démarrer..."


echo "✅ Tous les prérequis sont présents"

# --- ARGUMENTS ---
if [[ $# -ne 3 ]]; then
    echo "Usage: $0 <VM_NAME> <USER> <DEPOT_GIT>"
    exit 1
fi

NAME="$1"
USER="$2"
DEPOT_GIT="$3"
BRANCH="main"
ID_SSH_PUB="$(cat "$HOME/.ssh/${ID_SSH}.pub")"
REPO_NAME=$(basename "$DEPOT_GIT" .git)

#========= Cloud-init ==========
echo "➡️ Génération du cloud-init.yaml pour $USER et $DEPOT_GIT"
export USER DEPOT_GIT ID_SSH_PUB
envsubst < "$DIRHOME/create-VM/vps/cloud-init-template.yaml" > "$DIRHOME/create-VM/vps/cloud-init.yaml"
echo "✅ cloud-init.yaml généré"

# ========== (Re)création serveur ==========
if hcloud server describe "$NAME" >/dev/null 2>&1; then
  echo "Suppression du serveur $NAME existant..."
  hcloud server delete "$NAME"
fi

echo "➡️ Création de la VM $NAME..."
OUTPUT="$(hcloud server create \
  --name "$NAME" \
  --image ubuntu-22.04 \
  --type cpx21 \
  --user-data-from-file "$DIRHOME/create-VM/vps/cloud-init.yaml" \
  --ssh-key loic-vm-key)"
echo "$OUTPUT"

VM_IP="$(echo "$OUTPUT" | awk '/IPv4:/ {print $2}')"
[[ -n "$VM_IP" ]] || { echo "❌ Impossible de récupérer l'adresse IPv4"; exit 1; }
echo "✅ VM IP: $VM_IP"

# ========== Attente SSH ==========
ssh-keygen -R "$VM_IP" >/dev/null 2>&1 || true
echo "⏳ Attente de SSH..."
while ! nc -z -w2 "$VM_IP" 22; do sleep 2; done
echo "✅ SSH up"

# ========== Distant: HOME et ~/.ssh ==========
if [[ "$USER" == "root" ]]; then
  REMOTE_HOME="/root"
else
  REMOTE_HOME="/home/$USER"
fi

ssh -i "$HOME/.ssh/${ID_SSH}" $SSH_OPTS "$USER@$VM_IP" \
  "install -d -m 700 -o $USER -g $USER '$REMOTE_HOME/.ssh' && \
   ssh-keyscan github.com >> '$REMOTE_HOME/.ssh/known_hosts' && \
   chown $USER:$USER '$REMOTE_HOME/.ssh/known_hosts' && \
   chmod 644 '$REMOTE_HOME/.ssh/known_hosts' && \
   git config --global user.name 'loicgourmelon' && \
   git config --global user.email 'loicgourmelon@gmail.com'"

# ========== Clone via AGENT FORWARDING (aucune clé copiée) ==========
# ⚠️ Assure-toi d’avoir chargé ta clé GitHub en local :
#     ssh-add ~/.ssh/id_deploy_ed25519
ssh -A -i "$HOME/.ssh/${ID_SSH}" $SSH_OPTS "$USER@$VM_IP" bash <<'EOF'
set -euo pipefail
cd "$HOME"
rm -rf nudger || true
git clone --branch main --single-branch git@github.com:loicgo29/nudger.git nudger
chown -R "$USER":"$USER" nudger || true
EOF
echo "✅ Déploiement Git terminé sur $VM_IP"
echo "👉 Connexion: ssh -A -i ~/.ssh/${ID_SSH} $USER@$VM_IP"
