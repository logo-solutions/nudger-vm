#!/bin/bash
set -e

if [[ $EUID -ne 0 ]]; then
   echo "Ce script doit être exécuté en root (sudo)."
   exit 1
fi

echo "Désactivation du swap..."
swapoff -a

FSTAB="/etc/fstab"
SWAP_LINE=$(grep -E "^[^#].*/swap\.img" $FSTAB || true)

if [[ -n "$SWAP_LINE" ]]; then
    echo "Commentaire de la ligne /swap.img dans $FSTAB..."
    sed -i.bak '/\/swap\.img/ s/^/#/' $FSTAB
    echo "Sauvegarde originale : $FSTAB.bak"
fi

echo "Redémarrage de kubelet..."
systemctl restart kubelet
systemctl status kubelet --no-pager
