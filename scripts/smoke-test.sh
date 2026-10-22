#!/usr/bin/env bash
set -uo pipefail

errors=0

pass() {
  printf '[OK]   %s\n' "$*"
}

fail() {
  printf '[FAIL] %s\n' "$*" >&2
  errors=$((errors + 1))
}

check_command() {
  local command_name="$1"
  shift

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    fail "${command_name} is not in PATH"
    return
  fi

  if "$@" >/tmp/image-smoke-test.out 2>&1; then
    pass "${command_name}: $(head -n 1 /tmp/image-smoke-test.out)"
  else
    fail "${command_name} exists but its version check failed"
    sed -n '1,5p' /tmp/image-smoke-test.out >&2
  fi
}

check_present() {
  local command_name="$1"

  if command -v "${command_name}" >/dev/null 2>&1; then
    pass "${command_name} is installed"
  else
    fail "${command_name} is not in PATH"
  fi
}

check_ibus_hotkeys() {
  local schema="org.freedesktop.ibus.general.hotkey"
  local trigger
  local triggers
  local trigger_writable
  local triggers_writable

  if ! command -v gsettings >/dev/null 2>&1; then
    fail "gsettings is not in PATH"
    return
  fi

  trigger="$(DCONF_PROFILE=ibus gsettings get "${schema}" trigger 2>/dev/null || true)"
  triggers="$(DCONF_PROFILE=ibus gsettings get "${schema}" triggers 2>/dev/null || true)"
  trigger_writable="$(DCONF_PROFILE=ibus gsettings writable "${schema}" trigger 2>/dev/null || true)"
  triggers_writable="$(DCONF_PROFILE=ibus gsettings writable "${schema}" triggers 2>/dev/null || true)"

  if [[ "${trigger}" == "['Control+space']" ]]; then
    pass "IBus legacy trigger is limited to Control+space"
  else
    fail "unexpected IBus trigger value: ${trigger:-<empty>}"
  fi

  if [[ "${triggers}" == "['<Control>space', '<Super>space']" ]]; then
    pass "IBus GTK triggers use Control+space and Super+space"
  else
    fail "unexpected IBus triggers value: ${triggers:-<empty>}"
  fi

  if [[ "${trigger}${triggers}" == *Zenkaku_Hankaku* || \
     "${trigger}${triggers}" == *Alt+grave* ]]; then
    fail "IBus triggers still contain a keycode-49 conflict"
  else
    pass "IBus triggers exclude Zenkaku_Hankaku and Alt+grave"
  fi

  if [[ "${trigger_writable}" == "false" && "${triggers_writable}" == "false" ]]; then
    pass "IBus trigger settings are locked against persistent user overrides"
  else
    fail "IBus trigger locks are missing"
  fi
}

check_japanese_keyboard_profile() {
  local xsessionrc="${HOME}/.xsessionrc"
  local autostart="${HOME}/.config/autostart/japanese-keyboard.desktop"

  if grep -Fq 'setxkbmap -model pc105 -layout jp' "${xsessionrc}" 2>/dev/null; then
    pass "X session config selects the JIS 106/109 keyboard layout"
  else
    fail "JIS keyboard configuration is missing from ${xsessionrc}"
  fi

  if grep -Fq "Exec=sh -lc 'setxkbmap -model pc105 -layout jp'" "${autostart}" 2>/dev/null; then
    pass "XFCE autostart reapplies the JIS keyboard layout"
  else
    fail "JIS keyboard autostart is missing from ${autostart}"
  fi

  if grep -Fq 'xkb:jp::jpn' /dockerstartup/runtime-init.sh && \
     ! grep -Fq 'xkb:us::eng' /dockerstartup/runtime-init.sh; then
    pass "IBus direct input keeps the Japanese XKB layout"
  else
    fail "IBus direct input is not configured for the Japanese XKB layout"
  fi

  if grep -Eq '^[[:space:]]*raw_keyboard:[[:space:]]*false[[:space:]]*$' \
      /usr/share/kasmvnc/kasmvnc_defaults.yaml; then
    pass "KasmVNC raw keyboard mode remains disabled"
  else
    fail "KasmVNC raw_keyboard default is no longer false"
  fi
}

