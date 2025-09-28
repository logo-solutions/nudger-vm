#!/usr/bin/env bash
set -euo pipefail

remote="${REMOTE:-origin}"

# Récupère le dernier tag existant (sémantique), ou v0.0.0 par défaut
last_tag=$(git tag --sort=-v:refname | head -n1 || true)
[ -z "$last_tag" ] && last_tag="v0.0.0"
version=${last_tag#v}
IFS='.' read -r major minor patch <<< "$version"

# Message du dernier commit
last_commit_msg=$(git log -1 --pretty=%B)

# Détermine l’incrément
if [[ $last_commit_msg =~ BREAKING ]]; then
  major=$((major + 1)); minor=0; patch=0
elif [[ $last_commit_msg =~ ^feat ]]; then
  minor=$((minor + 1)); patch=0
else
  patch=$((patch + 1))
fi

new_tag="v${major}.${minor}.${patch}"

# Vérifie si le tag existe déjà (local ou distant)
if git rev-parse "$new_tag" >/dev/null 2>&1 || git ls-remote --tags "$remote" | grep -q "refs/tags/$new_tag"; then
  echo "⚠️ Le tag $new_tag existe déjà → aucun nouveau tag créé."
  exit 0
fi

# Création et push
git tag -a "$new_tag" -m "Release $new_tag"
git push "$remote" "$new_tag"

echo "✅ Nouveau tag semver : $new_tag"
