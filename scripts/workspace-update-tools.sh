#!/usr/bin/env bash
# Refresh user tools independently; a failed component does not block others.
set -uo pipefail
umask 077

log() { printf "[%s] %s\n" "$(date -u +%FT%TZ)" "$*"; }
export PATH="$HOME/.opencode/bin:$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
mkdir -p "$HOME/.local/state/kasm-workspace" "$HOME/.local/bin"
state="$HOME/.local/state/kasm-workspace"

if [[ "${1:-}" == --watch ]]; then
  exec 9>"$state/update-watch.lock"
  flock -n 9 || exit 0
  while :; do
    "$0" --once >> "$state/tool-update.log" 2>&1
    if [[ $? == 0 ]]; then sleep "${TOOL_UPDATE_INTERVAL_SECONDS:-86400}"; else sleep "${TOOL_UPDATE_RETRY_SECONDS:-3600}"; fi
  done
fi
[[ "${1:---once}" == --once ]] || { echo "Usage: $0 [--once|--watch]" >&2; exit 2; }
exec 8>"$state/update.lock"
flock -n 8 || { log "An update is already running; retry later"; exit 75; }
failed=0
run() {
  local name="$1"; shift
  log "Updating $name"
  if "$@"; then log "$name: OK"; else log "$name: FAILED"; failed=1; fi
}

update_npm() {
  [[ -s "$NVM_DIR/nvm.sh" ]] || return 1
  # shellcheck disable=SC1090
  source "$NVM_DIR/nvm.sh"
  nvm use default >/dev/null || return 1
  # Preserve global packages when the current LTS line changes.
  npm_config_ignore_scripts=true nvm install --lts --reinstall-packages-from=current --no-progress || return 1
  nvm alias default 'lts/*' || return 1
  nvm use default >/dev/null || return 1
  npm_config_engine_strict=true npm install -g --ignore-scripts --no-audit --no-fund \
    npm@latest @openai/codex@latest playwright@latest @playwright/cli@latest || return 1
  PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-/opt/ms-playwright}" playwright install chromium
}

update_rust() {
  rustup update stable && rustup default stable
}

release_json() {
  curl --fail --silent --show-error --location --retry 2 --connect-timeout 15 --max-time 120 --proto "=https" --proto-redir "=https" \
    -H "Accept: application/vnd.github+json" "https://api.github.com/repos/$1/releases/latest"
}

update_binary() {
  local repo="$1" asset="$2" target="$3" archive="${4:-0}" second="${5:-}" json tag digest tmp file name
  json="$(release_json "$repo")" || return 1
  tag="$(jq -er .tag_name <<< "$json")" || return 1
  digest="$(jq -er --arg asset "$asset" ".assets[] | select(.name == \$asset) | .digest | select(startswith(\"sha256:\")) | ltrimstr(\"sha256:\")" <<< "$json")" || return 1
  [[ "$tag" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ && "$digest" =~ ^[0-9a-f]{64}$ ]] || return 1
  tmp="$(mktemp -d)" || return 1
  if ! curl --fail --silent --show-error --location --retry 2 --connect-timeout 15 --max-time 600 --proto "=https" --proto-redir "=https" \
    "https://github.com/$repo/releases/download/$tag/$asset" -o "$tmp/download" ||
     ! printf "%s  %s\n" "$digest" "$tmp/download" | sha256sum -c -; then
    rm -rf "$tmp"; return 1
  fi
  file="$tmp/download"
  if [[ "$archive" == 1 ]]; then
    if ! python3 - "$file" "$tmp" "$target" "$second" <<"PY"
import pathlib, sys, tarfile
archive, dest, *names = sys.argv[1:]
with tarfile.open(archive, "r:gz") as t:
    for name in filter(None, names):
        matches = [m for m in t.getmembers() if m.isfile() and pathlib.PurePosixPath(m.name).name == name]
        if len(matches) != 1:
            raise SystemExit("Unexpected archive layout")
        src = t.extractfile(matches[0])
        with open(pathlib.Path(dest) / name, "wb") as out:
            while chunk := src.read(1024 * 1024):
                out.write(chunk)
PY
    then rm -rf "$tmp"; return 1; fi
    file="$tmp/$target"
  fi
  # Stage alongside the destination and rename atomically so a failed download
  # never leaves a truncated executable.
  for name in "$target" ${second:+"$second"}; do
    [[ "$name" == "$target" ]] || file="$tmp/$name"
    if ! install -m 0755 "$file" "$HOME/.local/bin/.$name.new" ||
       ! "$HOME/.local/bin/.$name.new" --version >/dev/null 2>&1; then
      rm -f "$HOME/.local/bin/.$target.new" ${second:+"$HOME/.local/bin/.$second.new"}
      rm -rf "$tmp"; return 1
    fi
  done
  for name in "$target" ${second:+"$second"}; do
    if ! mv -f "$HOME/.local/bin/.$name.new" "$HOME/.local/bin/$name"; then
      rm -f "$HOME/.local/bin/.$target.new" ${second:+"$HOME/.local/bin/.$second.new"}
      rm -rf "$tmp"; return 1
    fi
  done
  log "$target: release $tag"
  rm -rf "$tmp"
}

update_agmsg() {
  local json tag tmp installed
  json="$(release_json fujibee/agmsg)" || return 1
  tag="$(jq -er .tag_name <<< "$json")" || return 1
  [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  if [[ -f "$HOME/.agents/skills/agmsg/VERSION" ]]; then
    installed="$(tr -d "[:space:]" < "$HOME/.agents/skills/agmsg/VERSION")"
    [[ "${installed#v}" != "${tag#v}" ]] || return 0
  fi
  tmp="$(mktemp -d)" || return 1
  if ! git clone --quiet --depth 1 --branch "$tag" https://github.com/fujibee/agmsg.git "$tmp/agmsg" ||
     ! bash "$tmp/agmsg/install.sh" --cmd agmsg --update; then
    rm -rf "$tmp"; return 1
  fi
  log "agmsg: release $tag"
  rm -rf "$tmp"
}

run npm-and-codex update_npm
run claude claude update
run opencode opencode upgrade
run rust update_rust
run uv update_binary astral-sh/uv uv-x86_64-unknown-linux-gnu.tar.gz uv 1 uvx
run herdr update_binary herdrdev/herdr herdr-linux-x86_64 herdr
run agent-jsonl-compact update_binary yuki-inaho/agent-jsonl-compact agent-jsonl-compact-x86_64-unknown-linux-musl.tar.gz agent-jsonl-compact 1
run agmsg update_agmsg
run browsers sudo -n /usr/local/bin/update-system-browsers
if (( failed )); then log "Some tools failed; see this log and retry"; exit 1; fi
log "All user tools updated"