check_apt_noninteractive() {
  local keyboard=/etc/default/keyboard
  local apt_conf=/etc/apt/apt.conf.d/90-kasm-noninteractive
  local sudoers=/etc/sudoers.d/91-kasm-noninteractive
  local output

  if grep -qx 'XKBLAYOUT="jp"' "${keyboard}" 2>/dev/null; then
    pass "/etc/default/keyboard uses the JIS layout"
  else
    fail "/etc/default/keyboard is not set to XKBLAYOUT=\"jp\""
  fi

  if debconf-show keyboard-configuration 2>/dev/null | grep -Fqx '* keyboard-configuration/layoutcode: jp'; then
    pass "keyboard-configuration layoutcode is jp and marked seen"
  else
    fail "keyboard-configuration layoutcode is not preseeded as seen jp"
  fi

  if debconf-show code 2>/dev/null | grep -Fqx '* code/add-microsoft-repo: true'; then
    pass "VS Code repository question is preseeded as seen"
  else
    fail "code/add-microsoft-repo is not preseeded as seen"
  fi

  if grep -Fq -- '--force-confold' "${apt_conf}" 2>/dev/null; then
    pass "apt preserves local configuration files"
  else
    fail "apt configuration file policy is missing"
  fi

  if sudo -n test -f "${sudoers}" 2>/dev/null && \
     sudo -n grep -Fq 'DEBIAN_FRONTEND' "${sudoers}" 2>/dev/null; then
    pass "sudo keeps DEBIAN_FRONTEND"
  else
    fail "sudo does not keep DEBIAN_FRONTEND"
  fi

  if sudo -n env 2>/dev/null | grep -Fqx 'DEBIAN_FRONTEND=noninteractive'; then
    pass "sudo preserves DEBIAN_FRONTEND=noninteractive"
  else
    fail "DEBIAN_FRONTEND is not preserved through sudo"
  fi

  output="$(timeout 30 sudo -n env DEBIAN_FRONTEND=teletype \
    debconf /var/lib/dpkg/info/keyboard-configuration.config < /dev/null 2>&1 || true)"
  if [[ "${output}" != *"Country of origin"* && "${output}" != *"Keyboard layout:"* ]]; then
    pass "keyboard-configuration config script asks no questions"
  else
    fail "keyboard-configuration config script still asks questions"
  fi
}

check_remote_access() {
  if dpkg-query -W -f='${db:Status-Status}' openssh-server 2>/dev/null | grep -qx installed; then
    pass "openssh-server is installed"
  else
    fail "openssh-server is not installed"
  fi

  if grep -Fq 'protocol: http2' /etc/cloudflared/config.yml 2>/dev/null; then
    pass "cloudflared is configured for http2"
  else
    fail "cloudflared http2 configuration is missing"
  fi

  if [[ -x /usr/local/bin/kasm-remote-access ]] && \
     /usr/local/bin/kasm-remote-access help >/dev/null 2>&1; then
    pass "kasm-remote-access helper is installed"
  else
    fail "kasm-remote-access helper is missing or not executable"
  fi

  if grep -Fqx 'PasswordAuthentication no' /etc/ssh/sshd_config.d/10-kasm.conf 2>/dev/null; then
    pass "sshd requires public-key authentication"
  else
    fail "sshd public-key configuration is missing"
  fi
}

