# 🚀 Nudger VM Bootstrap

Ce dépôt contient les scripts pour **créer une VM Hetzner** et **initialiser automatiquement Ansible**.

---

## 📦 Prérequis
 ssh-keygen -t ed25519 -C "deploy-key-nudger-002" -f ~/.ssh/id_github_nudger_002%

- [hcloud CLI](https://github.com/hetznercloud/cli) installé et configuré (`hcloud context create nudger`).
- Clé SSH générée et ajoutée à Hetzner :
  ```bash
  ssh-keygen -t ed25519 -f ~/.ssh/id_vm_ed25519 -C "vm-nudger"

hcloud ssh-key create --name loic-vm-key --public-key-from-file ~/.ssh/id_vm_ed25519.pub
  ```
- Dépendances locales :
  ```bash
  brew install gettext jq nc
  ```
	2.	Installe la collection HashiCorp Vault :
```bash
ansible-galaxy collection install community.hashi_vault
  ```
Installe hvac dans ton venv ansible local :
```bash
  cd infra/k8s_ansible
source .venv/bin/activate
pip install hvac
  ```
Forcer Ansible à utiliser forkserver au lieu de fork
```bash
export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES
export no_proxy="*"
 ```

---

## ⚙️ Workflow

### 1. Déployer une VM + bootstrap Ansible
Tout est automatisé via `deploy.sh` :
```bash
./deploy.sh
```

- Crée la VM Hetzner (via `create-vm.sh`).
- Génére un inventaire Ansible (`infra/k8s_ansible/inventory.ini`).
- Installe Ansible + collections locales.
- Exécute le playbook principal (`playbooks/nudger.yml`).

À la fin, la commande SSH est affichée automatiquement :
```bash
ssh -i ~/.ssh/id_vm_ed25519 root@<IP_VM>
```

---

### 2. Créer manuellement une VM (optionnel)
Si tu veux juste créer une VM sans Ansible :
```bash
create-VM/vps/create-vm.sh <VM_NAME> <USER> <DEPOT_GIT>
```

Exemple :
```bash
create-VM/vps/create-vm.sh master1 root git@github.com:logo-solutions/nudger-vm.git
```

---

## 📂 Arborescence

```
create-VM/vps/create-vm.sh      # Script de création VM Hetzner
create-VM/vps/cloud-init.yaml   # Cloud-init généré
deploy.sh                       # Pipeline complet (VM + Ansible)
infra/k8s_ansible/              # Playbooks et rôles Ansible
```

---

## 🔒 Sécurité

- Les clés SSH privées ne doivent jamais être versionnées.
- `inventory.ini` est généré et mis en permissions 0600.
- Pour Ansible Vault, configure ton mot de passe dans `~/.vault-pass.txt` (0600).

