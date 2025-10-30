echo "=== [PREP] ==="
lsmod | grep br_netfilter
sysctl net.bridge.bridge-nf-call-iptables
sysctl net.ipv4.ip_forward
swapon --show
grep -E 'swap' /etc/fstab | grep -v '^#'


echo "	•	br_netfilter est présent
	•	net.bridge.bridge-nf-call-iptables = 1
	•	net.ipv4.ip_forward = 1
	•	Aucun swap actif ni non-commenté dans /etc/fstab.

⸻
"
echo -e "\n[1] Vérification du module br_netfilter..."
lsmod | grep br_netfilter && echo "✅ Module br_netfilter chargé" || echo "❌ Module br_netfilter absent"

echo -e "\n[2] Vérification du paramètre net.bridge.bridge-nf-call-iptables..."
sysctl net.bridge.bridge-nf-call-iptables 2>/dev/null || true

echo -e "\n[3] Vérification du paramètre net.ipv4.ip_forward..."
sysctl net.ipv4.ip_forward 2>/dev/null || true

echo -e "\n[4] Vérification du swap actif..."
if swapon --show | grep -q .; then
  echo "❌ Swap encore actif :"
  swapon --show
else
  echo "✅ Aucun swap actif"
fi

echo -e "\n[5] Vérification du /etc/fstab (swap non commenté)..."
if grep -E 'swap' /etc/fstab | grep -v '^#' >/dev/null; then
  echo "❌ Entrées swap détectées dans /etc/fstab :"
  grep -E 'swap' /etc/fstab | grep -v '^#'
else
  echo "✅ Aucun swap non commenté dans /etc/fstab"
fi