check_xfce_panel() {
  local panel_xml="${HOME}/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"
  local launcher="${HOME}/.config/xfce4/panel/launcher-16/org.gnome.Nautilus.desktop"

  if [[ -f "${launcher}" ]] && grep -q '^Exec=nautilus' "${launcher}"; then
    pass "XFCE file manager launcher is installed"
  else
    fail "XFCE file manager launcher is missing"
  fi

  if python3 - "${panel_xml}" <<'PANEL_CHECK'
import sys
import xml.etree.ElementTree as ET

path = sys.argv[1]
root = ET.parse(path).getroot()
panel1 = root.find("property[@name='panels']/property[@name='panel-1']")
if panel1 is None:
    raise SystemExit(1)
ids = [int(v.get("value")) for v in panel1.find("property[@name='plugin-ids']")]
if 16 not in ids or 17 not in ids or ids.index(16) > ids.index(17):
    raise SystemExit(1)
clock = root.find("property[@name='plugins']/property[@name='plugin-17']")
if clock is None or clock.get("value") != "clock":
    raise SystemExit(1)
fmt = clock.find("property[@name='digital-time-format']")
if fmt is None or fmt.get("value") != "%H:%M:%S":
    raise SystemExit(1)
launcher = root.find("property[@name='plugins']/property[@name='plugin-16']")
if launcher is None or launcher.get("value") != "launcher":
    raise SystemExit(1)
items = launcher.find("property[@name='items']")
if items is None or not any(v.get("value") == "org.gnome.Nautilus.desktop" for v in items):
    raise SystemExit(1)
PANEL_CHECK
  then
    pass "XFCE panel shows the file manager and a clock with seconds"
  else
    fail "XFCE panel clock/launcher configuration is incomplete"
  fi
}

export PATH="${HOME}/.opencode/bin:${HOME}/.local/bin:${HOME}/.cargo/bin:/opt/pyenv/bin:${PATH}"
export PYENV_ROOT="/opt/pyenv"
export NVM_DIR="${HOME}/.nvm"
IMAGE_VARIANT="${IMAGE_VARIANT:-standard}"

if [[ -s "${NVM_DIR}/nvm.sh" ]]; then
  # shellcheck disable=SC1090
  source "${NVM_DIR}/nvm.sh"
  nvm use default >/dev/null 2>&1 || true
fi
if [[ -s "${HOME}/.cargo/env" ]]; then
  # shellcheck disable=SC1091
  source "${HOME}/.cargo/env"
fi

printf 'OS: '
grep '^PRETTY_NAME=' /etc/os-release | cut -d= -f2- | tr -d '"'

check_command git git --version
check_command gh gh --version
check_command pyenv pyenv --version
check_command poetry poetry --version
check_command uv uv --version
check_command rustc rustc --version
check_command cargo cargo --version
check_command just just --version
check_command node node --version
check_command npm npm --version
check_command image-security-check image-security-check
check_command codex codex --version
check_command claude claude --version
check_command opencode opencode --version
check_command playwright-cli playwright-cli --version
check_command playwright playwright --version
check_command rtk rtk --version
check_command pixi pixi --version
check_command herdr herdr --version
check_command agent-jsonl-compact agent-jsonl-compact --version
check_command jq jq --version
check_command sqlite3 sqlite3 --version
check_command rg rg --version
check_command fdfind fdfind --version
check_command fzf fzf --version
check_command yq yq --version
check_command tree tree --version
check_command cloudflared cloudflared --version
check_command vlc vlc --version
check_command google-chrome bash -lc 'google-chrome --version 2>/dev/null'
check_ibus_hotkeys
check_japanese_keyboard_profile

if [[ -f "${HOME}/.codex/skills/agent-jsonl-compact-reader/SKILL.md" && \
      -f "${HOME}/.claude/skills/agent-jsonl-compact-reader/SKILL.md" ]]; then
  pass "agent-jsonl-compact reader skills are installed for Codex and Claude"
else
  fail "agent-jsonl-compact reader skills are missing from the default profile"
fi

plugin_package="$(find "${HOME}/.cache/opencode/npm" \
  -path '*/node_modules/@prevalentware/opencode-goal-plugin/package.json' \
  -print -quit 2>/dev/null)"

if grep -Fq '"plugins"' "${HOME}/.config/opencode/opencode.json" 2>/dev/null && \
   grep -Fq '@prevalentware/opencode-goal-plugin' "${HOME}/.config/opencode/opencode.json" 2>/dev/null && \
   grep -Fq '@prevalentware/opencode-goal-plugin' "${HOME}/.config/opencode/cli.json" 2>/dev/null && \
   [[ -n "${plugin_package}" ]]; then
  pass "OpenCode 2 goal plugin is configured in opencode.json and cli.json and cached"
