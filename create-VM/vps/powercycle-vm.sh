#!/usr/bin/env bash
set -euo pipefail

NAME="master1"
DRY_RUN="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) NAME="$2"; shift 2 ;;
    --dry-run) DRY_RUN="true"; shift 1 ;;
    *) echo "Arg inconnu: $1"; exit 1 ;;
  esac
done

# Vérification que hcloud CLI est installé
command -v hcloud >/dev/null || { echo "❌ hcloud CLI manquant"; exit 1; }

if [[ "$DRY_RUN" == "true" ]]; then
  echo "[DRY-RUN] hcloud server poweroff $NAME && hcloud server poweron $NAME"
  exit 0
fi

echo "⏳ Extinction de la VM $NAME..."
hcloud server poweroff "$NAME"

# Attente que la VM soit bien stoppée
while [[ "$(hcloud server describe "$NAME" -o json | jq -r .status)" != "off" ]]; do
  echo "⏳ En attente arrêt complet..."
  sleep 3
done
echo "✅ VM $NAME éteinte."

echo "⏳ Redémarrage de la VM $NAME..."
hcloud server poweron "$NAME"

# Attente que la VM soit bien en ligne
while [[ "$(hcloud server describe "$NAME" -o json | jq -r .status)" != "running" ]]; do
  echo "⏳ En attente démarrage complet..."
  sleep 3
done
echo "✅ VM $NAME redémarrée."

IP="$(hcloud server describe "$NAME" -o json | jq -r '.public_net.ipv4.ip')"
echo "ℹ️  IP publique: $IP"
