#!/usr/bin/env bash
set -euo pipefail

if [[ "$(id -u)" -eq 0 ]]; then
  echo "configure-default-profile.sh must run as the Kasm user" >&2
  exit 1
fi

BASHRC="${HOME}/.bashrc"
SESSIONRC="${HOME}/.xsessionrc"
AUTOSTART_DIR="${HOME}/.config/autostart"
XFCE_DIR="${HOME}/.config/xfce4"

replace_block() {
  local file="$1"
  local begin="$2"
  local end="$3"
  local content_file="$4"
  local tmp

  tmp="$(mktemp)"
  touch "${file}"
  sed "/^${begin}$/,/^${end}$/d" "${file}" > "${tmp}"
  cat "${content_file}" >> "${tmp}"
  mv "${tmp}" "${file}"
}

configure_bashrc() {
  local block
  block="$(mktemp)"
  cat > "${block}" <<'BLOCK'
# >>> kasm-noble-ai-workspace
export PATH="$HOME/.opencode/bin:$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_DATA_HOME="$HOME/.local/share"
export PLAYWRIGHT_BROWSERS_PATH="/opt/ms-playwright"
export PYENV_ROOT="/opt/pyenv"
[[ -d "$PYENV_ROOT/bin" ]] && export PATH="$PYENV_ROOT/bin:$PATH"
command -v pyenv >/dev/null 2>&1 && eval "$(pyenv init - bash)"

export NVM_DIR="$HOME/.nvm"
[[ -s "$NVM_DIR/nvm.sh" ]] && . "$NVM_DIR/nvm.sh"
[[ -s "$NVM_DIR/bash_completion" ]] && . "$NVM_DIR/bash_completion"

export GTK_IM_MODULE=ibus
export QT_IM_MODULE=ibus
export XMODIFIERS=@im=ibus

alias claude-auto='CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 claude --dangerously-skip-permissions'
alias codex-auto='codex --dangerously-bypass-approvals-and-sandbox'
alias opencode-auto='opencode --auto'

if [[ $- == *i* ]] && [[ "${AUTO_CD_WORKSPACE:-1}" == "1" ]] && \
   [[ "${PWD}" == "${HOME}" ]] && [[ -d "${WORKSPACE_DIR:-/workspace}" ]]; then
  cd "${WORKSPACE_DIR:-/workspace}"
fi
# <<< kasm-noble-ai-workspace
BLOCK

  replace_block "${BASHRC}" \
    '# >>> kasm-noble-ai-workspace' \
    '# <<< kasm-noble-ai-workspace' \
    "${block}"
  rm -f "${block}"
}

configure_xsession() {
  local block
  block="$(mktemp)"
  cat > "${block}" <<'BLOCK'
# >>> kasm-noble-ai-workspace
export GTK_IM_MODULE=ibus
export QT_IM_MODULE=ibus
export XMODIFIERS=@im=ibus

if command -v setxkbmap >/dev/null 2>&1; then
  setxkbmap -model pc105 -layout jp || true
fi
# <<< kasm-noble-ai-workspace
BLOCK

  replace_block "${SESSIONRC}" \
    '# >>> kasm-noble-ai-workspace' \
    '# <<< kasm-noble-ai-workspace' \
    "${block}"
  rm -f "${block}"
}

configure_ibus_autostart() {
  mkdir -p "${AUTOSTART_DIR}"
  cat > "${AUTOSTART_DIR}/ibus-daemon.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=IBus Daemon
Comment=Start Japanese input method
Exec=sh -lc 'pgrep -u "$(id -u)" -x ibus-daemon >/dev/null 2>&1 || ibus-daemon -drx'
OnlyShowIn=XFCE;
X-GNOME-Autostart-enabled=true
NoDisplay=true
DESKTOP

  im-config -n ibus || true
}

configure_keyboard_autostart() {
  mkdir -p "${AUTOSTART_DIR}"
  cat > "${AUTOSTART_DIR}/japanese-keyboard.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Japanese Keyboard Layout
Comment=Apply the JIS 106/109 keyboard layout after XFCE starts
Exec=sh -lc 'setxkbmap -model pc105 -layout jp'
OnlyShowIn=XFCE;
X-GNOME-Autostart-enabled=true
NoDisplay=true
DESKTOP
}

