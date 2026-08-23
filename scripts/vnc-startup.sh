#!/usr/bin/env bash
set -euo pipefail

# Set KASMVNC_REQUIRE_SSL=false when an upstream reverse proxy terminates TLS
# and forwards HTTP/WebSocket traffic to this container. The default preserves
# the direct TCP + TLS behavior of the upstream image.
case "${KASMVNC_REQUIRE_SSL:-true}" in
  true|1|yes)
    exec /dockerstartup/vnc_startup.ssl.sh "$@"
    ;;
  false|0|no)
    exec /dockerstartup/vnc_startup.http.sh "$@"
    ;;
  *)
    echo "KASMVNC_REQUIRE_SSL must be true or false" >&2
    exit 64
    ;;
esac
