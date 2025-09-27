#!/usr/bin/env bash
set -euo pipefail

# Params
POD_CIDR="${1:-10.244.0.0/16}"   # adapte si besoin
SVC_CIDR="${2:-10.96.0.0/12}"

# Détecte l'interface WAN (sortie par défaut)
WAN_IF="$(ip route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++) if ($i=="dev"){print $(i+1); exit}}')"
[ -n "${WAN_IF:-}" ] || { echo "WAN_IF introuvable"; exit 1; }

# Applique une config complète et idempotente en famille 'inet'
# - chain forward : autorise established/related + trafic des pods
# - chain postrouting : ne SNAT pas vers le CIDR services, sinon masquerade via WAN_IF
nft -f - <<NFT
table inet egress_nat {
  chain forward {
    type filter hook forward priority 0;
    policy drop;

    ct state established,related accept
    ip saddr ${POD_CIDR} accept
    ip6 saddr ::/0 drop
  }

  chain postrouting {
    type nat hook postrouting priority 100;

    ip saddr ${POD_CIDR} ip daddr ${SVC_CIDR} return
    oif "${WAN_IF}" ip saddr ${POD_CIDR} masquerade
  }
}
NFT

echo "[egress-nat] OK : POD_CIDR=${POD_CIDR}, SVC_CIDR=${SVC_CIDR}, WAN_IF=${WAN_IF}"
