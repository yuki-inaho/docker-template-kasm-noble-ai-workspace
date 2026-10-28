#!/usr/bin/env bash
set -euo pipefail
image="${1:?Pass a locally loaded image tag}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
container="kasm-runtime-${RANDOM}"
export VNC_PW
VNC_PW="$(openssl rand -hex 16)"
if [[ -n "${GITHUB_ACTIONS:-}" ]]; then echo "::add-mask::$VNC_PW"; fi
cleanup() {
  result=$?
  if [[ "$result" -ne 0 ]]; then docker logs "$container" || true; fi
  docker rm -f "$container" >/dev/null 2>&1 || true
  exit "$result"
}
trap cleanup EXIT
docker run -d --name "$container" --shm-size=1g -e VNC_PW \
  -e AUTO_UPDATE_TOOLS="${AUTO_UPDATE_TOOLS:-0}" \
  -p 127.0.0.1::6901 "$image" >/dev/null
port="$(docker port "$container" 6901/tcp | awk -F: '{print $NF}')"
ready=false
for ((attempt = 0; attempt < 90; attempt++)); do
  status="$(curl -ksS -o /dev/null -w '%{http_code}' "https://127.0.0.1:$port/" || true)"
  if [[ "$status" == 401 ]]; then ready=true; break; fi
  sleep 2
done
[[ "$ready" == true ]]
status="$(curl -ksS -u "kasm_user:$VNC_PW" -o /dev/null -w '%{http_code}' "https://127.0.0.1:$port/vnc.html")"
[[ "$status" == 200 ]]
echo "PASS: HTTPS rejects unauthenticated requests and accepts valid credentials"
docker exec "$container" bash -c '
  set -e
  for ((i=0; i<30; i++)); do
    [[ -f "$HOME/Desktop/AI-SETUP.md" ]] && break
    sleep 1
  done
  cmp "$HOME/Desktop/AI-SETUP.md" /usr/local/share/kasm-noble-ai-workspace/AI-SETUP.md
  printf "user-edited prompt\n" > "$HOME/Desktop/AI-SETUP.md"
  /dockerstartup/runtime-init.sh >/dev/null
  [[ "$(cat "$HOME/Desktop/AI-SETUP.md")" == "user-edited prompt" ]]
'
echo "PASS: desktop prompt is installed and user edits are preserved"
docker cp "$script_dir/test-kasmvnc-browser.cjs" "$container:/tmp/test-kasmvnc-browser.cjs"
docker exec -e VNC_PW "$container" bash -lc \
  'source "$HOME/.nvm/nvm.sh"; NODE_PATH="$(npm root -g)" node /tmp/test-kasmvnc-browser.cjs'
mkdir -p runtime-evidence
for viewer in 0 1; do
  docker cp "$container:/tmp/kasm-viewer-$viewer.png" "runtime-evidence/viewer-$viewer.png"
done
