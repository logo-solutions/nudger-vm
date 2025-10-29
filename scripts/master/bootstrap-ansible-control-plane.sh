#!/usr/bin/env bash
set -euo pipefail
set -o errtrace

# ─────────────────── Helpers ───────────────────
log() { printf "\n\033[1;36m👉 %s\033[0m\n" "$*"; }
ok()  { printf "\033[1;32m✅ %s\033[0m\n" "$*"; }
err() { printf "\033[1;31m❌ %s\033[0m\n" "$*" >&2; }
trap 'err "Échec à la ligne $LINENO (cmd: ${BASH_COMMAND:-?})"' ERR

as_root() { [ "$(id -u)" -eq 0 ] || { err "Ce script doit être exécuté en root."; exit 1; }; }

apt_retry() {
  # usage: apt_retry install -y pkg1 pkg2...
  local tries=3
  for i in $(seq 1 "$tries"); do
    if apt-get "$@" ; then return 0; fi
    log "APT tentative $i/$tries a échoué — nouvelle tentative dans 3s…"
    sleep 3
    apt-get -y -o Dpkg::Options::="--force-confnew" -f install || true
  done
  err "APT a échoué après $tries tentatives: apt-get $*"
  return 1
}

# ─────────────────── Préambule ───────────────────
as_root
export DEBIAN_FRONTEND=noninteractive
export LC_ALL=C.UTF-8 LANG=C.UTF-8

# ─────────────────── Système ───────────────────
log "Mise à jour des paquets système"
apt_retry update -y
apt_retry upgrade -y

log "Installation des dépendances système"
apt_retry install -y --no-install-recommends \
  zsh git curl wget jq tree unzip bash-completion make tar gzip ca-certificates \
  python3 python3-venv python3-pip python3-dev build-essential \
  ruby ruby-dev \
  python3-kubernetes \
  gnupg \
  software-properties-common \
  snapd

log "Ajout du dépôt HashiCorp"

# 1️⃣ Préparer le dossier keyrings
mkdir -p /etc/apt/keyrings

# 2️⃣ (Optionnel) Supprimer la clé si elle est vide/corrompue
if [ -f /etc/apt/keyrings/hashicorp-archive-keyring.gpg ] && [ ! -s /etc/apt/keyrings/hashicorp-archive-keyring.gpg ]; then
  rm -f /etc/apt/keyrings/hashicorp-archive-keyring.gpg
fi

# 3️⃣ Importer la clé GPG officielle HashiCorp (avec retry si besoin)
curl -fsSL https://apt.releases.hashicorp.com/gpg | \
  gpg --dearmor -o /etc/apt/keyrings/hashicorp-archive-keyring.gpg || {
    rm -f /etc/apt/keyrings/hashicorp-archive-keyring.gpg
    curl -fsSL https://apt.releases.hashicorp.com/gpg | \
      gpg --dearmor -o /etc/apt/keyrings/hashicorp-archive-keyring.gpg
  }

# 4️⃣ Ajouter le dépôt HashiCorp pour Ubuntu (jammy = 22.04)
cat >/etc/apt/sources.list.d/hashicorp.list <<'EOF'
deb [signed-by=/etc/apt/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com jammy main
EOF

# 5️⃣ Mettre à jour le cache APT et installer Terraform
# 1️⃣ Mise à jour des paquets
apt_retry update

# 2️⃣ Installation de Terraform
apt_retry install -y terraform

# 3️⃣ Installer Helm via Snap
snap install helm --classic
# ─────────────────── yq (binaire statique) ───────────────────
if ! command -v yq >/dev/null 2>&1; then
  log "Installation de yq (binaire GitHub officiel)"
  arch=$(uname -m)
  case "$arch" in
    x86_64) bin="yq_linux_amd64" ;;
    aarch64|arm64) bin="yq_linux_arm64" ;;
    *) err "Architecture non supportée: $arch" ;;
  esac
  curl -fsSL "https://github.com/mikefarah/yq/releases/latest/download/${bin}" -o /usr/local/bin/yq
  chmod +x /usr/local/bin/yq
  ok "yq installé: $(yq --version)"
else
  ok "yq déjà présent: $(yq --version)"
fi

ok "Base système OK"
apt-get update -y
apt-get install -y wget
wget https://github.com/mikefarah/yq/releases/download/v4.44.2/yq_linux_amd64 -O /usr/local/bin/yq
chmod +x /usr/local/bin/yq
yq --version

