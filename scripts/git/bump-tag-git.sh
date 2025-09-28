#!/usr/bin/env bash
set -euo pipefail

remote="${REMOTE:-origin}"

# Filtrer uniquement les tags semver vX.Y.Z
last_tag=$(git tag --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -n1 || true)
[ -z "$last_tag" ] && last_tag="v0.0.0"

version=${last_tag#v}
IFS='.' read -r major minor patch <<< "$version"

# Dernier message de commit
last_commit_msg=$(git log -1 --pretty=%B)

# Incrémentation selon commit
if [[ $last_commit_msg =~ BREAKING ]]; then
  major=$((major + 1)); minor=0; patch=0
elif [[ $last_commit_msg =~ ^feat ]]; then
  minor=$((minor + 1)); patch=0
else
  patch=$((patch + 1))
fi

new_tag="v${major}.${minor}.${patch}"

# Vérifier si le tag existe déjà
if git rev-parse "$new_tag" >/dev/null 2>&1 2>/dev/null || git ls-remote --tags "$remote" | grep -q "refs/tags/$new_tag"; then
  echo "⚠️ Le tag $new_tag existe déjà → aucun nouveau tag créé."
  exit 0
fi

# Création + push
git tag -a "$new_tag" -m "Release $new_tag"
git push "$remote" "$new_tag"

echo "✅ Nouveau tag semver : $new_tag"
