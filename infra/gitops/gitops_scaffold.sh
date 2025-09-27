#!/usr/bin/env bash
set -euo pipefail

# -------- Vars --------
TARGET_DIR="${TARGET_DIR:-gitops}"
ENVS=(${ENVS:-staging prod})
BRANCH="${BRANCH:-main}"
GIT_URL="${GIT_URL:-}"  # ssh://git@github.com/OWNER/REPO.git ou https://github.com/OWNER/REPO.git
SYNC_INTERVAL="${SYNC_INTERVAL:-15m}"
KUSTOMIZE_INTERVAL="${KUSTOMIZE_INTERVAL:-30m}"
INGRESS_CLASS="${INGRESS_CLASS:-nginx}"
DOMAIN_BASE="${DOMAIN_BASE:-example.com}"

# -------- Arbo --------
mkdir -p "${TARGET_DIR}/flux-system"
for ENV in "${ENVS[@]}"; do
  mkdir -p "${TARGET_DIR}/clusters/${ENV}"
done
mkdir -p "${TARGET_DIR}/apps/whoami/base" "${TARGET_DIR}/apps/whoami/overlays/staging" "${TARGET_DIR}/apps/whoami/overlays/prod"
mkdir -p "${TARGET_DIR}/apps/podinfo/helm/${ENV:-staging}" "${TARGET_DIR}/apps/podinfo/helm/prod"

# -------- GitRepository + Kustomizations --------
cat > "${TARGET_DIR}/flux-system/gitrepository.yaml" <<YAML
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: gitops
  namespace: flux-system
spec:
  interval: ${SYNC_INTERVAL}
  url: ${GIT_URL:-"https://REPLACE_ME"}
  ref: { branch: ${BRANCH} }
YAML

for ENV in "${ENVS[@]}"; do
cat > "${TARGET_DIR}/flux-system/kustomization-${ENV}.yaml" <<YAML
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: ${ENV}-root
  namespace: flux-system
spec:
  interval: ${KUSTOMIZE_INTERVAL}
  path: ./clusters/${ENV}
  prune: true
  sourceRef: { kind: GitRepository, name: gitops }
YAML
done

# -------- Kustomization roots par env --------
for ENV in "${ENVS[@]}"; do
cat > "${TARGET_DIR}/clusters/${ENV}/kustomization.yaml" <<YAML
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../apps/whoami/overlays/${ENV}
  - ../../apps/podinfo/helm/${ENV}
YAML
done

# -------- whoami (Kustomize) --------
cat > "${TARGET_DIR}/apps/whoami/base/deployment.yaml" <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata: { name: whoami, labels: { app: whoami } }
spec:
  replicas: 2
  selector: { matchLabels: { app: whoami } }
  template:
    metadata: { labels: { app: whoami } }
    spec:
      containers:
        - name: whoami
          image: traefik/whoami:v1.10.2
          ports: [{containerPort: 80}]
          resources:
            requests: { cpu: "50m", memory: "64Mi" }
            limits:   { cpu: "200m", memory: "128Mi" }
YAML

cat > "${TARGET_DIR}/apps/whoami/base/service.yaml" <<'YAML'
apiVersion: v1
kind: Service
metadata: { name: whoami }
spec:
  selector: { app: whoami }
  ports: [{ port: 80, targetPort: 80 }]
YAML

cat > "${TARGET_DIR}/apps/whoami/base/kustomization.yaml" <<'YAML'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources: [deployment.yaml, service.yaml]
YAML

for ENV in "${ENVS[@]}"; do
cat > "${TARGET_DIR}/apps/whoami/overlays/${ENV}/ingress.yaml" <<YAML
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: whoami
  annotations:
    kubernetes.io/ingress.class: "${INGRESS_CLASS}"
spec:
  rules:
    - host: "whoami.${ENV}.${DOMAIN_BASE}"
      http:
        paths:
          - path: /
            pathType: Prefix
            backend: { service: { name: whoami, port: { number: 80 } } }
YAML

cat > "${TARGET_DIR}/apps/whoami/overlays/${ENV}/kustomization.yaml" <<'YAML'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources: [../../base, ingress.yaml]
# patchesStrategicMerge: []  # tes overrides par env si besoin
YAML
done

# -------- podinfo (HelmRelease) --------
for ENV in "${ENVS[@]}"; do
cat > "${TARGET_DIR}/apps/podinfo/helm/${ENV}/helmrelease.yaml" <<'YAML'
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: podinfo
spec:
  interval: 30m
  chart:
    spec:
      chart: podinfo
      version: "6.x"
      sourceRef:
        kind: HelmRepository
        name: podinfo-charts
        namespace: flux-system
  values:
    replicaCount: 1
YAML
cat > "${TARGET_DIR}/apps/podinfo/helm/${ENV}/kustomization.yaml" <<'YAML'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources: [helmrelease.yaml]
YAML
done

# HelmRepository (source chart) — commun
cat > "${TARGET_DIR}/flux-system/helmrepository-podinfo.yaml" <<'YAML'
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: podinfo-charts
  namespace: flux-system
spec:
  interval: 1h
  url: https://stefanprodan.github.io/podinfo
YAML

# -------- Secrets en clair (provisoire) --------
mkdir -p "${TARGET_DIR}/apps/whoami/overlays/staging"
cat > "${TARGET_DIR}/apps/whoami/overlays/staging/secret.example.yaml" <<'YAML'
apiVersion: v1
kind: Secret
metadata: { name: whoami-secret }
type: Opaque
stringData:
  API_KEY: "remplace-moi"
YAML

# -------- README --------
cat > "${TARGET_DIR}/README.md" <<EOF
# Repo GitOps (single-repo, staging + prod)
- Git source unique (Flux GitRepository 'gitops')
- Kustomization par env: ./clusters/{staging,prod}
- Apps métiers uniquement (whoami: Kustomize, podinfo: HelmRelease)
- Sync: source=${SYNC_INTERVAL}, kustomize=${KUSTOMIZE_INTERVAL}

## Reconcile (exemples)
flux reconcile source git gitops -n flux-system
flux reconcile kustomization staging-root -n flux-system
flux reconcile kustomization prod-root -n flux-system
EOF

echo "✅ Arbo GitOps générée dans ${TARGET_DIR}"