# ─────────────────── hcloud CLI (idempotent) ───────────────────
if ! command -v hcloud >/dev/null 2>&1; then
  log "Installation du client Hetzner Cloud (hcloud)"
  tmpdir="$(mktemp -d)"; trap 'rm -rf "$tmpdir"' EXIT
  curl -fsSL "https://github.com/hetznercloud/cli/releases/latest/download/hcloud-linux-amd64.tar.gz" -o "$tmpdir/hcloud.tar.gz"
  tar -xzf "$tmpdir/hcloud.tar.gz" -C "$tmpdir"
  install -m 0755 "$tmpdir/hcloud" /usr/local/bin/hcloud
  ok "hcloud installé"
else
  ok "hcloud déjà présent"
fi

# ─────────────────── Virtualenv Ansible ───────────────────
ANSIBLE_VENV="${ANSIBLE_VENV:-/root/ansible_venv}"

if [[ ! -d "$ANSIBLE_VENV" || ! -x "$ANSIBLE_VENV/bin/activate" ]]; then
  log "Création / reconstruction du venv Ansible: $ANSIBLE_VENV"
  rm -rf "$ANSIBLE_VENV"
  python3 -m venv "$ANSIBLE_VENV"
fi

# shellcheck disable=SC1091
source "$ANSIBLE_VENV/bin/activate"

log "Mise à jour pip (venv)"
python -m pip install --upgrade pip

log "Installation des paquets Python (venv)"
python -m pip install \
  "ansible-core>=2.16,<2.18" \
  ansible-lint \
  openshift kubernetes pyyaml passlib \
  "hvac>=2.3"

ok "Paquets Python venv OK"

# ─────────────────── Collections Ansible ───────────────────
log "Installation des collections Ansible"
# Répertoire user par défaut
export ANSIBLE_COLLECTIONS_PATHS="$HOME/.ansible/collections:/usr/share/ansible/collections"

ansible-galaxy collection install \
  kubernetes.core \
  ansible.posix \
  community.general \
  community.crypto \
  community.hashi_vault \
  community.kubernetes \
  --force

# requirements optionnels (deux chemins possibles)
REQ_VM="$HOME/nudger-vm/infra/k8s_ansible/requirements.yml"
REQ_ALT="$HOME/nudger/infra/k8s-ansible/requirements.yml"
for REQ in "$REQ_VM" "$REQ_ALT"; do
  if [[ -f "$REQ" ]]; then
    log "Installation des collections depuis $REQ"
    ansible-galaxy collection install -r "$REQ" --force
  fi
done

ok "Collections Ansible OK"

# ─────────────────── Outils confort ───────────────────
# fzf (non interactif)
if [[ ! -d "$HOME/.fzf" ]]; then
  log "Installation fzf"
  git clone -q --depth 1 https://github.com/junegunn/fzf.git "$HOME/.fzf"
  "$HOME/.fzf/install" --all >/dev/null
  ok "fzf installé"
else
  ok "fzf déjà présent"
fi

# lazygit
if ! command -v lazygit >/dev/null 2>&1 && ! command -v "$HOME/bin/lazygit" >/dev/null 2>&1; then
  log "Installation lazygit"
  LG_VER="$(curl -fsSL https://api.github.com/repos/jesseduffield/lazygit/releases/latest | jq -r '.tag_name' | sed 's/^v//')"
  curl -fsSL -o /tmp/lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${LG_VER}_Linux_x86_64.tar.gz"
  tar -xzf /tmp/lazygit.tar.gz -C /tmp lazygit
  install -D -m 0755 /tmp/lazygit "$HOME/bin/lazygit"
  rm -f /tmp/lazygit /tmp/lazygit.tar.gz
  grep -q 'export PATH=\$HOME/bin:\$PATH' "$HOME/.bashrc" || echo 'export PATH=$HOME/bin:$PATH' >> "$HOME/.bashrc"
  ok "lazygit installé"
else
  ok "lazygit déjà présent"
fi

# ─────────────────── Versions ───────────────────
log "Vérifications versions"
ansible --version || true
python - <<'PY' || true
import importlib.metadata as m, sys
def v(p):
    try: print(p, m.version(p))
    except Exception as e: print(p, "N/A:", e)
v("ansible-core"); v("ansible-lint"); v("hvac"); v("kubernetes"); v("openshift"); v("PyYAML"); v("passlib")
print("python:", sys.executable)
PY

ok "Installation terminée !"

