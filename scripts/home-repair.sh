#!/usr/bin/env bash
# Repair the Kasm user's home, login profile and shell.
#
# This script is the single source of truth for the repair. It is executed by
# the image's custom_startup (runtime-init.sh) and by the Vast.ai template
# onstart. It is safe to run repeatedly.
set -u

KASM_USER_HOME="${KASM_USER_HOME:-/home/kasm-user}"
DEFAULT_PROFILE_HOME="${DEFAULT_PROFILE_HOME:-/home/kasm-default-profile}"
KASM_HOME_REPAIR="${KASM_HOME_REPAIR:-1}"
KASM_HOME_REPAIR_FORCE="${KASM_HOME_REPAIR_FORCE:-0}"

home_repair_log() {
  printf '[home-repair] %s\n' "$*"
}

home_repair_run_sudo() {
  if command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
    sudo -n "$@"
  else
    "$@"
  fi
}

configure_home_profile() {
  local default_profile="${DEFAULT_PROFILE_HOME}"
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
    home_repair_log "Default profile ${default_profile} is missing; skipping home repair"
    return
  fi

  # The home directory itself must stay writable by the user even when another
  # startup script created it as root. OpenSSH StrictModes also rejects a
  # group/world-writable home, so keep it at 0755.
  home_repair_run_sudo chown "${user_id}:${user_group}" "${HOME}" 2>/dev/null || true
  home_repair_run_sudo chmod 0755 "${HOME}" 2>/dev/null || true

  # The template onstart may have linked ~/.cargo to the default profile. A
  # directory cannot be copied over that symlink, so remove only that exact
  # link before the no-clobber copy; user-created links are left alone.
  if [[ -L "${HOME}/.cargo" ]] && \
     [[ "$(readlink -f "${HOME}/.cargo" 2>/dev/null || true)" == "${default_profile}/.cargo" ]]; then
    home_repair_run_sudo rm -f "${HOME}/.cargo" 2>/dev/null || true
  fi

  home_repair_run_sudo install -d -m 0755 -o "${user_id}" -g "${user_group}" \
    "${HOME}/.config" "${HOME}/.cache" "${HOME}/.local/share" \
    "${HOME}/.local/state" "${HOME}/.local/bin" "${HOME}/.opencode/bin" \
    2>/dev/null || true

  # Vast.ai writes its own ~/.bashrc before Kasm copies the image profile, so
  # Kasm's "profile already exists" check skips the copy and the user home ends
  # up without the tools. Restore only missing entries; user files always win.
  # The marker avoids rescanning the multi-gigabyte profile on every restart.
  local marker="${HOME}/.kasm-profile-restored"
  if [[ "${KASM_HOME_REPAIR_FORCE}" == "1" ]]; then
    home_repair_run_sudo rm -f "${marker}" 2>/dev/null || true
  fi
  if [[ ! -f "${marker}" ]] && \
     { [[ ! -x "${HOME}/.local/bin/herdr" ]] || \
       [[ ! -x "${HOME}/.opencode/bin/opencode" ]] || \
       [[ ! -s "${HOME}/.nvm/nvm.sh" ]] || \
       [[ ! -s "${HOME}/.cargo/env" ]]; }; then
    home_repair_log "Restoring missing files from ${default_profile}"
    if home_repair_run_sudo cp -a --update=none "${default_profile}/." "${HOME}/"; then
      home_repair_run_sudo touch "${marker}" 2>/dev/null || true
      home_repair_run_sudo chown "${user_id}:${user_group}" "${marker}" 2>/dev/null || true
    else
      home_repair_log "Could not fully restore the default profile"
    fi
  fi

  # `cp -a src/. dest/` can apply the source directory's ownership and mode to
  # dest, so restore the home ownership and 0755 mode after the copy as well.
  # OpenSSH StrictModes rejects a group/world-writable home.
  home_repair_run_sudo chown "${user_id}:${user_group}" "${HOME}" 2>/dev/null || true
  home_repair_run_sudo chmod 0755 "${HOME}" 2>/dev/null || true

  # Only user-owned state is repaired. Kasm-managed files (.vast_api_key,
  # .kasmpasswd, .Xauthority, .vnc) are deliberately excluded.
  local dir
  for dir in .local .local/bin .local/share .local/state .config .cache .opencode \
             .opencode/bin .cargo .nv .gnupg \
             Desktop Documents Downloads Music Pictures Public Templates Videos PDF; do
    if [[ -e "${HOME}/${dir}" ]]; then
      home_repair_run_sudo chown -R "${user_id}:${user_group}" "${HOME}/${dir}" 2>/dev/null || true
    fi
  done
  home_repair_run_sudo chmod 0755 "${HOME}/.local" "${HOME}/.local/bin" 2>/dev/null || true

  # Link any tool that the copy could not add (for example when the home was
  # partly created by another startup script).
  local tool_dir source name
  for tool_dir in .local/bin .opencode/bin; do
    [[ -d "${default_profile}/${tool_dir}" ]] || continue
    home_repair_run_sudo mkdir -p "${HOME}/${tool_dir}" 2>/dev/null || true
    for source in "${default_profile}/${tool_dir}"/*; do
      [[ -e "${source}" || -L "${source}" ]] || continue
      name="$(basename "${source}")"
      if [[ ! -e "${HOME}/${tool_dir}/${name}" && ! -L "${HOME}/${tool_dir}/${name}" ]]; then
        home_repair_run_sudo ln -s "${source}" "${HOME}/${tool_dir}/${name}" 2>/dev/null || true
      fi
    done
    home_repair_run_sudo chown -h "${user_id}:${user_group}" "${HOME}/${tool_dir}"/* 2>/dev/null || true
  done

  if [[ ! -e "${HOME}/.cargo" && ! -L "${HOME}/.cargo" && -d "${default_profile}/.cargo" ]]; then
    home_repair_run_sudo ln -s "${default_profile}/.cargo" "${HOME}/.cargo" 2>/dev/null || true
  fi

  local profile="${HOME}/.profile"
  home_repair_run_sudo touch "${profile}" 2>/dev/null || true
  home_repair_run_sudo chown "${user_id}:${user_group}" "${profile}" 2>/dev/null || true
  if [[ -f "${profile}" ]] && \
     ! grep -Fq '# >>> kasm-noble-ai-workspace-profile' "${profile}"; then
    {
      printf '\n%s\n' '# >>> kasm-noble-ai-workspace-profile'
      printf '%s\n' 'case ":$PATH:" in'
      printf '%s\n' '  *":$HOME/.opencode/bin:"*) ;;'
      printf '%s\n' '  *) export PATH="$HOME/.opencode/bin:$HOME/.local/bin:$HOME/.cargo/bin:$PATH" ;;'
      printf '%s\n' 'esac'
      printf '%s\n' 'if [ -n "${BASH_VERSION:-}" ] && [ -f "$HOME/.bashrc" ]; then'
      printf '%s\n' '  . "$HOME/.bashrc"'
      printf '%s\n' 'fi'
      printf '%s\n' '# <<< kasm-noble-ai-workspace-profile'
    } >> "${profile}" 2>/dev/null || true
  fi

  if [[ ! -f "${HOME}/.bashrc" ]]; then
    home_repair_run_sudo cp "${default_profile}/.bashrc" "${HOME}/.bashrc" 2>/dev/null || true
  fi
  home_repair_run_sudo chown "${user_id}:${user_group}" "${HOME}/.bashrc" 2>/dev/null || true
  # Vast's .bashrc exports an empty PYENV_ROOT and then evaluates `pyenv init`,
  # which prints "pyenv: command not found" on every login. Repair only that
  # exact broken assignment; the image block later sets the same value.
  if grep -Fqx 'export PYENV_ROOT=' "${HOME}/.bashrc" 2>/dev/null; then
    home_repair_run_sudo sed -i 's|^export PYENV_ROOT=$|export PYENV_ROOT="/opt/pyenv"|' \
      "${HOME}/.bashrc" 2>/dev/null || true
  fi
  # Vast's own .bashrc replaces the image block (PATH, nvm, pyenv, aliases).
  # Append that block verbatim when it is missing; never overwrite user edits.
  if [[ -f "${HOME}/.bashrc" ]] && [[ -f "${default_profile}/.bashrc" ]] && \
     ! grep -Fqx '# >>> kasm-noble-ai-workspace' "${HOME}/.bashrc"; then
    home_repair_run_sudo sed -n '/^# >>> kasm-noble-ai-workspace$/,/^# <<< kasm-noble-ai-workspace$/p' \
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
  home_repair_run_sudo chown "${user_id}:${user_group}" "${profile}" "${HOME}/.bashrc" 2>/dev/null || true
}

configure_login_shell() {
  local user_name
  user_name="$(basename "${HOME}")"

  if ! getent passwd "${user_name}" >/dev/null 2>&1; then
    home_repair_log "Cannot resolve the login user for ${HOME}; skipping shell change"
    return
  fi
  if [[ "$(getent passwd "${user_name}" | cut -d: -f7)" == "/bin/bash" ]]; then
    return
  fi
  home_repair_run_sudo usermod -s /bin/bash "${user_name}" || \
    home_repair_log "Could not change the login shell for ${user_name}"
}

home_repair_main() {
  if [[ "${KASM_HOME_REPAIR}" != "1" ]]; then
    home_repair_log "disabled by KASM_HOME_REPAIR=${KASM_HOME_REPAIR}"
    return 0
  fi

  # The Vast onstart runs as root with HOME=/root. Target the Kasm user unless
  # the caller explicitly supplied another home.
  if [[ -z "${HOME:-}" || "${HOME}" == "/root" ]]; then
    HOME="${KASM_USER_HOME}"
  fi
  export HOME

  configure_home_profile
  configure_login_shell
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  home_repair_main "$@"
fi
