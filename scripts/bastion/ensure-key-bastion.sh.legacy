ensure_hcloud_key() {
  local PUB="${1:-/root/.ssh/id_vm_ed25519.pub}"
  local KEY_NAME="${2:-nudger-vm-default}"
  [ -f "$PUB" ] || { echo "Pub inexistante: $PUB"; return 2; }

  # calcule empreinte MD5 locale (format aaaa:bbbb:...)
  local LOCAL_MD5
  LOCAL_MD5="$(ssh-keygen -lf "$PUB" -E md5 | awk '{print $2}' | sed 's/^MD5://')"

  # vérifie par nom si la clé existe déjà
  if hcloud ssh-key describe "$KEY_NAME" -o json >/dev/null 2>&1; then
    local HC_FINGERPRINT
    HC_FINGERPRINT="$(hcloud ssh-key describe "$KEY_NAME" -o json | jq -r '.fingerprint')"
    if [[ "$HC_FINGERPRINT" == "$LOCAL_MD5" ]]; then
      echo "OK: clé Hetzner '$KEY_NAME' existe et matche la pub locale."
      hcloud ssh-key describe "$KEY_NAME" -o json | jq -r '.id'
      return 0
    else
      echo "Attention: une clé Hetzner nommée '$KEY_NAME' existe mais ne matche pas (hc:$HC_FINGERPRINT != local:$LOCAL_MD5)."
      echo "Tu peux créer une nouvelle clé avec un nom différent."
      return 3
    fi
  fi

  # sinon crée la clé
  echo "Création de la clé Hetzner $KEY_NAME à partir de $PUB ..."
  hcloud ssh-key create --name "$KEY_NAME" --public-key "$(cat "$PUB")" >/dev/null
  hcloud ssh-key describe "$KEY_NAME" -o json | jq -r '.id'
}

# utilisation:
ensure_hcloud_key /root/.ssh/id_vm_ed25519.pub nudger-vm-default
