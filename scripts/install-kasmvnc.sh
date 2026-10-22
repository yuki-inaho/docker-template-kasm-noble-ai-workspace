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

export DEBIAN_FRONTEND=noninteractive
apt-get -o Acquire::Retries=5 -o APT::Update::Error-Mode=any update
apt-get -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold \
  install -y --no-install-recommends "$package_dir/kasmvnc.deb"
[[ "$(dpkg-query -W -f='${Version}' kasmvncserver)" == "$KASMVNC_PACKAGE_VERSION" ]]
Xvnc -version 2>&1 | tee "$package_dir/xvnc-version"
grep -Fq '12101025' "$package_dir/xvnc-version"
apt-get clean
rm -rf /var/lib/apt/lists/*
