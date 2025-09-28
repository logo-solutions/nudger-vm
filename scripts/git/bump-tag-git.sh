#!/usr/bin/env bash
set -euo pipefail

remote="${REMOTE:-origin}"

# Récupère uniquement les tags semver (ignore v202... etc.)
last_tag="$(git tag --list 'v[0-9]*.[0-9]*.[0-9]*' | sort -V | tail -n1)"

if [[ -z "$last_tag" ]]; then
  last_tag="v0.0.0"
fi

version="${last_tag#v}"

# Initialisation safe
major=0; minor=0; patch=0
if [[ "$version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  major="${BASH_REMATCH[1]}"
  minor="${BASH_REMATCH[2]}"
  patch="${BASH_REMATCH[3]}"
fi

# Message du dernier commit
last_commit_msg="$(git log -1 --pretty=%B)"

# Détermine le bump
if [[ "$last_commit_msg" =~ BREAKING ]]; then
  major=$((major + 1)); minor=0; patch=0
elif [[ "$last_commit_msg" =~ ^feat ]]; then
  minor=$((minor + 1)); patch=0
else
  patch=$((patch + 1))
fi

new_tag="v${major}.${minor}.${patch}"

# Création et push
git tag -a "$new_tag" -m "Release $new_tag"
git push "$remote" "$new_tag"

echo "✅ Nouveau tag semver : $new_tag"
