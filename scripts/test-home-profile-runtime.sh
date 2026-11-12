#!/usr/bin/env bash
set -euo pipefail

image="${1:?usage: test-home-profile-runtime.sh IMAGE}"

docker run --rm --user 0 --entrypoint bash "$image" -c '
set -euo pipefail

# Minimal image profile: the real one is multi-gigabyte and would only slow the
# policy test down. The repair logic is what this test exercises.
profile=/tmp/default-profile
rm -rf "$profile"
mkdir -p "$profile/.local/bin" "$profile/.local/share" "$profile/.opencode/bin" "$profile/.cargo"

printf "%s\n" "#!/bin/sh" "echo \"herdr 0.9.5\"" > "$profile/.local/bin/herdr"
printf "%s\n" "#!/bin/sh" "echo \"opencode v2.2.7\"" > "$profile/.opencode/bin/opencode"
printf "%s\n" "#!/bin/sh" "echo \"profile-only tool\"" > "$profile/.local/bin/tool-only-in-profile"
printf "%s\n" "export PATH=\"\$HOME/.opencode/bin:\$HOME/.local/bin:\$HOME/.cargo/bin:\$PATH\"" > "$profile/.local/bin/env"
printf "%s\n" "export PATH=\"\$HOME/.cargo/bin:\$PATH\"" > "$profile/.cargo/env"
printf "%s\n" "export PS1=\"default-profile\"" "export PYENV_ROOT=" "# >>> kasm-noble-ai-workspace" "export FAKE_IMAGE_BLOCK=1" "# <<< kasm-noble-ai-workspace" > "$profile/.bashrc"
printf "%s\n" ". \"\$HOME/.local/share/../bin/env\"" ". \"\$HOME/.cargo/env\"" > "$profile/.profile"
chmod 0755 "$profile/.local/bin/herdr" "$profile/.opencode/bin/opencode" \
  "$profile/.local/bin/tool-only-in-profile"
chmod -R a+rX "$profile"
chmod 0777 "$profile"

prepare_home() {
  # Reproduce the Vast.ai first boot: its own .bashrc exists, and a partial
  # root-owned ~/.local/bin prevented Kasm from copying the default profile.
  rm -rf /home/kasm-user
  install -d -m 0700 /home/kasm-user/.local/bin /home/kasm-user/.local/share
  cp "$profile/.local/bin/herdr" /home/kasm-user/.local/bin/herdr
  ln -s "$profile/.cargo" /home/kasm-user/.cargo
  printf "%s\n" "export PS1=\"Vast test PS1\"" "export PYENV_ROOT=" > /home/kasm-user/.bashrc
  chown -R root:root /home/kasm-user
  chmod 0777 /home/kasm-user
}

assert_repaired() {
  test -x /home/kasm-user/.local/bin/herdr
  test -x /home/kasm-user/.opencode/bin/opencode
  test -x /home/kasm-user/.local/bin/tool-only-in-profile
  test -s /home/kasm-user/.cargo/env
  test -f /home/kasm-user/.profile
  grep -Fq "export PATH=\"\$HOME/.opencode/bin:\$HOME/.local/bin:\$HOME/.cargo/bin:\$PATH\"" \
    /home/kasm-user/.profile
  grep -Fq ". \"\$HOME/.bashrc\"" /home/kasm-user/.profile
  grep -Fq "Vast test PS1" /home/kasm-user/.bashrc
  grep -Fq "export FAKE_IMAGE_BLOCK=1" /home/kasm-user/.bashrc
  grep -Fq "# >>> kasm-noble-ai-workspace-runtime" /home/kasm-user/.bashrc
  grep -Fqx "export PYENV_ROOT=\"/opt/pyenv\"" /home/kasm-user/.bashrc
  test "$(grep -c "export PATH=\"" /home/kasm-user/.bashrc)" = "1"
  test "$(stat -c %u /home/kasm-user/.local)" = "1000"
  test "$(stat -c %u /home/kasm-user/.local/bin/herdr)" = "1000"
  test "$(stat -c %a /home/kasm-user)" = "755"
  test -f /home/kasm-user/.no_auto_tmux
  test -d /home/kasm-user/.config
  test -d /home/kasm-user/.cache
  test "$(stat -c %u /home/kasm-user/.config)" = "1000"
  getent passwd kasm-user | cut -d: -f7 | grep -qx /bin/bash
  su - kasm-user -c "herdr --version" | grep -q "0.9.5"
  su - kasm-user -c "opencode --version" | grep -q "v2.2.7"
}

env_args="HOME=/home/kasm-user DEFAULT_PROFILE_HOME=$profile ENABLE_JAPANESE_INPUT=0 AUTO_UPDATE_TOOLS=0 WORKSPACE_CHOWN=0"

prepare_home
env $env_args /dockerstartup/runtime-init.sh
assert_repaired
printf "%s\n" "PASS: repair when runtime-init runs as root"

env $env_args /dockerstartup/runtime-init.sh >/dev/null
test "$(grep -c "export PATH=\"" /home/kasm-user/.bashrc)" = "1"
grep -Fqx "export PYENV_ROOT=\"/opt/pyenv\"" /home/kasm-user/.bashrc
printf "%s\n" "PASS: rerun does not duplicate PATH or break PYENV_ROOT"

# A previous boot may have added only the runtime PATH block. The image block
# must still be appended because the runtime marker is not the image marker.
prepare_home
printf "%s\n" "# >>> kasm-noble-ai-workspace-runtime" \
  "export PATH=\"\$HOME/.local/bin:\$PATH\"" \
  "# <<< kasm-noble-ai-workspace-runtime" >> /home/kasm-user/.bashrc
chown root:root /home/kasm-user/.bashrc
env $env_args /dockerstartup/runtime-init.sh
grep -Fq "export FAKE_IMAGE_BLOCK=1" /home/kasm-user/.bashrc
printf "%s\n" "PASS: image block is added when only the runtime block exists"

prepare_home
su -s /bin/bash kasm-user -c "env $env_args /dockerstartup/runtime-init.sh"
assert_repaired
printf "%s\n" "PASS: repair when runtime-init runs as kasm-user with sudo"

printf "%s\n" "PASS: home repair, login profile and bash login shell"
'
