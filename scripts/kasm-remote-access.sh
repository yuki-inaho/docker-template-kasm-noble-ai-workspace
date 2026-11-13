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

ssh_port_open() {
  ss -H -ltn 'sport = :22' | grep -q .
}

ssh_listener_pid() {
  local pid="" exe=""
  [[ -r /run/sshd.pid ]] || return 1
  read -r pid < /run/sshd.pid || return 1
  [[ "$pid" =~ ^[0-9]+$ ]] && (( pid > 1 )) || return 1
  [[ "$(stat -c %u "/proc/$pid")" == 0 ]] || return 1
  exe="$(readlink -f "/proc/$pid/exe")" || return 1
  [[ "$exe" == /usr/sbin/sshd ]] || return 1
  ss -H -ltnp 'sport = :22' | grep -q "pid=$pid," || return 1
  printf '%s\n' "$pid"
}

ssh_log_writer_alive() {
  local listener="$1" writer="" listener_parent="" writer_parent=""
  [[ -r /run/kasm-sshd-log-writer.pid ]] || return 1
  read -r writer < /run/kasm-sshd-log-writer.pid || return 1
  [[ "$writer" =~ ^[0-9]+$ ]] && kill -0 "$writer" 2>/dev/null || return 1
  [[ "$(cat "/proc/$writer/comm" 2>/dev/null)" == bash ]] || return 1
  listener_parent="$(ps -o ppid= -p "$listener" | tr -d ' ')"
  writer_parent="$(ps -o ppid= -p "$writer" | tr -d ' ')"
  [[ -n "$listener_parent" && "$listener_parent" == "$writer_parent" ]]
}

prepare_ssh_log() {
  install -d -m 0750 -o root -g "${SSH_USER}" /var/log/kasm-access || return 1
  if [[ -L /var/log/kasm-access/sshd.log ]]; then
    echo "refusing symlink for SSH log" >&2
    return 1
  fi
  touch /var/log/kasm-access/sshd.log || return 1
  chown root:"${SSH_USER}" /var/log/kasm-access/sshd.log || return 1
  chmod 0640 /var/log/kasm-access/sshd.log || return 1
  /usr/sbin/sshd -t || { echo "invalid SSH configuration; not starting sshd" >&2; return 1; }
}

start_logged_ssh() {
  # The timestamp is when the writer receives the line, in Japan time.
  nohup setsid bash -c '
    set -o pipefail
    /usr/sbin/sshd -D -e 2>&1 | {
      printf "%s\n" "$BASHPID" > /run/kasm-sshd-log-writer.pid
      while IFS= read -r line; do
        TZ=Asia/Tokyo printf "%(%Y-%m-%dT%H:%M:%S%z)T %s\n" -1 "$line"
      done
    } >> /var/log/kasm-access/sshd.log
  ' 9>&- </dev/null >/dev/null 2>&1 &
  for _ in {1..50}; do
    local listener=""
    if listener="$(ssh_listener_pid)" && ssh_log_writer_alive "$listener"; then
      echo "sshd started on port 22 with access logging"
      return 0
    fi
    sleep 0.1
  done
  echo "logged sshd did not become ready; inspect /var/log/kasm-access/sshd.log" >&2
  return 1
}

start_ssh() {
  # Only our helper operations take this lock; release it in the background
  # writer so that subsequent checks cannot be blocked by the daemon.
  exec 9>/run/kasm-remote-access.lock
  flock -x -w 10 9 || { echo "SSH start lock unavailable" >&2; return 1; }
  install -d -m 0755 /run/sshd
  ssh-keygen -A >/dev/null
  local listener=""
  if ssh_port_open; then
    if [[ "${ACCESS_LOG:-0}" != "1" ]]; then
      echo "sshd already running; no listener change requested"
      return 0
    fi
    if [[ "${KASM_SSH_HANDOFF:-0}" != "1" ]]; then
      if listener="$(ssh_listener_pid)" && ssh_log_writer_alive "$listener"; then
        echo "SSH log writer PID exists; verify recorded events separately" >&2
      else
        echo "SSH log writer unavailable; existing sshd was not restarted" >&2
      fi
      return 0
    fi
    listener="$(ssh_listener_pid)" || { echo "SSH listener could not be verified; not changed" >&2; return 1; }
    if ssh_log_writer_alive "$listener"; then
      echo "SSH log writer already running"
      return 0
    fi
    # Validate everything possible while the original listener remains live.
    prepare_ssh_log || return 1
    kill -TERM "$listener" || return 1
    for _ in {1..50}; do
      ssh_port_open || break
      sleep 0.1
    done
    if ssh_port_open; then
      echo "port 22 remains occupied; no replacement attempted" >&2
      return 1
    fi
    if start_logged_ssh; then return 0; fi
    # Keep SSH reachable if the logging setup fails after the handoff.
    if ! ssh_port_open; then /usr/sbin/sshd || true; fi
    echo "SSH logging handoff failed; check access and logs" >&2
    return 1
  fi
  if [[ "${ACCESS_LOG:-0}" == "1" ]]; then
    if ! prepare_ssh_log || ! start_logged_ssh; then
      if ! ssh_port_open; then /usr/sbin/sshd || true; fi
      echo "SSH logging setup failed; check access and logs" >&2
      return 1
    fi
  else
    /usr/sbin/sshd
    echo "sshd started on port 22"
  fi
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
