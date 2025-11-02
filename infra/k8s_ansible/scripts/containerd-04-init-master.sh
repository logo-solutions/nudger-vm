#!/bin/bash
echo "=== [INIT_MASTER] Vérification de l'initialisation du cluster ==="

echo
echo "[1] Vérification de la présence du master dans la liste des nœuds..."
if kubectl get nodes >/dev/null 2>&1; then
  kubectl get nodes || true
  if kubectl get nodes 2>/dev/null | grep -q "Ready"; then
    echo "✅ Le master est en état Ready"
  elif kubectl get nodes 2>/dev/null | grep -q "NotReady"; then
    echo "⚠️  Le master est présent mais NotReady (probablement en attente de la CNI)"
  else
    echo "❌ Aucun nœud détecté pour l'instant"
  fi
else
  echo "❌ kubectl ne parvient pas à contacter l'API server"
fi

echo
echo "[2] Vérification des pods système (namespace kube-system)..."
if kubectl get pods -n kube-system >/dev/null 2>&1; then
  kubectl get pods -n kube-system -o wide || true
  echo
  echo "✅ Les pods kube-system ont été listés ci-dessus"
  echo "   → vérifier que etcd, apiserver, controller-manager et scheduler sont Running"
else
  echo "❌ Impossible d'obtenir la liste des pods kube-system (API injoignable)"
fi

echo
echo "[3] Vérification des informations de cluster..."
if kubectl cluster-info >/dev/null 2>&1; then
  kubectl cluster-info || true
  echo "✅ L'API Kubernetes répond (URL du control-plane détectée)"
else
  echo "❌ cluster-info ne répond pas — kube-apiserver probablement injoignable"
fi

echo
echo "-------------------------------------------"
echo "Résultats attendus :"
echo "  - Le master apparaît (Ready ou NotReady si CNI pas encore appliquée)"
echo "  - etcd, apiserver, controller-manager et scheduler sont Running"
echo "  - 'kubectl cluster-info' renvoie une URL d'API fonctionnelle"
echo "-------------------------------------------"
