#!/usr/bin/env bash
# Run in the graphical session only for an explicitly marked fresh home.
set -u
pending="${HOME}/.kasm-ibus-initialize"
done_marker="${HOME}/.kasm-ibus-initialized"
[[ -f "${pending}" && ! -L "${pending}" ]] || exit 0
[[ ! -e "${done_marker}" && ! -L "${done_marker}" ]] || exit 0

for ((attempt = 0; attempt < 20; attempt++)); do
  timeout 3 ibus engine mozc-jp >/dev/null 2>&1 || true
  if [[ "$(timeout 3 ibus engine 2>/dev/null || true)" == "mozc-jp" ]]; then
    mv -n -- "${pending}" "${done_marker}"
    exit 0
  fi
  sleep 1
done
exit 1
