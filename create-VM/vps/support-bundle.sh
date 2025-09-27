#!/usr/bin/env bash
set -euo pipefail
IP="${1:?IP requise}"
SSH_KEY="${2:?clé SSH requise}"
OUT_DIR="${3:?out dir requis}"
STAMP="$(date +%Y%m%d)"
BASENAME="support-bundle-${STAMP}.tgz"
DEST="$OUT_DIR/support-bundle"; mkdir -p "$DEST"

# NEW: seed known_hosts
KN="$OUT_DIR/known_hosts"
mkdir -p "$OUT_DIR"
touch "$KN"
# si l'IP n'est pas déjà présente, on l’ajoute
ssh-keygen -F "$IP" -f "$KN" >/dev/null || ssh-keyscan -H -t ed25519,ecdsa,rsa -T 5 "$IP" >> "$KN"

ssh -i "$HOME/.ssh/$SSH_KEY" -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$KN" root@"$IP" '
  set -euo pipefail
  mkdir -p /tmp/support-bundle
  {
    echo "== uname -a =="; uname -a
    echo "== date =="; date -Is
    echo "== uptime =="; uptime
    echo "== ip a =="; ip a
    echo "== journalctl -xe (tail) =="; journalctl -xe --no-pager | tail -n 500
    echo "== systemctl --failed =="; SYSTEMD_PAGER=cat SYSTEMD_COLORS=0 systemctl --no-pager --failed || true
    echo "== dmesg (tail) =="; dmesg | tail -n 200 || true
    echo "== kubelet status =="; SYSTEMD_PAGER=cat systemctl --no-pager status kubelet || true
    echo "== containerd status =="; SYSTEMD_PAGER=cat systemctl --no-pager status containerd || true
    echo "== ss -ltnp =="; ss -ltnp || true
    echo "== manifest kube-apiserver =="; cat /etc/kubernetes/manifests/kube-apiserver.yaml || true
    echo "== manifest etcd.yaml =="; cat /etc/kubernetes/manifests/etcd.yaml || true
    echo "== manifest kube-scheduler.yaml =="; cat /etc/kubernetes/manifests/kube-scheduler.yaml || true
    echo "== manifest ikube-controller-manager =="; cat /etc/kubernetes/manifests/kube-controller-manager.yaml || true
  } > /tmp/support-bundle/host.txt
  tar -C /tmp -czf /tmp/support-bundle.tgz support-bundle
'

scp -i "$HOME/.ssh/$SSH_KEY" -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$KN" \
  root@"$IP":/tmp/support-bundle.tgz "$DEST/$BASENAME"

# NEW: petit nettoyage distant (optionnel)
ssh -i "$HOME/.ssh/$SSH_KEY" -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$KN" root@"$IP" \
  'rm -rf /tmp/support-bundle /tmp/support-bundle.tgz || true'

echo "✅ Bundle récupéré: $DEST/$BASENAME"
