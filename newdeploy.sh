#!/usr/bin/env bash
set -euo pipefail

# Dossiers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="$SCRIPT_DIR/out"; mkdir -p "$OUT_DIR"

# Defaults (surchargables via env ou flags)
TAGS="${TAGS:-${tags:-}}"
NAME="${NAME:-master1}"
TYPE="${TYPE:-cpx21}"
LOCATION="${LOCATION:-nbg1}"
IMAGE="${IMAGE:-ubuntu-22.04}"
SSH_KEY="${SSH_KEY:-id_vm_ed25519}"
VAULT_PASS_FILE="${VAULT_PASS_FILE:-$HOME/.vault-pass.txt}"
DRY_RUN="${DRY_RUN:-false}"
PLAYBOOK="${PLAYBOOK:-playbooks/nudger.yml}"
ANSIBLE_PIP_SPEC="${ANSIBLE_PIP_SPEC:-ansible-core>=2.16,<2.18}"

usage() {
  cat <<EOF
Usage: $0 <plan|create|bootstrap|run|ansible|support-bundle> [--flag value]
Flags:
  --name $NAME   --type $TYPE   --location $LOCATION   --image $IMAGE
  --ssh-key $SSH_KEY   --vault-pass-file $VAULT_PASS_FILE
  --dry-run (active --check pour ansible-playbook)
  --playbook $PLAYBOOK
  --tags "$TAGS"
EOF
}

# Parse flags
cmd="${1:-}"; shift || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) NAME="$2"; shift 2 ;;
    --tags) TAGS="$2"; shift 2 ;;
    --type) TYPE="$2"; shift 2 ;;
    --location) LOCATION="$2"; shift 2 ;;
    --image) IMAGE="$2"; shift 2 ;;
    --ssh-key) SSH_KEY="$2"; shift 2 ;;
    --vault-pass-file) VAULT_PASS_FILE="$2"; shift 2 ;;
    --dry-run) DRY_RUN="true"; shift 1 ;;
    --playbook) PLAYBOOK="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Arg inconnu: $1" >&2; usage; exit 1 ;;
  esac
done

