#!/usr/bin/env bash
set -euo pipefail
CLOUD_USER="${CLOUD_USER:-root}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUT_DIR="$ROOT_DIR/out"; mkdir -p "$OUT_DIR"

NAME="master1"; TYPE="cpx21"; LOCATION="nbg1"; IMAGE="ubuntu-22.04"
SSH_KEY="id_vm_ed25519"; ENABLE_IPV6="false"; DRY_RUN="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) NAME="$2"; shift 2 ;;
    --type) TYPE="$2"; shift 2 ;;
    --location) LOCATION="$2"; shift 2 ;;
    --image) IMAGE="$2"; shift 2 ;;
    --ssh-key) SSH_KEY="$2"; shift 2 ;;
    --enable-ipv6) ENABLE_IPV6="$2"; shift 2 ;;
    --dry-run) DRY_RUN="true"; shift 1 ;;
    *) echo "Arg inconnu: $1"; exit 1 ;;
  esac
done

# Prérequis uniques (dé-dup)
for cmd in hcloud envsubst nc ssh ssh-keygen awk tee base64; do
  command -v "$cmd" >/dev/null || { echo "❌ $cmd manquant"; exit 1; }
done
[[ -f "$HOME/.ssh/$SSH_KEY" ]] || { echo "❌ ~/.ssh/$SSH_KEY manquant"; exit 1; }
[[ -f "$HOME/.ssh/${SSH_KEY}.pub" ]] || { echo "❌ ~/.ssh/${SSH_KEY}.pub manquant"; exit 1; }

# Génère une paire HOST unique (local) et l’injecte au boot -> on peut pinner
HOST_PRIV="$OUT_DIR/ssh_host_ed25519_${NAME}"
HOST_PUB="${HOST_PRIV}.pub"
if [[ ! -f "$HOST_PRIV" ]]; then
  ssh-keygen -t ed25519 -N '' -f "$HOST_PRIV" >/dev/null
fi
HOST_PRIV_B64="$(base64 < "$HOST_PRIV" | tr -d '\n')"
HOST_PUB_STR="$(cat "$HOST_PUB")"
ID_SSH_PUB="$(cat "$HOME/.ssh/${SSH_KEY}.pub")"

export CLOUD_USER HOST_PRIV_B64 HOST_PUB_STR ID_SSH_PUB
echo "export $CLOUD_USER $HOST_PRIV_B64 $HOST_PUB_STR $ID_SSH_PUB"

echo "envsubst < $SCRIPT_DIR/newcloud-init-template.yaml > $SCRIPT_DIR/cloud-init.yaml"
envsubst < "$SCRIPT_DIR/newcloud-init-template.yaml" > "$SCRIPT_DIR/cloud-init.yaml"

# Prépare la commande hcloud (IPv6 optionnel si supporté)
HCMD=(hcloud server create --name "$NAME" --type "$TYPE" --image "$IMAGE" --location "$LOCATION" --user-data-from-file "$SCRIPT_DIR/cloud-init.yaml")
if [[ "$ENABLE_IPV6" == "true" ]]; then
  HCMD+=(--enable-ipv6)
fi

if [[ "$DRY_RUN" == "true" ]]; then
  echo "[DRY-RUN] ${HCMD[*]}"
  echo "0.0.0.0"
  exit 0
fi

OUT="$("${HCMD[@]}")"
echo "$OUT" | tee "$OUT_DIR/hcloud-create-$NAME.txt"

IP="$(echo "$OUT" | awk '/IPv4:/ {print $2}')"
[[ -n "$IP" ]] || { echo "❌ IP introuvable"; exit 1; }
echo "✅ VM IP: $IP"

# Attente SSH
ssh-keygen -R "$IP" >/dev/null 2>&1 || true
echo "⏳ Attente SSH $IP:22..."
while ! nc -z -w2 "$IP" 22; do sleep 2; done
echo "✅ SSH up"

# Pin known_hosts **avec la clé PUB que NOUS avons générée**
KN="$OUT_DIR/known_hosts"
echo "[$IP]:22 $HOST_PUB_STR" >> "$KN"
echo "✅ known_hosts écrit: $KN"
echo "$IP"
KN="$OUT_DIR/known_hosts"
printf '[%s]:22 %s\n' "$IP" "$HOST_PUB_STR" >> "$KN"
echo "✅ known_hosts écrit: $KN"

echo "⏳ Attente SSH prêt (auth clé) sur $IP ..."
