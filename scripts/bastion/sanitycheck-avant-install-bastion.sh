#!/usr/bin/env bash
set -Eeuo pipefail

FAIL=0
STEP=0

step() {
  STEP=$((STEP+1))
  echo ""
  echo "[$STEP] $1"
}

ok()   { echo "   ✅ $1"; }
warn() { echo "   ⚠️  $1"; }
err()  { echo "   ❌ $1"; FAIL=1; }

echo "🔍 Sanity check des prérequis (AVANT création de la VM Bastion)"

# 1) Vérifier outils de base
step "Vérification des outils requis (sert à pouvoir créer/commander la VM)"
for cmd in git ssh; do
  if command -v "$cmd" >/dev/null 2>&1; then
    ok "$cmd trouvé ($(command -v $cmd))"
  else
    err "$cmd introuvable — installez-le puis relancez"
  fi
done
  if command -v "hcloud" >/dev/null 2>&1; then
    ok "hcloud trouvé -"
  else
    err "hcloud introuvable — installez-le puis relancezi (pour macos > brew install hcloud)"
  fi
echo "bitwarden actif"
# 2) Vérifier clé privée
SSH_KEY="${HOME}/.ssh/hetzner-bastion"
step "Vérification de la clé privée SSH (sert à te connecter au Bastion ensuite)"
if [[ -f "$SSH_KEY" ]]; then
  ok "Clé privée trouvée"
  perms=$(stat -f "%Lp" "$SSH_KEY" 2>/dev/null || stat -c "%a" "$SSH_KEY" 2>/dev/null || echo "???")
  if [[ "$perms" != "600" ]]; then
    warn "Permissions = $perms (correction en 600 appliquée)"
    chmod 600 "$SSH_KEY" || true
  else
    ok "Permissions correctes (600)"
  fi
else
  err "Clé privée manquante. Générez-la : ssh-keygen -t ed25519 -f $SSH_KEY -C 'bastion-hetzner' -a 100"
fi

# 3) Vérifier clé publique
PUB_KEY="${SSH_KEY}.pub"
step "Vérification de la clé publique SSH (sert à enregistrer la clé chez Hetzner)"
if [[ -f "$PUB_KEY" ]]; then
  ok "Clé publique trouvée"
else
  err "Clé publique manquante. Générez-la : ssh-keygen -y -f $SSH_KEY > $PUB_KEY"
fi

# 4) Vérifier enregistrement clé publique Hetzner
step "Vérification de l'enregistrement de la clé publique dans Hetzner Cloud (sert à ce que Hetzner injecte la clé dans la VM)"

# D'abord vérifier si le token est bien exporté (sinon inutile de tester hcloud)
if [[ -z "${HCLOUD_TOKEN:-}" ]]; then
  err "Aucun HCLOUD_TOKEN défini — impossible de contacter l'API Hetzner."
  err "Exemple : export HCLOUD_TOKEN=\$(bw get item \"token_hcloud_bastion\" | jq -r '.login.password')"
else
  # Si le token est présent, on le rend disponible pour la CLI
  export HCLOUD_TOKEN

  # Vérifier que hcloud fonctionne bien avec ce token
  if ! hcloud server list >/dev/null 2>&1; then
    err "Le token semble invalide ou le contexte hcloud n'est pas actif."
    err "Essayez : hcloud context create nudger --token \"\$HCLOUD_TOKEN\""
  else
    # Si tout est bon côté token, on peut vérifier la clé publique
    if [[ -f "$PUB_KEY" ]]; then
      local_pub="$(cat "$PUB_KEY")"
      if hcloud ssh-key list -o noheader --output columns=public_key | grep -Fq "$local_pub"; then
        ok "Clé publique présente dans Hetzner (OK)"
      else
        err "Clé publique ABSENTE chez Hetzner."
        echo "    ➜ Ajoutez-la manuellement :"
        echo "      hcloud ssh-key create --name hetzner-bastion --public-key \"$(cat "$PUB_KEY")\""
      fi
    else
      err "Clé publique introuvable localement : $PUB_KEY"
    fi
  fi
fi


# 5) Vérifier variable HCLOUD_TOKEN
step "Vérification de la variable HCLOUD_TOKEN (sert à autoriser les appels API Hetzner)"
if [[ -n "${HCLOUD_TOKEN:-}" ]]; then
  ok "HCLOUD_TOKEN est défini."
else
  err "HCLOUD_TOKEN non défini."
  echo "    ➜ Exemple : export HCLOUD_TOKEN=\$(bw get item \"token_hcloud_bastion\" | jq -r '.login.password')"
fi


# 6) Vérifier validité du token Hetzner
step "Vérification de la validité du token Hetzner (sert à s'assurer que l’API est accessible)"
if [[ -n "${HCLOUD_TOKEN:-}" ]]; then
  if hcloud server list >/dev/null 2>&1; then
    ok "Token valide (API Hetzner OK)."
  else
    err "Échec d'appel API Hetzner — token invalide ou réseau indisponible."
  fi
else
  warn "HCLOUD_TOKEN non défini, test de validité sauté."
fi
echo ""
if [[ "$FAIL" -eq 0 ]]; then
  echo "✅ Sanity check terminé : tous les prérequis critiques sont présents."
  echo "ℹ️  Le GITHUB_TOKEN sera vérifié plus tard, côté bastion, avant le 'git clone'."
else
  echo "❌ Sanity check terminé avec des erreurs. Corrigez les points ci-dessus puis relancez."
  exit 1
fi
echo ""
if [[ "$FAIL" -eq 0 ]]; then
  echo "✅ Sanity check terminé : tous les prérequis critiques sont présents."
  exit 0
else
  echo "❌ Sanity check terminé avec des erreurs. Corrigez les points ci-dessus puis relancez."
  exit 1
fi
