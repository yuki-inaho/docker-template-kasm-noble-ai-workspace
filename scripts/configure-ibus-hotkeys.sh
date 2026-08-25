#!/usr/bin/env bash
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "configure-ibus-hotkeys.sh must run as root" >&2
  exit 1
fi

ibus_profile_dir="/etc/dconf/profile"
ibus_profile="${ibus_profile_dir}/ibus"
ibus_db_dir="/etc/dconf/db/ibus.d"
ibus_lock_dir="${ibus_db_dir}/locks"

install -d -m 0755 "${ibus_profile_dir}" "${ibus_db_dir}" "${ibus_lock_dir}"

# The IBus dconf component explicitly selects DCONF_PROFILE=ibus. Keep its
# user database first so normal per-user settings continue to work, then load
# the system database containing the image defaults and locks below.
if [[ ! -f "${ibus_profile}" ]]; then
  printf '%s\n' 'user-db:user' 'system-db:ibus' > "${ibus_profile}"
fi

if ! grep -Fqx 'user-db:user' "${ibus_profile}" || \
   ! grep -Fqx 'system-db:ibus' "${ibus_profile}"; then
  echo "Unexpected IBus dconf profile: ${ibus_profile}" >&2
  exit 1
fi

cat > "${ibus_db_dir}/90-kasm-hotkeys" <<'SETTINGS'
[desktop/ibus/general/hotkey]
trigger=['Control+space']
triggers=['<Control>space', '<Super>space']
SETTINGS

# Persistent Kasm homes may already contain the upstream Zenkaku_Hankaku or
# Alt+grave shortcuts. Lock only the on/off trigger keys so those stale user
# values cannot restore the observed keycode-49 conflict; engine ordering
# remains editable.
cat > "${ibus_lock_dir}/90-kasm-hotkeys" <<'LOCKS'
/desktop/ibus/general/hotkey/trigger
/desktop/ibus/general/hotkey/triggers
LOCKS

dconf update
