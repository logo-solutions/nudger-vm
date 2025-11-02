#!/bin/bash
set -euo pipefail

echo "=== [KUBERNETES] Sanity Check post-install ==="

# --- [1] Vérification des binaires kubeadm / kubelet / kubectl ---
echo
echo "[1] Vérification des binaires kubeadm / kubelet / kubectl..."
missing=0
for bin in kubeadm kubelet kubectl; do
  if command -v "$bin" >/dev/null 2>&1; then
    echo "✅ $bin est installé : $(command -v "$bin")"
  else
    echo "❌ $bin introuvable dans le PATH"
    missing=1
  fi
done
[[ "$missing" -eq 0 ]] || exit 1

# --- [2] Vérification des versions locales ---
echo
echo "[2] Vérification des versions installées..."
for bin in kubeadm kubelet kubectl; do
  if command -v "$bin" >/dev/null 2>&1; then
    echo -n "🧩 $bin version : "
    case "$bin" in
      kubeadm)
        ver=$(kubeadm version -o short 2>/dev/null || kubeadm version 2>/dev/null | grep -Eo 'v[0-9]+\.[0-9]+\.[0-9]+') ;;
      kubelet)
        ver=$(kubelet --version 2>/dev/null | grep -Eo 'v[0-9]+\.[0-9]+\.[0-9]+') ;;
      kubectl)
        ver=$(kubectl version --client -o yaml 2>/dev/null | grep gitVersion | awk '{print $2}' | tr -d '"') ;;
    esac
    echo "${ver:-N/A}"
  fi
done

# --- [3] Vérification du service kubelet ---
echo
echo "[3] Vérification du service kubelet..."

# On vérifie la présence réelle du b binaire ET du service
if command -v kubelet >/dev/null 2>&1; then
    if systemctl list-units --all | grep -q 'kubelet.service'; then
        state=$(systemctl show -p ActiveState --value kubelet 2>/dev/null || echo "unknown")
        case "$state" in
            active)
                echo "✅ kubelet actif (running)"
                ;;
            inactive)
                echo "⚠️ kubelet présent mais inactif"
                ;;
            failed)
                echo "❌ kubelet présent mais en erreur"
                ;;
            *)
                echo "⚠️ kubelet présent mais état inconnu ($state)"
                ;;
        esac
    else
        echo "⚠️ kubelet installé mais unité systemd non listée (daemon non rechargé ?)"
        echo "   → Astuce : systemctl daemon-reexec && systemctl daemon-reload"
    fi
else
    echo "❌ kubelet non trouvé dans systemd ni dans PATH"
fi
# --- [4] Vérification du dépôt apt Kubernetes ---
echo
echo "[4] Vérification du dépôt apt Kubernetes..."
repo=$(grep -hR "pkgs.k8s.io" /etc/apt/sources.list.d/ /etc/apt/sources.list 2>/dev/null | head -n1 || true)
if [[ -n "$repo" ]]; then
  echo "$repo"
  echo "✅ Dépôt pkgs.k8s.io configuré"
else
  echo "⚠️  Aucun dépôt pkgs.k8s.io trouvé"
fi

# --- [5] Vérification du keyring GPG ---
echo
echo "[5] Vérification du keyring GPG Kubernetes..."
if [[ -f /etc/apt/keyrings/kubernetes-archive-keyring.gpg ]]; then
  echo "✅ Clé GPG présente : /etc/apt/keyrings/kubernetes-archive-keyring.gpg"
else
  echo "❌ Clé GPG manquante"
fi

# --- [6] Vérification du swap ---
echo
echo "[6] Vérification du swap..."
if swapon --show | grep -q '^'; then
  echo "⚠️  Swap encore actif :"
  swapon --show
else
  echo "✅ Aucun swap actif"
fi

# --- [7] Vérification du paramètre vm.swappiness ---
echo
echo "[7] Vérification du paramètre vm.swappiness..."
swappiness=$(sysctl -n vm.swappiness 2>/dev/null || echo "N/A")
echo "vm.swappiness = $swappiness"
if [[ "$swappiness" == "0" ]]; then
  echo "✅ Swappiness désactivé (OK)"
else
  echo "⚠️  Swappiness non nul : $swappiness"
fi

# --- [8] Vérification build info kubeadm ---
echo
echo "[8] Vérification build info kubeadm..."
kubeadm version -o json 2>/dev/null | jq '{gitVersion, buildDate, platform}' || kubeadm version -o short 2>/dev/null

# --- [9] Vérification cohérence Client / Serveur ---
echo
echo "[9] Vérification cohérence kubeadm/kubelet/kubectl (Client/Serveur)..."
export KUBECONFIG=/etc/kubernetes/admin.conf
if kubectl version -o json >/tmp/kubever.json 2>/dev/null; then
  client=$(jq -r '.clientVersion.gitVersion' /tmp/kubever.json)
  server=$(jq -r '.serverVersion.gitVersion' /tmp/kubever.json)
  echo "Client Version : $client"
  echo "Server Version : $server"
  if [[ "$client" == "$server" ]]; then
    echo "✅ Versions client et serveur cohérentes"
  else
    echo "⚠️  Versions divergentes : client=$client / serveur=$server"
  fi
else
  echo "❌ Impossible d’interroger le serveur API (vérifie admin.conf ou l’état du control-plane)"
fi

# --- Résumé ---
echo
echo "-------------------------------------------"
echo "Résultats attendus :"
echo "  • kubeadm, kubelet, kubectl présents"
echo "  • Versions cohérentes (ex: v1.31.x)"
echo "  • kubelet actif ou prêt à l’être"
echo "  • Dépôt pkgs.k8s.io configuré"
echo "  • Clé GPG installée"
echo "  • Swap désactivé, vm.swappiness=0"
echo "  • API Kubernetes accessible via admin.conf"
echo "-------------------------------------------"
