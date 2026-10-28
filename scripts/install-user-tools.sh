#!/usr/bin/env bash
set -euo pipefail

if [[ "$(id -u)" -eq 0 ]]; then
  echo "install-user-tools.sh must run as the Kasm user, not root" >&2
  exit 1
fi

NODE_VERSION="${NODE_VERSION:-22.23.4}"
NPM_VERSION="${NPM_VERSION:-12.2.1}"
NVM_VERSION="${NVM_VERSION:-v0.40.2}"
POETRY_VERSION="${POETRY_VERSION:-1.8.5}"
UV_VERSION="${UV_VERSION:-0.12.5}"
RUST_VERSION="${RUST_VERSION:-1.98.0}"
JUST_VERSION="${JUST_VERSION:-1.58.0}"
JUST_SHA256="${JUST_SHA256:-4a5cc2f53e6f0f8c59092a6cc38291eb729d46a7dd95d3ae582008881b84931d}"
CODEX_VERSION="${CODEX_VERSION:-0.163.0}"
CLAUDE_VERSION="${CLAUDE_VERSION:-2.1.306}"
OPENCODE_VERSION="${OPENCODE_VERSION:-2.1.2}"
RTK_VERSION="${RTK_VERSION:-v1.0.1}"
PIXI_VERSION="${PIXI_VERSION:-0.77.1}"
PIXI_SHA256="${PIXI_SHA256:-5115a89a9189a2e4e7e8d2f04236a7be586d8f6091dfc9ea869fb3c4a52b6935}"
HERDR_VERSION="${HERDR_VERSION:-v0.9.5}"
HERDR_SHA256="${HERDR_SHA256:-14d9e8bc8b4a9e0118d77c32266f76d461f09b40342eb23752960bd89f59929d}"
AGENT_JSONL_COMPACT_VERSION="${AGENT_JSONL_COMPACT_VERSION:-v0.5.1}"
AGENT_JSONL_COMPACT_SHA256="${AGENT_JSONL_COMPACT_SHA256:-769460cc12ebabae2d2e7d43bd7992ab41e9c12dd12778145825c91ecf462c69}"
AGMSG_VERSION="${AGMSG_VERSION:-v1.5.3}"
PLAYWRIGHT_CLI_VERSION="${PLAYWRIGHT_CLI_VERSION:-0.1.22}"
PLAYWRIGHT_VERSION="${PLAYWRIGHT_VERSION:-1.64.1}"
PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-/opt/ms-playwright}"
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

  export PATH="${HOME}/.opencode/bin:${HOME}/.local/bin:${HOME}/.cargo/bin:${PYENV_ROOT}/bin:${PATH}"
  export PYENV_ROOT NVM_DIR

  append_once 'export PATH="$HOME/.opencode/bin:$HOME/.local/bin:$HOME/.cargo/bin:$PATH"' "${BASHRC}"
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

install_node() {
  log "Installing Node.js ${NODE_VERSION}"
  if [[ ! -s "${NVM_DIR}/nvm.sh" ]]; then
    retry bash -o pipefail -c "curl --retry 5 --retry-all-errors -o- https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh | bash"
  fi

  # shellcheck disable=SC1090
  source "${NVM_DIR}/nvm.sh"
  nvm install "${NODE_VERSION}"
  nvm alias default "${NODE_VERSION}"
  nvm use "${NODE_VERSION}"
}

install_npm() {
  log "Installing npm ${NPM_VERSION}"
  # shellcheck disable=SC1090
  source "${NVM_DIR}/nvm.sh"
  nvm use "${NODE_VERSION}" >/dev/null

  if [[ "$(npm --version)" != "${NPM_VERSION}" ]]; then
    retry npm install -g --no-audit --no-fund "npm@${NPM_VERSION}"
  fi

  test "$(npm --version)" = "${NPM_VERSION}"
}

install_codex() {
  log "Installing Codex CLI ${CODEX_VERSION}"
  # shellcheck disable=SC1090
  source "${NVM_DIR}/nvm.sh"
  nvm use "${NODE_VERSION}"

  if [[ -n "${CODEX_VERSION}" && "${CODEX_VERSION}" != "latest" ]]; then
    retry npm install -g --no-audit --no-fund "@openai/codex@${CODEX_VERSION}"
    codex --version | grep -Fq "${CODEX_VERSION}"
  else
    retry npm install -g --no-audit --no-fund @openai/codex
  fi
}

