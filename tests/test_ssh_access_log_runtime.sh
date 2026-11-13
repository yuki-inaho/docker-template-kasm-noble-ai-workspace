#!/usr/bin/env bash
# Run real SSH tests only in ephemeral, network-isolated containers.
set -euo pipefail

if [[ "${1:-}" != --inside ]]; then
  repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  image="${1:?Pass a locally available Kasm image}"
  for flag in 0 1; do
    docker run --rm --network none --user root --entrypoint bash \
      -e ACCESS_LOG="$flag" \
      -v "$repo_dir/scripts/kasm-remote-access.sh:/probe-helper:ro" \
      -v "$repo_dir/tests/test_ssh_access_log_runtime.sh:/probe-test:ro" \
      "$image" /probe-test --inside
  done
  exit 0
fi

install -d -m 0700 -o kasm-user -g kasm-user /home/kasm-user/.ssh
ssh-keygen -q -t ed25519 -f /tmp/probe-key -N ''
install -m 0600 -o kasm-user -g kasm-user /tmp/probe-key.pub /home/kasm-user/.ssh/authorized_keys
bash /probe-helper start-ssh
before=$(pgrep -x sshd | head -1)
ssh_args=(-q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o IdentitiesOnly=yes -i /tmp/probe-key)
ssh "${ssh_args[@]}" kasm-user@127.0.0.1 true
if [[ "$ACCESS_LOG" == 1 ]]; then
  grep -q 'Accepted publickey for kasm-user' /var/log/kasm-access/sshd.log
  su -s /bin/bash kasm-user -c 'test -r /var/log/kasm-access/sshd.log'
  echo 'public-key event and user-readable log: PASS'
else
  test ! -e /var/log/kasm-access/sshd.log
  echo 'logging disabled: PASS'
fi
ssh "${ssh_args[@]}" kasm-user@127.0.0.1 'sleep 3; echo survived' > /tmp/probe-session &
session_pid=$!
sleep 1
bash /probe-helper start-ssh
test "$before" = "$(pgrep -x sshd | head -1)"
wait "$session_pid"
grep -q survived /tmp/probe-session
echo 'existing SSH connection preserved: PASS'
