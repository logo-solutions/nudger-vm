# Vérification des prérequis pour `create-vm-bastion.sh`

Ce document décrit comment installer et vérifier tous les prérequis pour exécuter le script de création de VM sur Hetzner.

---

## 🖥️ macOS (Homebrew)
```bash
# Installer Homebrew si pas déjà fait
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Outils nécessaires
brew install hcloud gettext netcat openssh

# Lien symbolique pour envsubst (fourni par gettext)
brew link --force gettext

# Vérification
which hcloud envsubst nc ssh ssh-keygen
```

---

## 🐧 Ubuntu / Debian
```bash
# Mise à jour
sudo apt update

# Outils nécessaires
sudo apt install -y hcloud-cli gettext-base netcat-openbsd openssh-client

# Vérification
which hcloud envsubst nc ssh ssh-keygen
```

---

## 🔑 Clé SSH
```bash
# Vérifie si ta clé privée existe
ls -l ~/.ssh/id_vm_ed25519

# Si elle n’existe pas, génère-la
ssh-keygen -t ed25519 -f ~/.ssh/id_vm_ed25519 -C "loic@bastion"
```

⚠️ Ensuite, ajoute la clé publique `~/.ssh/id_vm_ed25519.pub` dans ton Hetzner Cloud, avec le nom `loic-vm-key` :  
```bash
hcloud ssh-key create --name loic-vm-key --public-key-from-file ~/.ssh/id_vm_ed25519.pub
```

---

## 🌐 Token Hetzner
```bash
# À exécuter une seule fois (remplace par ton vrai token Hetzner stocké dans bitwarden)
export HCLOUD_TOKEN=ton_token_hetzner
```

Tu peux ajouter cette ligne à ton `~/.zshrc` ou `~/.bashrc` pour la rendre permanente.  

---

## ✅ Vérification finale
```bash
hcloud context create nudger
# (colle ton token Hetzner quand demandé)

hcloud server list
```

Si la liste s’affiche, ton environnement est prêt 🎉

---

## 🚀 Script de diagnostic (optionnel)

Crée un fichier `check-prereqs.sh` :

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "🔍 Vérification des prérequis..."

for cmd in hcloud envsubst nc ssh ssh-keygen; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "❌ $cmd manquant"
    MISSING=1
  else
    echo "✅ $cmd présent"
  fi
done

if [[ ! -f "$HOME/.ssh/id_vm_ed25519" ]]; then
  echo "❌ Clé SSH absente (~/.ssh/id_vm_ed25519)"
else
  echo "✅ Clé SSH présente"
fi

if [[ -z "${HCLOUD_TOKEN:-}" ]]; then
  echo "❌ Variable HCLOUD_TOKEN non définie"
else
  echo "✅ HCLOUD_TOKEN défini"
fi

[[ -n "${MISSING:-}" ]] && exit 1 || echo "🎉 Tous les prérequis sont OK !"
```

Exécute :

```bash
chmod +x check-prereqs.sh
./check-prereqs.sh
```