configure_file_manager() {
  mkdir -p "${XFCE_DIR}"
  local helpers="${XFCE_DIR}/helpers.rc"
  touch "${helpers}"

  if grep -q '^FileManager=' "${helpers}"; then
    sed -i 's/^FileManager=.*/FileManager=nautilus/' "${helpers}"
  else
    printf '%s\n' 'FileManager=nautilus' >> "${helpers}"
  fi
}

configure_playwright_cli() {
  mkdir -p "${HOME}/.playwright"
  cat > "${HOME}/.playwright/cli.config.json" <<'JSON'
{
  "browser": {
    "browserName": "chromium",
    "launchOptions": {
      "channel": "chrome",
      "chromiumSandbox": false
    }
  }
}
JSON
}

configure_xfce_panel() {
  local panel_xml="${XFCE_DIR}/xfconf/xfce-perchannel-xml/xfce4-panel.xml"

  if [[ ! -f "${panel_xml}" ]]; then
    echo "xfce4-panel.xml not found: ${panel_xml}" >&2
    exit 1
  fi

  python3 - "${panel_xml}" <<'PANEL_PY'
import sys
import xml.etree.ElementTree as ET

path = sys.argv[1]
tree = ET.parse(path)
root = tree.getroot()

panels = root.find("property[@name='panels']")
if panels is None:
    raise SystemExit("panels property not found")
panel1 = panels.find("property[@name='panel-1']")
if panel1 is None:
    raise SystemExit("panel-1 not found")
plugin_ids = panel1.find("property[@name='plugin-ids']")
plugins = root.find("property[@name='plugins']")
if plugin_ids is None or plugins is None:
    raise SystemExit("plugin-ids or plugins property not found")


def ensure_plugin(plugin_id, kind):
    name = f"plugin-{plugin_id}"
    node = plugins.find(f"property[@name='{name}']")
    if node is None:
        node = ET.SubElement(
            plugins, "property", {"name": name, "type": "string", "value": kind}
        )
    else:
        node.set("value", kind)
    return node


def set_property(node, key, ptype, value):
    child = node.find(f"property[@name='{key}']")
    if child is None:
        child = ET.SubElement(node, "property", {"name": key, "type": ptype})
    child.set("value", value)


launcher = ensure_plugin(16, "launcher")
items = launcher.find("property[@name='items']")
if items is None:
    items = ET.SubElement(launcher, "property", {"name": "items", "type": "array"})
for value in list(items):
    items.remove(value)
ET.SubElement(items, "value", {"type": "string", "value": "org.gnome.Nautilus.desktop"})

clock = ensure_plugin(17, "clock")
set_property(clock, "mode", "uint", "2")
set_property(clock, "digital-layout", "uint", "0")
set_property(clock, "digital-date-format", "string", "%Y-%m-%d")
set_property(clock, "digital-time-format", "string", "%H:%M:%S")
set_property(clock, "digital-format", "string", "%Y-%m-%d %H:%M:%S")
set_property(clock, "show-seconds", "bool", "true")

wanted = [16, 17]
for value in list(plugin_ids):
    if int(value.get("value")) in wanted:
        plugin_ids.remove(value)

current = [int(value.get("value")) for value in plugin_ids]
if 15 in current:
    insert_at = current.index(15) + 1
elif 2 in current:
    insert_at = current.index(2)
else:
    insert_at = len(current)
for offset, plugin_id in enumerate(wanted):
    plugin_ids.insert(
        insert_at + offset,
        ET.Element("value", {"type": "int", "value": str(plugin_id)}),
    )

ET.indent(tree, space="  ")
tree.write(path, encoding="UTF-8", xml_declaration=True)
PANEL_PY

  mkdir -p "${XFCE_DIR}/panel/launcher-16"
  cp /usr/share/applications/org.gnome.Nautilus.desktop \
    "${XFCE_DIR}/panel/launcher-16/org.gnome.Nautilus.desktop"
}

main() {
  mkdir -p "${HOME}/Desktop"
  configure_bashrc
  configure_xsession
  configure_ibus_autostart
  configure_keyboard_autostart
  configure_file_manager
  configure_playwright_cli
  configure_xfce_panel
}

main "$@"
