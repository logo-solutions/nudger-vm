a# Rôle Ansible : users-config

Rôle Ansible pour **créer/configurer des comptes “K8s/dev”** sur des hôtes, déployer leurs clés SSH, préparer l’environnement (kubeconfig, complétion, alias), et **cloner des dépôts Git privés** via une **deploy key** chiffrée avec **Ansible Vault**.

---

## Ce que fait le rôle (ordre d’exécution)

1. Crée les **groupes** nécessaires (déduits de `users_k8s[].groups`).
2. Crée les **utilisateurs** (shell bash, home).
3. Optionnel : **sudo NOPASSWD** par utilisateur (`sudo_nopass: true`).
4. Prépare `~/.ssh` et installe les **authorized_keys** (clé unique `ssh_public_key` ou liste `ssh_public_keys`).
5. Prépare `~/.kube/config` (copie depuis `kubeconfig` ou `kubeconfig_src`, ou rendu d’un template si `kubeconfig_template: true`) et exporte `KUBECONFIG` dans `.bashrc`.
6. Déploie un fichier d’**alias bash** et s’assure qu’il est sourcé.
7. Active la **complétion kubectl** (si `kubectl` est présent sur l’hôte).
8. Crée `~/bin` et, si demandé, **symlink** des outils existants (`tools_symlinks`).
9. Installe **git**.
10. Ajoute **github.com** dans `known_hosts` pour chaque user (via `ssh-keyscan`).
11. **Copie la deploy key** chiffrée (**Vault**) vers `~/.ssh/id_deploy_nudger` (`0600`).
12. **Clone/Met à jour** les repos déclarés pour chaque user, via `key_file`.

---

## Variables attendues (exemples)

Fichier : `group_vars/k8s_masters.yml` (ou équivalent)

```yaml
users_k8s:
  - name: kubernetes-admin
    groups: [sudo]
    ssh_public_key: "{{ lookup('file', '~/.ssh/id_vm_ed25519.pub') }}"
    kubeconfig: /etc/kubernetes/admin.conf
    git_repos:
      - repo: git@github.com:loicgo29/nudger.git
        dest: /home/kubernetes-admin/nudger
        # optionnels :
        # version: main
        # shallow: true
        # submodules: true

  - name: dev-loic
    groups: [sudo, docker]
    sudo_nopass: true
    ssh_public_key: "{{ lookup('file', '~/.ssh/id_vm_ed25519.pub') }}"
    kubeconfig: /home/kubernetes-admin/.kube/config
    git_repos:
      - repo: git@github.com:loicgo29/nudger.git
        dest: /home/dev-loic/nudger

# Options (facultatives)
bash_aliases_enable: true
bash_aliases_file: .bash_aliases
bashrc_file: .bashrc
kubectl_completion_enable: true
git_known_hosts_enable: true

# Symlinks d’outils existants sur l’hôte (facultatif)
tools_symlinks:
  - { name: kubectl, src: /usr/bin/kubectl }
  - { name: helm,    src: /usr/local/bin/helm }
```

---

## Secret requis : deploy key GitHub (via Ansible Vault)

Le rôle attend un **fichier vaulté** :

```
roles/users-config/files/id_deploy_nudger
```

- Contenu : **clé privée OpenSSH** (associée à la *Deploy key* **read‑only** du repo GitHub).
- Format : fichier **chiffré** Ansible Vault (en‑tête `$ANSIBLE_VAULT;1.1;AES256`).
- Déploiement : tâche `copy` avec `decrypt: yes` + permissions `0600`.

### Création & ajout de la deploy key

```bash
# Générer une paire locale
ssh-keygen -t ed25519 -f /tmp/id_deploy_nudger -N "" -C "ansible-deploy-nudger"

# Ajouter la PUBLIC (.pub) sur GitHub → Settings > Deploy keys (Read-only)
gh repo deploy-key add /tmp/id_deploy_nudger.pub --repo <owner>/<repo>

# Chiffrer la PRIVÉE comme fichier du rôle
mkdir -p roles/users-config/files
cp /tmp/id_deploy_nudger roles/users-config/files/id_deploy_nudger
ansible-vault encrypt roles/users-config/files/id_deploy_nudger
```

