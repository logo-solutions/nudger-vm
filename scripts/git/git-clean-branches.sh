#!/usr/bin/env bash
set -euo pipefail

git fetch -p

# fichiers temporaires
remote_tmp=$(mktemp)

# récupérer branches distantes en excluant main/master et HEAD
git branch -r --format="%(refname:short)" \
  | grep -v '^origin$' \
  | grep -v 'origin/HEAD' \
  | grep -vE 'origin/(main|master)' > "$remote_tmp"

branches_to_delete=$(cat "$remote_tmp")
rm -f "$remote_tmp"

if [[ -z "$branches_to_delete" ]]; then
  echo "✅ Aucune branche distante à supprimer."
  exit 0
fi

echo ""
echo "=== Branches distantes candidates à suppression ==="
echo "$branches_to_delete" | nl -w2 -s'. '

echo ""
read -rp "👉 Numéro(s) des branches à supprimer (séparés par un espace) ou 'all' pour tout : " NUMS

if [[ "$NUMS" == "all" ]]; then
  for branch in $branches_to_delete; do
    git push origin --delete "${branch#origin/}"
    echo "✅ Branche distante '$branch' supprimée."
  done
  echo "🎉 Nettoyage terminé."
  exit 0
fi

for NUM in $NUMS; do
  if ! [[ "$NUM" =~ ^[0-9]+$ ]]; then
    echo "⛔ '$NUM' n’est pas un numéro valide."
    continue
  fi
  branch=$(echo "$branches_to_delete" | sed -n "${NUM}p")
  if [[ -z "$branch" ]]; then
    echo "⛔ Numéro $NUM hors limites."
    continue
  fi
  git push origin --delete "${branch#origin/}"
  echo "✅ Branche distante '$branch' supprimée."
  git branch -D "${branch#origin/}" 2>/dev/null || true
echo "✅ Branche locale '${branch#origin/}' supprimée (si elle existait)."

done

echo "🎉 Nettoyage terminé."
