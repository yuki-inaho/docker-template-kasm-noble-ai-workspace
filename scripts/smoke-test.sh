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

export PATH="${HOME}/.local/bin:${HOME}/.cargo/bin:/opt/pyenv/bin:${PATH}"
export PYENV_ROOT="/opt/pyenv"
export NVM_DIR="${HOME}/.nvm"
IMAGE_VARIANT="${IMAGE_VARIANT:-standard}"

if [[ -s "${NVM_DIR}/nvm.sh" ]]; then
  # shellcheck disable=SC1090
  source "${NVM_DIR}/nvm.sh"
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
check_command codex codex --version
check_command claude claude --version
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
check_command google-chrome bash -lc 'google-chrome --version 2>/dev/null'
check_ibus_hotkeys
check_japanese_keyboard_profile

if [[ -f "${HOME}/.codex/skills/agent-jsonl-compact-reader/SKILL.md" && \
      -f "${HOME}/.claude/skills/agent-jsonl-compact-reader/SKILL.md" ]]; then
  pass "agent-jsonl-compact reader skills are installed for Codex and Claude"
else
  fail "agent-jsonl-compact reader skills are missing from the default profile"
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
check_command emacs emacs --version

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
