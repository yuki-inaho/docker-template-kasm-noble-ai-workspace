#!/usr/bin/env bash
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "configure-apt-noninteractive.sh must run as root" >&2
  exit 1
fi

PRESEED_FILE="/tmp/kasm-debconf-preseed"

log() {
  printf '\n[apt-noninteractive] %s\n' "$*"
}

write_preseed() {
  cat > "${PRESEED_FILE}" <<'PRESEED'
# Keyboard: JIS 106/109 (pc105 + jp), matching the XFCE session settings.
keyboard-configuration keyboard-configuration/model select Generic 105-key PC
keyboard-configuration keyboard-configuration/modelcode select pc105
keyboard-configuration keyboard-configuration/layout select Japanese
keyboard-configuration keyboard-configuration/layoutcode select jp
keyboard-configuration keyboard-configuration/variant select Japanese
keyboard-configuration keyboard-configuration/variantcode select
keyboard-configuration keyboard-configuration/optionscode select
keyboard-configuration keyboard-configuration/xkb-keymap select jp
keyboard-configuration keyboard-configuration/altgr select The default for the keyboard layout
keyboard-configuration keyboard-configuration/compose select No compose key
keyboard-configuration keyboard-configuration/toggle select No toggling
keyboard-configuration keyboard-configuration/switch select No temporary switch
keyboard-configuration keyboard-configuration/ctrl_alt_bksp boolean false
console-setup console-setup/charmap47 select UTF-8
console-setup console-setup/codeset47 select Guess optimal character set
console-setup console-setup/fontface47 select Do not change the boot/kernel font

# VS Code / Code - OSS installers ask whether to add Microsoft's APT repository.
code code/add-microsoft-repo boolean true

# Timezone used by the desktop image.
tzdata tzdata/Areas select Asia
tzdata tzdata/Zones/Asia select Tokyo

# Certificate refresh, library restart and locale prompts.
ca-certificates ca-certificates/trust_new_crts select yes
glibc glibc/restart-services string
libraries libraries/restart-without-asking boolean true
locales locales/default_environment_locale select en_US.UTF-8
locales locales/locales_to_be_generated multiselect en_US.UTF-8 UTF-8, ja_JP.UTF-8 UTF-8
PRESEED
}

configure_keyboard() {
  log "Configuring the JIS keyboard layout"

  cat > /etc/default/keyboard <<'KEYBOARD'
# KEYBOARD CONFIGURATION FILE

# Consult the keyboard(5) manual page.

XKBMODEL="pc105"
XKBLAYOUT="jp"
XKBVARIANT=""
XKBOPTIONS=""

BACKSPACE="guess"
KEYBOARD

  debconf-set-selections "${PRESEED_FILE}"
  dpkg-reconfigure -f noninteractive keyboard-configuration
}

configure_timezone() {
  log "Configuring the Asia/Tokyo timezone"

  printf 'Asia/Tokyo\n' > /etc/timezone
  ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime
  dpkg-reconfigure -f noninteractive tzdata
}

mark_existing_questions_seen() {
  log "Marking already-answered debconf questions as seen"

  if ! command -v debconf-get-selections >/dev/null 2>&1; then
    echo "debconf-get-selections is required; install debconf-utils first" >&2
    return 1
  fi

  # debconf-get-selections also emits question types that debconf-set-selections
  # does not accept (error, detect-keyboard). Filter to the supported types so
  # the round-trip cannot fail on an unknown type.
  debconf-get-selections \
    | awk '$3 ~ /^(string|boolean|select|multiselect|note|text|password)$/' \
    | debconf-set-selections

  # Re-apply the image answers after the generic pass so they always win.
  debconf-set-selections "${PRESEED_FILE}"
}

configure_apt() {
  log "Forcing local configuration files to be preserved"

  cat > /etc/apt/apt.conf.d/90-kasm-noninteractive <<'APTCONF'
// Keep the image's configuration files during unattended upgrades.
DPkg::Options { "--force-confdef"; "--force-confold"; };
APTCONF
}

configure_sudo() {
  log "Preserving the non-interactive debconf frontend through sudo"

  cat > /etc/sudoers.d/91-kasm-noninteractive <<'SUDOERS'
Defaults env_keep += "DEBIAN_FRONTEND NEEDRESTART_MODE APT_LISTCHANGES_FRONTEND"
SUDOERS
  chmod 0440 /etc/sudoers.d/91-kasm-noninteractive
  visudo -cf /etc/sudoers.d/91-kasm-noninteractive
}

cleanup() {
  rm -f "${PRESEED_FILE}"
}

main() {
  write_preseed
  mark_existing_questions_seen
  configure_keyboard
  configure_timezone
  configure_apt
  configure_sudo
  cleanup
}

main "$@"
