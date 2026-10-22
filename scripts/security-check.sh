#!/usr/bin/env bash
# Minimum versions for the October 2026 security refresh, not a general CVE scan.
set -euo pipefail

require_version() {
  local name="$1" actual="$2" minimum="$3"
  if ! dpkg --compare-versions "${actual}" ge "${minimum}"; then
    printf '[FAIL] %s %s is older than %s\n' "${name}" "${actual}" "${minimum}" >&2
    return 1
  fi
  printf '[OK] %s %s (minimum %s)\n' "${name}" "${actual}" "${minimum}"
}

require_version ca-certificates \
  "$(dpkg-query -W -f='${Version}' ca-certificates)" 20260816ubuntu0.24.04.1

node_version="$(node -p 'process.versions.node')"
case "${node_version}" in
  22.*) require_version Node.js "${node_version}" 22.23.4 ;;
  24.*) require_version Node.js "${node_version}" 24.22.1 ;;
  26.*) require_version Node.js "${node_version}" 26.12.1 ;;
  *) echo "[FAIL] Node.js line has no reviewed security minimum: ${node_version}" >&2; exit 1 ;;
esac
require_version npm "$(npm --version)" 12.2.1
require_version google-chrome-stable \
  "$(dpkg-query -W -f='${Version}' google-chrome-stable)" 156.0.8078.47-1

# Node has its own bundled roots; updating Ubuntu's bundle alone is insufficient.
node <<'JS'
const { X509Certificate } = require('node:crypto');
const { rootCertificates } = require('node:tls');
if (rootCertificates.some(pem => new X509Certificate(pem).subject.includes('emSign ECC Root CA - G3'))) {
  throw new Error('Distrusted emSign ECC Root CA - G3 remains in the Node.js bundle');
}
console.log('[OK] Distrusted emSign root is absent from the Node.js bundle');
JS

system_roots="$(openssl crl2pkcs7 -nocrl -certfile /etc/ssl/certs/ca-certificates.crt \
  | openssl pkcs7 -print_certs -noout)"
if grep -q 'emSign ECC Root CA - G3' <<< "${system_roots}"; then
  echo '[FAIL] Distrusted emSign root remains in the system CA bundle' >&2
  exit 1
fi
echo '[OK] Distrusted emSign root is absent from the system CA bundle'

# PHP is not installed by this template. Check Ubuntu PHP packages if a future
# base image adds them, rather than installing PHP solely to patch it.
while IFS=$'\t' read -r package version source status; do
  [[ "${status}" == installed ]] || continue
  case "${source}" in
    php8.3) require_version "${package}" "${version}" 8.3.6-0ubuntu0.24.04.13 ;;
    php[0-9]*)
      echo "[FAIL] Review security minimum for unexpected PHP source: ${source}" >&2
      exit 1
      ;;
  esac
done < <(dpkg-query -W -f='${binary:Package}\t${Version}\t${source:Package}\t${db:Status-Status}\n')

echo '[OK] October 2026 image security checks passed; host kernel needs separate review'
