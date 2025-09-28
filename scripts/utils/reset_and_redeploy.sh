#!/usr/bin/env bash
set -euo pipefail

# ===== Paramètres =====
NAME="${NAME:-master1}"                 # nom VM (optionnel si tu utilises Hetzner)
TYPE="${TYPE:-cpx21}"
LOCATION="${LOCATION:-nbg1}"
IMAGE="${IMAGE:-ubuntu-22.04}"
SSH_KEY="${SSH_KEY:-id_vm_ed25519}"     # nom de la clé côté Hetzner
INVENTORY="${INVENTORY:-inventory.ini}" # chemin inventaire (si présent)
ANSIBLE_USER="${ANSIBLE_USER:-root}"
PYTHON="${PYTHON:-python3}"
VENV_DIR="${VENV_DIR:-.venv}"
RECREATE_VM="${RECREATE_VM:-0}"         # 0=ne pas toucher la VM, 1=delete+create via hcloud
INSTALL_DEPS="${INSTALL_DEPS:-1}"       # 1=réinstaller pip deps + collections, 0=non
DRY_RUN="${DRY_RUN:-1}"                 # 1=dry-run (par défaut), 0=exécuter

# ===== Logging =====
LOG_FILE="${LOG_FILE:-reset.log}"
: > "${LOG_FILE}"  # purge le log au démarrage

# ===== Helpers =====
say()    { printf "%s\n" "$*"; }
warn()   { printf "⚠️  %s\n" "$*"; }
header() { printf "\n——— %s ———\n" "$*"; }

log_section() { printf "\n# %s\n" "$*" >> "${LOG_FILE}"; }

