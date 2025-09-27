#!/usr/bin/env bash
set -euo pipefail

# Inventaire + hôte
INV_FILE="${INV_FILE:-/Users/loicgourmelon/Devops/nudger/infra/k8s_ansible/inventory.ini}"
HOST="${1:-master1}"

# Sanity checks
if [[ ! -f "$INV_FILE" ]]; then
  echo "Inventory introuvable: $INV_FILE" >&2
  exit 1
fi

# Récupère ansible_host / ansible_user / ansible_ssh_private_key_file pour l'hôte
# - ignore commentaires & lignes vides
# - match sur 1ère colonne == HOST
# - gère a=b, retire quotes éventuelles
read -r ip user key <<EOF
$(awk -v h="$HOST" '
  /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
  $1 == h {
    for (i=2;i<=NF;i++) {
      n=split($i,a,"=")
      if (n==2) {
        # retire quotes "..." ou '\''...'\'' en bord
        gsub(/^"/,"",a[2]); gsub(/"$/,"",a[2]);
        gsub(/^'\''/,"",a[2]); gsub(/'\''$/,"",a[2]);
        if (a[1]=="ansible_host") host=a[2];
        else if (a[1]=="ansible_user") user=a[2];
        else if (a[1]=="ansible_ssh_private_key_file" || a[1]=="ansible_private_key_file") key=a[2];
      }
    }
    # valeurs par défaut côté awk si non trouvées
    if (user=="") user="root";
    print host "\t" user "\t" key;
    exit
  }
' "$INV_FILE")
EOF

# Vérifs
if [[ -z "${ip:-}" ]]; then
  echo "Hôte '$HOST' introuvable dans $INV_FILE ou ansible_host manquant." >&2
  exit 1
fi
user="${user:-root}"
key="${key:-}"

# Expand ~ au début du chemin de clé si présent (sans eval)
case "$key" in
  "~/"*) key="${HOME}${key#\~}";;
esac

# Args SSH
ssh_args=(-o StrictHostKeyChecking=accept-new)
[[ -n "$key" ]] && ssh_args+=(-i "$key")

echo "→ SSH vers ${user}@${ip} ${key:+(clé: $key)}"
remote_profile="~/nudger/config-vm/profile_logo.sh"

# On ouvre un bash interactif, en sourçant le profil s’il existe
# # Force l'allocation d'un TTY (-tt) et ouvre UN seul bash interactif
ssh_args+=(-t -t)

exec ssh "${ssh_args[@]}" "${user}@${ip}" \
  '[[ -f ~/nudger/config-vm/profile_logo.sh ]] && source ~/nudger/config-vm/profile_logo.sh&& cd nudger; exec bash -i'
