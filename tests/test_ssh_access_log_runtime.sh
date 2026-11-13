#!/usr/bin/env bash
# Run real SSH tests only in ephemeral, network-isolated containers.
set -euo pipefail

if [[ "${1:-}" != --inside ]]; then
  repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  image="${1:?Pass a locally available Kasm image}"
  for flag in 0 1; do
    docker run --rm --network none --user root --entrypoint bash \
      -e ACCESS_LOG="$flag" -e TZ=UTC \
      -v "$repo_dir/scripts/kasm-remote-access.sh:/probe-helper:ro" \
      -v "$repo_dir/tests/test_ssh_access_log_runtime.sh:/probe-test:ro" \
      "$image" /probe-test --inside
  done
  for failure in bad-config symlink writer handoff handoff-disabled handoff-manual handoff-symlink handoff-bad-pid handoff-fallback; do
    docker run --rm --network none --user root --entrypoint bash \
      -e ACCESS_LOG=1 -e PROBE_FAILURE="$failure" \
      -v "$repo_dir/scripts/kasm-remote-access.sh:/probe-helper:ro" \
      -v "$repo_dir/tests/test_ssh_access_log_runtime.sh:/probe-test:ro" \
      "$image" /probe-test --inside
  done
  exit 0
fi

if [[ "${PROBE_FAILURE:-}" == bad-config ]]; then
  printf '\nInvalidProbeOption yes\n' >> /etc/ssh/sshd_config
  if bash /probe-helper start-ssh; then
    echo 'invalid SSH configuration accepted' >&2; exit 1
  fi
  if pgrep -x sshd >/dev/null; then
    echo 'sshd started despite invalid configuration' >&2; exit 1
  fi
  echo 'invalid SSH configuration rejected: PASS'
  exit 0
fi
if [[ "${PROBE_FAILURE:-}" == symlink ]]; then
  mkdir -p /var/log/kasm-access
  printf 'unchanged\n' > /tmp/probe-target
  ln -s /tmp/probe-target /var/log/kasm-access/sshd.log
  if bash /probe-helper start-ssh; then
    echo 'log symlink accepted' >&2; exit 1
  fi
  grep -qx unchanged /tmp/probe-target
  ss -H -ltn 'sport = :22' | grep -q .
  echo 'log symlink rejected: PASS'
  exit 0
fi

