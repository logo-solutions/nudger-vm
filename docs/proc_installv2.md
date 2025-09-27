/home/nudger-k8s/nudger/create-VM/vps/create-vm.sh nudger-k8s https://github.com/loicgo29/nudger.git nudger-vm-k8s-0 id_vm_ed25519
su - nudger-k8s
cd nudger
 ./config-vm/install_all_devops.sh
./config-vm/setup_ssh_ansible.sh
source ~/ansible_venv/bin/activate


Pour générer ton mot de passe hashé (mode Linux standard) :
# avec openssl
openssl passwd -6

A date : Processes
