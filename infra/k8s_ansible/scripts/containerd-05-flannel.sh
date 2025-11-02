#!/bin/bash
echo "=== [FLANNEL] Vérification du CNI (Flannel) ==="

# --- [1] Vérification du DaemonSet ---
echo
echo "[1] Vérification du DaemonSet kube-flannel-ds..."
if kubectl -n kube-flannel get ds kube-flannel-ds >/dev/null 2>&1; then
  ds_output=$(kubectl -n kube-flannel get ds kube-flannel-ds 2>/dev/null | tail -n1)
  echo "$ds_output"
  desired=$(echo "$ds_output" | awk '{print $2}')
  ready=$(echo "$ds_output" | awk '{print $4}')

  if [[ "$desired" == "$ready" && "$desired" != "0" ]]; then
    echo "✅ DaemonSet kube-flannel-ds est complet ($ready/$desired)"
  else
    echo "⚠️  DaemonSet présent mais incomplet ($ready/$desired)"
  fi
else
  echo "❌ Aucun DaemonSet kube-flannel-ds détecté (Flannel non appliqué ?)"
fi

# --- [2] Vérification des pods Flannel ---
echo
echo "[2] Vérification des pods Flannel..."
if kubectl -n kube-flannel get pods >/dev/null 2>&1; then
  kubectl -n kube-flannel get pods -o wide || true
  if kubectl -n kube-flannel get pods 2>/dev/null | grep -q "Running"; then
    echo "✅ Les pods Flannel sont Running"
  else
    echo "⚠️  Certains pods Flannel ne sont pas Running"
    echo "   → Derniers logs kube-flannel :"
    kubectl logs -n kube-flannel -l app=flannel -c kube-flannel --tail=20 2>/dev/null || true
  fi
else
  echo "❌ Namespace kube-flannel introuvable ou inaccessible"
fi

# --- [3] Vérification de l’état des nœuds ---
echo
echo "[3] Vérification de l’état des nœuds et du PodCIDR..."
if kubectl get nodes -o wide >/dev/null 2>&1; then
  kubectl get nodes -o wide || true
  podcidr=$(kubectl get node master1 -o jsonpath='{.spec.podCIDR}' 2>/dev/null)
  if [[ -n "$podcidr" ]]; then
    echo "✅ Le nœud a un PodCIDR configuré : $podcidr"
  else
    echo "⚠️  PodCIDR non affiché — le CNI a peut-être été appliqué mais non reporté dans l’objet Node"
  fi
else
  echo "❌ Impossible d’obtenir la liste des nœuds"
fi

# --- [4] Vérification d’éventuelles erreurs réseau ---
echo
echo "[4] Vérification d’éventuelles erreurs réseau..."
if kubectl logs -n kube-flannel -l app=flannel -c kube-flannel 2>/dev/null | grep -q "no such network interface"; then
  echo "❌ Erreur détectée : 'no such network interface' (problème d’interface hôte)"
else
  echo "✅ Aucune erreur 'no such network interface' détectée dans les logs Flannel"
fi

# --- Résumé ---
echo
echo "-------------------------------------------"
echo "Résultats attendus :"
echo "  - DaemonSet kube-flannel-ds complet (READY = DESIRED)"
echo "  - Pods Flannel Running"
echo "  - Nœuds avec un PodCIDR (ex: 10.244.x.x)"
echo "  - Aucune erreur 'no such network interface'"
echo "-------------------------------------------"
