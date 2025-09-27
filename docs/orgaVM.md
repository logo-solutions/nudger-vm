+-----------------------------------------------------------+
|                   INFRASTRUCTURE / NODES                 |
|                                                           |
|   [OS VM / Serveur physique]                              |
|                                                           |
|   Users système :                                        |
|   ----------------                                       |
|   root               -> gestion globale de la VM         |
|   ansible            -> déploiement infra & Kubernetes  |
|   kubernetes         -> account interne pour k8s         |
|                                                           |
|   Key Points:                                             |
|   - ansible a accès SSH passwordless                     |
|   - root limité à maintenance OS                          |
|   - kubernetes user créé automatiquement par playbook    |
+-----------------------------------------------------------+
                         |
                         v
+-----------------------------------------------------------+
|                      KUBERNETES CLUSTER                 |
|                                                           |
|   Namespaces / Pods / Deployments                         |
|   --------------------------------                         |
|   Apps tournent sous service accounts dédiés             |
|   (ex: frontend-sa, backend-sa, db-sa)                   |
|                                                           |
|   Key Points:                                             |
|   - Apps n’ont jamais accès root de la VM                |
|   - Sécurité et audit facilité                           |
|   - Gestion RBAC Kubernetes pour chaque app             |
+-----------------------------------------------------------+
                         |
                         v
+-----------------------------------------------------------+
|                      DEVELOPERS / OPS                    |
|                                                           |
|   Users pour gérer cluster et apps :                      |
|   - developer / ops                                       |
|   - Accès via kubectl avec kubeconfig                     |
|   - Pas besoin de root VM                                 |
|   - Accès limité aux namespaces ou ressources spécifiques|
+-----------------------------------------------------------+


User ansible

Utilisé pour l’automatisation complète : création de VM, installation de Docker/containerd, Kubernetes, configuration SSH, déploiement de configs.

SSH passwordless via clé dédiée.

User kubernetes

Créé automatiquement par le playbook pour gérer les fichiers et processus liés au cluster.

Sert de base pour les processus kubelet, kubeadm, etc.

Users developer/ops

Pour accéder au cluster via kubectl ou autres outils, mais jamais en root sur le node.

Sécurité renforcée, audit simple.

Apps / Pods

Chaque application a son service account dans Kubernetes.

Isolation complète : pas de root, pas d’accès aux fichiers système.




---------
Clés SSH :

id_vm_ed25519 → utilisée pour provisionner la VM (root ou ansible).

id_ansible → utilisée par Ansible pour toutes les tâches sur les nodes.

Tu peux combiner avec une seule clé si tu veux simplifier.
