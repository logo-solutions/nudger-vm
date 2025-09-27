
# Gestion de l’exposition Ingress — Nudger

Ce rôle Ansible `ingress_dnat` permet de rendre l’ingress (Ingress-NGINX) accessible depuis Internet, 
même si le cluster Kubernetes ne dispose pas de LoadBalancer cloud.

Deux **options** principales sont possibles :

---

## 🔹 Option A — DNAT via iptables (actuel)

Le rôle déploie une **unité systemd** `ingress-dnat.service` sur chaque nœud maître/frontale.  
Celle-ci applique une règle `iptables` qui **redirige le trafic entrant sur les ports 80 et 443** vers les NodePorts de l’Ingress NGINX.

### Caractéristiques
- Ne nécessite aucun service externe (LB ou proxy).
- Compatible avec un simple VPS/VM (Hetzner, OVH, etc.).
- Les NodePorts par défaut sont `30080` (HTTP) et `30443` (HTTPS), configurables via les variables :
  ```yaml
  ingress_http_nodeport: 30080
  ingress_https_nodeport: 30443
  ```
- Service géré par systemd : démarre automatiquement au boot et applique les règles.

### Ce qu’il faut faire
- Garder `enable_ingress_dnat: true` dans `group_vars/all.yml`.
- Vérifier que les ports **80 et 443** sont ouverts sur le pare-feu/SG de la VM.
- Facultatif : activer aussi la redirection IPv6 si tu publies des enregistrements AAAA.

---

## 🔹 Option B — LoadBalancer / Proxy externe

Dans ce mode, on **désactive le DNAT** et on expose l’ingress via un **LoadBalancer (LB)** ou un reverse proxy devant le cluster.

Exemples :
- **LB Hetzner** ou équivalent cloud → pointe en TCP/80 et TCP/443 vers le nœud master/Ingress.
- **HAProxy / Traefik externe** → déployé hors cluster pour router vers le service Ingress NGINX.

### Caractéristiques
- Plus “propre” et standard en prod.
- Support natif de la haute-disponibilité si plusieurs nœuds ingress.
- Permet la gestion centralisée du TLS côté proxy/LB.

### Ce qu’il faut faire
- Mettre `enable_ingress_dnat: false` dans `group_vars/all.yml`.
- Déclarer et configurer le LB/proxy en frontal (Hetzner LB, Nginx, HAProxy…).  
- Vérifier que les règles DNS (A/AAAA) pointent bien sur l’IP du LB.

---

## 🧾 Résumé

- **Option A (DNAT iptables)** : simple, fonctionne partout, bonne pour du lab ou mono‑VM.  
- **Option B (LoadBalancer/Proxy externe)** : plus robuste, à privilégier en production ou multi‑nœuds.

👉 Tu peux basculer d’une option à l’autre uniquement via la variable `enable_ingress_dnat`.


