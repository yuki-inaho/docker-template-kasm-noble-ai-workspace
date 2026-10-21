#!/usr/bin/env bash
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "install-awscli.sh must run as root" >&2
  exit 1
fi

version="${AWSCLI_VERSION:?AWSCLI_VERSION is required}"
case "$(uname -m)" in
  x86_64|amd64)
    ;;
  *)
    echo "AWS CLI v2 is installed for x86_64 only; found $(uname -m)" >&2
    exit 1
    ;;
esac

tmpdir="$(mktemp -d)"
cleanup() {
  rm -rf "${tmpdir}"
}
trap cleanup EXIT

archive="${tmpdir}/awscliv2.zip"
url="https://awscli.amazonaws.com/awscli-exe-linux-x86_64-${version}.zip"

printf '\n[awscli] Installing AWS CLI %s\n' "${version}"
curl --retry 5 --retry-all-errors -fsSL "${url}" -o "${archive}"
unzip -q "${archive}" -d "${tmpdir}"
"${tmpdir}/aws/install" --update
aws --version | grep -Fq "${version}"
