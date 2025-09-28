# 🚀 Bootstrap Bastion VM avec Ansible & Vault

Ce guide décrit les étapes pour **créer et préparer le bastion** qui pilote ton cluster Kubernetes avec Ansible et Vault.

---

## 1. Créer la VM sur Hetzner

```bash
cd create-VM/vps
./create-vm.sh bastion
```

👉 Cela :  
- Supprime l’ancienne VM si elle existe.  
- Crée une nouvelle VM `bastion` (Ubuntu 22.04, type `cpx31`).  
- Attends que le SSH soit disponible.  
- Affiche l’IP de la VM.  

---

## 2. Préparer les secrets GitHub App

Copier la clé privée GitHub App sur la VM :

```bash
scp -i ~/.ssh/id_vm_ed25519   ~/Downloads/nudger-vm-003.2025-09-27.private-key.pem   root@$VM_IP:/etc/github-app/nudger-vm.private-key.pem

ssh -i ~/.ssh/id_vm_ed25519 root@$VM_IP   "chown root:root /etc/github-app/nudger-vm.private-key.pem && chmod 600 /etc/github-app/nudger-vm.private-key.pem"
```

---

## 3. Connexion au bastion

```bash
ssh -i ~/.ssh/id_vm_ed25519 root@$VM_IP
```

---

## 4. Cloner le repo Nudger

Depuis la VM :

```bash
git clone git@github.com:loicgo29/nudger-vm.git
cd nudger-vm/scripts/bastion
```

---

## 5. Installer Ansible et dépendances

```bash
./install-ansible.sh
```

👉 Ce script :  
- Met à jour le système.  
- Crée un virtualenv `~/ansible_venv`.  
- Installe **ansible-core**, `ansible-lint`, `kubernetes`, `openshift`, `pyyaml`, `passlib`.  
- Installe les collections : `kubernetes.core`, `ansible.posix`, `community.general`, `community.hashi_vault`.  
- Installe `fzf` et `lazygit`.  

---

## 6. Activer Ansible et exécuter les playbooks

```bash
source ~/ansible_venv/bin/activate
cd ~/nudger-vm/infra/k8s_ansible
ansible-playbook -i inventory.ini playbooks/bastion/001-setup-github-deploykey.yml
```

👉 Puis enchaîne avec :  
```bash
ansible-playbook -i inventory.ini playbooks/bastion/002-setup-github-app.yml
ansible-playbook -i inventory.ini playbooks/bastion/004-secure-ssh.yml
ansible-playbook -i inventory.ini playbooks/bastion/007-init-vault.yml
```

---

## 7. Vérifications

- `systemctl status vault` → doit être **active (running)**.  
- `vault status` → doit être **unsealed** et **initialized**.  
- `ls /etc/github-app/` → doit contenir `nudger-vm.private-key.pem`.  
- `ansible --version` → doit pointer sur le venv.  

---

✅ Ton bastion est prêt à piloter l’infra Kubernetes !

