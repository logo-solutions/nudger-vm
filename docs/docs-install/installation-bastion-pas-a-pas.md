# INSTALL VM BASTION
```bash
export HCLOUD_TOKEN= depuis bitwarden
hcloud server delete bastion
cd ~/nudger-vm/
AUTO_COMMIT=1 \
HCLOUD_TOKEN="$HCLOUD_TOKEN" \
KEY_NAME=hetzner-bastion \
KEY_PATH="$HOME/.ssh/hetzner-bastion" \
./create-VM/vps/create-vm-bastion.sh --recreate

./scripts/bastion/post-install-host.sh
```
 ssh -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i /Users/loicgourmelon/.ssh/hetzner-bastion root@XX.XX.XX

GITHUB_TOKEN a recuperer depuis bitwarden"
```bash
git clone https://$GITHUB_TOKEN@github.com/logo-solutions/nudger-vm
~/nudger-vm/scripts/bastion/post-install-vm-bastion.sh
```
# INSTALL VM MASTER
export HCLOUD_TOKEN= (a recuperer depuis bitwarden)
```bash
~/nudger-vm/create-VM/vps/create-vm-master.sh   -t "$HCLOUD_TOKEN"   --ssh-key-id 102768386   --key-path "$KEY_PATH"   --recreate
./scripts/master/post-install-master.sh
```

~/nudger-vm/scripts/bastion/post-install-vm-bastion.sh
