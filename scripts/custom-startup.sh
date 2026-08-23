#!/usr/bin/env bash
set -u

if ! /dockerstartup/runtime-init.sh; then
  echo "[custom-startup] runtime initialization failed; continuing with Kasm startup" >&2
fi

if [[ -x /dockerstartup/custom_startup.base.sh ]]; then
  exec /dockerstartup/custom_startup.base.sh
fi

# Kasm expects the custom startup process to remain alive.
while true; do
  sleep 3600
done
