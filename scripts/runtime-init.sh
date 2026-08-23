#!/usr/bin/env bash
set -u

log() {
  printf '[runtime-init] %s\n' "$*"
}

run_sudo() {
  if command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
    sudo -n "$@"
  else
    "$@"
  fi
}

configure_workspace() {
  local workspace="${WORKSPACE_DIR:-/workspace}"

  if [[ "${WORKSPACE_CHOWN:-1}" == "1" ]]; then
    run_sudo mkdir -p "${workspace}" || true
    run_sudo chown "$(id -u):0" "${workspace}" || true
    run_sudo chmod 2775 "${workspace}" || true
  else
    mkdir -p "${workspace}" 2>/dev/null || true
  fi

  mkdir -p "${HOME}/Desktop"
  if [[ -e "${HOME}/Desktop/workspace" && ! -L "${HOME}/Desktop/workspace" ]]; then
    log "Desktop/workspace already exists and is not a symlink; leaving it unchanged"
  else
    ln -sfn "${workspace}" "${HOME}/Desktop/workspace"
  fi

  if command -v git >/dev/null 2>&1; then
    if ! git config --global --get-all safe.directory 2>/dev/null | grep -Fqx "${workspace}"; then
      git config --global --add safe.directory "${workspace}"
    fi
  fi
}

configure_git_identity() {
  if ! command -v git >/dev/null 2>&1; then
    return
  fi

  if [[ -n "${GIT_USER_NAME:-}" ]]; then
    git config --global user.name "${GIT_USER_NAME}"
  fi
  if [[ -n "${GIT_USER_EMAIL:-}" ]]; then
    git config --global user.email "${GIT_USER_EMAIL}"
  fi
  git config --global init.defaultBranch "${GIT_DEFAULT_BRANCH:-main}"
}

configure_japanese_input() {
  if [[ "${ENABLE_JAPANESE_INPUT:-1}" != "1" ]]; then
    return
  fi

  export GTK_IM_MODULE=ibus
  export QT_IM_MODULE=ibus
  export XMODIFIERS=@im=ibus

  if [[ -n "${DISPLAY:-}" ]] && command -v setxkbmap >/dev/null 2>&1; then
    setxkbmap -layout jp || true
  fi

  if command -v gsettings >/dev/null 2>&1; then
    gsettings set org.freedesktop.ibus.general.hotkey triggers \
      "['Zenkaku_Hankaku', '<Super>space', 'Control+space']" || true
    gsettings set org.freedesktop.ibus.general preload-engines \
      "['xkb:us::eng', 'mozc-jp']" || true
    gsettings set org.freedesktop.ibus.general engines-order \
      "['mozc-jp', 'xkb:us::eng']" || true
  fi

  if command -v ibus-daemon >/dev/null 2>&1 && \
     ! pgrep -u "$(id -u)" -x ibus-daemon >/dev/null 2>&1; then
    ibus-daemon -drx >/tmp/ibus-daemon.log 2>&1 &
  fi
}

configure_file_manager() {
  if command -v xdg-mime >/dev/null 2>&1 && \
     [[ -f /usr/share/applications/org.gnome.Nautilus.desktop ]]; then
    xdg-mime default org.gnome.Nautilus.desktop inode/directory || true
    xdg-mime default org.gnome.Nautilus.desktop application/x-gnome-saved-search || true
  fi
}

main() {
  export XDG_CONFIG_HOME="${HOME}/.config"
  export XDG_CACHE_HOME="${HOME}/.cache"
  export XDG_DATA_HOME="${HOME}/.local/share"
  mkdir -p "${XDG_CONFIG_HOME}" "${XDG_CACHE_HOME}" "${XDG_DATA_HOME}"

  log "Applying runtime settings"
  configure_workspace
  configure_git_identity
  configure_japanese_input
  configure_file_manager
  log "Runtime settings complete"
}

main "$@"
