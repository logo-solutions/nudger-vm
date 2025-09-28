#!/usr/bin/env bash
set -euo pipefail

# git-new-feature.sh — crée une branche feature et éventuellement une PR
# Usage: ./git-new-feature.sh <feature_name> <type> [--pr=draft|open|never]
# Exemple: ./git-new-feature.sh xwiki feat --pr=draft

feature="${1:?feature manquant}"
type="${2:?type manquant (feat|fix|chore|...)}"
pr_mode="${3:---pr=draft}"
pr_mode="${pr_mode#--pr=}"  # draft|open|never

today=$(date +%Y%m%d)
branch_name="${type}/${today}-${feature}"
base_branch="${BASE_BRANCH:-main}"
remote="${REMOTE:-origin}"
default_remote_url="git@github.com:logo-solutions/nudger-vm.git"

# Sanity: corrige le remote si nécessaire
if ! git remote get-url "$remote" >/dev/null 2>&1; then
  echo "⚠️ Remote '$remote' absent, création avec $default_remote_url"
  git remote add "$remote" "$default_remote_url"
fi

# Sanity: gh CLI ?
if ! command -v gh >/dev/null 2>&1; then
  echo "⚠️  gh non trouvé. PR skip forcé (--pr=never)" >&2
  pr_mode="never"
fi

# Mise à jour base
echo "🔄 Mise à jour de $base_branch..."
git fetch "$remote" "$base_branch"
git checkout "$base_branch"
git pull --ff-only "$remote" "$base_branch"

# Création branche (idempotent)
echo "🌱 Création de la branche '$branch_name'..."
git checkout -B "$branch_name"

# Commit vide si rien (optionnel)
if [ -z "$(git diff --staged --name-only)" ] && [ -z "$(git diff --name-only)" ]; then
  echo "ℹ️ Aucun changement pour l'instant."
fi

# Push
git push -u "$remote" "$branch_name"

# PR logic
case "$pr_mode" in
  never) echo "🛑 PR non créée (--pr=never)"; exit 0 ;;
  draft|open)
    if ! gh auth status >/dev/null 2>&1; then
      echo "⚠️  gh non authentifié → PR skip"; exit 0
    fi
    # Skip si PR existe déjà
    if gh pr view "$branch_name" --head "$branch_name" >/dev/null 2>&1; then
      echo "ℹ️  PR existe déjà pour $branch_name."; exit 0
    fi
    title="$branch_name"
    body="Branche créée automatiquement le $today pour *$feature*"
    range_commits=$(git rev-list "$remote/$base_branch"..HEAD || true)
    extra_args=()
    [ "$pr_mode" = "draft" ] && extra_args+=(--draft)
    echo "🚀 Création de la Pull Request ($pr_mode)…"
    gh pr create \
      --base "$base_branch" \
      --head "$branch_name" \
      --title "$title" \
      --body "$body" \
      "${extra_args[@]}"
    ;;
  *) echo "❌ --pr doit être draft|open|never"; exit 2 ;;
esac

echo "✅ Branche '$branch_name' poussée et PR ($pr_mode) créée si applicable."
