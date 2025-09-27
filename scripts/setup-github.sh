#!/bin/bash

# Générer une clé SSH ed25519 avec ton email
ssh-keygen -t ed25519 -C "loicgourmelon@gmail.com" -f ~/.ssh/id_ed25519 -N ""

# Lancer l'agent SSH
eval "$(ssh-agent -s)"

# Ajouter la clé à l'agent
ssh-add ~/.ssh/id_ed25519

# Afficher la clé publique pour la copier sur GitHub
echo "----- COPIE LA CLE CI-DESSOUS DANS GITHUB (Settings > SSH and GPG keys) -----"
cat ~/.ssh/id_ed25519.pub
echo "----------------------------------------------------------------------------"

# Pause pour te laisser le temps de l'ajouter
echo  "Appuie sur [Entrée] après avoir ajouté la clé sur GitHub..."
read

# Cloner le repo via SSH
git clone git@github.com:loicgo29/nudger.git
# Se déplacer dans le repo cloné
cd nudger || exit
git config user.name "Loïc Gourmelon"
git config user.email "loicgourmelon@gmail.com"
