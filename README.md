# Kasm Noble AI Workspace

[![Docker build](https://github.com/yuki-inaho/docker-template-kasm-noble-ai-workspace/actions/workflows/build-and-push.yml/badge.svg?branch=main)](https://github.com/yuki-inaho/docker-template-kasm-noble-ai-workspace/actions/workflows/build-and-push.yml)

Ubuntu 24.04 KasmVNC desktop image with CUDA and development tools.

Image: [Docker Hub](https://hub.docker.com/r/yukiinaho/kasm-noble-ai)

## Images

Standard image (default):

```bash
docker pull yukiinaho/kasm-noble-ai:latest
```

Full image (adds Chromium):

```bash
docker pull yukiinaho/kasm-noble-ai:full
```

The standard image includes Chrome from the base image, Japanese input, GitHub
CLI, Poetry, uv, Pixi, Rust, Codex CLI, Claude Code, OpenCode 2 with the goal
plugin, Playwright CLI, the Playwright Chromium build, Herdr, RTK, agmsg,
cloudflared, OpenSSH server, AWS CLI v2, and the prebuilt `agent-jsonl-compact` CLI
with its Codex/Claude reader skills. Common terminal utilities include `jq`, `sqlite3`,
`rg`, `fdfind`, `fzf`, `tree`, and `yq`, and the desktop adds VLC and gedit.

The `codex-auto`, `claude-auto`, and `opencode-auto` shell aliases start each
agent with its unattended flags for trusted workspaces.

VS Code is intentionally not installed. The base image ships a VS Code tarball,
but the build removes it because the desktop already provides gedit, VLC and a
browser. This keeps the image smaller and the APT transactions shorter. The
`code/add-microsoft-repo` debconf answer is still preseeded so installing VS Code
later never blocks an upgrade.

### Playwright

`playwright-cli` reuses the Google Chrome shipped in the base image (headless by
default) and disables the Chromium sandbox through the global
`~/.playwright/cli.config.json`, so browser automation works without a browser
download. In addition, the matching Playwright Chromium and headless shell are
preinstalled under `/opt/ms-playwright` (`PLAYWRIGHT_BROWSERS_PATH`), so a plain
`playwright` CLI or `@playwright/test` project can run without a first-run
download.

## Non-interactive APT upgrades

The image is preseeded so `sudo apt update && sudo apt upgrade` does not ask the
debconf questions that a desktop container normally shows:

- `keyboard-configuration` is answered as a JIS 106/109 keyboard
  (`pc105` + `jp`), matching the XFCE/IBus session configuration.
- The VS Code Microsoft APT repository question (`code/add-microsoft-repo`) is
  answered `true`.
- `tzdata` is fixed to `Asia/Tokyo`, certificate refresh is allowed, and
  library/service restart questions are suppressed.
- Every debconf question that already has an answer is marked as seen, so the
  next upgrade does not ask it again.
- `sudo` keeps `DEBIAN_FRONTEND=noninteractive`, and
  `/etc/apt/apt.conf.d/90-kasm-noninteractive` uses `--force-confdef` and
  `--force-confold` to preserve local configuration files.

Run `image-smoke-test` inside the container to verify these settings.

## Desktop defaults

The top XFCE panel is configured with a Files (Nautilus) launcher and a digital
clock on the right side. The clock shows `%Y-%m-%d` above `%H:%M:%S`, so seconds
are always visible.

## Remote access (optional)

`openssh-server` and `cloudflared` are installed, but neither service starts
until credentials are supplied. Host keys are generated on the first start, not
baked into the image, and password authentication is disabled.

```bash
# Register a client public key
sudo kasm-remote-access ssh-key "ssh-ed25519 AAAAC3Nza... user@example"

# Store a Cloudflare Tunnel token without echoing it, then start
sudo kasm-remote-access tunnel-token "<token>"
sudo kasm-remote-access start

# Check state
kasm-remote-access status
```

`runtime-init.sh` starts sshd and cloudflared on later container restarts only
when `authorized_keys` / `/etc/cloudflared/token` exist.

## AWS CLI and RunPod S3

AWS CLI v2 is installed as `/usr/local/bin/aws`. Credentials are not baked into
the image; set them in the environment or with a profile.

For the RunPod S3-compatible endpoint, `aws-runpod` maps the `RUNPOD_S3_*`
environment variables on each call:

```bash
export RUNPOD_S3_ACCESS_KEY_ID=...
export RUNPOD_S3_SECRET_ACCESS_KEY=...
export RUNPOD_S3_REGION=eu-ro-1
export RUNPOD_S3_ENDPOINT=https://s3api-eu-ro-1.runpod.io

aws-runpod s3 ls "s3://$RUNPOD_S3_BUCKET/"
aws-runpod s3 cp ./file.txt "s3://$RUNPOD_S3_BUCKET/path/file.txt"
```

Alternatively create a persistent profile:

```bash
aws configure set aws_access_key_id "$RUNPOD_S3_ACCESS_KEY_ID" --profile runpod
aws configure set aws_secret_access_key "$RUNPOD_S3_SECRET_ACCESS_KEY" --profile runpod
aws configure set region "$RUNPOD_S3_REGION" --profile runpod
aws --profile runpod s3 ls \
  --region "$RUNPOD_S3_REGION" \
  --endpoint-url "$RUNPOD_S3_ENDPOINT" \
  "s3://$RUNPOD_S3_BUCKET/"
```

## Keyboard and Japanese input

The desktop uses the Japanese (`jp`) XKB layout for JIS 106/109 keyboards with
IBus and Mozc; direct input also uses IBus's Japanese XKB engine. Toggle the
input method with `Control+space` or `Super+space`. The global
`Zenkaku_Hankaku` and `Alt+grave` triggers are disabled to prevent IBus shortcut
grabs from intercepting `~` in KasmVNC's browser keyboard path. KasmVNC raw
keyboard mode remains disabled.

After deploying a new image, verify the real VNC input path with `xev`; XTEST
tools such as `xdotool` do not reproduce browser-to-KasmVNC keyboard handling.

## Build

```bash
docker build --target standard -t yukiinaho/kasm-noble-ai:latest .
docker build --target full -t yukiinaho/kasm-noble-ai:full .
```

Tool versions are pinned in the `Dockerfile` (`NPM_VERSION`, `CODEX_VERSION`,
`CLAUDE_VERSION`, `OPENCODE_VERSION`, `PLAYWRIGHT_VERSION`, `PLAYWRIGHT_CLI_VERSION`,
`RTK_VERSION`, `AGMSG_VERSION`, `HERDR_VERSION`, `AGENT_JSONL_COMPACT_VERSION`).
The weekly canary overrides the agent versions with `latest` to catch upstream
breakage. Docker BuildKit cache mounts keep the npm downloads out of the image
layers and speed up rebuilds.

## Connection

Expose `6901/tcp`, keep the inherited ENTRYPOINT, and pass `--wait` as its
argument. Set a strong `VNC_PW` environment variable, then open the mapped
port with `https://` and sign in as `kasm_user`.

By default, the VNC service uses TLS for direct TCP connections. When an HTTPS
reverse proxy terminates TLS before forwarding to port `6901`, set
`KASMVNC_REQUIRE_SSL=false` and expose `6901` as an HTTP service.
