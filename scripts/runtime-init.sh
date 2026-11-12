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

configure_home_profile() {
  local default_profile="${DEFAULT_PROFILE_HOME:-/home/kasm-default-profile}"
  local user_name user_id user_group
  user_name="$(basename "${HOME}")"
  if getent passwd "${user_name}" >/dev/null 2>&1; then
    user_id="$(id -u "${user_name}")"
    user_group="$(id -g "${user_name}")"
  else
    user_id="$(id -u)"
    user_group="$(id -g)"
  fi

  if [[ ! -d "${default_profile}" ]]; then
    log "Default profile ${default_profile} is missing; skipping home repair"
    return
  fi

  # The home directory itself must stay writable by the user even when another
  # startup script created it as root. OpenSSH StrictModes also rejects a
  # group/world-writable home, so keep it at 0755.
  run_sudo chown "${user_id}:${user_group}" "${HOME}" 2>/dev/null || true
  run_sudo chmod 0755 "${HOME}" 2>/dev/null || true

  # The template onstart may have linked ~/.cargo to the default profile. A
  # directory cannot be copied over that symlink, so remove only that exact
  # link before the no-clobber copy; user-created links are left alone.
  if [[ -L "${HOME}/.cargo" ]] && \
     [[ "$(readlink -f "${HOME}/.cargo" 2>/dev/null || true)" == "${default_profile}/.cargo" ]]; then
    run_sudo rm -f "${HOME}/.cargo" 2>/dev/null || true
  fi

  run_sudo install -d -m 0755 -o "${user_id}" -g "${user_group}" \
    "${HOME}/.config" "${HOME}/.cache" "${HOME}/.local/share" \
    "${HOME}/.local/state" "${HOME}/.local/bin" "${HOME}/.opencode/bin" \
    2>/dev/null || true

  # Vast.ai writes its own ~/.bashrc before Kasm copies the image profile, so
  # Kasm's "profile already exists" check skips the copy and the user home ends
  # up without the tools. Restore only missing entries; user files always win.
  # The marker avoids rescanning the multi-gigabyte profile on every restart.
  local marker="${HOME}/.kasm-profile-restored"
  if [[ ! -f "${marker}" ]] && \
     { [[ ! -x "${HOME}/.local/bin/herdr" ]] || \
       [[ ! -x "${HOME}/.opencode/bin/opencode" ]] || \
       [[ ! -s "${HOME}/.nvm/nvm.sh" ]] || \
       [[ ! -s "${HOME}/.cargo/env" ]]; }; then
    log "Restoring missing files from ${default_profile}"
    if run_sudo cp -an "${default_profile}/." "${HOME}/"; then
      run_sudo touch "${marker}" 2>/dev/null || true
      run_sudo chown "${user_id}:${user_group}" "${marker}" 2>/dev/null || true
    else
      log "Could not fully restore the default profile"
    fi
  fi

  # `cp -a src/. dest/` can apply the source directory's ownership and mode to
  # dest, so restore the home ownership and 0755 mode after the copy as well.
  # OpenSSH StrictModes rejects a group/world-writable home.
  run_sudo chown "${user_id}:${user_group}" "${HOME}" 2>/dev/null || true
  run_sudo chmod 0755 "${HOME}" 2>/dev/null || true

  # Only user-owned state is repaired. Kasm-managed files (.vast_api_key,
  # .kasmpasswd, .Xauthority, .vnc) are deliberately excluded.
  local dir
  for dir in .local .local/bin .local/share .local/state .config .cache .opencode \
             .opencode/bin .cargo .nv .gnupg \
             Desktop Documents Downloads Music Pictures Public Templates Videos PDF; do
    if [[ -e "${HOME}/${dir}" ]]; then
      run_sudo chown -R "${user_id}:${user_group}" "${HOME}/${dir}" 2>/dev/null || true
    fi
  done
  run_sudo chmod 0755 "${HOME}/.local" "${HOME}/.local/bin" 2>/dev/null || true

  # Link any tool that the copy could not add (for example when the home was
  # partly created by another startup script).
  local tool_dir source name
  for tool_dir in .local/bin .opencode/bin; do
    [[ -d "${default_profile}/${tool_dir}" ]] || continue
    run_sudo mkdir -p "${HOME}/${tool_dir}" 2>/dev/null || true
    for source in "${default_profile}/${tool_dir}"/*; do
      [[ -e "${source}" || -L "${source}" ]] || continue
      name="$(basename "${source}")"
      if [[ ! -e "${HOME}/${tool_dir}/${name}" && ! -L "${HOME}/${tool_dir}/${name}" ]]; then
        run_sudo ln -s "${source}" "${HOME}/${tool_dir}/${name}" 2>/dev/null || true
      fi
    done
    run_sudo chown -h "${user_id}:${user_group}" "${HOME}/${tool_dir}"/* 2>/dev/null || true
  done

  if [[ ! -e "${HOME}/.cargo" && ! -L "${HOME}/.cargo" && -d "${default_profile}/.cargo" ]]; then
    run_sudo ln -s "${default_profile}/.cargo" "${HOME}/.cargo" 2>/dev/null || true
  fi

  local profile="${HOME}/.profile"
  run_sudo touch "${profile}" 2>/dev/null || true
  run_sudo chown "${user_id}:${user_group}" "${profile}" 2>/dev/null || true
  if [[ -f "${profile}" ]] && \
     ! grep -Fq '# >>> kasm-noble-ai-workspace-profile' "${profile}"; then
    {
      printf '\n%s\n' '# >>> kasm-noble-ai-workspace-profile'
      printf '%s\n' 'export PATH="$HOME/.opencode/bin:$HOME/.local/bin:$HOME/.cargo/bin:$PATH"'
      printf '%s\n' 'if [ -n "${BASH_VERSION:-}" ] && [ -f "$HOME/.bashrc" ]; then'
      printf '%s\n' '  . "$HOME/.bashrc"'
      printf '%s\n' 'fi'
      printf '%s\n' '# <<< kasm-noble-ai-workspace-profile'
    } >> "${profile}" 2>/dev/null || true
  fi

  if [[ ! -f "${HOME}/.bashrc" ]]; then
    run_sudo cp "${default_profile}/.bashrc" "${HOME}/.bashrc" 2>/dev/null || true
  fi
  run_sudo chown "${user_id}:${user_group}" "${HOME}/.bashrc" 2>/dev/null || true
  # Vast's .bashrc exports an empty PYENV_ROOT and then evaluates `pyenv init`,
  # which prints "pyenv: command not found" on every login. Repair only that
  # exact broken assignment; the image block later sets the same value.
  if grep -Fqx 'export PYENV_ROOT=' "${HOME}/.bashrc" 2>/dev/null; then
    run_sudo sed -i 's|^export PYENV_ROOT=$|export PYENV_ROOT="/opt/pyenv"|' \
      "${HOME}/.bashrc" 2>/dev/null || true
  fi
  # Vast's own .bashrc replaces the image block (PATH, nvm, pyenv, aliases).
  # Append that block verbatim when it is missing; never overwrite user edits.
  if [[ -f "${HOME}/.bashrc" ]] && [[ -f "${default_profile}/.bashrc" ]] && \
     ! grep -Fqx '# >>> kasm-noble-ai-workspace' "${HOME}/.bashrc"; then
    run_sudo sed -n '/^# >>> kasm-noble-ai-workspace$/,/^# <<< kasm-noble-ai-workspace$/p' \
      "${default_profile}/.bashrc" >> "${HOME}/.bashrc" 2>/dev/null || true
  fi
  if [[ -f "${HOME}/.bashrc" ]] && \
     ! grep -Fq 'export PATH="$HOME/.opencode/bin:$HOME/.local/bin:$HOME/.cargo/bin:$PATH"' "${HOME}/.bashrc"; then
    {
      printf '\n%s\n' '# >>> kasm-noble-ai-workspace-runtime'
      printf '%s\n' 'case ":$PATH:" in'
      printf '%s\n' '  *":$HOME/.opencode/bin:"*) ;;'
      printf '%s\n' '  *) export PATH="$HOME/.opencode/bin:$HOME/.local/bin:$HOME/.cargo/bin:$PATH" ;;'
      printf '%s\n' 'esac'
      printf '%s\n' '# <<< kasm-noble-ai-workspace-runtime'
    } >> "${HOME}/.bashrc" 2>/dev/null || true
  fi
  run_sudo chown "${user_id}:${user_group}" "${profile}" "${HOME}/.bashrc" 2>/dev/null || true
}

configure_login_shell() {
  local user_name
  user_name="$(basename "${HOME}")"

  if ! getent passwd "${user_name}" >/dev/null 2>&1; then
    log "Cannot resolve the login user for ${HOME}; skipping shell change"
    return
  fi
  if [[ "$(getent passwd "${user_name}" | cut -d: -f7)" == "/bin/bash" ]]; then
    return
  fi
  run_sudo usermod -s /bin/bash "${user_name}" || \
    log "Could not change the login shell for ${user_name}"
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
  if [[ ! -e "${HOME}/Desktop/AI-SETUP.md" && ! -L "${HOME}/Desktop/AI-SETUP.md" ]]; then
    install -m 0644 /usr/local/share/kasm-noble-ai-workspace/AI-SETUP.md "${HOME}/Desktop/AI-SETUP.md" || \
      log "Could not install the AI setup instructions"
  fi
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
    setxkbmap -model pc105 -layout jp || true
  fi

  if command -v gsettings >/dev/null 2>&1; then
    # IBus on/off shortcuts are configured and locked in the system dconf
    # database so persistent user settings cannot restore conflicting grabs.
    gsettings set org.freedesktop.ibus.general preload-engines \
      "['xkb:jp::jpn', 'mozc-jp']" || true
    gsettings set org.freedesktop.ibus.general engines-order \
      "['mozc-jp', 'xkb:jp::jpn']" || true
  fi

  if command -v ibus-daemon >/dev/null 2>&1 && \
     ! pgrep -u "$(id -u)" -x ibus-daemon >/dev/null 2>&1; then
    ibus-daemon -drx >/tmp/ibus-daemon.log 2>&1 &
  fi
}

configure_remote_access() {
  if [[ -s "${HOME}/.ssh/authorized_keys" ]] && \
     ! pgrep -x sshd >/dev/null 2>&1; then
    run_sudo /usr/local/bin/kasm-remote-access start-ssh || true
  fi

  if [[ -s /etc/cloudflared/token ]] && \
     ! pgrep -f 'cloudflared.*tunnel run' >/dev/null 2>&1; then
    run_sudo /usr/local/bin/kasm-remote-access start-tunnel || true
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

  log "Applying runtime settings"
  configure_home_profile
  mkdir -p "${XDG_CONFIG_HOME}" "${XDG_CACHE_HOME}" "${XDG_DATA_HOME}"
  configure_login_shell
  configure_workspace
  configure_git_identity
  configure_japanese_input
  configure_remote_access
  configure_file_manager
  if [[ "${AUTO_UPDATE_TOOLS:-1}" == 1 ]] && [[ -x /usr/local/bin/workspace-update-tools ]]; then
    local update_user
    update_user="$(basename "${HOME}")"
    if [[ "$(id -u)" -eq 0 ]] && getent passwd "${update_user}" >/dev/null 2>&1; then
      run_sudo su -s /bin/bash "${update_user}" -c \
        'nohup /usr/local/bin/workspace-update-tools --watch >/dev/null 2>&1 &'
    else
      nohup /usr/local/bin/workspace-update-tools --watch >/dev/null 2>&1 &
    fi
  fi
  log "Runtime settings complete"
}

main "$@"
