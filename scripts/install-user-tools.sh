#!/usr/bin/env bash
set -euo pipefail

if [[ "$(id -u)" -eq 0 ]]; then
  echo "install-user-tools.sh must run as the Kasm user, not root" >&2
  exit 1
fi

NODE_VERSION="${NODE_VERSION:-22.23.2}"
NVM_VERSION="${NVM_VERSION:-v0.40.2}"
POETRY_VERSION="${POETRY_VERSION:-1.8.5}"
UV_VERSION="${UV_VERSION:-0.12.5}"
RUST_VERSION="${RUST_VERSION:-1.98.0}"
JUST_VERSION="${JUST_VERSION:-1.58.0}"
JUST_SHA256="${JUST_SHA256:-4a5cc2f53e6f0f8c59092a6cc38291eb729d46a7dd95d3ae582008881b84931d}"
CODEX_VERSION="${CODEX_VERSION:-latest}"
CLAUDE_VERSION="${CLAUDE_VERSION:-latest}"
RTK_VERSION="${RTK_VERSION:-v0.45.0}"
PYENV_ROOT="${PYENV_ROOT:-/opt/pyenv}"
NVM_DIR="${NVM_DIR:-${HOME}/.nvm}"
BASHRC="${BASHRC:-${HOME}/.bashrc}"

log() {
  printf '\n[user-tools] %s\n' "$*"
}

append_once() {
  local line="$1"
  local file="$2"

  touch "${file}"
  if ! grep -Fqx "${line}" "${file}"; then
    printf '%s\n' "${line}" >> "${file}"
  fi
}

retry() {
  local attempts=0
  local max_attempts=3
  local delay=5

  until "$@"; do
    attempts=$((attempts + 1))
    if (( attempts >= max_attempts )); then
      return 1
    fi
    printf '[user-tools] Command failed; retrying in %ss (%s/%s)\n' \
      "${delay}" "${attempts}" "${max_attempts}" >&2
    sleep "${delay}"
    delay=$((delay * 2))
  done
}

prepare_environment() {
  mkdir -p "${HOME}/.local/bin" "${HOME}/.cargo/bin" "${HOME}/.config"
  touch "${BASHRC}"

  export PATH="${HOME}/.local/bin:${HOME}/.cargo/bin:${PYENV_ROOT}/bin:${PATH}"
  export PYENV_ROOT NVM_DIR

  append_once 'export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"' "${BASHRC}"
  append_once 'export PYENV_ROOT="/opt/pyenv"' "${BASHRC}"
  append_once '[[ -d "$PYENV_ROOT/bin" ]] && export PATH="$PYENV_ROOT/bin:$PATH"' "${BASHRC}"
  append_once 'command -v pyenv >/dev/null 2>&1 && eval "$(pyenv init - bash)"' "${BASHRC}"
}

ensure_pyenv() {
  if [[ ! -x "${PYENV_ROOT}/bin/pyenv" ]]; then
    log "Installing pyenv because the base image does not contain it"
    git clone --depth 1 https://github.com/pyenv/pyenv.git "${PYENV_ROOT}"
  fi

  export PATH="${PYENV_ROOT}/bin:${PATH}"

  local plugin_dir="${PYENV_ROOT}/plugins/pyenv-update"
  if [[ -d "${plugin_dir}/.git" ]]; then
    git -C "${plugin_dir}" pull --ff-only || true
  else
    git clone --depth 1 https://github.com/pyenv/pyenv-update.git "${plugin_dir}"
  fi
}

install_poetry() {
  log "Installing Poetry ${POETRY_VERSION}"
  if [[ ! -x "${HOME}/.local/bin/poetry" ]] || \
     ! "${HOME}/.local/bin/poetry" --version | grep -Fq "${POETRY_VERSION}"; then
    retry env POETRY_VERSION="${POETRY_VERSION}" \
      bash -o pipefail -c 'curl --retry 5 --retry-all-errors -sSL https://install.python-poetry.org | python3 -'
  fi

  export PATH="${HOME}/.local/bin:${PATH}"

  # Poetry 1.8 already includes `poetry shell`. Install the plugin only when the
  # command is absent, which also keeps this image forward-compatible with 2.x.
  if ! poetry shell --help >/dev/null 2>&1 && \
     ! poetry self show plugins 2>/dev/null | grep -q 'poetry-plugin-shell'; then
    retry poetry self add poetry-plugin-shell
  fi
}

install_uv() {
  log "Installing uv ${UV_VERSION}"
  if ! command -v uv >/dev/null 2>&1 || \
     ! uv --version | grep -Fq "uv ${UV_VERSION}"; then
    retry env UV_VERSION="${UV_VERSION}" bash -o pipefail -c \
      'curl --retry 5 --retry-all-errors -LsSf "https://astral.sh/uv/${UV_VERSION}/install.sh" | sh'
  fi
}

