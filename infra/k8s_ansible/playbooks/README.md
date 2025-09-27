# 🧭 Bootstrap GitOps / Flux — Guide d’exploitation (nudger)

Objectif : **raser la VM et remonter l’environnement** rapidement, de façon **idempotente**.
Ce README documente les playbooks et rôles Ansible listés par `scripts/cat.sh` et donne un **parcours recommandé** (install core, Kubernetes, Flux) + **pièges** à éviter.

> Style : franc, sans blabla. Les commandes sont prêtes à copier/coller.

---

## Sommaire

- [Pré-requis (poste d’admin)](#pré-requis-poste-dadmin)
- [Inventaire & variables](#inventaire--variables)
- [Parcours recommandé (from scratch)](#parcours-recommandé-from-scratch)
- [Playbooks disponibles](#playbooks-disponibles)
- [Rôles / stacks et incompatibilités](#rôles--stacks-et-incompatibilités)
- [FluxCD — Bootstrap “propre”](#fluxcd--bootstrap-propre)
- [Scaffold du dépôt GitOps](#scaffold-du-dépôt-gitops)
- [Utilisateurs & clones Git](#utilisateurs--clones-git)
- [Swap / conformité Kubernetes](#swap--conformité-kubernetes)
- [Vault — ⚠️ artefacts sensibles](#vault--️-artefacts-sensibles)
- [Dépannage rapide](#dépannage-rapide)

---

## Pré-requis (poste d’admin)

Sur ta machine d’orchestration (là où tu lances Ansible) :

```bash
# Python & Ansible
python3 --version
ansible --version

# Collections Ansible
cat > collections/requirements.yml <<'YAML'
---
collections:
  - name: kubernetes.core
  - name: community.general
YAML

ansible-galaxy collection install -r collections/requirements.yml

# Modules Python pour kubernetes.core (selon distro)
sudo apt-get install -y python3-kubernetes || true
```

**GitHub PAT ou clé SSH** : prépare **au moins une** méthode d’accès au repo GitOps live.

---

## Inventaire & variables

- **Inventaire** : groupe cible `k8s_masters` (ou `masters`, selon ton inventaire).
- **Variables globales** : `infra/k8s_ansible/group_vars/all.yml` (tu as déjà une version propre).
- **Secrets** : `group_vars/vault.yml` (non commité) — ex. `vault_github_pat`, clés SSH.

Extraits utiles attendus :

```yaml
# group_vars/all.yml (extraits)
kubeconfig_admin_path: "/etc/kubernetes/admin.conf"
kubeconfig: "/root/.kube/config"

flux_namespace: "flux-system"
flux_version: "2.3.0"
gitops:
  github_owner: "loicgo29"
  github_repo: "nudger-gitops"
  branch: "main"
  use_github_pat: true
  use_deploy_key: false

gitops_envs:
  - "lab"

github:
  pat: "{{ vault_github_pat | default('') }}"
  repo_ssh_url: "git@github.com:loicgo29/nudger-gitops.git"
  deploy_key_private: "{{ vault_git_deploy_key_private | default('') }}"
  deploy_key_public:  "{{ vault_git_deploy_key_public  | default('') }}"
```

---

## Parcours recommandé (from scratch)

> Ne mélange pas Docker **et** containerd. Choisis **une stack**.

1) **Bootstrap DevOps (outillage, sys basics)**
   ```bash
   ansible-playbook -i inventory.ini infra-devops.yml
   ```

2) **Kubernetes (runtime + kubeadm + CNI)**
   Tu as deux chemins selon tes rôles :
   - *Stack containerd* :
     ```bash
     ansible-playbook -i inventory.ini infra_containerd.yml
     ansible-playbook -i inventory.ini kubernetes-setup.yml
     ```
   - *Stack docker* (si tu assumes Docker, sinon **évite**) :
     ```bash
     ansible-playbook -i inventory.ini infra_docker.yml
     ansible-playbook -i inventory.ini kubernetes-setup.yml
     ```

3) **FluxCD (GitOps)**
   ```bash
   # Secrets fournis via group_vars/vault.yml
   ansible-playbook -i inventory.ini flux.yml
   ```

4) (Optionnel) **Helm stack** (ingress-nginx, cert-manager, etc.)
   ```bash
   ansible-playbook -i inventory.ini helm.yml
   ```

5) (Optionnel) **Users & clones Git**
   ```bash
   ansible-playbook -i inventory.ini setup-k8s-users.yml
   ```

---

## Playbooks disponibles

### `clone_repo_git.yml` (via `playbooks/users_and_git.yml`)
- Crée des **utilisateurs** + **groupes**.
- Installe **authorized_keys**, **known_hosts (github.com)**.
- Clone/pull les dépôts déclarés dans `users_k8s[*].git_repos` (dest, repo, branche).
- **Paramètres clés** : `shallow_clone`, `enforce_known_hosts`.

**Ex variable `users_k8s` :**
```yaml
users_k8s:
  - name: alice
    groups: [sudo]
    sudo_nopass: true
    ssh_public_key: "ssh-ed25519 AAAA... alice@host"
    git_repos:
      - { repo: "git@github.com:loicgo29/nudger.git", dest: "/home/alice/dev/nudger", version: "main" }
```

---

### `disable_swap.yml`
- Commente les entrées **swap** dans `/etc/fstab`.
- **swapoff -a** immédiat + service systemd pour désactiver au boot.
- Idempotent. Useful si tu ne le fais pas ailleurs.

> Remarque : `kubernetes-setup.yml` désactive déjà le swap. Évite le doublon.

---

### `setup-k8s-users.yml`
- Minimal : appelle le rôle `users-config`. À combiner avec `clone_repo_git.yml` selon ton flux.

---

### `flux.yml`
- **Le** playbook à garder pour GitOps. Appelle le rôle `flux_bootstrap` qui :
  - crée `flux-system`, installe Flux via `--export | kubectl apply -f -`,
  - configure le **secret Git** (PAT/SSH, idempotent),
  - crée la **GitRepository** `gitops` (branche `main`),
  - crée les **Kustomizations root** (ex : `cluster-lab` via `gitops_envs`),
  - **untaint** automatique si cluster **mono-nœud**,
  - fait les **reconcile** avec timeouts.

> Le vieux `gitops.yml` est gardé en **`gitops.yml.legacy`** : **ne l’utilise plus**.

---

### `infra_containerd.yml` / `infra_docker.yml`
- Choisis **une** seule stack de runtime.
- `containerd` recommandé pour K8s. `docker` seulement si besoin legacy.

---

### `nudger.yml` (site)
- Playbook “orchestrateur” : enchaîne bootstrap devops, Kubernetes, Vault, users.
- Pratique pour une **mise en place complète**. À adapter selon ce que tu veux inclure.

---

### `helm.yml`
- Déploie une “stack” Helm via un rôle `helm_stack` (ex : ingress-nginx, cert-manager).
- Bien, mais **optionnel** pour le bootstrap Flux. Pense à **pinner** les versions de charts.

---

### `bootstrap-devops.yml` / `infra-devops.yml`
- Prépare la VM (outillage de base, confort shell, etc.). Pas bloquant pour K8s.

---

### `infra_kubernetes.yml` / `kubernetes-setup.yml`
- Installe kubeadm/kubelet/kubectl, configure containerd ou docker, **désactive le swap**.
- CNI (Flannel/Calico) peut être installé depuis ces rôles (selon ton design).

---

### `vault-setup.yml`
- Installe et initialise **Vault**. Cf. section **Artefacts sensibles** ci-dessous.

---

### `gitops_scaffold.yml`
- Génère l’**arborescence** du repo GitOps (clusters/…, apps/…) côté **localhost**.
- Utile pour démarrer un dépôt vide propre, sans bricolage.

---

## Rôles / stacks et incompatibilités

- `containerd` **ou** `docker` — **pas les deux**.
- `flux_bootstrap` est la **référence** pour l’installation Flux (ne double pas avec `gitops.yml.legacy`).
- Les rôles Kubernetes doivent être cohérents sur :
  - version K8s (`k8s_version`, `kubectl_version`),
  - CNI (Flannel: `pod_network_cidr`),
  - swap **off**,
  - mono-nœud : **untaint** control-plane si nécessaire.

---

## FluxCD — Bootstrap “propre”

**Commande unique :**
```bash
ansible-playbook -i inventory.ini flux.yml
```

**Ce que ça fait (rôle `flux_bootstrap`) :**
- Installe le **CLI flux** (pinné) et applique les manifests avec `--export` (idempotent).
- Crée le secret git **HTTPS+PAT** *ou* **SSH** (au choix).
- Crée `GitRepository/gitops` → `https://github.com/loicgo29/nudger-gitops.git` (branche `main`).
- Crée une **Kustomization root par env** (ex : `lab`) pointant `./clusters/<env>`, `timeout: 5m`.
- `reconcile` source + kustomizations.

**Sanity checks :**
```bash
flux check
kubectl -n flux-system get deploy
flux -n flux-system get sources git
flux -n flux-system get kustomizations
flux -n flux-system tree kustomization cluster-lab
```

**Reconcile manuel (après un git push)** :
```bash
flux -n flux-system reconcile kustomization cluster-lab --with-source --timeout=5m
```

---

## Scaffold du dépôt GitOps

Si ton repo `nudger-gitops` est vide :
```bash
ansible-playbook gitops_scaffold.yml
# ou fais-le à la main :
# clusters/lab/kustomization.yaml → références vers tes apps de base
```

**Règle d’or Kustomize** : **un seul** fichier `kustomization.yaml` par dossier.

---

## Utilisateurs & clones Git

```bash
ansible-playbook -i inventory.ini setup-k8s-users.yml
# puis éventuellement
ansible-playbook -i inventory.ini clone_repo_git.yml
```

- `clone_repo_git.yml` gère `authorized_keys`, `known_hosts`, `git clone/pull` par utilisateur.
- Active le **ForwardAgent** si tu utilises tes clés locales.

---

## Swap / conformité Kubernetes

Tu as deux playbooks qui touchent au swap : `disable_swap.yml` et la logique dans `kubernetes-setup.yml`.
**Choisis-en un**. Le plus simple : **laisse `kubernetes-setup.yml` faire** et ne lance pas `disable_swap.yml` à côté, pour éviter les surprises.

---

## Vault — ⚠️ artefacts sensibles

`artifacts/master1/vault-init.json` contient des **clés d’unseal** et un **root_token**.
**C’est du secret en clair.** À **ne jamais** committer côté public ni copier sur une autre machine.

- Stocke-le dans un coffre (1Password/Bitwarden/Vault…).
- Regénère des secrets si ce fichier a fuité.

---

## Dépannage rapide

- **Flux bloque / “context deadline exceeded”**
  → `spec.timeout: "5m"` dans la Kustomization + `--timeout=5m` côté CLI.

- **“Found multiple kustomization files”**
  → garde **un seul** `kustomization.yaml` par dossier (supprime `Kustomization`, `.yml`, etc.).

- **Repo GitOps “empty” / “path not found”**
  → pousse au moins une `kustomization.yaml` sous `clusters/<env>` et relance :
  ```bash
  flux -n flux-system reconcile source git gitops && \
  flux -n flux-system reconcile kustomization cluster-lab
  ```

- **Mono-nœud ⇒ Pods Pending**
  → dé-taint control-plane :
  ```bash
  kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true
  ```

- **Secrets Git**
  → PAT : vérifier `github.pat` côté `group_vars/vault.yml`.
  → SSH : clés déployées + `known_hosts` (github.com).

---

## TL;DR

1. `ansible-playbook infra-devops.yml`
2. `ansible-playbook infra_containerd.yml` **puis** `ansible-playbook kubernetes-setup.yml`
3. `ansible-playbook -i inventory.ini flux.yml`
4. `flux -n flux-system tree kustomization cluster-lab`

Tu veux faire plus propre ensuite (TLS, ingress, charts pinnés) ? ajoute `helm.yml` quand prêt.
