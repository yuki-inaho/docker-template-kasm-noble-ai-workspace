#!/usr/bin/env bash
# Install the reviewed fork package, preserving the existing Kasm configuration.
set -euo pipefail

[[ "$(id -u)" -eq 0 ]] || { echo "Run as root" >&2; exit 1; }
[[ "$(dpkg --print-architecture)" == amd64 ]] || { echo "Only amd64 is supported" >&2; exit 1; }
: "${KASMVNC_DEB_URL:?KASMVNC_DEB_URL is required}"
: "${KASMVNC_DEB_SHA256:?KASMVNC_DEB_SHA256 is required}"
: "${KASMVNC_PACKAGE_VERSION:?KASMVNC_PACKAGE_VERSION is required}"
[[ "$KASMVNC_DEB_URL" == https://github.com/yuki-inaho/KasmVNC/releases/download/* ]] ||
  { echo "Unexpected package origin" >&2; exit 1; }
[[ "$KASMVNC_DEB_SHA256" =~ ^[0-9a-f]{64}$ ]] ||
  { echo "Invalid SHA256" >&2; exit 1; }

package_dir="$(mktemp -d)"
trap 'rm -rf "$package_dir"' EXIT
curl --fail --location --retry 5 --proto '=https' --proto-redir '=https' \
  "$KASMVNC_DEB_URL" -o "$package_dir/kasmvnc.deb"
printf '%s  %s\n' "$KASMVNC_DEB_SHA256" "$package_dir/kasmvnc.deb" | sha256sum --check -
[[ "$(dpkg-deb -f "$package_dir/kasmvnc.deb" Package)" == kasmvncserver ]]
[[ "$(dpkg-deb -f "$package_dir/kasmvnc.deb" Architecture)" == amd64 ]]
[[ "$(dpkg-deb -f "$package_dir/kasmvnc.deb" Version)" == "$KASMVNC_PACKAGE_VERSION" ]]

installed_version="$(dpkg-query -W -f='${Version}' kasmvncserver 2>/dev/null || true)"
if [[ -n "$installed_version" ]]; then
  echo "kasmvncserver before: ${installed_version}"
  if dpkg --compare-versions "$installed_version" gt "$KASMVNC_PACKAGE_VERSION"; then
    echo "Refusing downgrade: installed ${installed_version} is newer than target ${KASMVNC_PACKAGE_VERSION}" >&2
    exit 1
  fi
else
  echo "kasmvncserver before: none"
fi

export DEBIAN_FRONTEND=noninteractive
apt-get -o Acquire::Retries=5 -o APT::Update::Error-Mode=any update
apt-get -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold \
  install -y --no-install-recommends "$package_dir/kasmvnc.deb"
installed_after="$(dpkg-query -W -f='${Version}' kasmvncserver)"
echo "kasmvncserver after: ${installed_after}"
[[ "$installed_after" == "$KASMVNC_PACKAGE_VERSION" ]] ||
  { echo "Installed version mismatch: expected ${KASMVNC_PACKAGE_VERSION}, got ${installed_after}" >&2; exit 1; }

xvnc_output="$(Xvnc -version 2>&1)"
printf '%s\n' "$xvnc_output" | tee "$package_dir/xvnc-version"
xorg_version="$(printf '%s\n' "$xvnc_output" | sed -n 's/.*Underlying X server release //p')"
[[ "$xorg_version" =~ ^[0-9]+$ ]] ||
  { echo "Cannot determine embedded X.Org version" >&2; exit 1; }
if (( 10#$xorg_version < 12101025 )); then
  echo "Embedded X.Org ${xorg_version} is below required 12101025" >&2
  exit 1
fi
apt-get clean
rm -rf /var/lib/apt/lists/*
