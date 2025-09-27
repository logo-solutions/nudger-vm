# Rôle / Tâches Ansible – Installation & Bootstrap de HashiCorp Vault

Ce fichier documente un bloc de tâches Ansible pour **installer**, **configurer**, **initialiser**, **dé-scelller** et **activer KV v2** sur HashiCorp Vault, puis **rapatrier l’artefact d’initialisation** côté contrôleur.

> Ton objectif : un Vault **up** sous systemd, initialisé (shares `1`/threshold `1`), *unsealed* si nécessaire, avec le moteur **KV v2** actif sur `secret/` et un **artefact d’init** stocké **en local contrôleur** (à ne jamais versionner).

---

## Ce que font les tâches (ordre logique)

1. **Pré-requis système**
   - Installe `unzip` et `curl` via `apt`.
   - Crée l’utilisateur système `vault_user` (shell `nologin`).

2. **Installation binaire**
   - Télécharge Vault `vault_version` depuis `releases.hashicorp.com`.
   - Décompresse vers `/usr/local/bin/` (ou via `vault_bin`).

3. **Structure & configuration**
   - Crée les répertoires `vault_data_dir` et `vault_config_dir` (owner `vault_user:vault_group`).
   - Déploie `vault.hcl` depuis `vault.hcl.j2` (dans `vault_config_dir`).

4. **Service systemd**
   - Crée `/etc/systemd/system/vault.service` (ExecStart: `vault server -config=...`).
   - `daemon-reload`, puis **enable + start** du service.

5. **Attente d’écoute**
   - Attend `127.0.0.1:8200` (port par défaut) jusqu’à 30s.

6. **Statut / Initialisation**
   - Appelle `vault status -format=json` → parse JSON.
   - Si **non initialisé** → `vault operator init -key-shares=1 -key-threshold=1 -format=json` (⚠️ dev-only).
   - Sauvegarde l’**output d’init** sur la **cible**: `/etc/vault/.vault_initialized` (0600).

7. **Chargement des secrets d’init**
   - Si pas d’init en mémoire, lit le fichier via `slurp`.
   - Définit les facts :
     - `vault_root_token`
     - `vault_unseal_key` (1ère clé Base64)
   - Échoue si Vault est **sealed** et qu’aucune **unseal key** n’est disponible.

8. **Unseal conditionnel**
   - Si `sealed: true` et `vault_unseal_key` dispo → `vault operator unseal <key>`.
   - Re-vérifie le statut et échoue si toujours scellé.

9. **Artefacts (contrôleur)**
   - Crée localement (sur le **contrôleur**) `~/.ansible/artifacts/<inventory_hostname>/`.
   - **Fetch** du fichier `/etc/vault/.vault_initialized` vers le contrôleur (`vault-init.json`).

10. **Secrets Engine**
    - Active **KV v2** sur `path=secret/` via `vault secrets enable -path=secret kv-v2` (auth: `VAULT_TOKEN: vault_root_token`).
    - Crée un **flag** `/tmp/kv2_enabled.flag` (idempotence “soft”).

---

## Variables attendues

| Variable              | Type / Exemple                                        | Rôle |
|----------------------|---------------------------------------------------------|------|
| `vault_user`         | `vault`                                                | Utilisateur système propriétaire des fichiers/dirs |
| `vault_group`        | `vault`                                                | Groupe associé |
| `vault_version`      | `1.17.3`                                               | Version à télécharger |
| `vault_bin`          | `/usr/local/bin/vault`                                 | Chemin du binaire (idempotence `unarchive.creates`) |
| `vault_data_dir`     | `/var/lib/vault`                                       | Données Vault |
| `vault_config_dir`   | `/etc/vault`                                           | Configurations (`vault.hcl`) |
| `vault_addr`         | `http://127.0.0.1:8200` (par défaut)                   | Adresse d’API utilisée par les commandes |
| `inventory_hostname` | fournie par Ansible                                    | Nom de la cible (pour le chemin d’artefacts côté contrôleur) |

> Le template `vault.hcl.j2` **doit** exposer au moins `listener`, `storage`, etc. et pointer vers `vault_data_dir`/`vault_config_dir` selon ton design.

---

## Fichiers créés / modifiés

**Sur la cible (serveur)** :
- `{{ vault_bin }}` (ex: `/usr/local/bin/vault`) – binaire Vault
- `{{ vault_config_dir }}/vault.hcl` – config rendue
- `/etc/systemd/system/vault.service` – unit file
- `{{ vault_data_dir }}` (ex: `/var/lib/vault`) – données
- `{{ vault_config_dir }}` (ex: `/etc/vault`) – config + **.vault_initialized** (0600)
- `/tmp/kv2_enabled.flag` – simple témoin d’activation KV v2