case "${cmd:-}" in
  plan)
    echo "➡️ Plan:" >&2
    echo "  - Create VM Hetzner: name=$NAME type=$TYPE location=$LOCATION image=$IMAGE" >&2
    echo "  - Bootstrap: venv + collections Ansible" >&2
    echo "  - Inventaire: infra/k8s_ansible/inventory.ini" >&2
    echo "  - Run: ansible-playbook $PLAYBOOK $( [[ -n "${TAGS:-}" ]] && printf -- '--tags "%s"' "$TAGS" )" >&2
    ;;

  create)
    echo "➡️ Création de la VM Hetzner…" >&2
    DRY=""; [[ "$DRY_RUN" == "true" ]] && DRY="--dry-run"
    echo "ℹ️ Cmd: $SCRIPT_DIR/create-VM/vps/newcreate-vm.sh --name \"$NAME\" --type \"$TYPE\" --location \"$LOCATION\" --image \"$IMAGE\" --ssh-key \"$SSH_KEY\" $DRY" >&2

    # On capture TOUT (stdout+stderr) pour debug, puis on EXTRAIT UNE IPv4 propre
    CREATE_OUT="$("$SCRIPT_DIR/create-VM/vps/newcreate-vm.sh" \
                    --name "$NAME" --type "$TYPE" --location "$LOCATION" --image "$IMAGE" \
                    --ssh-key "$SSH_KEY" $DRY 2>&1 || true)"
    echo "$CREATE_OUT" >&2

    # 1) Format "IPv4: x.x.x.x"
    IP="$(printf '%s\n' "$CREATE_OUT" | awk '/^IPv4:[[:space:]]/{print $2; exit}')"
    # 2) fallback: 1ʳᵉ IPv4 trouvée n’importe où
    [[ -z "${IP:-}" ]] && IP="$(printf '%s\n' "$CREATE_OUT" | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n1 || true)"
    [[ -n "${IP:-}" ]] || { echo "❌ Impossible d’extraire l’IPv4 depuis la sortie du create" >&2; exit 1; }

    printf '%s\n' "$IP" > "$OUT_DIR/ip"
    echo "✅ VM IP: $IP (écrite dans $OUT_DIR/ip)" >&2
    echo "ℹ️ Pour pinner la clé SSH:  cat out/known_hosts >> ~/.ssh/known_hosts" >&2
    ;;

  bootstrap)
    echo "➡️ Bootstrap Ansible…" >&2
    cd "$SCRIPT_DIR/infra/k8s_ansible"

    # venv optionnelle
    python3 -m venv .venv >/dev/null 2>&1 || true
    # shellcheck disable=SC1091
    source .venv/bin/activate || true
    python -m pip -q install --upgrade pip || true
    python -m pip -q install "$ANSIBLE_PIP_SPEC" cryptography
    ansible-galaxy collection install -r requirements.yml -p ./collections

    # Vars inventaire
    VM_NAME="$NAME"
    ANSIBLE_USER="root"
    ID_SSH="$SSH_KEY"

    [[ -s "$OUT_DIR/ip" ]] || { echo "❌ $OUT_DIR/ip introuvable ou vide. Lance '$0 create' d’abord." >&2; exit 1; }
    RAW_IP="$(tr -d '\r' < "$OUT_DIR/ip")"
    IP="$(printf '%s\n' "$RAW_IP" | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n1 || true)"
    [[ -n "${IP:-}" ]] || { echo "❌ $OUT_DIR/ip ne contient pas d’IPv4 exploitable"; sed -n '1,20p' "$OUT_DIR/ip"; exit 1; }

    echo "➡️ Génération de inventory.ini…" >&2
    {
      echo "# inventory.ini"
      echo
      echo "[k8s_masters]"
      printf "%s ansible_host=%s ansible_user=%s ansible_ssh_private_key_file=%s/.ssh/%s ansible_python_interpreter=/usr/bin/python3\n" \
        "$VM_NAME" "$IP" "$ANSIBLE_USER" "$HOME" "$ID_SSH"
    } > inventory.ini.tmp
    mv -f inventory.ini.tmp inventory.ini
    echo "✅ Inventory: $(pwd)/inventory.ini" >&2

    # Sanity check
    grep -Eq '^\[k8s_masters\]$' inventory.ini && \
    grep -Eq '^[^ ]+ ansible_host=([0-9]{1,3}\.){3}[0-9]{1,3} ' inventory.ini \
      || { echo "❌ inventory.ini invalide :" >&2; sed -n '1,30p' inventory.ini >&2; exit 1; }
    ;;

  run)
    echo "➡️ Exécution du playbook (pipeline complet)…" >&2
    cd "$SCRIPT_DIR/infra/k8s_ansible"
    [[ -f "$VAULT_PASS_FILE" ]] || { echo "❌ Vault pass file manquant: $VAULT_PASS_FILE" >&2; exit 1; }
    [[ -f .venv/bin/activate ]] && source .venv/bin/activate || true

    VAULT_ARGS=(--vault-id "@$VAULT_PASS_FILE")
    CHK=(); [[ "$DRY_RUN" == "true" ]] && CHK=(--check)
    TAG_ARGS=(); [[ -n "${TAGS:-}" ]] && TAG_ARGS=(--tags "$TAGS")

    echo "ℹ️ Cmd: ansible-playbook -i inventory.ini $PLAYBOOK ${VAULT_ARGS[*]} ${CHK[*]} ${TAG_ARGS[*]}" >&2
    ansible-playbook -i inventory.ini "$PLAYBOOK" "${VAULT_ARGS[@]}" "${CHK[@]}" "${TAG_ARGS[@]}" | tee "$OUT_DIR/ansible-run.log"
    ;;

  ansible)
    echo "➡️ Exécution Ansible seule…" >&2
    cd "$SCRIPT_DIR/infra/k8s_ansible"
    [[ -f .venv/bin/activate ]] && source .venv/bin/activate || true
    [[ -f "$VAULT_PASS_FILE" ]] || { echo "❌ Vault pass file manquant: $VAULT_PASS_FILE" >&2; exit 1; }
    [[ -f inventory.ini ]] || { echo "❌ inventory.ini introuvable (fais '$0 bootstrap')" >&2; exit 1; }

    VAULT_ARGS=(--vault-id "@$VAULT_PASS_FILE")
    CHK=(); [[ "$DRY_RUN" == "true" ]] && CHK=(--check)
    TAG_ARGS=(); [[ -n "${TAGS:-}" ]] && TAG_ARGS=(--tags "$TAGS")

    echo "ℹ️ Cmd: ansible-playbook -i inventory.ini $PLAYBOOK ${VAULT_ARGS[*]} ${CHK[*]} ${TAG_ARGS[*]}" >&2
    ansible-playbook -i inventory.ini "$PLAYBOOK" "${VAULT_ARGS[@]}" "${CHK[@]}" "${TAG_ARGS[@]}" | tee "$OUT_DIR/ansible-run.log"
    ;;

  support-bundle)
    echo "➡️ Support-bundle…" >&2
    [[ -s "$OUT_DIR/ip" ]] || { echo "❌ $OUT_DIR/ip introuvable" >&2; exit 1; }
    IP="$(head -n1 "$OUT_DIR/ip")"
    "$SCRIPT_DIR/create-VM/vps/support-bundle.sh" "$IP" "$SSH_KEY" "$OUT_DIR"
    echo "✅ Support-bundle généré" >&2
    ;;

  *)
    usage; exit 1 ;;
esac
