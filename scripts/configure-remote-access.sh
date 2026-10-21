#!/usr/bin/env bash
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "configure-remote-access.sh must run as root" >&2
  exit 1
fi

log() {
  printf '\n[remote-access] %s\n' "$*"
}

install_sshd_config() {
  log "Installing the SSH server defaults for kasm-user"

  if ! dpkg-query -W -f='${db:Status-Status}' openssh-server 2>/dev/null | grep -qx installed; then
    echo "openssh-server must be installed by the system package layer" >&2
    return 1
  fi

  install -d -m 0755 /etc/ssh/sshd_config.d
  cat > /etc/ssh/sshd_config.d/10-kasm.conf <<'CONF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
AllowUsers kasm-user
CONF
  chmod 0644 /etc/ssh/sshd_config.d/10-kasm.conf

  # Host keys must be generated per container at runtime, never baked into an
  # image layer.
  rm -f /etc/ssh/ssh_host_*
}

install_cloudflared_config() {
  log "Writing the Cloudflare Tunnel defaults"

  install -d -m 0755 /etc/cloudflared
  cat > /etc/cloudflared/config.yml <<'CONF'
protocol: http2
no-autoupdate: true
CONF
  chmod 0644 /etc/cloudflared/config.yml
}

install_helper() {
  log "Installing the kasm-remote-access helper"

  install -m 0755 /opt/image-build/kasm-remote-access.sh /usr/local/bin/kasm-remote-access
  test -x /usr/local/bin/kasm-remote-access
}

main() {
  install_sshd_config
  install_cloudflared_config
  install_helper
}

main "$@"
