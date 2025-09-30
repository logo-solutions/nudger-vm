# INSTALL VM BASTION

```bash
cd ~/nudger-vm/
FIREWALL_ENABLE=0 HZ_KEY_NAME=hetzner-bastion SSH_KEY_FILE=$HOME/.ssh/hetzner-bastion ./create-VM/vps/create-vm-bastion.sh bastion
./scripts/bastion/post-install-host.sh

👉 Connecte-toi ensuite : ssh -i ~/.ssh/id_vm_ed25519 root@XX.XX.XX
```

ssh -i ~/.ssh/id_vm_ed25519 root@XX.XX.XX
GITHUB_TOKEN a recuperer depuis bitwarden"
GITHUB_TOKEN=
```bash
git clone https://$GITHUB_TOKEN@github.com/logo-solutions/nudger-vm
~/nudger-vm/scripts/bastion/post-install-vm-bastion.sh
```

# INSTALL VM MASTER
export HCLOUD_TOKEN= (a recuperer depuis bitwarden)
```bash
./create-VM/vps/create-vm-master.sh -t "$HCLOUD_TOKEN" --ssh-key-id 102768386
./scripts/master/post-install-master.sh
```


