# 🚀 Installation & Configuration Ansible Vault + Deploy Key GitHub

## 1. Créer un fichier de mot de passe pour Ansible Vault
Le fichier `.vault_pass.txt` contient le mot de passe maître de Vault (ici `nudgervault`).

```bash
echo "password-de-vault" > .vault_pass.txt
chmod 600 .vault_pass.txt
```

⚠️ Ne versionne **jamais** `.vault_pass.txt` dans Git.

---

## 2. Créer le fichier de variables chiffrées
On va stocker les secrets dans `group_vars/vault.yml`.

```bash
ansible-vault create group_vars/vault.yml   --vault-password-file .vault_pass.txt   --encrypt-vault-id default
```

Ajoute ton secret GitHub Personal Access Token (PAT) dedans :
il est créee sous github > setting > developpeur settings > create PAT > cocher repo

```yaml
vault_github_pat: ghp_VN3tsbK5LsMEfYrULWKO3dddddJddddd---------
```

---

## 3. Générer une paire de clés SSH (Deploy Key)
On crée une clé SSH spécifique au déploiement.

```bash
ssh-keygen -t ed25519 -f id_deploy_nudger -C "flux-deploy-key" -N ""
```

- `-t ed25519` : plus moderne et sécurisé que RSA
- `-f id_deploy_nudger` : nom de fichier
- `-C` : commentaire (optionnel)
- `-N ""` : pas de passphrase (sinon l’automatisation bloque)

Résultat :
- `id_deploy_nudger` → **clé privée**
- `id_deploy_nudger.pub` → **clé publique**

---

## 4. Vérifier les fichiers
```bash
ls -l id_deploy_nudger*
```

Tu dois voir deux fichiers.

---

## 5. Chiffrer la clé privée avec Vault (optionnel mais conseillé)
Seule la **clé privée** est chiffrée, **pas** la `.pub`.

```bash
ansible-vault encrypt id_deploy_nudger   --vault-password-file PATH/.vault_pass.txt   --encrypt-vault-id default
```

---

## 6. Ajouter la clé publique sur GitHub (Deploy Key)
1. Va dans ton repo → **Settings** → **Deploy Keys**
2. Clique **Add deploy key**
   - Name : `flux-deploy-key`
   - Copie-colle le contenu de :
     ```bash
     cat id_deploy_nudger.pub
     ```
   - Si tu veux **push** avec cette clé → coche “Allow write access”.
   - Sinon laisse décoché (pull-only).

---

## 7. Copier les clés dans ton rôle Ansible
Place les fichiers dans `roles/users-config/files/` :

```bash
cp id_deploy_nudger* roles/users-config/files/
```

Dans ton rôle `users-config`, tu pourras ensuite distribuer la clé privée (vaultée) et la publique sur la machine cible.

---

✅ À ce stade :
- Tu as un mot de passe Vault centralisé (`.vault_pass.txt`).
- Tu as un fichier `group_vars/vault.yml` chiffré avec tes secrets.
- Tu as une paire de clés SSH (`id_deploy_nudger` + `.pub`).
- La clé privée est chiffrée avec Vault, la publique ajoutée sur GitHub.
- Les deux fichiers sont copiés dans `roles/users-config/files/` pour être provisionnés.
