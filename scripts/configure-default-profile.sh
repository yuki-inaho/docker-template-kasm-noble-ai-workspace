#!/usr/bin/env bash
set -euo pipefail

if [[ "$(id -u)" -eq 0 ]]; then
  echo "configure-default-profile.sh must run as the Kasm user" >&2
  exit 1
fi

BASHRC="${HOME}/.bashrc"
SESSIONRC="${HOME}/.xsessionrc"
AUTOSTART_DIR="${HOME}/.config/autostart"
XFCE_DIR="${HOME}/.config/xfce4"

replace_block() {
  local file="$1"
  local begin="$2"
  local end="$3"
  local content_file="$4"
  local tmp

  tmp="$(mktemp)"
  touch "${file}"
  sed "/^${begin}$/,/^${end}$/d" "${file}" > "${tmp}"
  cat "${content_file}" >> "${tmp}"
  mv "${tmp}" "${file}"
}

configure_bashrc() {
  local block
  block="$(mktemp)"
  cat > "${block}" <<'BLOCK'
# >>> kasm-noble-ai-workspace
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_DATA_HOME="$HOME/.local/share"
export PYENV_ROOT="/opt/pyenv"
[[ -d "$PYENV_ROOT/bin" ]] && export PATH="$PYENV_ROOT/bin:$PATH"
command -v pyenv >/dev/null 2>&1 && eval "$(pyenv init - bash)"

export NVM_DIR="$HOME/.nvm"
[[ -s "$NVM_DIR/nvm.sh" ]] && . "$NVM_DIR/nvm.sh"
[[ -s "$NVM_DIR/bash_completion" ]] && . "$NVM_DIR/bash_completion"

export GTK_IM_MODULE=ibus
export QT_IM_MODULE=ibus
export XMODIFIERS=@im=ibus

alias claude-auto='CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 claude --dangerously-skip-permissions'
alias codex-auto='codex --dangerously-bypass-approvals-and-sandbox'

if [[ $- == *i* ]] && [[ "${AUTO_CD_WORKSPACE:-1}" == "1" ]] && \
   [[ "${PWD}" == "${HOME}" ]] && [[ -d "${WORKSPACE_DIR:-/workspace}" ]]; then
  cd "${WORKSPACE_DIR:-/workspace}"
fi
# <<< kasm-noble-ai-workspace
BLOCK

  replace_block "${BASHRC}" \
    '# >>> kasm-noble-ai-workspace' \
    '# <<< kasm-noble-ai-workspace' \
    "${block}"
  rm -f "${block}"
}

configure_xsession() {
  local block
  block="$(mktemp)"
  cat > "${block}" <<'BLOCK'
# >>> kasm-noble-ai-workspace
export GTK_IM_MODULE=ibus
export QT_IM_MODULE=ibus
export XMODIFIERS=@im=ibus

if command -v setxkbmap >/dev/null 2>&1; then
  setxkbmap -model pc105 -layout jp || true
fi
# <<< kasm-noble-ai-workspace
BLOCK

  replace_block "${SESSIONRC}" \
    '# >>> kasm-noble-ai-workspace' \
    '# <<< kasm-noble-ai-workspace' \
    "${block}"
  rm -f "${block}"
}

configure_ibus_autostart() {
  mkdir -p "${AUTOSTART_DIR}"
  cat > "${AUTOSTART_DIR}/ibus-daemon.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=IBus Daemon
Comment=Start Japanese input method
Exec=sh -lc 'pgrep -u "$(id -u)" -x ibus-daemon >/dev/null 2>&1 || ibus-daemon -drx'
OnlyShowIn=XFCE;
X-GNOME-Autostart-enabled=true
NoDisplay=true
DESKTOP

  im-config -n ibus || true
}

configure_keyboard_autostart() {
  mkdir -p "${AUTOSTART_DIR}"
  cat > "${AUTOSTART_DIR}/japanese-keyboard.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Japanese Keyboard Layout
Comment=Apply the JIS 106/109 keyboard layout after XFCE starts
Exec=sh -lc 'setxkbmap -model pc105 -layout jp'
OnlyShowIn=XFCE;
X-GNOME-Autostart-enabled=true
NoDisplay=true
DESKTOP
}

configure_file_manager() {
  mkdir -p "${XFCE_DIR}"
  local helpers="${XFCE_DIR}/helpers.rc"
  touch "${helpers}"

  if grep -q '^FileManager=' "${helpers}"; then
    sed -i 's/^FileManager=.*/FileManager=nautilus/' "${helpers}"
  else
    printf '%s\n' 'FileManager=nautilus' >> "${helpers}"
  fi
}

main() {
  mkdir -p "${HOME}/Desktop"
  configure_bashrc
  configure_xsession
  configure_ibus_autostart
  configure_keyboard_autostart
  configure_file_manager
}

main "$@"
