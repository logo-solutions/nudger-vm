# INSTALL VM BASTION

```bash
cd ~/nudger-vm/
./create-VM/vps/create-vm-bastion.sh
```
## Output
```bash
❯ ./create-vm-bastion.sh
 ✓ Waiting for delete_server       100% 11s (server: 109829082)
Server bastion deleted
Waiting for create_server (server: 109866929, image: 67794396) ...
Waiting for start_server (server: 109866929) ...
Waiting for create_server (server: 109866929, image: 67794396) ... done
Waiting for start_server (server: 109866929) ... done
✅ VM bastion IP: 65.109.12.160
Connection to 65.109.12.160 port 22 [tcp/ssh] succeeded!
✅ SSH up
👉 Mise à jour de /Users/loicgourmelon/logo-projects/nudger-vm/infra/k8s_ansible/inventory.ini
✅ Inventaire mis à jour
👉 Test SSH: ssh -i ~/.ssh/id_vm_ed25519 root@65.109.12.160
👉 Test Ansible: ansible -i /Users/loicgourmelon/logo-projects/nudger-vm/infra/k8s_ansible/inventory.ini bastion_host -m ping
```

```bash
 ./scripts/bastion/post-install-host.sh
```
## output
```bash
👉 Préparation côté hôte pour root@65.109.12.160
The authenticity of host '65.109.12.160 (65.109.12.160)' can't be established.
ED25519 key fingerprint is SHA256:k8G8g6BYtaSBcJ0lwJQptOMK17wXdYB3wt/ex6HP02U.
This key is not known by any other names.
Are you sure you want to continue connecting (yes/no/[fingerprint])? yes
Warning: Permanently added '65.109.12.160' (ED25519) to the list of known hosts.
nudger-vm-003.2025-09-27.private-key.pem                                          100% 1675    29.7KB/s   00:00
✅ Clé GitHub App déployée.

👉 Connecte-toi ensuite : ssh -i ~/.ssh/id_vm_ed25519 root@65.109.12.160
Puis lance : ~/nudger-vm/scripts/post-install-vm.sh
  │  ~/l/nudger-vm │   main !3 ?1
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
```