install_opencode() {
  log "Installing OpenCode ${OPENCODE_VERSION} (v2 installer)"

  local version="${OPENCODE_VERSION#v}"
  if [[ "${OPENCODE_VERSION}" == "latest" ]]; then
    retry bash -o pipefail -c \
      'curl --retry 5 --retry-all-errors -fsSL https://opencode.ai/v2/install | bash -s -- --no-modify-path'
  else
    retry bash -o pipefail -c \
      "curl --retry 5 --retry-all-errors -fsSL https://opencode.ai/v2/install | bash -s -- --no-modify-path --version ${version}"
  fi

  test -x "${HOME}/.opencode/bin/opencode"
  if [[ "${OPENCODE_VERSION}" != "latest" ]]; then
    "${HOME}/.opencode/bin/opencode" --version | grep -Fq "${version}"
  fi
}

install_opencode_goal_plugin() {
  log "Installing OpenCode goal plugin (v2 configuration)"
  # shellcheck disable=SC1090
  source "${NVM_DIR}/nvm.sh"
  nvm use "${NODE_VERSION}" >/dev/null
  export PATH="${HOME}/.opencode/bin:${PATH}"

  retry opencode plugin add "@prevalentware/opencode-goal-plugin"

  # OpenCode v2 resolves the passwd home (/home/kasm-user) when that directory
  # exists, and falls back to $HOME otherwise. Accept either location, then
  # normalize the plugin configuration into the profile Kasm copies at runtime.
  local build_home="/home/kasm-user"
  local source_home=""
  if [[ -f "${HOME}/.config/opencode/opencode.json" ]]; then
    source_home="${HOME}"
  elif [[ -f "${build_home}/.config/opencode/opencode.json" ]]; then
    source_home="${build_home}"
  else
    echo "OpenCode did not write an opencode.json in ${HOME} or ${build_home}" >&2
    return 1
  fi

  rm -f "${HOME}/.config/opencode/opencode.jsonc" "${HOME}/.config/opencode/tui.json"
  install -d -m 0755 "${HOME}/.config/opencode" "${HOME}/.cache/opencode"

  if [[ "${source_home}" != "${HOME}" ]]; then
    cp -a "${source_home}/.config/opencode/opencode.json" "${HOME}/.config/opencode/opencode.json"
    if [[ -d "${source_home}/.cache/opencode/npm" ]]; then
      rm -rf "${HOME}/.cache/opencode/npm"
      cp -a "${source_home}/.cache/opencode/npm" "${HOME}/.cache/opencode/npm"
    fi
  fi

  cat > "${HOME}/.config/opencode/cli.json" <<'JSON'
{
  "$schema": "https://opencode.ai/v2/cli.json",
  "plugins": ["@prevalentware/opencode-goal-plugin"]
}
JSON

  grep -Fq '"plugins"' "${HOME}/.config/opencode/opencode.json"
  grep -Fq '@prevalentware/opencode-goal-plugin' "${HOME}/.config/opencode/opencode.json"
  grep -Fq '@prevalentware/opencode-goal-plugin' "${HOME}/.config/opencode/cli.json"

  local plugin_package
  plugin_package="$(find "${HOME}/.cache/opencode/npm" \
    -path '*/node_modules/@prevalentware/opencode-goal-plugin/package.json' \
    -print -quit 2>/dev/null)"
  if [[ -z "${plugin_package}" ]]; then
    echo "OpenCode goal plugin package was not found in the cache" >&2
    return 1
  fi

  if [[ "${source_home}" == "${build_home}" ]]; then
    rm -rf "${build_home}/.config/opencode" \
      "${build_home}/.cache/opencode" \
      "${build_home}/.local/share/opencode"
  fi
  rm -rf "${HOME}/.local/share/opencode"
}

install_playwright() {
  log "Installing Playwright ${PLAYWRIGHT_VERSION}, Playwright CLI ${PLAYWRIGHT_CLI_VERSION} and Chromium"
  # shellcheck disable=SC1090
  source "${NVM_DIR}/nvm.sh"
  nvm use "${NODE_VERSION}" >/dev/null

  retry npm install -g --no-audit --no-fund \
    "playwright@${PLAYWRIGHT_VERSION}" \
    "@playwright/cli@${PLAYWRIGHT_CLI_VERSION}"

  install -d -m 0775 "${PLAYWRIGHT_BROWSERS_PATH}"
  retry env PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH}" \
    playwright install chromium

  test -n "$(find "${PLAYWRIGHT_BROWSERS_PATH}" -maxdepth 1 -type d -name 'chromium-*' -print -quit)"
}

