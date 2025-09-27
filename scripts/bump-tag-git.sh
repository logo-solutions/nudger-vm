#!/bin/bash
set -e

# Récupère le dernier tag, ou v0.0.0 s'il n'y en a pas
last_tag=$(git tag --sort=-v:refname | head -n 1)
[ -z "$last_tag" ] && last_tag="v0.0.0"
version=${last_tag#v}
IFS='.' read -r major minor patch <<< "$version"

# Récupère le dernier message de commit
last_commit_msg=$(git log -1 --pretty=%B)

# Détermine quel numéro incrémenter
if [[ $last_commit_msg =~ BREAKING ]]; then
  major=$((major + 1))
  minor=0
  patch=0
elif [[ $last_commit_msg =~ ^feat ]]; then
  minor=$((minor + 1))
  patch=0
else
  patch=$((patch + 1))
fi

# Nouvelle version
new_tag="v${major}.${minor}.${patch}"

# Création et push du tag
git tag -a "$new_tag" -m "Release $new_tag"
git push origin "$new_tag"

echo "✅ Tag $new_tag créé et poussé automatiquement !"
