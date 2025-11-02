#!/usr/bin/env bash
set -euo pipefail

# Vérifier si le token est défini
if [ -z "${TOKEN:-}" ]; then
  echo "🛑 Aucune variable TOKEN définie. Vérifie si tu as exporté ton PAT."
  echo "   Si tu n'as pas de PAT, connecte-toi via Bitwarden avec la commande :"
  echo "   bw login"
  echo "   export TOKEN=\$(bw get item \"github-token-v2\" | jq -r '.login.username')"
  echo "   echo \"\$TOKEN\"  | gh auth login --with-token"
  exit 1
fi

# Paramètres d'entrée simplifiés
feature="${1:?feature manquant}"
type="${2:?type manquant (feat|fix|chore|...)}"

# --- Sécurité: vérifier qu'on est bien dans un repo git
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "❌ Pas dans un dépôt git"; exit 1;
}

# --- Déterminer la branche par défaut (main)
base_branch="main"

today=$(date +%Y%m%d)
branch_name="${type}/${today}-${feature}"

echo "🔄 Mise à jour de $base_branch depuis origin..."
git fetch origin "$base_branch"
git checkout "$base_branch"
git pull --ff-only origin "$base_branch"

echo "🌱 Création de la branche '$branch_name'..."
git checkout -B "$branch_name"

# Push systématique
git push -u origin "$branch_name"

echo "✅ Branche '$branch_name' poussée sur 'origin'."
