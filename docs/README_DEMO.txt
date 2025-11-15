######## HOTE ###########
export LOGO_DIR=/Users/logo/logo-projects/Dev/
export LOGO_DIR=/Volumes/DevSSD/Dev

bw login
export BW_SESSION=$(bw unlock --raw)
export HCLOUD_TOKEN=$(bw get item "token_hcloud_bastion" | jq -r '.login.password')
$LOGO_DIR/nudger-vm/scripts/bastion/sanitycheck-avant-install-bastion.sh

AUTO_COMMIT=1 KEY_NAME=hetzner-bastion KEY_PATH="$HOME/.ssh/hetzner-bastion" $LOGO_DIR/nudger-vm/create-VM/vps/create-vm-bastion.sh --recreate

$LOGO_DIR/nudger-vm/scripts/bastion/post-install-host.sh
#Bien recuperer la commande git clone à executer sur bastion"

ssh -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ~/.ssh/hetzner-bastion root@157.180.42.146

######## BASTION  ###########
# lancer le git clone avec la sortie du script précedent
/root/nudger-vm/scripts/profile-bashrc/setup-bashrc.sh && exec bash -l
/root/nudger-vm/scripts/bastion/bootstrap-ansible-on-bastion.sh
/root/nudger-vm/scripts/bastion/configure-bastion-after-deploy.sh
bw login
export BW_SESSION=$(bw unlock --raw)
######## MASTER ###################
cd nudger-vm && /root/nudger-vm/create-VM/vps/create-vm-master.sh 
ssh -i ~/.ssh/hetzner-bastion root@91.98.16.184 'bash -s' < ~/nudger-vm/scripts/master/bootstrap-ansible-control-plane.sh
/root/nudger-vm/scripts/master/configure-k8s-master.sh
######## APP sur MASTER ###################
cd  ~/nudger-infra/terraform/ && ls
cd  ~/nudger-infra/terraform/local-path/
terraform init
terraform plan
terraform apply --auto-approve
kubectl get all -n local-path-storage

cd  ~/nudger-infra/terraform/cert-manager-core/ && ls
terraform init
terraform plan
terraform apply --auto-approve
 k get all -n cert-manager
 cd  ~/nudger-infra/terraform/cert-manager-issuer/ && ls
terraform init
terraform plan\
  -var "email=loicgourmelon@gmail.com" \
  -var "dns_zone=logo-solutions.fr" \
  -var "cloudflare_api_token=$(bw get item token_cloudflare | jq -r .login.password)"
terraform apply -auto-approve \
  -var "email=loicgourmelon@gmail.com" \
  -var "dns_zone=logo-solutions.fr" \
  -var "cloudflare_api_token=$(bw get item token_cloudflare | jq -r .login.password)"
k get all -n cert-manager

cd ~/nudger-infra/terraform/ingress-nginx && ls
terraform init
terraform plan
terraform apply --auto-approve
k get all -n ingress-nginx

cd ~/nudger-infra/arc && ls
ls ~/nudger-infra/arc/scripts/ 
export BW_SESSION=$(bw unlock --raw)
 ~/nudger-infra/arc/scripts/00_fetch_from_bw.sh
cat /etc/arc/arc_env.sh
./scripts/20_install_arc.sh
k get all -n arc
k get po -n arc -w
./scripts/35_verify_arc_github.sh
./scripts/36_verify_arc_full.sh

cd  ~/nudger-infra/manifests && ls
cd ~/nudger-infra/manifests/xwiki && ls
ls base/
 ls overlays/
 ls overlays/integration/
 k apply -k overlays/integration/
 k get all -n integration
k get po -n integration -w

cd ~/nudger-infra/manifests/recovery_mysql && ls
k create -f mysql-recovery-deployment.yaml
k get po -n integration -l app=mysql -w
 ./import-mysql.sh

