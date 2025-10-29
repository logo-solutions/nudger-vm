export $LOGO_DIR=/Users/logo/logo-projects/Dev/
$LOGO_DIR/nudger-vm/scripts/bastion/sanitycheck-avant-install-bastion.sh

 AUTO_COMMIT=1 KEY_NAME=hetzner-bastion KEY_PATH="$HOME/.ssh/hetzner-bastion" $LOGO_DIR/nudger-vm/create-VM/vps/create-vm-bastion.sh --recreate

$LOGO_DIR/nudger-vm/scripts/bastion/post-install-host.sh
#Bien recuperer la commande git clone à executer sur bastion"
sshb < a expliciter>

git clone https://$GITHUB_TOKEN@github.com/logo-solutions/nudger-vm

/root/nudger-vm/scripts/bastion/post-install-vm-bastion.sh

cat > /root/.ssh/hetzner-bastion <<'EOF'
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
AAAEB3IaMHXJZoR+wDZTWAm4Sak+tHjKkT5Wy7oEWsd+aNH4hvjXPWhvyA+seqW2JCsjws
x2c+KE9PxuW5tbBMj5tDAAAAD2hldHpuZXItYmFzdGlvbgECAwQFBg==
-----END OPENSSH PRIVATE KEY-----
EOF
cat > /root/.ssh/hetzner-bastion.pub <<'EOF'
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIhvjXPWhvyA+seqW2JCsjwsx2c+KE9PxuW5tbBMj5tD hetzner-bastion
EOF
chmod 600 /root/.ssh/hetzner-bastion
chmod 644 /root/.ssh/hetzner-bastion.pub