# Liste (dans reset.log) tout ce qui serait supprimé pour les chemins donnés
will_remove() {
  local path m
  for path in "$@"; do
    # Expand globs en incluant dotfiles si besoin
    shopt -s nullglob dotglob
    # shellcheck disable=SC2206
    local matched=(${path})
    shopt -u nullglob dotglob

    # Si aucun match ET que c'est un nom littéral, on log quand même l'absence
    if [[ ${#matched[@]} -eq 0 ]]; then
      printf "[absent] %s\n" "$path" >> "${LOG_FILE}"
      continue
    fi

    for m in "${matched[@]}"; do
      if [[ -d "$m" ]]; then
        # Tout le contenu + le dossier
        find "$m" -mindepth 0 -print >> "${LOG_FILE}" 2>/dev/null || true
      elif [[ -e "$m" ]]; then
        printf "%s\n" "$m" >> "${LOG_FILE}"
      else
        printf "[absent] %s\n" "$m" >> "${LOG_FILE}"
      fi
    done
  done
}

run_cmd() {
  if [[ "$DRY_RUN" == "1" ]]; then
    printf "DRY-RUN ▶ %s\n" "$*"
  else
    printf "RUN     ▶ %s\n" "$*"
    eval "$@"
  fi
}

write_file() { # write_file <chemin> <contenu>
  local path="$1"; shift
  if [[ "$DRY_RUN" == "1" ]]; then
    printf "DRY-RUN ▶ cat > %s <<'EOF'\n%s\nEOF\n" "$path" "$*"
  else
    printf "%s" "$*" > "$path"
  fi
}

have() { command -v "$1" >/dev/null 2>&1; }

# ===== Résumé =====
header "Résumé"
cat <<EOF
DRY_RUN=${DRY_RUN}  (1=dry-run, 0=exécution)
RECREATE_VM=${RECREATE_VM} (0=ne touche pas à la VM)
INSTALL_DEPS=${INSTALL_DEPS} (1=réinstalle pip/collections)
Projet: venv=${VENV_DIR}, inventory=${INVENTORY}
Hetzner: NAME=${NAME}, TYPE=${TYPE}, LOCATION=${LOCATION}, IMAGE=${IMAGE}, SSH_KEY=${SSH_KEY}
EOF

# ===== Confirmation (uniquement en exécution réelle) =====
header "Confirmation"
if [[ "$DRY_RUN" == "1" ]]; then
  say "Dry-run: pas de suppression réelle."
else
  read -r -p "⚠️  Tu vas PURGER caches locaux et (optionnel) recréer la VM. Continuer ? [y/N] " ans
  [[ "${ans:-}" == [yY] ]] || { say "Abandon."; exit 1; }
fi

# ===== 1) Purge caches locaux côté macOS =====
header "Purge caches locaux (poste)"
log_section "Purge repo: ${VENV_DIR} .pytest_cache __pycache__ out logs"
will_remove "${VENV_DIR}" ".pytest_cache" "__pycache__" "out" "logs"
run_cmd "rm -rf '${VENV_DIR}' ./.pytest_cache ./__pycache__ ./out ./logs"

log_section "Purge collections locales: ./collections ./ansible_collections ./galaxy_cache"
will_remove "./collections" "./ansible_collections" "./galaxy_cache"
run_cmd "rm -rf ./collections ./ansible_collections ./galaxy_cache"

log_section "Purge caches user: ~/.cache/pip ~/.cache/ansible ~/.ansible/tmp ~/.ansible/pc ~/.ansible/collections ~/.cache/helm"
for p in "$HOME/.cache/pip" "$HOME/.cache/ansible" "$HOME/.ansible/tmp" "$HOME/.ansible/pc" "$HOME/.ansible/collections" "$HOME/.cache/helm"; do
  will_remove "$p"
  run_cmd "rm -rf '$p'"
done

# __pycache__ dispersés
header "Scan __pycache__"
PYC_LIST="$(find . -type d -name '__pycache__' -prune 2>/dev/null || true)"
log_section "Dossiers __pycache__ trouvés"
if [[ -n "${PYC_LIST}" ]]; then
  printf "%s\n" "${PYC_LIST}" >> "${LOG_FILE}"
else
  printf "[none]\n" >> "${LOG_FILE}"
fi
run_cmd "find . -type d -name '__pycache__' -prune -exec rm -rf {} + 2>/dev/null || true"

# ===== 2) Nettoyage SSH local =====
header "Nettoyage SSH (known_hosts, sockets)"
if [[ -f "${INVENTORY}" ]]; then
  mapfile -t IPS < <(grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' "${INVENTORY}" | sort -u || true)
  if [[ "${#IPS[@]}" -gt 0 ]]; then
    for ip in "${IPS[@]}"; do
      log_section "known_hosts: suppression éventuelle lignes pour ${ip}"
      # On loggue les lignes correspondantes si non hashées
      if [[ -f "$HOME/.ssh/known_hosts" ]]; then
        grep -n "^[^|].*${ip}" "$HOME/.ssh/known_hosts" >> "${LOG_FILE}" || true
      fi
      run_cmd "ssh-keygen -R '${ip}' >/dev/null 2>&1 || true"
    done
  else
    say "Aucune IP trouvée dans ${INVENTORY}."
  fi
else
  say "Inventory ${INVENTORY} absent (ok)."
fi

# sockets de multiplexage
header "Sockets SSH"
SOCK_LIST="$(find "$HOME/.ssh" -maxdepth 1 -type s -name 'ssh_mux_*' 2>/dev/null || true)"
log_section "Sockets SSH à supprimer (~/.ssh/ssh_mux_*)"
if [[ -n "${SOCK_LIST}" ]]; then
  printf "%s\n" "${SOCK_LIST}" >> "${LOG_FILE}"
else
  printf "[none]\n" >> "${LOG_FILE}"
fi
run_cmd "find ~/.ssh -maxdepth 1 -type s -name 'ssh_mux_*' -delete 2>/dev/null || true"

# ===== 3) (Optionnel) Recréation VM Hetzner =====
if [[ "$RECREATE_VM" == "1" ]]; then
  header "Hetzner (optionnel) : delete + create VM"
  if ! have hcloud; then
    warn "hcloud CLI introuvable. Installe-le (brew install hcloud) ou mets RECREATE_VM=0."
    exit 1
  fi
  say "→ Les actions Hetzner ne touchent pas des fichiers locaux. Rien à lister dans reset.log ici."
  run_cmd "hcloud server delete '${NAME}' >/dev/null 2>&1 || true"
  run_cmd "hcloud server create --name '${NAME}' --type '${TYPE}' --image '${IMAGE}' --location '${LOCATION}' --ssh-key '${SSH_KEY}' --label env=lab --wait"

  IP_CMD="hcloud server describe '${NAME}' -o template='{{ (index .PublicNet.IPv4.IP) }}'"
  if [[ "$DRY_RUN" == "1" ]]; then
    say "DRY-RUN ▶ IP=\$(${IP_CMD})"
    IP="\${IP:-REPLACE_ME}"
  else
    IP="$(${IP_CMD})"
    say "IP=${IP}"
  fi

  header "Génération inventory (minimal)"
  INV_CONTENT="[master]
${NAME} ansible_host=${IP} ansible_user=${ANSIBLE_USER} ansible_ssh_common_args='-o StrictHostKeyChecking=no -o ControlMaster=no'
[k8s_masters]
${NAME}
"
  write_file "${INVENTORY}" "${INV_CONTENT}"
else
  header "Hetzner"
  say "RECREATE_VM=0 → je ne touche pas à ta VM. (Tu peux l’activer plus tard)"
fi

# ===== 4) Recréation venv + réinstallation deps (facultatif) =====
header "Environnement Python + deps"
# (récréation venv n'efface rien par elle-même; pas de listing ici)
run_cmd "${PYTHON} -m venv '${VENV_DIR}'"
if [[ "$INSTALL_DEPS" == "1" ]]; then
  run_cmd "bash -lc 'source \"${VENV_DIR}/bin/activate\" && pip install --upgrade pip wheel'"
  if [[ -f "requirements.txt" ]]; then
    run_cmd "bash -lc 'source \"${VENV_DIR}/bin/activate\" && pip install --no-cache-dir -r requirements.txt'"
  else
    say "requirements.txt absent (ok)."
  fi
  if [[ -f "requirements.yml" ]]; then
    if have ansible-galaxy; then
      run_cmd "ansible-galaxy collection install -r requirements.yml --force"
    else
      warn "ansible-galaxy introuvable. Installe Ansible (brew install ansible) ou active ton venv avant."
    fi
  else
    say "requirements.yml absent (ok)."
  fi
else
  say "INSTALL_DEPS=0 → je ne réinstalle pas pip/collections."
fi

# ===== 5) (Info) Commandes utiles post-reset =====
header "Prochaines étapes (manuel, aucun déploiement auto)"
cat <<'EOT'
- (Optionnel) Tester SSH:
    ssh -A -i ~/.ssh/id_vm_ed25519 root@<IP>

- (Optionnel) Tester Ansible:
    source .venv/bin/activate
    ansible -i inventory.ini all -m ping -e ansible_python_interpreter=/usr/bin/python3

- (Quand tu voudras déployer):
    ansible-playbook -i inventory.ini playbooks/nudger.yml --flush-cache -vv
EOT

header "Fin"
say "Mode: $([[ \"$DRY_RUN\" == 1 ]] && echo DRY-RUN || echo EXECUTION RÉELLE)"
say "📄 Détail des suppressions listé dans: ${LOG_FILE}"
