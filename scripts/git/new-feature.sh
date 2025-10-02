#!/usr/bin/env bash
set -euo pipefail

# git-new-feature.sh — crée une branche feature et éventuellement une PR
# Usage: ./git-new-feature.sh <feature_name> <type> [--pr=draft|open|never]
# Ex: ./git-new-feature.sh xwiki feat --pr=draft
# Vars optionnelles: REMOTE (default: origin), BASE_BRANCH (auto), GH_REPO=owner/name (fallback)

feature="${1:?feature manquant}"
type="${2:?type manquant (feat|fix|chore|...)}"
pr_mode="${3:---pr=draft}"
pr_mode="${pr_mode#--pr=}"  # draft|open|never

# --- Sécurité: vérifier qu'on est bien dans un repo git
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "❌ Pas dans un dépôt git"; exit 1;
}

remote="${REMOTE:-origin}"

# --- Détecter/valider l'URL du remote
remote_url="$(git remote get-url "$remote" 2>/dev/null || true)"

if [ -z "${remote_url}" ]; then
  # Pas de remote -> essayer via gh ou GH_REPO
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    owner_repo="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
  else
    owner_repo="${GH_REPO:-}"
  fi
  if [ -z "${owner_repo:-}" ]; then
    echo "🛑 Aucun remote '$remote' et impossible de déduire le repo."
    echo "   Définis GH_REPO=owner/name ou crée le remote manuellement :"
    echo "   git remote add origin git@github.com:<owner>/<name>.git"
    exit 1
  fi
  remote_url="git@github.com:${owner_repo}.git"
  echo "ℹ️ Ajout du remote '$remote' → $remote_url"
  git remote add "$remote" "$remote_url"
else
  echo "ℹ️ Remote '$remote' détecté → $remote_url"
fi

# --- Déterminer la branche par défaut si BASE_BRANCH non fournie
if [ -n "${BASE_BRANCH:-}" ]; then
  base_branch="$BASE_BRANCH"
else
  # Exemple: refs/remotes/origin/HEAD -> origin/main
  head_ref="$(git symbolic-ref -q "refs/remotes/${remote}/HEAD" || true)"
  if [ -n "$head_ref" ]; then
    base_branch="${head_ref#refs/remotes/${remote}/}"
  else
    # fallback: main puis master
    if git ls-remote --exit-code --heads "$remote" main >/dev/null 2>&1; then
      base_branch="main"
    elif git ls-remote --exit-code --heads "$remote" master >/dev/null 2>&1; then
      base_branch="master"
    else
      echo "🛑 Impossible de déterminer la branche de base (main/master)."
      echo "   Fournis BASE_BRANCH=xxx"
      exit 1
    fi
  fi
fi

# --- PR activable uniquement si gh est dispo
if ! command -v gh >/dev/null 2>&1; then
  [ "$pr_mode" != "never" ] && echo "⚠️  gh non trouvé → PR skip forcé (--pr=never)" >&2
  pr_mode="never"
fi

today=$(date +%Y%m%d)
branch_name="${type}/${today}-${feature}"

echo "🔄 Mise à jour de $base_branch depuis $remote..."
git fetch "$remote" "$base_branch"
git checkout "$base_branch"
git pull --ff-only "$remote" "$base_branch"

echo "🌱 Création de la branche '$branch_name'..."
git checkout -B "$branch_name"

# Push systématique (même si pas de change) pour ouvrir une PR vierge si besoin
git push -u "$remote" "$branch_name"

case "$pr_mode" in
  never) echo "🛑 PR non créée (--pr=never)"; exit 0 ;;
  draft|open)
    if ! gh auth status >/dev/null 2>&1; then
      echo "⚠️  gh non authentifié → PR skip"; exit 0
    fi
    # vérifier si une PR existe déjà
    if gh pr view "$branch_name" --head "$branch_name" >/dev/null 2>&1; then
      echo "ℹ️ PR existe déjà pour $branch_name."; exit 0
    fi
    title="$branch_name"
    body="Branche créée automatiquement le $today pour *$feature*"
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

echo "✅ Branche '$branch_name' poussée sur '$remote' ($remote_url) et PR ($pr_mode) créée si applicable."
