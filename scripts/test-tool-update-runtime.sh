#!/usr/bin/env bash
set -euo pipefail

image="${1:?usage: test-tool-update-runtime.sh IMAGE}"
container="tool-update-test-$$"
cleanup() { docker rm -f "$container" >/dev/null 2>&1 || true; }
trap cleanup EXIT
docker run -d --name "$container" --shm-size=1g \
  -e VNC_PW=temporary-test-only "$image" >/dev/null

for ((i=0; i<300; i++)); do
  log="$(docker exec "$container" cat /home/kasm-user/.local/state/kasm-workspace/tool-update.log 2>/dev/null || true)"
  if [[ "$log" == *"All user tools updated"* ]]; then
    docker exec "$container" pgrep -f 'workspace-update-tools --watch' >/dev/null
    echo 'PASS: startup updater completed and remains scheduled'
    exit 0
  fi
  if [[ "$log" == *"Some tools failed"* ]]; then
    printf '%s\n' "$log" >&2
    exit 1
  fi
  sleep 1
done
echo 'FAIL: startup updater did not complete within 300 seconds' >&2
printf '%s\n' "$log" >&2
exit 1
