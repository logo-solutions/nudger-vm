#!/bin/bash
echo "=== [CONTAINERD] Vérifications du runtime container ==="

echo
echo "[1] Vérification du statut du service containerd..."
if systemctl is-active --quiet containerd; then
  echo "✅ OK : containerd est actif (running)"
else
  echo "❌ ERREUR : containerd n'est pas actif"
  systemctl status containerd --no-pager | grep Active || true
fi

echo
echo "[2] Vérification de la présence de crictl..."
if command -v crictl >/dev/null 2>&1; then
  echo "ℹ️  crictl est installé"
  if crictl info 2>/dev/null | grep -E '"name":|"version"' >/dev/null; then
    echo "✅ OK : crictl communique correctement avec containerd"
  else
    echo "⚠️  crictl est présent mais ne répond pas (probablement pas configuré)"
  fi
else
  echo "⚠️  crictl n'est pas installé — test ignoré (non bloquant)"
fi

echo
echo "[3] Vérification de la version ctr..."
if command -v ctr >/dev/null 2>&1; then
  if ctr version 2>/dev/null | grep -q 'Version'; then
    ctr version 2>/dev/null | grep Version || true
    echo "✅ OK : ctr fonctionne (binaire présent et runtime accessible)"
  else
    echo "⚠️  ctr est présent mais ne renvoie pas de version"
  fi
else
  echo "❌ ctr n'est pas installé — problème potentiel"
fi

echo
echo "-------------------------------------------"
echo "Résultats attendus :"
echo "  - containerd est actif (running)"
echo "  - crictl est optionnel (non installé = non bloquant)"
echo "  - ctr version affiche une version cohérente (>=1.6)"
echo "-------------------------------------------"
