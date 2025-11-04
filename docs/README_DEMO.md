# 🚀 Déploiement complet de l’infrastructure Nudger

Ce guide décrit l’ensemble des étapes permettant de déployer l’infrastructure **Nudger**, depuis le poste hôte jusqu’à l’application XWiki fonctionnelle sur Kubernetes.

---

## 🖥️ 1. Configuration sur l’hôte local

### 📁 Préparation de l’environnement de travail
```bash
export LOGO_DIR=/Users/logo/logo-projects/Dev/
export LOGO_DIR=/Volumes/DevSSD/Dev
```

### 🔐 Authentification et récupération des secrets
```bash
bw login
export BW_SESSION=$(bw unlock --raw)
export HCLOUD_TOKEN=$(bw get item "token_hcloud_bastion" | jq -r '.login.password')
```

### 🧪 Vérification avant déploiement du bastion
```bash
$LOGO_DIR/nudger-vm/scripts/bastion/sanitycheck-avant-install-bastion.sh
```

### ⚙️ Création du bastion Hetzner
```bash
AUTO_COMMIT=1 KEY_NAME=hetzner-bastion KEY_PATH="$HOME/.ssh/hetzner-bastion" $LOGO_DIR/nudger-vm/create-VM/vps/create-vm-bastion.sh --recreate
```

### 🔧 Post-installation du bastion
```bash
$LOGO_DIR/nudger-vm/scripts/bastion/post-install-host.sh
```
💡 **Note :** Bien récupérer la commande `git clone` affichée à la fin du script pour l’exécuter sur le bastion.

### 🔗 Connexion SSH au bastion
```bash
ssh -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ~/.ssh/hetzner-bastion root@157.180.42.146
```

---

## 🧱 2. Configuration sur le Bastion

### 📥 Initialisation et installation d’Ansible
```bash
/root/nudger-vm/scripts/profile-bashrc/setup-bashrc.sh && exec bash -l
/root/nudger-vm/scripts/bastion/bootstrap-ansible-on-bastion.sh
/root/nudger-vm/scripts/bastion/configure-bastion-after-deploy.sh
bw login
export BW_SESSION=$(bw unlock --raw)
```

---

## 🧠 3. Déploiement du nœud Master Kubernetes

### 🏗️ Création du master
```bash
cd nudger-vm && /root/nudger-vm/create-VM/vps/create-vm-master.sh
ssh -i ~/.ssh/hetzner-bastion root@91.98.16.184 'bash -s' < ~/nudger-vm/scripts/master/bootstrap-ansible-control-plane.sh
/root/nudger-vm/scripts/master/configure-k8s-master.sh
```

---

## ☸️ 4. Installation des composants Kubernetes (Terraform)

### 📦 Local Path Provisioner
```bash
cd ~/nudger-infra/terraform/local-path/
terraform init
terraform plan
terraform apply --auto-approve
kubectl get all -n local-path-storage
```

### 🔒 Cert-Manager (core + issuer)
```bash
cd ~/nudger-infra/terraform/cert-manager-core/
terraform init && terraform apply --auto-approve
kubectl get all -n cert-manager

cd ~/nudger-infra/terraform/cert-manager-issuer/
terraform init
terraform plan   -var "email=loicgourmelon@gmail.com"   -var "dns_zone=logo-solutions.fr"   -var "cloudflare_api_token=$(bw get item token_cloudflare | jq -r .login.password)"

terraform apply -auto-approve   -var "email=loicgourmelon@gmail.com"   -var "dns_zone=logo-solutions.fr"   -var "cloudflare_api_token=$(bw get item token_cloudflare | jq -r .login.password)"

kubectl get all -n cert-manager
```

### 🌐 Ingress NGINX Controller
```bash
cd ~/nudger-infra/terraform/ingress-nginx/
terraform init && terraform apply --auto-approve
kubectl get all -n ingress-nginx
```

---

## ⚙️ 5. Déploiement du GitHub Actions Runner Controller (ARC)

### 📤 Récupération des secrets Bitwarden
```bash
cd ~/nudger-infra/arc/
export BW_SESSION=$(bw unlock --raw)
~/nudger-infra/arc/scripts/00_fetch_from_bw.sh
cat /etc/arc/arc_env.sh
```

### 🚀 Installation du contrôleur et des runners
```bash
./scripts/20_install_arc.sh
kubectl get all -n arc
kubectl get po -n arc -w
```

### ✅ Vérification de la connectivité GitHub
```bash
./scripts/35_verify_arc_github.sh
./scripts/36_verify_arc_full.sh
```

---

## 📦 6. Déploiement de l’application XWiki

### 🧱 Déploiement du namespace et des manifests
```bash
cd ~/nudger-infra/manifests/xwiki/
kubectl apply -k overlays/integration/
kubectl get all -n integration
kubectl get po -n integration -w
```

---

## 💾 7. Restauration de la base MySQL (si nécessaire)

### 📥 Déploiement et import
```bash
cd ~/nudger-infra/manifests/recovery_mysql/
kubectl create -f mysql-recovery-deployment.yaml
kubectl get po -n integration -l app=mysql -w
./import-mysql.sh
```

---

### ✨ Auteur : Thomas Toussaint  
*Documentation générée automatiquement — Infrastructure Nudger*

