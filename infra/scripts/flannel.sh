#!/bin/bash
set -e

echo "👉 Chargement du module br_netfilter..."
sudo modprobe br_netfilter

echo "👉 Vérification du module..."
lsmod | grep br_netfilter || echo "⚠️ Module br_netfilter non trouvé dans lsmod"

echo "👉 Activation du paramètre sysctl..."
sudo sysctl net.bridge.bridge-nf-call-iptables=1

echo "👉 Ajout du paramètre pour persistance..."
echo "net.bridge.bridge-nf-call-iptables = 1" | sudo tee /etc/sysctl.d/99-kubernetes.conf > /dev/null

echo "👉 Rechargement des paramètres sysctl..."
sudo sysctl --system

echo "👉 Redémarrage des pods Flannel..."
kubectl delete pod -n kube-flannel -l app=flannel

echo "✅ Correction appliquée. Flannel devrait redémarrer correctement."
