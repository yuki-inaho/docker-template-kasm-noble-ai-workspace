#!/usr/bin/env bash
# Update the system Chrome and, when present, the opt-in Chromium snapshot.
set -euo pipefail
[[ "$(id -u)" == 0 ]] || { echo "Run as root" >&2; exit 1; }
# The unprivileged version probe must be able to traverse the extracted files.
umask 022
export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l
# Chromium and package hooks must not create root-owned files in the user's home.
export HOME=/root XDG_CONFIG_HOME=/root/.config XDG_CACHE_HOME=/root/.cache XDG_DATA_HOME=/root/.local/share
apt-get -o Acquire::Retries=3 -o APT::Update::Error-Mode=any update
apt-get -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold \
  install -y --no-install-recommends google-chrome-stable

# The standard variant intentionally has no standalone Chromium.
[[ -x /usr/local/bin/chromium && -d /opt/chromium ]] || exit 0
base="https://www.googleapis.com/download/storage/v1/b/chromium-browser-snapshots/o/Linux_x64"
revision="$(curl -fsSL --retry 3 --connect-timeout 15 --max-time 120 --proto "=https" --proto-redir "=https" "$base%2FLAST_CHANGE?alt=media")"
[[ "$revision" =~ ^[0-9]+$ ]] || { echo "Invalid Chromium revision" >&2; exit 1; }
current="$(cat /usr/local/share/kasm-noble-ai-workspace/chromium-revision 2>/dev/null || true)"
[[ "$current" != "$revision" ]] || exit 0
metadata="$(curl -fsSL --retry 3 --connect-timeout 15 --max-time 120 --proto "=https" --proto-redir "=https" "https://www.googleapis.com/storage/v1/b/chromium-browser-snapshots/o/Linux_x64%2F$revision%2Fchrome-linux.zip")"
expected="$(jq -er .md5Hash <<< "$metadata")"
tmp="$(mktemp -d /opt/.chromium-update.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
curl -fsSL --retry 3 --connect-timeout 15 --max-time 600 --proto "=https" --proto-redir "=https" "$base%2F$revision%2Fchrome-linux.zip?alt=media" -o "$tmp/chrome.zip"
actual="$(openssl dgst -md5 -binary "$tmp/chrome.zip" | openssl base64 -A)"
[[ "$actual" == "$expected" ]] || { echo "Chromium archive checksum mismatch" >&2; exit 1; }
sha256sum "$tmp/chrome.zip"
unzip -q "$tmp/chrome.zip" -d "$tmp/unpacked"
test -x "$tmp/unpacked/chrome-linux/chrome"
# Probe newly downloaded code without root privileges or access to the user's home.
chmod 0755 "$tmp"
runuser -u nobody -- env HOME=/tmp XDG_CONFIG_HOME=/tmp XDG_CACHE_HOME=/tmp \
  "$tmp/unpacked/chrome-linux/chrome" --no-sandbox --version
if [[ -f "$tmp/unpacked/chrome-linux/chrome_sandbox" ]]; then
  chown root:root "$tmp/unpacked/chrome-linux/chrome_sandbox"
  chmod 4755 "$tmp/unpacked/chrome-linux/chrome_sandbox"
fi
install -d -m 0755 /opt/kasm-chromium
release="/opt/kasm-chromium/$revision"
[[ ! -e "$release" ]] || { echo "Chromium release directory already exists" >&2; exit 1; }
mv "$tmp/unpacked" "$release"
if [[ ! -L /opt/chromium ]]; then
  mv /opt/chromium "/opt/kasm-chromium/inherited-$(date +%s)-$$"
fi
ln -s "$release" /opt/.chromium-next-$$
mv -Tf /opt/.chromium-next-$$ /opt/chromium
printf "%s\n" "$revision" > /usr/local/share/kasm-noble-ai-workspace/chromium-revision
printf "Updated Chromium snapshot to revision %s\n" "$revision"
# Previous directories are kept because an open browser may still read them.
