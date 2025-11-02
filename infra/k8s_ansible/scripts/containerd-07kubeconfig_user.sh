#!/bin/bash
echo "=== [KUBECONFIG_USER] Vérification de l'accès utilisateur (ansible) ==="

ANSIBLE_HOME="/home/ansible"
KUBECONFIG_PATH="$ANSIBLE_HOME/.kube/config"

# [1] Vérifie si l'utilisateur existe
if id ansible &>/dev/null; then
  echo "[1] Vérification du fichier ~/.kube/config pour l’utilisateur ansible..."
  if [ -f "$KUBECONFIG_PATH" ]; then
    ls -l "$KUBECONFIG_PATH"
    echo "✅ kubeconfig présent pour ansible"
  else
    echo "❌ Aucun fichier kubeconfig trouvé à $KUBECONFIG_PATH"
  fi

  echo
  echo "[2] Vérification de l’accès au cluster via 'kubectl get nodes'..."
  if sudo -u ansible kubectl get nodes &>/dev/null; then
    sudo -u ansible kubectl get nodes
    echo "✅ kubectl get nodes fonctionne sans sudo"
  else
    echo "⚠️ kubectl ne retourne pas de nœuds (cluster vide ou config incorrecte)"
  fi

  echo
  echo "[3] Vérification de la lecture des pods dans tous les namespaces..."
  if sudo -u ansible kubectl get pods -A &>/dev/null; then
    sudo -u ansible kubectl get pods -A | head -n 10
    echo "✅ kubectl get pods -A fonctionne"
  else
    echo "⚠️ Impossible de vérifier la liste des pods (cluster vide ?)"
  fi

  echo
  echo "[4] Vérification du cluster configuré dans le kubeconfig..."
  if [ -f "$KUBECONFIG_PATH" ]; then
    grep -A2 "server:" "$KUBECONFIG_PATH" || echo "⚠️ Impossible d’extraire les infos du cluster depuis le kubeconfig"
  else
    echo "⚠️ Aucun kubeconfig disponible pour extraire les infos du cluster"
  fi

else
  echo "❌ L'utilisateur 'ansible' n'existe pas sur ce système."
  echo "⚠️ Vérification de l’accès root à la place..."
  if kubectl get nodes &>/dev/null; then
    echo "✅ kubectl (root) fonctionne, cluster accessible"
  else
    echo "❌ kubectl (root) ne fonctionne pas — problème d’accès API ?"
  fi
fi

echo
echo "-------------------------------------------"
echo "Résultats attendus :"
echo "  • ~/.kube/config existe, appartient à ansible, permissions correctes"
echo "  • 'kubectl get nodes' fonctionne sans sudo"
echo "  • 'kubectl get pods -A' retourne des ressources"
echo "  • Cluster et API visibles dans le kubeconfig"
echo "-------------------------------------------"