Configurer le chargement du Vault :

```ini
# ansible.cfg
[defaults]
vault_identity_list = default@.vault_pass.txt
```

---

## Prérequis

- `ansible`/`ansible-core` compatible (modules/builtin, filtre `subelements`).
- Sur les hôtes : `kubectl` présent si `kubectl_completion_enable: true`.
- Accès SSH sortant vers GitHub.
- Deploy key **publique** ajoutée sur le repo GitHub ciblé.

---

## Utilisation

Playbook minimal :

```yaml
# playbooks/setup-k8s-users.yml
- name: Setup Kubernetes users and dev environment
  hosts: k8s_masters
  become: true
  roles:
    - role: users-config
```

Commande :

```bash
ansible-playbook -i inventory.ini playbooks/setup-k8s-users.yml
# ou (si ansible.cfg non configuré) :
# ansible-playbook -i inventory.ini playbooks/setup-k8s-users.yml --vault-id default@.vault_pass.txt
```

---

## Idempotence

- Les tâches sont **idempotentes**.
- La tâche Git fera un **pull** si l’upstream a bougé → `changed` attendu.

---

## Dépannage

**`Permission denied (publickey)` lors du clone**
- Vérifier que `~/.ssh/id_deploy_nudger` existe (par user), en `0600`, commence par `-----BEGIN OPENSSH PRIVATE KEY-----`.
- Tester côté hôte :
  ```bash
  sudo -u <user> -H ssh -i ~/.ssh/id_deploy_nudger -T git@github.com
  ```
- S’assurer que la **clé publique** correspondante est bien une **Deploy key** du repo.

**`Attempting to decrypt but no vault secrets found`**
- Oubli de `--vault-id` / pas de `vault_identity_list` dans `ansible.cfg`.

**Complétion kubectl**
- Mettre `kubectl_completion_enable: false` si `kubectl` absent sur l’hôte.

**Prompt fingerprint GitHub**
- Laissez `git_known_hosts_enable: true` (ou gardez `accept_newhostkey: true` dans la tâche `git`).

---

## Sécurité

- La **clé privée** est **vaultée**, déployée en `0600`.
- **Ne committez jamais** d’artefacts sensibles (tokens Vault, unseal,
  `vault-init.json`, etc.).
- Ajoutez au `.gitignore` :
  ```
  infra/k8s_ansible/playbooks/artifacts/
  *vault-init*.json
  *.unseal
  ```

---

## Critique du fichier actuel (à corriger)

- **Doublons à supprimer :**
  - Tâche « Ajouter github.com au known_hosts de chaque user » (présente 2×).
  - Tâche « Install per-user deploy key for GitHub (from vaulted file) » (présente 2×).

Passez un `ansible-lint` pour détecter ces redondances.

---

## Astuces utiles

Pour que `git pull` en shell utilise la deploy key par défaut :

```yaml
- name: SSH config pour GitHub (IdentityFile)
  ansible.builtin.blockinfile:
    path: "/home/{{ item.name }}/.ssh/config"
    create: true
    owner: "{{ item.name }}"
    group: "{{ item.name }}"
    mode: '0600'
    block: |
      Host github.com
        HostName github.com
        User git
        IdentityFile ~/.ssh/id_deploy_nudger
        IdentitiesOnly yes
  loop: "{{ users_k8s }}"
  become: true
```

Lister les tags / tâches :

```bash
ansible-playbook -i inventory.ini playbooks/setup-k8s-users.yml --list-tags
ansible-playbook -i inventory.ini playbooks/setup-k8s-users.yml --list-tasks
```