else
  fail "OpenCode 2 goal plugin is missing from opencode.json / cli.json / plugin cache"
fi

if [[ -f "${HOME}/.playwright/cli.config.json" ]] && \
   grep -Fq '"channel": "chrome"' "${HOME}/.playwright/cli.config.json" && \
   grep -Fq '"chromiumSandbox": false' "${HOME}/.playwright/cli.config.json"; then
  pass "Playwright CLI is configured to reuse the system Chrome without the sandbox"
else
  fail "Playwright CLI global config is missing or incomplete"
fi

if [[ -f "${HOME}/.agents/skills/agmsg/SKILL.md" && \
      -x "${HOME}/.agents/skills/agmsg/scripts/version.sh" && \
      -f "${HOME}/.config/opencode/skills/agmsg/SKILL.md" && \
      -f "${HOME}/.claude/commands/agmsg.md" ]]; then
  pass "agmsg is installed with OpenCode and Claude integration"
else
  fail "agmsg installation is incomplete (skill, version.sh, OpenCode skill, or Claude command missing)"
fi

if bash -ic 'alias opencode-auto' 2>/dev/null | grep -Fq 'opencode --auto'; then
  pass "opencode-auto alias is registered in the default profile"
else
  fail "opencode-auto alias is missing from the default profile"
fi

if grep -Fq -- '-sslOnly' /dockerstartup/vnc_startup.http.sh; then
  fail "HTTP VNC startup script still enforces -sslOnly"
else
  pass "HTTP VNC startup script accepts plain HTTP/WebSocket connections"
fi

if grep -Fq -- '-sslOnly' /dockerstartup/vnc_startup.ssl.sh; then
  pass "TLS VNC startup script enforces -sslOnly"
else
  fail "TLS VNC startup script does not enforce -sslOnly"
fi

if awk '
  /^[[:space:]]*pem_key:/ {
    getline
    if ($0 ~ /^[[:space:]]*require_ssl:[[:space:]]*false[[:space:]]*$/) {
      found = 1
    }
  }
  END { exit !found }
' /etc/kasmvnc/kasmvnc.yaml; then
  pass "KasmVNC permits HTTP when the HTTP startup script is selected"
else
  fail "KasmVNC require_ssl: false is missing below pem_key"
fi

case "${IMAGE_VARIANT}" in
  standard)
    if command -v chromium >/dev/null 2>&1; then
      fail "chromium must not be installed in the standard image"
    else
      pass "standard image does not include Chromium"
    fi
    ;;
  full)
    check_command chromium chromium --version
    ;;
  *)
    fail "unknown IMAGE_VARIANT: ${IMAGE_VARIANT}"
    ;;
esac

check_command ibus ibus version
# These GUI applications try to open an X display even for --version. Presence
# is the useful build-time contract; desktop launch is covered at runtime.
check_present nautilus
check_present nomacs
check_present gedit
check_command emacs emacs --version
check_command aws aws --version
check_apt_noninteractive
check_remote_access
check_xfce_panel

if command -v code >/dev/null 2>&1 || command -v code-insiders >/dev/null 2>&1; then
  fail "VS Code is installed but is not required by this image"
else
  pass "VS Code is not installed"
fi

if [[ -x /usr/local/bin/aws-runpod ]]; then
  pass "aws-runpod wrapper is installed"
else
  fail "aws-runpod wrapper is missing"
fi

if command -v nvidia-smi >/dev/null 2>&1; then
  if nvidia-smi >/tmp/image-smoke-test-nvidia.out 2>&1; then
    pass "NVIDIA runtime is available"
  else
    printf '[WARN] nvidia-smi exists but no GPU is attached to this container\n'
  fi
else
  printf '[WARN] nvidia-smi is not present; attach a GPU runtime when testing GPU support\n'
fi

rm -f /tmp/image-smoke-test.out /tmp/image-smoke-test-nvidia.out

if (( errors > 0 )); then
  printf '\nSmoke test failed with %d error(s).\n' "${errors}" >&2
  exit 1
fi

printf '\nAll required command checks passed.\n'