install -d -m 0700 -o kasm-user -g kasm-user /home/kasm-user/.ssh
ssh-keygen -q -t ed25519 -f /tmp/probe-key -N ''
install -m 0600 -o kasm-user -g kasm-user /tmp/probe-key.pub /home/kasm-user/.ssh/authorized_keys
ssh_args=(-q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o IdentitiesOnly=yes -i /tmp/probe-key)
if [[ "${PROBE_FAILURE:-}" == handoff* ]]; then
  ACCESS_LOG=0 bash /probe-helper start-ssh
  read -r old_listener < /run/sshd.pid
  ssh "${ssh_args[@]}" kasm-user@127.0.0.1 'sleep 8; echo survived' > /tmp/probe-session &
  session_pid=$!
  python3 -m http.server 18888 --bind 127.0.0.1 >/dev/null 2>&1 &
  server=$!
  ssh "${ssh_args[@]}" -o ExitOnForwardFailure=yes -N -L 18889:127.0.0.1:18888 kasm-user@127.0.0.1 &
  tunnel=$!
  trap 'kill "$server" "$tunnel" 2>/dev/null || true' EXIT
  for _ in {1..50}; do
    if curl -fsS --max-time 1 -o /dev/null http://127.0.0.1:18889/ 2>/dev/null; then break; fi
    sleep .1
  done
  curl -fsS --max-time 2 -o /dev/null http://127.0.0.1:18889/
  case "$PROBE_FAILURE" in
    handoff-symlink)
      mkdir -p /var/log/kasm-access
      printf 'unchanged\n' > /tmp/probe-target
      ln -s /tmp/probe-target /var/log/kasm-access/sshd.log
      ;;
    handoff-bad-pid) printf 'not-a-pid\n' > /run/sshd.pid ;;
    handoff-fallback)
      mkdir -p /tmp/probe-bin
      printf '#!/bin/sh\nexit 1\n' > /tmp/probe-bin/setsid
      chmod 0755 /tmp/probe-bin/setsid
      export PATH="/tmp/probe-bin:$PATH"
      ;;
  esac
  if [[ "$PROBE_FAILURE" == handoff-disabled || "$PROBE_FAILURE" == handoff-manual ]]; then
    if [[ "$PROBE_FAILURE" == handoff-disabled ]]; then
      ACCESS_LOG=0 KASM_SSH_HANDOFF=1 bash /probe-helper start-ssh
    else
      ACCESS_LOG=1 KASM_SSH_HANDOFF=0 bash /probe-helper start-ssh
    fi
    read -r same_listener < /run/sshd.pid
    [[ "$old_listener" == "$same_listener" ]]
  elif [[ "$PROBE_FAILURE" == handoff ]]; then
    ACCESS_LOG=1 KASM_SSH_HANDOFF=1 bash /probe-helper start-ssh
    read -r new_listener < /run/sshd.pid
    [[ "$old_listener" != "$new_listener" ]]
    ACCESS_LOG=1 KASM_SSH_HANDOFF=1 bash /probe-helper start-ssh
    read -r same_listener < /run/sshd.pid
    [[ "$new_listener" == "$same_listener" ]]
  else
    if ACCESS_LOG=1 KASM_SSH_HANDOFF=1 bash /probe-helper start-ssh; then
      echo 'invalid handoff unexpectedly succeeded' >&2; exit 1
    fi
    if [[ "$PROBE_FAILURE" != handoff-fallback ]]; then
      kill -0 "$old_listener"
    fi
    if [[ "$PROBE_FAILURE" == handoff-symlink ]]; then
      grep -qx unchanged /tmp/probe-target
    fi
  fi
  curl -fsS --max-time 2 -o /dev/null http://127.0.0.1:18889/
  ssh "${ssh_args[@]}" kasm-user@127.0.0.1 true
  if [[ "$PROBE_FAILURE" == handoff ]]; then
    grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}T.*\+0900 .*Accepted publickey' /var/log/kasm-access/sshd.log
  fi
  wait "$session_pid"
  grep -qx survived /tmp/probe-session
  echo "$PROBE_FAILURE: SSH session, tunnel and new connection preserved: PASS"
  exit 0
fi
bash /probe-helper start-ssh
before=$(pgrep -x sshd | head -1)
ssh "${ssh_args[@]}" kasm-user@127.0.0.1 true
if [[ "$ACCESS_LOG" == 1 ]]; then
  ssh "${ssh_args[@]}" kasm-user@127.0.0.1 'printf user-command-sentinel' > /tmp/probe-command-output
  grep -qx user-command-sentinel /tmp/probe-command-output
  grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\+0900 .*Accepted publickey for kasm-user' /var/log/kasm-access/sshd.log
  if grep -q user-command-sentinel /var/log/kasm-access/sshd.log; then
    echo 'SSH log captured command contents' >&2; exit 1
  fi
  su -s /bin/bash kasm-user -c 'test -r /var/log/kasm-access/sshd.log'
  echo 'public-key event; command contents not captured; user-readable log: PASS'
else
  test ! -e /var/log/kasm-access/sshd.log
  echo 'logging disabled: PASS'
fi
ssh "${ssh_args[@]}" kasm-user@127.0.0.1 'sleep 3; echo survived' > /tmp/probe-session &
session_pid=$!
sleep 1
if [[ "${PROBE_FAILURE:-}" == writer ]]; then
  read -r writer_pid < /run/kasm-sshd-log-writer.pid
  kill -KILL "$writer_pid"
  for _ in {1..30}; do
    kill -0 "$writer_pid" 2>/dev/null || break
    sleep 0.1
  done
  result=$(bash /probe-helper start-ssh 2>&1)
  grep -q 'SSH log writer unavailable' <<< "$result"
else
  bash /probe-helper start-ssh
fi
test "$before" = "$(pgrep -x sshd | head -1)"
wait "$session_pid"
grep -q survived /tmp/probe-session
if [[ "${PROBE_FAILURE:-}" == writer ]]; then
  ssh "${ssh_args[@]}" kasm-user@127.0.0.1 true
  echo 'writer failure reported; existing and new SSH work: PASS'
fi
echo 'existing SSH connection preserved: PASS'
