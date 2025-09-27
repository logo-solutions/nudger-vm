./fstabnudger.sh
./flannel.sh
kubectl config set-context --current --namespace=open4goods

curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

kubectl create secret generic xwiki-mysql-auth \
  --namespace=open4goods \
  --from-literal=mysql-root-password='xwiki' \
  --from-literal=mysql-user='xwiki' \
  --from-literal=mysql-password='xwiki' \
  --from-literal=mysql-database='xwiki'

LONGHORN

sudo mkdir -p /var/lib/longhorn/engine-binaries
sudo chown -R 1000000000:1000000000 /var/lib/longhorn/engine-binaries
sudo chmod -R 755 /var/lib/longhorn/engine-binaries
sudo chown -R 1000000000:1000000000 /var/lib/longhorn
sudo chmod -R 700 /var/lib/longhorn

Important : 1000000000 est l’UID utilisé par le container Longhorn. Si le dossier existe déjà mais appartient à root, le pod échouera comme tu as vu.

2️⃣ Déployer Longhorn avec Helm
bash
Copier
Modifier
helm repo add longhorn https://charts.longhorn.io
helm repo update

helm upgrade --install longhorn longhorn/longhorn \
  --namespace longhorn-system \
  --create-namespace \
  --set defaultSettings.numberOfReplicas=1 \
  --set defaultSettings.backupTarget="" \
  --set defaultSettings.defaultDataPath="/var/lib/longhorn" \
  --set engineImageBinariesHostPath="/var/lib/longhorn/engine-binaries"


kubectl label node vagrant longhorn.io/node=ready

KUSOTIMSE
Récupère la dernière version (exemple v5.4.1) :

VERSION=5.4.1
curl -LO "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${VERSION}/kustomize_v${VERSION}_linux_amd64.tar.gz"


Décompresse :

tar -xzf kustomize_v${VERSION}_linux_amd64.tar.gz


Déplace le binaire :

sudo mv kustomize /usr/local/bin/


Vérifie :

kustomize version


VERSION=v4.44.3
wget https://github.com/mikefarah/yq/releases/download/${VERSION}/yq_linux_amd64 -O yq
chmod +x yq
sudo mv yq /usr/local/bin/



4. Vérifier le déploiement
kubectl get pods -n longhorn-system
sudo systemctl enable --now iscsid
helm install xwiki ./ -f minimal_values.yaml -n open4goods --create-namespace
