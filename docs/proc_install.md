# Nudger Infrastructure Toolkit

## Structure de l'Arborescence

nudger/
├── config-vm/ # Scripts de configuration de base
│ ├── profile_logo.sh # Personnalisation du shell
│ ├── ansible-setup.sh.old # Ancienne version du setup Ansible
│ ├── setup_ssh_ansible.sh # Configuration SSH pour Ansible
│ └── install_all_devops.sh # Installation des outils DevOps
│
├── infra/ # Infrastructure Kubernetes
│ └── k8s-ansible/
│ ├── ansible.cfg # Configuration Ansible
│ ├── inventory.ini # Inventaire des hôtes
│ ├── requirements.yml # Dépendances Ansible
│ │
│ ├── playbooks/ # Playbooks principaux
│ │ ├── kubernetes-setup.yml
│ │ └── disable_swap.yml
│ │
│ └── roles/ # Rôles Ansible
│ ├── common/ # Configuration commune
│ ├── containerd/ # Runtime de conteneurs
│ │ ├── handlers/
│ │ ├── templates/config.toml.j2
│ │ └── tasks/main.yml
│ ├── docker/ # Installation Docker
│ ├── kubernetes/ # Cluster K8s
│ └── flannel/ # Networking
│
└── vagrant/ # Environnements Vagrant
├── Vagrantfile # Définition des VMs
├── scripts/ # Scripts de provisionnement
└── provision.yml # Playbook de provisionnement


## Utilisation

###  Provisionnement avec Vagrant
```bash
cd nudger/vagrant
stopvagrant.sh
vagrant up  # Démarre les machines virtuelles
vagrant provision  # Applique la configuration
```

### clone github
# Générer une clé SSH ed25519 avec ton email
```bash
ssh-keygen -t ed25519 -C "loicgourmelon@gmail.com" -f ~/.ssh/id_ed25519 -N ""
# Lancer l'agent SSH
eval "$(ssh-agent -s)"
# Ajouter la clé à l'agent
ssh-add ~/.ssh/id_ed25519
# Afficher la clé publique pour la copier sur GitHub
echo "----- COPIE LA CLE CI-DESSOUS DANS GITHUB (Settings > SSH and GPG keys) -----"
cat ~/.ssh/id_ed25519.pub
```

# Pause pour te laisser le temps de l'ajouter dans github

### Cloner le repo via SSH
```bash
git clone git@github.com:loicgo29/nudger.git
# Se déplacer dans le repo cloné
cd nudger || exit
git config user.name "Loïc Gourmelon"
git config user.email "loicgourmelon@gmail.com"
git branch -a
echo "git checkout -b fix/15082025"
echo "git pull origin fix/15082025-2OK"
echo "git push -u origin fix/15082025"
echo "git branch --set-upstream-to=origin/fix/16082025 fix/16082025"

```

### configuration de la VM
cd config-vm
./setup_ssh_ansible.sh
./install_all_devops.sh

### install profile LOGO
source ~/ansible_venv/bin/activate
profile_logo.sh

### installation de l'infra
cd nudger/infra/k8s-ansible
ansible-playbook -i inventory.ini playbooks/kubernetes-setup.yml

### patcher br si reboot
./patch1.sh

### creer directory pour stockage des pv
sudo mkdir -p /data/xwiki /data/mysql
sudo chmod 777 /data/xwiki /data/mysql