install_foundation() {
  prepare_environment
  ensure_pyenv
  install_poetry
  install_uv
  install_rust_and_just
  install_node
  install_npm
  cleanup_user_caches
}

install_agent_tools() {
  prepare_environment
  install_codex
  install_claude
  install_opencode
  install_opencode_goal_plugin
  install_playwright
  install_rtk
  verify
  cleanup_user_caches
}

require_x86_64_prebuilt() {
  case "$(uname -m)" in
    x86_64|amd64)
      ;;
    *)
      echo "Workspace prebuilt CLIs support x86_64 only; found $(uname -m)" >&2
      return 1
      ;;
  esac
}

download_and_verify() {
  local url="$1"
  local checksum="$2"
  local destination="$3"

  retry curl --retry 5 --retry-all-errors -fsSL "${url}" -o "${destination}"
  printf '%s  %s\n' "${checksum}" "${destination}" | sha256sum -c -
}

install_pixi() {
  log "Installing Pixi ${PIXI_VERSION}"

  if command -v pixi >/dev/null 2>&1 && \
     pixi --version | grep -Fq "${PIXI_VERSION}"; then
    return
  fi

  local binary
  binary="$(mktemp)"
  download_and_verify \
    "https://github.com/prefix-dev/pixi/releases/download/v${PIXI_VERSION#v}/pixi-x86_64-unknown-linux-musl" \
    "${PIXI_SHA256}" \
    "${binary}"
  install -m 0755 "${binary}" "${HOME}/.local/bin/pixi"
  rm -f "${binary}"
}

install_herdr() {
  log "Installing Herdr ${HERDR_VERSION}"

  if command -v herdr >/dev/null 2>&1 && \
     herdr --version | grep -Fq "${HERDR_VERSION#v}"; then
    return
  fi

  local binary
  binary="$(mktemp)"
  download_and_verify \
    "https://github.com/herdrdev/herdr/releases/download/${HERDR_VERSION}/herdr-linux-x86_64" \
    "${HERDR_SHA256}" \
    "${binary}"
  install -m 0755 "${binary}" "${HOME}/.local/bin/herdr"
  rm -f "${binary}"
  herdr --version | grep -Fq "${HERDR_VERSION#v}"
}

install_agent_jsonl_compact() {
  log "Installing agent-jsonl-compact ${AGENT_JSONL_COMPACT_VERSION}"

  if ! command -v agent-jsonl-compact >/dev/null 2>&1 || \
     ! agent-jsonl-compact --version | grep -Fq "${AGENT_JSONL_COMPACT_VERSION#v}"; then
    local archive
    local extract_dir
    local binary

    archive="$(mktemp)"
    extract_dir="$(mktemp -d)"
    download_and_verify \
      "https://github.com/yuki-inaho/agent-jsonl-compact/releases/download/${AGENT_JSONL_COMPACT_VERSION}/agent-jsonl-compact-x86_64-unknown-linux-musl.tar.gz" \
      "${AGENT_JSONL_COMPACT_SHA256}" \
      "${archive}"
    tar -xzf "${archive}" -C "${extract_dir}"
    binary="$(find "${extract_dir}" -type f -name agent-jsonl-compact -print -quit)"
    if [[ -z "${binary}" ]]; then
      echo "agent-jsonl-compact binary was not found after extraction" >&2
      return 1
    fi
    install -m 0755 "${binary}" "${HOME}/.local/bin/agent-jsonl-compact"
    rm -rf "${extract_dir}"
    rm -f "${archive}"
  fi

  agent-jsonl-compact --version | grep -Fq "${AGENT_JSONL_COMPACT_VERSION#v}"

  mkdir -p "${HOME}/.codex" "${HOME}/.claude"
  agent-jsonl-compact install-skills
}

install_agmsg() {
  log "Installing agmsg ${AGMSG_VERSION}"

  if ! command -v sqlite3 >/dev/null 2>&1; then
    echo "agmsg requires sqlite3, which must come from the system layer" >&2
    return 1
  fi

  if [[ "$(tr -d '[:space:]' < "${HOME}/.agents/skills/agmsg/VERSION" 2>/dev/null)" == "${AGMSG_VERSION}" ]]; then
    return
  fi

  local checkout
  checkout="$(mktemp -d)"
  retry git clone --quiet --branch "${AGMSG_VERSION}" --depth 1 \
    https://github.com/fujibee/agmsg.git "${checkout}/agmsg"
  bash "${checkout}/agmsg/install.sh" --cmd agmsg
  rm -rf "${checkout}"

  test -f "${HOME}/.agents/skills/agmsg/SKILL.md"
  test -x "${HOME}/.agents/skills/agmsg/scripts/version.sh"
  test -f "${HOME}/.config/opencode/skills/agmsg/SKILL.md"
  test -f "${HOME}/.claude/commands/agmsg.md"
  test "$(tr -d '[:space:]' < "${HOME}/.agents/skills/agmsg/VERSION")" = "${AGMSG_VERSION}"
}

