#!/usr/bin/env bash
set -euo pipefail

HTTP_NODEPORT="${1:?HTTP nodePort manquant}"
HTTPS_NODEPORT="${2:?HTTPS nodePort manquant}"

# Assure table/chaîne
nft list table ip nat >/dev/null 2>&1 || nft 'add table ip nat'
nft 'add chain ip nat PREROUTING { type nat hook prerouting priority 0 ; }' 2>/dev/null || true

# Règles idempotentes (on supprime si déjà présentes puis on remet proprement)
# HTTP
nft --handle list chain ip nat PREROUTING 2>/dev/null \
 | awk -v p="${HTTP_NODEPORT}" '/tcp dport 80 .* redirect to :/ {print $NF}' \
 | awk '{print $2}' \
 | xargs -r -I{} nft delete rule ip nat PREROUTING handle {}

nft add rule ip nat PREROUTING tcp dport 80  redirect to :"${HTTP_NODEPORT}"

# HTTPS
nft --handle list chain ip nat PREROUTING 2>/dev/null \
 | awk -v p="${HTTPS_NODEPORT}" '/tcp dport 443 .* redirect to :/ {print $NF}' \
 | awk '{print $2}' \
 | xargs -r -I{} nft delete rule ip nat PREROUTING handle {}

nft add rule ip nat PREROUTING tcp dport 443 redirect to :"${HTTPS_NODEPORT}"

echo "[ingress-dnat][nft] OK -> 80→:${HTTP_NODEPORT}  443→:${HTTPS_NODEPORT}"
