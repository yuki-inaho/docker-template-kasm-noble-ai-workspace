#!/usr/bin/env bash
set -euo pipefail

SSH_USER="${KASM_SSH_USER:-kasm-user}"
SSH_HOME="${KASM_SSH_HOME:-/home/kasm-user}"
TOKEN_FILE="${KASM_TUNNEL_TOKEN_FILE:-/etc/cloudflared/token}"
CONFIG_FILE="${KASM_TUNNEL_CONFIG:-/etc/cloudflared/config.yml}"
LOG_FILE="${KASM_TUNNEL_LOG:-/var/log/cloudflared.log}"

usage() {
  cat <<'EOF'
Usage: sudo kasm-remote-access <command> [argument]

Commands:
  ssh-key <public-key>   Add an SSH public key to kasm-user's authorized_keys.
  tunnel-token <token>   Store a Cloudflare Tunnel token (0600) without echoing it.
  start                  Generate host keys if needed, then start sshd and cloudflared.
  start-ssh              Generate host keys if needed, then start sshd only.
  start-tunnel           Start cloudflared only.
  status                 Show whether sshd and cloudflared are running.
  help                   Show this message.

Environment overrides:
  KASM_SSH_USER, KASM_SSH_HOME, KASM_TUNNEL_TOKEN_FILE,
  KASM_TUNNEL_CONFIG, KASM_TUNNEL_LOG
EOF
}

require_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "kasm-remote-access must run as root (use sudo)" >&2
    exit 1
  fi
}

add_ssh_key() {
  local key="${1:-}"
  if [[ -z "${key}" ]]; then
    echo "ssh-key requires a public key argument" >&2
    exit 2
  fi

  install -d -m 0700 -o "${SSH_USER}" -g "${SSH_USER}" "${SSH_HOME}/.ssh"
  touch "${SSH_HOME}/.ssh/authorized_keys"
  chown "${SSH_USER}:${SSH_USER}" "${SSH_HOME}/.ssh/authorized_keys"
  chmod 0600 "${SSH_HOME}/.ssh/authorized_keys"

  if grep -Fqx "${key}" "${SSH_HOME}/.ssh/authorized_keys"; then
    echo "SSH key already registered"
    return
  fi

  printf '%s\n' "${key}" >> "${SSH_HOME}/.ssh/authorized_keys"
  echo "SSH key registered for ${SSH_USER}"
}

set_tunnel_token() {
  local token="${1:-}"
  if [[ -z "${token}" ]]; then
    echo "tunnel-token requires a token argument" >&2
    exit 2
  fi

  install -d -m 0755 "$(dirname "${TOKEN_FILE}")"
  umask 077
  printf '%s\n' "${token}" > "${TOKEN_FILE}"
  chown root:root "${TOKEN_FILE}"
  chmod 0600 "${TOKEN_FILE}"

  install -d -m 0755 "$(dirname "${CONFIG_FILE}")"
  if [[ ! -f "${CONFIG_FILE}" ]]; then
    printf '%s\n' 'protocol: http2' 'no-autoupdate: true' > "${CONFIG_FILE}"
  fi

  echo "Cloudflare Tunnel token stored in ${TOKEN_FILE}"
  echo "Run 'sudo kasm-remote-access start' to start the tunnel."
}

start_ssh() {
  install -d -m 0755 /run/sshd
  ssh-keygen -A >/dev/null
  if pgrep -x sshd >/dev/null 2>&1; then
    echo "sshd already running"
    return
  fi
  /usr/sbin/sshd
  echo "sshd started on port 22"
}

start_tunnel() {
  if [[ ! -s "${TOKEN_FILE}" ]]; then
    echo "No tunnel token found at ${TOKEN_FILE}; skipping cloudflared" >&2
    return 0
  fi
  if pgrep -f 'cloudflared.*tunnel run' >/dev/null 2>&1; then
    echo "cloudflared already running"
    return
  fi

  install -d -m 0755 "$(dirname "${LOG_FILE}")"
  nohup cloudflared tunnel run \
    --config "${CONFIG_FILE}" \
    --token-file "${TOKEN_FILE}" \
    >>"${LOG_FILE}" 2>&1 &
  echo "cloudflared started; log: ${LOG_FILE}"
}

show_status() {
  if pgrep -x sshd >/dev/null 2>&1; then
    echo "sshd: running"
  else
    echo "sshd: stopped"
  fi
  if pgrep -f 'cloudflared.*tunnel run' >/dev/null 2>&1; then
    echo "cloudflared: running"
  else
    echo "cloudflared: stopped"
  fi
  if [[ -s "${TOKEN_FILE}" ]]; then
    echo "tunnel token: configured"
  else
    echo "tunnel token: missing"
  fi
}

main() {
  local command="${1:-help}"
  case "${command}" in
    ssh-key)
      require_root
      add_ssh_key "${2:-}"
      ;;
    tunnel-token)
      require_root
      set_tunnel_token "${2:-}"
      ;;
    start)
      require_root
      start_ssh
      start_tunnel
      ;;
    start-ssh)
      require_root
      start_ssh
      ;;
    start-tunnel)
      require_root
      start_tunnel
      ;;
    status)
      show_status
      ;;
    help|-h|--help)
      usage
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
}

main "$@"