verify_workspace_tools() {
  log "Installed workspace CLI versions"
  export PATH="${HOME}/.local/bin:${PATH}"

  pixi --version
  herdr --version
  agent-jsonl-compact --version
  jq --version
  sqlite3 --version
  rg --version
  fdfind --version
  fzf --version
  yq --version
  tree --version
  test -f "${HOME}/.codex/skills/agent-jsonl-compact-reader/SKILL.md"
  test -f "${HOME}/.claude/skills/agent-jsonl-compact-reader/SKILL.md"
  test -f "${HOME}/.agents/skills/agmsg/SKILL.md"
  test -x "${HOME}/.agents/skills/agmsg/scripts/version.sh"
  test -f "${HOME}/.config/opencode/skills/agmsg/SKILL.md"
  test -f "${HOME}/.claude/commands/agmsg.md"
  test "$(tr -d '[:space:]' < "${HOME}/.agents/skills/agmsg/VERSION")" = "${AGMSG_VERSION}"
}

install_workspace_tools() {
  prepare_environment
  require_x86_64_prebuilt
  install_pixi
  install_herdr
  install_agent_jsonl_compact
  install_agmsg
  verify_workspace_tools
  cleanup_user_caches
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
    "${HOME}/.local/bin/claude" --version | grep -Fq "${CLAUDE_VERSION}"
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

  if [[ -n "${RTK_VERSION}" ]]; then
    rtk --version | grep -Fq "${RTK_VERSION#v}"
  fi
}

cleanup_user_caches() {
  log "Cleaning user-level installer caches"

  if [[ -s "${NVM_DIR}/nvm.sh" ]]; then
    # shellcheck disable=SC1090
    source "${NVM_DIR}/nvm.sh"
    nvm cache clear || true
    # BuildKit provides /tmp/npm-cache as a cache mount; clearing it would
    # defeat layer-to-layer reuse. Only clean caches that live in the layer.
    if [[ "${NPM_CONFIG_CACHE:-}" != /tmp/* ]]; then
      npm cache clean --force || true
    fi
  fi

  if command -v uv >/dev/null 2>&1; then
    uv cache clean || true
  fi

  # Clear every ~/.cache entry except the preinstalled OpenCode plugin store,
  # which must survive so the goal plugin is available without a first-run fetch.
  find "${HOME}/.cache" -mindepth 1 -maxdepth 1 \
    ! -name opencode -exec rm -rf {} + 2>/dev/null || true
  rm -rf \
    "${HOME}/.cargo/git" \
    "${HOME}/.cargo/registry/cache" \
    "${HOME}/.cargo/registry/index" \
    "${HOME}/.cargo/registry/src" \
    "${HOME}/.npm/_cacache" \
    "${HOME}/.nvm/.cache"
}

verify() {
  log "Installed versions"
  export PATH="${HOME}/.opencode/bin:${HOME}/.local/bin:${HOME}/.cargo/bin:${PYENV_ROOT}/bin:${PATH}"

  # shellcheck disable=SC1090
  source "${NVM_DIR}/nvm.sh"
  nvm use "${NODE_VERSION}" >/dev/null
  # shellcheck disable=SC1091
  source "${HOME}/.cargo/env"

  pyenv --version
  poetry --version
  uv --version
  test "$(npm --version)" = "${NPM_VERSION}"
  playwright --version
  rustc --version
  cargo --version
  just --version
  node --version
  npm --version
  codex --version
  claude --version
  opencode --version
  rtk --version
  playwright-cli --version
}

main() {
  case "${1:-all}" in
    foundation)
      install_foundation
      ;;
    agents)
      install_agent_tools
      ;;
    workspace)
      install_workspace_tools
      ;;
    all)
      install_foundation
      install_agent_tools
      install_workspace_tools
      ;;
    *)
      echo "Usage: $0 [foundation|agents|workspace|all]" >&2
      return 2
      ;;
  esac
}

main "$@"
