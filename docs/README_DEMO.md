######## HOTE ###########
export $LOGO_DIR=/Users/logo/logo-projects/Dev/
$LOGO_DIR/nudger-vm/scripts/bastion/sanitycheck-avant-install-bastion.sh
export BW_SESSION=$(bw unlock --raw)

 AUTO_COMMIT=1 KEY_NAME=hetzner-bastion KEY_PATH="$HOME/.ssh/hetzner-bastion" $LOGO_DIR/nudger-vm/create-VM/vps/create-vm-bastion.sh --recreate

$LOGO_DIR/nudger-vm/scripts/bastion/post-install-host.sh
#Bien recuperer la commande git clone à executer sur bastion"

ssh -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ~/.ssh/hetzner-bastion root@157.180.42.146

######## BASTION  ###########
# lancer le git clone avec la sortie du script précedent
/root/nudger-vm/scripts/bastion/post-install-vm-bastion.sh
/root/nudger-vm/scripts/profile-bashrc/setup-bashrc.sh
exec bash -l


