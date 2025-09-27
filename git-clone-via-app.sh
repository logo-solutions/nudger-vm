#!/usr/bin/env bash
set -euo pipefail

# =========================
# Fonctions utilitaires
# =========================
fail() { echo "❌ $*" >&2; exit 1; }
ok()   { echo "✅ $*"; }
info() { echo "➡️  $*"; }

# =========================
# Paramètres
# =========================
VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"
VAULT_TOKEN="${VAULT_TOKEN:?VAULT_TOKEN manquant}"
SECRET_PATH="${SECRET_PATH:-secret/github/app}"

OWNER="logo-solutions"
REPO="nudger-vm"
BRANCH="${BRANCH:-main}"
CLONE_DIR="${CLONE_DIR:-$HOME/$REPO}"

# =========================
# Récupération secrets Vault
# =========================
info "Lecture secrets GitHub App depuis Vault..."
APP_ID=$(vault kv get -field=app_id -address="$VAULT_ADDR" -token="$VAULT_TOKEN" "$SECRET_PATH") || fail "Impossible de lire app_id"
INSTALLATION_ID=$(vault kv get -field=installation_id -address="$VAULT_ADDR" -token="$VAULT_TOKEN" "$SECRET_PATH") || fail "Impossible de lire installation_id"
PEM_FILE=$(mktemp)
vault kv get -field=private-key -address="$VAULT_ADDR" -token="$VAULT_TOKEN" "$SECRET_PATH" > "$PEM_FILE" || fail "Impossible de lire private-key"
chmod 600 "$PEM_FILE"

ok "Secrets récupérés depuis Vault"

# =========================
# Génération JWT (valide 10 min)
# =========================
info "Génération JWT..."
JWT=$(ruby -ropenssl -rbase64 -rjson -e "
t = Time.now.to_i
payload = { iat: t-60, exp: t+600, iss: $APP_ID.to_i }
key = OpenSSL::PKey::RSA.new(File.read('$PEM_FILE'))
puts JWT.encode(payload, key, 'RS256')
") || fail "Impossible de générer JWT"

# =========================
# Récupération Installation Token
# =========================
info "Demande d'un Installation Token..."
TOKEN=$(curl -s -X POST \
  -H "Authorization: Bearer $JWT" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/app/installations/$INSTALLATION_ID/access_tokens" \
  | jq -r .token)

[[ -n "$TOKEN" && "$TOKEN" != "null" ]] || fail "Impossible d'obtenir un installation token"
ok "Installation Token récupéré"

# =========================
# Clonage repo
# =========================
info "Clonage du repo $OWNER/$REPO..."
rm -rf "$CLONE_DIR"
GIT_ASKPASS=$(mktemp)
echo "echo $TOKEN" > "$GIT_ASKPASS"
chmod +x "$GIT_ASKPASS"

GIT_ASKPASS=$GIT_ASKPASS git clone --branch "$BRANCH" "https://github.com/$OWNER/$REPO.git" "$CLONE_DIR" || fail "Échec clone"
ok "Repo cloné dans $CLONE_DIR"
