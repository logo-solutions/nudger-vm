#!/bin/bash
set -e

echo "👉 Vérification des droits..."
if [[ $EUID -ne 0 ]]; then
  echo "⚠️ Ce script doit être exécuté avec sudo."
  exit 1
fi

# 1️⃣ Charger le module br_netfilter
echo "👉 Chargement du module br_netfilter..."
modprobe br_netfilter

# 2️⃣ Activer le sysctl pour les bridges
echo "👉 Activation du sysctl net.bridge.bridge-nf-call-iptables=1..."
sysctl net.bridge.bridge-nf-call-iptables=1

# 3️⃣ Persist si pas déjà présent
SYSCTL_CONF="/etc/sysctl.d/99-kubernetes.conf"
if ! grep -q "net.bridge.bridge-nf-call-iptables" "$SYSCTL_CONF" 2>/dev/null; then
  echo "net.bridge.bridge-nf-call-iptables = 1" > "$SYSCTL_CONF"
fi
sysctl --system

# 4️⃣ Redémarrer les pods Flannel pour régénérer /run/flannel/subnet.env
echo "👉 Redémarrage des pods Flannel..."
kubectl delete pod -n kube-flannel -l app=flannel || true

# 5️⃣ Vérifier que les pods Flannel sont Running
echo "👉 Vérification des pods Flannel..."
sleep 5
kubectl get pods -n kube-flannel -o wide

echo "✅ Script terminé. Flannel devrait être opérationnel."
