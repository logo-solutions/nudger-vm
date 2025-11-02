=== [K8S_PACKAGES] Vérifications des binaires Kubernetes ===

[1] Vérification de la présence des binaires kubeadm / kubelet / kubectl...
✅ kubeadm est installé : /usr/bin/kubeadm
✅ kubelet est installé : /usr/bin/kubelet
✅ kubectl est installé : /usr/bin/kubectl

[2] Vérification des versions des binaires...
kubeadm version: &version.Info{Major:"1", Minor:"31", GitVersion:"v1.31.13", GitCommit:"c601ba40fa8f2254acd93bb31a02a6eb24948ec5", GitTreeState:"clean", BuildDate:"2025-09-09T22:59:05Z", GoVersion:"go1.23.12", Compiler:"gc", Platform:"linux/amd64"}
Kubernetes v1.31.13
Client Version: v1.31.13
Kustomize Version: v5.4.2

[3] Vérification de l'état du service kubelet...
⚠️  kubelet est installé mais pas encore actif (peut être 'activating' avant init)
     Active: activating (auto-restart) (Result: exit-code) since Thu 2025-10-30 08:53:14 UTC; 1s ago

-------------------------------------------
Résultats attendus :
  - kubeadm, kubelet, kubectl présents dans /usr/bin/
  - Versions cohérentes (ex: v1.31.x)
  - kubelet actif ou en phase d'activation
-------------------------------------------
root@master1:~#
