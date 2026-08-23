#!/usr/bin/env bash
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "install-chromium.sh must run as root" >&2
  exit 1
fi

revision="${CHROMIUM_REVISION:-}"
install_dir="/opt/chromium"
snapshot_base="https://www.googleapis.com/download/storage/v1/b/chromium-browser-snapshots/o/Linux_x64"
tmp_dir="$(mktemp -d)"
archive="${tmp_dir}/chromium-linux.zip"

cleanup() {
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

if [[ -z "${revision}" ]]; then
  revision="$(curl --retry 5 --retry-all-errors -fsSL "${snapshot_base}%2FLAST_CHANGE?alt=media")"
fi

if [[ ! "${revision}" =~ ^[0-9]+$ ]]; then
  echo "Invalid Chromium revision: ${revision}" >&2
  exit 1
fi

printf '[chromium] Installing snapshot revision %s\n' "${revision}"

curl --retry 5 --retry-all-errors -fL --progress-bar \
  -o "${archive}" \
  "${snapshot_base}%2F${revision}%2Fchrome-linux.zip?alt=media"

rm -rf "${install_dir}"
mkdir -p "${install_dir}"
unzip -q "${archive}" -d "${install_dir}"

if [[ ! -x "${install_dir}/chrome-linux/chrome" ]]; then
  echo "Chromium executable was not found after extraction" >&2
  exit 1
fi

if [[ -f "${install_dir}/chrome-linux/chrome_sandbox" ]]; then
  chown root:root "${install_dir}/chrome-linux/chrome_sandbox"
  chmod 4755 "${install_dir}/chrome-linux/chrome_sandbox"
fi

cat > /usr/local/bin/chromium <<'WRAPPER'
#!/usr/bin/env bash
set -euo pipefail

export CHROME_DEVEL_SANDBOX=/opt/chromium/chrome-linux/chrome_sandbox
args=()

# Kasm/RunPod/Vast containers commonly run without the namespace permissions
# Chromium's sandbox expects. Set CHROMIUM_NO_SANDBOX=0 to try the setuid sandbox.
if [[ "${CHROMIUM_NO_SANDBOX:-1}" == "1" ]]; then
  args+=(--no-sandbox)
fi

exec /opt/chromium/chrome-linux/chrome "${args[@]}" "$@"
WRAPPER
chmod 0755 /usr/local/bin/chromium

cat > /usr/local/bin/chromium-browser <<'WRAPPER'
#!/usr/bin/env bash
exec /usr/local/bin/chromium "$@"
WRAPPER
chmod 0755 /usr/local/bin/chromium-browser

cat > /usr/share/applications/chromium.desktop <<'DESKTOP'
[Desktop Entry]
Version=1.0
Name=Chromium
GenericName=Web Browser
Comment=Access the Internet
Exec=chromium %U
Terminal=false
Icon=/opt/chromium/chrome-linux/product_logo_48.png
Type=Application
Categories=Network;WebBrowser;
MimeType=text/html;text/xml;application/xhtml+xml;x-scheme-handler/http;x-scheme-handler/https;
StartupNotify=true
DESKTOP

mkdir -p /usr/local/share/kasm-noble-ai-workspace
printf '%s\n' "${revision}" > /usr/local/share/kasm-noble-ai-workspace/chromium-revision

CHROMIUM_NO_SANDBOX=1 chromium --version
