#!/bin/bash
set -euo pipefail

echo "=== [KUBE_PROXY] Vérification du composant kube-proxy ==="
echo

# --- [1] Vérification du DaemonSet kube-proxy ---
echo "[1] Vérification du DaemonSet kube-proxy..."
if kubectl -n kube-system get ds kube-proxy >/dev/null 2>&1; then
  ds_output=$(kubectl -n kube-system get ds kube-proxy 2>/dev/null | tail -n1)
  echo "$ds_output" | column -t
  desired=$(echo "$ds_output" | awk '{print $2}')
  ready=$(echo "$ds_output" | awk '{print $4}')
  available=$(echo "$ds_output" | awk '{print $6}')

  if [[ "$desired" == "$ready" && "$ready" == "$available" && "$desired" != "0" ]]; then
    echo "✅ DaemonSet kube-proxy est complet ($ready/$desired pods prêts)"
  else
    echo "⚠️  DaemonSet présent mais incomplet (READY=$ready / DESIRED=$desired / AVAILABLE=$available)"
  fi
else
  echo "❌ Aucun DaemonSet kube-proxy détecté dans le namespace kube-system"
fi

# --- [2] Vérification des pods kube-proxy ---
echo
echo "[2] Vérification de l’état des pods kube-proxy..."
if kubectl -n kube-system get pods -l k8s-app=kube-proxy >/dev/null 2>&1; then
  pods_output=$(kubectl -n kube-system get pods -l k8s-app=kube-proxy -o wide --no-headers)
  echo "$pods_output" | column -t
  total_pods=$(echo "$pods_output" | wc -l | tr -d ' ')
  running_pods=$(echo "$pods_output" | grep -c "Running" || true)

  if [[ "$total_pods" -eq "$running_pods" && "$total_pods" -gt 0 ]]; then
    echo "✅ Tous les pods kube-proxy sont Running ($running_pods/$total_pods)"
  else
    echo "⚠️  Certains pods kube-proxy ne sont pas Running ($running_pods/$total_pods)"
    echo "   → Derniers logs (20 lignes) :"
    kubectl logs -n kube-system -l k8s-app=kube-proxy --tail=20 2>/dev/null || true
  fi
else
  echo "❌ Aucun pod kube-proxy trouvé dans le namespace kube-system"
fi

# --- [3] Vérification des erreurs réseau connues ---
echo
echo "[3] Vérification des erreurs réseau connues (iptables / connection refused)..."
logs=$(kubectl logs -n kube-system -l k8s-app=kube-proxy --tail=100 2>/dev/null || true)
if echo "$logs" | grep -qiE "connection refused|iptables-save|failed to connect"; then
  echo "❌ Erreurs détectées dans les logs kube-proxy :"
  echo "$logs" | grep -iE "connection refused|iptables-save|failed to connect" | tail -n 10
else
  echo "✅ Aucun message d’erreur critique trouvé dans les logs kube-proxy"
fi

# --- [4] Vérification des IPs de pods (réseau cluster) ---
echo
echo "[4] Vérification du réseau des pods (IP attribuée par la CNI)..."
pod_ips=$(kubectl -n kube-system get pods -l k8s-app=kube-proxy -o wide --no-headers 2>/dev/null | awk '{print $6}')
if echo "$pod_ips" | grep -qE '^10\.'; then
  echo "✅ Les pods kube-proxy ont une IP dans le réseau cluster (10.x.x.x)"
else
  echo "⚠️  Les pods kube-proxy n’ont pas encore d’adresse 10.x.x.x (CNI en attente ?)"
  echo "    IPs détectées :"
  echo "$pod_ips" | sed 's/^/    - /'
fi

# --- [5] Vérification du rollout ---
echo
echo "[5] Vérification du déploiement (rollout) kube-proxy..."
if kubectl -n kube-system rollout status ds/kube-proxy --timeout=30s >/dev/null 2>&1; then
  echo "✅ Rollout kube-proxy terminé avec succès"
else
  echo "⚠️  Rollout kube-proxy en attente ou partiel"
fi

# --- [6] Vérification de la connectivité du plan de contrôle ---
echo
echo "[6] Vérification de la connectivité API Kubernetes..."
if kubectl get nodes >/dev/null 2>&1; then
  echo "✅ L’API Kubernetes répond (kubectl OK)"
else
  echo "❌ L’API Kubernetes ne répond pas — problème de réseau ou kubeconfig"
fi

# --- Résumé final ---
echo
echo "-------------------------------------------"
echo "Résultats attendus :"
echo "  • DaemonSet kube-proxy complet (READY = DESIRED = AVAILABLE)"
echo "  • Pods kube-proxy Running dans kube-system"
echo "  • Pas d’erreur 'connection refused' ni 'iptables-save' dans les logs"
echo "  • IPs de pods dans le réseau 10.x.x.x (CNI Flannel fonctionnelle)"
echo "  • Rollout kube-proxy terminé et stable"
echo "  • kubectl répond à l’API Kubernetes"
echo "-------------------------------------------"
