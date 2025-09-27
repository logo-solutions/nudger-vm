#!/usr/bin/env bash
set -euo pipefail

branch=$(git rev-parse --abbrev-ref HEAD)

# Interdit commit direct sur main/master
if [[ "$branch" == "main" || "$branch" == "master" ]]; then
  echo "❌ Tu es sur '$branch'. Crée une feature branch avant de commit."
  exit 1
fi

# Vérifie s'il y a des modifs à commit
if ! git diff --quiet || ! git diff --cached --quiet || [ -n "$(git ls-files --others --exclude-standard)" ]; then
  echo "📌 Modifs détectées :"
  git status -s
else
  echo "✅ Rien à commit"
  exit 0
fi

# Vérifie le message
if [ $# -eq 0 ]; then
  echo "❌ Fournis un message de commit (ex: feat: ajoute script gcp)"
  exit 1
fi

msg="$*"

# Vérifie la convention (feat|fix|chore|docs|refactor|test|perf)
if ! [[ "$msg" =~ ^(BREAKING|feat|fix|chore|docs|refactor|test|perf)(\([a-z0-9_-]+\))?:\ .+ ]]; then
  echo "❌ Message invalide. Utilise la convention :"
  echo "   feat: ajout d'une nouvelle fonctionnalité"
  echo "   fix: correction d'un bug"
  echo "   chore: tâches diverses"
  echo "   docs: documentation"
  echo "   refactor: refactorisation du code"
  echo "   test: ajout/modif de tests"
  echo "   perf: optimisation de performance"
  exit 1
fi

# Commit et push
echo "➡️ Commit sur '$branch' avec : \"$msg\""
git add -A
git commit -m "$msg" -n
git push -u origin "$branch"
