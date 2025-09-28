#!/usr/bin/env bash
set -euo pipefail

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
REMOTE="${REMOTE:-origin}"
BASE_BRANCH="${BASE_BRANCH:-main}"

if [ "$CURRENT_BRANCH" = "$BASE_BRANCH" ]; then
  echo "❌ Déjà sur $BASE_BRANCH, rien à merger."
  exit 1
fi

echo "➡️ Fusion de $CURRENT_BRANCH dans $BASE_BRANCH ..."

# Sanity check : sync remote
git fetch "$REMOTE" "$BASE_BRANCH" "$CURRENT_BRANCH"

# Basculer sur base et update
git checkout "$BASE_BRANCH"
git pull --ff-only "$REMOTE" "$BASE_BRANCH"

# Merge
git merge --no-ff "$CURRENT_BRANCH" -m "merge branch '$CURRENT_BRANCH' into $BASE_BRANCH"

# Push
if git push "$REMOTE" "$BASE_BRANCH"; then
  echo "✅ Push réussi."
  git branch -d "$CURRENT_BRANCH"
else
  echo "⛔ Push échoué, branche locale conservée."
  exit 1
fi