install_rust_and_just() {
  log "Installing Rust ${RUST_VERSION} and just ${JUST_VERSION}"
  if [[ -x "${HOME}/.cargo/bin/rustup" ]]; then
    "${HOME}/.cargo/bin/rustup" toolchain install "${RUST_VERSION}" --profile minimal
    "${HOME}/.cargo/bin/rustup" default "${RUST_VERSION}"
  else
    retry bash -o pipefail -c "curl --retry 5 --retry-all-errors --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain ${RUST_VERSION}"
  fi

  # shellcheck disable=SC1091
  source "${HOME}/.cargo/env"
  if ! command -v just >/dev/null 2>&1 || \
     ! just --version | grep -Fq "just ${JUST_VERSION}"; then
    local archive
    archive="$(mktemp)"
    retry curl --retry 5 --retry-all-errors -fsSL \
      "https://github.com/casey/just/releases/download/${JUST_VERSION}/just-${JUST_VERSION}-x86_64-unknown-linux-musl.tar.gz" \
      -o "${archive}"
    echo "${JUST_SHA256}  ${archive}" | sha256sum -c -
    mkdir -p "${HOME}/.local/bin"
    tar -xzf "${archive}" -C "${HOME}/.local/bin" just
    chmod 0755 "${HOME}/.local/bin/just"
    rm -f "${archive}"
  fi
}

install_node_and_codex() {
  log "Installing Node.js ${NODE_VERSION} and Codex CLI"
  if [[ ! -s "${NVM_DIR}/nvm.sh" ]]; then
    retry bash -o pipefail -c "curl --retry 5 --retry-all-errors -o- https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh | bash"
  fi

  # shellcheck disable=SC1090
  source "${NVM_DIR}/nvm.sh"
  nvm install "${NODE_VERSION}"
  nvm alias default "${NODE_VERSION}"
  nvm use "${NODE_VERSION}"

  if [[ -n "${CODEX_VERSION}" ]]; then
    retry npm install -g "@openai/codex@${CODEX_VERSION}"
  else
    retry npm install -g @openai/codex
  fi
}

install_claude() {
  log "Installing Claude Code ${CLAUDE_VERSION}"
  if [[ "${CLAUDE_VERSION}" == "latest" ]]; then
    retry bash -o pipefail -c \
      'curl --retry 5 --retry-all-errors -fsSL https://claude.ai/install.sh | bash'
  elif [[ ! -x "${HOME}/.local/bin/claude" ]] || \
       ! "${HOME}/.local/bin/claude" --version | grep -Fq "${CLAUDE_VERSION}"; then
    retry env CLAUDE_VERSION="${CLAUDE_VERSION}" bash -o pipefail -c \
      'curl --retry 5 --retry-all-errors -fsSL https://claude.ai/install.sh | bash -s -- "${CLAUDE_VERSION}"'
  fi
}

install_rtk() {
  log "Installing RTK"
  if [[ -n "${RTK_VERSION}" ]]; then
    retry env RTK_VERSION="${RTK_VERSION}" \
      bash -o pipefail -c 'curl --retry 5 --retry-all-errors -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh'
  else
    retry bash -o pipefail -c 'curl --retry 5 --retry-all-errors -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh'
  fi
}

cleanup_user_caches() {
  log "Cleaning user-level installer caches"

  if [[ -s "${NVM_DIR}/nvm.sh" ]]; then
    # shellcheck disable=SC1090
    source "${NVM_DIR}/nvm.sh"
    nvm cache clear || true
    npm cache clean --force || true
  fi

  if command -v uv >/dev/null 2>&1; then
    uv cache clean || true
  fi

  rm -rf \
    "${HOME}/.cache" \
    "${HOME}/.cargo/git" \
    "${HOME}/.cargo/registry/cache" \
    "${HOME}/.cargo/registry/index" \
    "${HOME}/.cargo/registry/src" \
    "${HOME}/.npm/_cacache" \
    "${HOME}/.nvm/.cache"
}

verify() {
  log "Installed versions"
  export PATH="${HOME}/.local/bin:${HOME}/.cargo/bin:${PYENV_ROOT}/bin:${PATH}"

  # shellcheck disable=SC1090
  source "${NVM_DIR}/nvm.sh"
  # shellcheck disable=SC1091
  source "${HOME}/.cargo/env"

  pyenv --version
  poetry --version
  uv --version
  rustc --version
  cargo --version
  just --version
  node --version
  npm --version
  codex --version
  claude --version
  rtk --version
}

main() {
  prepare_environment
  ensure_pyenv
  install_poetry
  install_uv
  install_rust_and_just
  install_node_and_codex
  install_claude
  install_rtk
  verify
  cleanup_user_caches
}

main "$@"
