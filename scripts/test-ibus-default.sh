#!/usr/bin/env bash
# Run on an image in an isolated container; the temporary user database is disposable.
set -euo pipefail
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT
mkdir -m 700 "${tmp_dir}/runtime"
mkdir -p "${tmp_dir}/config"
env HOME="${tmp_dir}" XDG_CONFIG_HOME="${tmp_dir}/config" \
  XDG_RUNTIME_DIR="${tmp_dir}/runtime" DCONF_PROFILE=ibus dbus-run-session -- bash -eu -c '
    schema=org.freedesktop.ibus.general
    test "$(gsettings get "$schema" enable-by-default)" = true
    test "$(gsettings writable "$schema" enable-by-default)" = true
    gsettings set "$schema" enable-by-default false
    test "$(gsettings get "$schema" enable-by-default)" = false
    gsettings reset "$schema" enable-by-default
    test "$(gsettings get "$schema" enable-by-default)" = true
    echo "IBus default and explicit user override: PASS"
  '
