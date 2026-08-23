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
check_command google-chrome bash -lc 'google-chrome --version 2>/dev/null'

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
