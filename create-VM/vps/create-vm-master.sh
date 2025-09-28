#!/usr/bin/env bash
set -euo pipefail

NAME="master1"
TYPE="${TYPE:-cpx21}"
LOCATION="${LOCATION:-nbg1}"
IMAGE="${IMAGE:-ubuntu-22.04}"
SSH_KEY_ID="${SSH_KEY_ID:?❌ SSH_KEY_ID requis (export SSH_KEY_ID=xxxx)}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INV_FILE="$SCRIPT_DIR/../../infra/k8s_ansible/inventory.ini"
KEY_PATH="/root/.ssh/bastion-vm-key-hetzner"

echo "👉 Création de la VM $NAME avec clé SSH '$SSH_KEY_ID' ..."
OUTPUT="$(hcloud server create \
  --name "$NAME" \
  --image "$IMAGE" \
  --type "$TYPE" \
  --ssh-key "$SSH_KEY_ID" \
  --location "$LOCATION")"

IP="$(echo "$OUTPUT" | awk '/IPv4:/ {print $2}')"
echo "✅ VM $NAME créée avec IP $IP"

# Nettoyage known_hosts
echo "👉 Suppression de l'ancienne clé SSH dans known_hosts pour $IP"
ssh-keygen -R "$IP" >/dev/null 2>&1 || true

# Mise à jour inventory.ini
if [[ -f "$INV_FILE" ]]; then
  echo "👉 Mise à jour de l’inventaire $INV_FILE"

  # Supprime les anciennes lignes du master1
  sed -i "/^$NAME /d" "$INV_FILE"

  # Si la section [k8s_masters] existe déjà → ajoute en dessous
  if grep -q "^\[k8s_masters\]" "$INV_FILE"; then
    awk -v name="$NAME" -v ip="$IP" -v key="$KEY_PATH" '
      BEGIN { added=0 }
      /^\[k8s_masters\]/ {
        print; 
        print name " ansible_host=" ip " ansible_user=root ansible_ssh_private_key_file=" key " ansible_python_interpreter=/usr/bin/python3";
        added=1; next
      }
      { print }
      END { if (!added) print "[k8s_masters]\n" name " ansible_host=" ip " ansible_user=root ansible_ssh_private_key_file=" key " ansible_python_interpreter=/usr/bin/python3" }
    ' "$INV_FILE" > "$INV_FILE.tmp" && mv "$INV_FILE.tmp" "$INV_FILE"
  else
    # Sinon ajoute la section complète en haut
    echo "[k8s_masters]" | cat - "$INV_FILE" > "$INV_FILE.tmp"
    mv "$INV_FILE.tmp" "$INV_FILE"
    echo "$NAME ansible_host=$IP ansible_user=root ansible_ssh_private_key_file=$KEY_PATH ansible_python_interpreter=/usr/bin/python3" >> "$INV_FILE"
  fi
else
  echo "⚠️ Inventaire $INV_FILE introuvable → création"
  cat > "$INV_FILE" <<EOF
[k8s_masters]
$NAME ansible_host=$IP ansible_user=root ansible_ssh_private_key_file=$KEY_PATH ansible_python_interpreter=/usr/bin/python3

[bastion]
bastion ansible_host=127.0.0.1 ansible_connection=local ansible_python_interpreter=/usr/bin/python3
EOF
fi

echo "👉 Test SSH possible : ssh -i $KEY_PATH root@$IP"