**Sur le contrôleur (ta machine Ansible)** :
- `~/.ansible/artifacts/{{ inventory_hostname }}/vault-init.json` – **artefact sensible** contenant *root token + unseal key(s)*

> **N’ajoute jamais** ces artefacts dans un dépôt Git. Ajoute un `.gitignore` strict (voir “Sécurité”).

---

## Pré-requis

- Distribution Debian/Ubuntu (utilise `apt`).
- Accès internet sortant vers `releases.hashicorp.com`.
- `systemd` disponible et opérationnel.
- Port `8200` libre en écoute locale (ou adapte `vault_addr` et `vault.hcl`).

---

## Utilisation (exemple de playbook)

```yaml
- name: Install & bootstrap Vault
  hosts: vault_nodes
  become: true
  vars:
    vault_user: vault
    vault_group: vault
    vault_version: "1.17.3"
    vault_bin: /usr/local/bin/vault
    vault_data_dir: /var/lib/vault
    vault_config_dir: /etc/vault
    vault_addr: "http://127.0.0.1:8200"
  tasks:
    # (colle ici le bloc de tâches fourni)
```

Après run, tu peux valider côté cible :
```bash
systemctl status vault --no-pager
curl -s http://127.0.0.1:8200/v1/sys/health | jq .   # si listener HTTP local autorisé
```

---

## Idempotence & logique conditionnelle

- `unarchive.creates: {{ vault_bin }}` évite de ré-extraire si le binaire est présent.
- `status/init/unseal` : ne **(ré-)init** que si `initialized == false`; *unseal* seulement si `sealed == true` et une clé est disponible.
- Activation **KV v2** tolère “path is already in use” et considère `success` comme `changed`.
- Le `flag` `/tmp/kv2_enabled.flag` n’est qu’un garde-fou “local” (non contractuel).

---

## Sécurité (cash)

- **Danger PRODUCTION** : `key-shares=1` & `key-threshold=1` ⇒ **anti-pattern** en prod. Utilise **≥ 3 shares** et un **threshold ≥ 2**.
- L’artefact `/etc/vault/.vault_initialized` **contient** le *root token* et les *unseal keys*. Il est copié côté **contrôleur**. **Ne le versionne pas**.
- Ajoute à ton `.gitignore` **du repo d’infra** :
  ```gitignore
  .ansible/
  **/.ansible/
  **/artifacts/
  *vault-init*.json
  *.unseal
  ```
- Si ces secrets ont fuité, **révoque** le *root token* et **re-key** les *unseal keys* (`vault operator rekey`).

---

## Dépannage

- **`vault status` échoue / timeouts** : vérifie le service systemd, les logs (`journalctl -u vault`), le listener dans `vault.hcl`, le port/pare-feu.
- **Toujours scellé** après unseal : mauvais `unseal_key` ou `key-threshold` non satisfait.
- **KV v2** : si l’activation renvoie “path already in use”, c’est OK si c’est `kv-v2`. Pour vérifier : `vault secrets list -detailed`.
- **Artefact non rapatrié** : assure-toi que la condition `when` est vraie (init en mémoire **ou** fichier `.vault_initialized` présent) et que le répertoire côté contrôleur est accessible.

---

## Choix techniques (et ce que tu peux challenger)

- **Stockage artefact côté cible + fetch contrôleur** : OK pour bootstrap, mais risqué. Alternative : **ne conserve rien** côté cible après rotation des secrets.
- **Listener 127.0.0.1** par défaut : simple pour single-node. Pour HA/remote clients, revois `vault.hcl` (TLS, mTLS, storage backend, etc.).
- **systemd unit minimaliste** : ajoute `Environment=...` si tu externalises `VAULT_ADDR`/`VAULT_API_ADDR`, durcis `ProtectSystem`, `PrivateTmp`, `CapabilityBoundingSet`, etc.

---

## Prochaines étapes (reco)

- Mettre en place **TLS** (certs valides) et **storage** adapté (Raft intégré ou backend cloud/consul).
- Passer `key-shares` / `key-threshold` à des valeurs **saines**.
- Supprimer/rotater le **root token** post-bootstrap, créer des policies + tokens dédiés CI/CD.
- Éviter les artefacts persistants : garder les *unseal keys* dans un coffre séparé (HSM/secret manager).
