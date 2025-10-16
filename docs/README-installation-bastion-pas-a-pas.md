# Procédure d’installation – Nudger VM

---

## Sanity check avant création du Bastion ( Prérequis indispensables))

Avant de lancer la création de la VM Bastion, exécute le script suivant pour vérifier que tous les prérequis sont en place.

`scripts/bastion/sanitycheck-avant-install-bastion.sh` :

```bash

- **Clé privée SSH Hetzner Bastion** disponible sur ton **laptop** (ex. `~/.ssh/hetzner-bastion`) et **protégée par passphrase**.
- **Clé publique correspondante** **enregistrée** dans Hetzner Cloud (Console ou CLI) pour obtenir un **`ssh-key-id`** (ex. `102827339`).
- **Bitwarden** contient `HCLOUD_TOKEN` et `GITHUB_TOKEN`.
- **hcloud CLI** et **git** installés (côté laptop), **Ansible** côté bastion.

### Générer et enregistrer la clé (si besoin)

```bash
Depuis bitwarden : 
export HCLOUD_TOKEN=I4zSmFuaXXXXXX
création de la clé privée et publique de hetzner
```

## 1. Création du Bastion
- Récupérer **HCLOUD_TOKEN** depuis Bitwarden.
- Exécuter :
  ```bash
    AUTO_COMMIT=1 \                          
     KEY_NAME=hetzner-bastion \
     KEY_PATH="$HOME/.ssh/hetzner-bastion" \
     ./create-VM/vps/create-vm-bastion.sh --recreate
     ./scripts/bastion/post-install-host.sh
  ```
  → Hetzner crée la VM Bastion avec la **clé publique Bastion** injectée (clé déjà enregistrée dans Hetzner Cloud).

- Lancer le script post-install depuis le host
  ```bash
  ./scripts/bastion/post-install-host.sh
  ```

  → se connecter en ssh sur la machine
- Connexion SSH avec la **clé privée Bastion** :
  ```bash
 ssh -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i /Users/loicgourmelon/.ssh/hetzner-bastion root@157.180.42.146
  ```
  ```bash

- Lancer le script post-install depuis bastion:
  ```bash
  ```

## 2. Clonage du dépôt GitHub
###  depuis bitwarden : 
- GITHUB_TOKEN=ghp_Wir8MaUt6lgnR8XC5OsMeOAEhiXXXXXXXXXXXX &&  git clone https://$GITHUB_TOKEN@github.com/logo-solutions/nudger-vm
- cat > /etc/github-app/nudger-vm.private-key.pem <<'EOF'
- export HCLOUD_TOKEN=I4zSmFuaRyXeS
- cat > /root/.ssh/hetzner-bastion <<'EOF'
- Récupérer **GITHUB_TOKEN (PAT)** depuis Bitwarden.
- Cloner le dépôt :
  ```bash
  git clone https://$GITHUB_TOKEN@github.com/logo-solutions/nudger-vm
  ```
## 2. Mise en place Librairie devops et installation de vault

- Cloner le dépôt :
  ```bash
~/nudger-vm/scripts/bastion/post-install-vm-bastion.sh
  ```
---

## 3. Création du Master Kubernetes
- Réutiliser **HCLOUD_TOKEN** (Bitwarden).
- Créer la VM Master :
  ```bash
 ./create-VM/vps/create-vm-master.sh
  ```
  → Ici, **l’ID de la clé SSH Bastion** (ex: `102827339`) est fourni pour que **la clé publique Bastion** soit injectée dans la VM Master.  
  → Sans ça, impossible d’accéder au Master depuis le Bastion.

---

## 4. Configuration du Master
- Depuis le Bastion, Ansible/SSH se connecte au Master via la clé Bastion.
- Lancer :
  ```bash
  ./scripts/master/post-install-master.sh
  ```
- Ce script configure :
  - Kubernetes control plane
  - HashiCorp Vault

---


## Cartographie des secrets

| Secret | Quand il apparaît | Où il est stocké | Utilisation |
|--------|------------------|-----------------|-------------|
| **HCLOUD_TOKEN** | Avant la création des VMs | Bitwarden | Auth API Hetzner (`create-vm-bastion.sh`, `create-vm-master.sh`) |
| **Clé SSH Bastion (privée)** | Générée avant tout | Laptop | Connexion SSH → Bastion et Bastion → Master |
| **Clé SSH Bastion (publique, enregistrée Hetzner)** | Avant la création Master | Hetzner Cloud (ssh-key-id) | Injection dans Bastion/Master `authorized_keys` |
| **GITHUB_TOKEN (PAT)** | Après Bastion prêt | Bitwarden | Auth GitHub pour `git clone` sur Bastion |
| **Vault root token** | Généré à `vault operator init` | Copié immédiatement dans Bitwarden | Administration Vault |
| **Vault unseal keys** | Générées à `vault operator init` | Copiées immédiatement dans Bitwarden | Démarrage/déverrouillage de Vault |

---


