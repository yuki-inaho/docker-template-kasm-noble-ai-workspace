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

The build removes the VS Code tarball supplied by the base image to reduce image
size and APT work. The `code/add-microsoft-repo` debconf answer is preseeded so a
later VS Code installation does not block upgrades.

### Playwright

`playwright-cli` uses the installed Google Chrome in headless mode by default.
Its global configuration at `~/.playwright/cli.config.json` disables the
Chromium sandbox. Playwright's matching Chromium and headless shell are also
preinstalled under `/opt/ms-playwright` (`PLAYWRIGHT_BROWSERS_PATH`).

The base image's `/usr/bin/google-chrome` wrapper also passes `--no-sandbox`
for desktop launches. In a default local Docker test, Chrome could not create
the namespaces it needed for its sandbox. Treat browser sessions in this image
as unsandboxed and use a separately isolated environment for untrusted pages.

## Non-interactive APT upgrades

Before installing tools, the build runs `apt-get upgrade --with-new-pkgs --no-remove`
for Ubuntu packages and configured third-party repositories, including Chrome.
An APT index failure stops the build. Local configuration is preserved, and
package versions depend on the repositories at build time. Pinning the base tag
alone does not fix those versions.

The image preanswers the debconf questions that can block an APT upgrade:

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

### October 2026 security refresh

The October 2026 review covered upstream advisories and packages in
`kasmweb/ubuntu-noble-nvidia:1.19.0`. The version checks below remain minimums;
the update worker can install newer releases.

| Component | Finding and action |
| --- | --- |
| KasmVNC | Install the fork's **1.5.2+git20261028-1** development snapshot, built from [the integration commit](https://github.com/yuki-inaho/KasmVNC/commit/ae591980874c6777c24c59ba4d508c5251b59e7e) containing fork PR #2, WebSocket bounds checks and the retained session and screen-update fixes. It includes **X.Org 21.1.25**, libjpeg-turbo 3.2.1 and libwebp 1.6.0. The package URL and SHA-256 are pinned independently of the Kasm base image. |
| Node.js | Update 22.23.2 to **22.23.4**, the [October security release](https://nodejs.org/en/blog/release/v22.23.4), including TLS, DNS, Brotli and bundled CA fixes. |
| npm | Update to **12.2.1** and patch its bundled `undici` and `ip-address` libraries to versions without the advisories found during this review. The updater checks the selected npm dependency trees against OSV. |
| Ubuntu CA bundle | The base contains 20240203. Require **20260816ubuntu0.24.04.1** or later for [USN-8944-1](https://ubuntu.com/security/notices/USN-8944-1), which removes the distrusted emSign root. |
| Ubuntu userland | Refresh inherited packages, including OpenSSL, curl, OpenSSH, xz and Chrome, rather than only installing extra development packages. |
| Browsers | Require Chrome **156.0.8078.47** or later ([stable security release](https://chromereleases.googleblog.com/2026/10/stable-channel-update-for-desktop_02018666648.html)). Refresh the optional Chromium snapshot from revision 1684548 (154.0.8020.0) to **1724358 (158.0.8117.0)**, with a pinned SHA-256. Snapshots remain development builds, not stable security releases. |
| PHP | No PHP packages or executable were found in the inspected base; this template does not install PHP. If a future base adds Ubuntu PHP 8.3, require **8.3.6-0ubuntu0.24.04.13** or later for [USN-8948-1](https://ubuntu.com/security/notices/USN-8948-1). |
| Linux kernel | No kernel image package is installed here. Containers [share the host kernel](https://docs.docker.com/get-started/docker-concepts/the-basics/what-is-a-container/). The host operator must apply the notice for its kernel flavour, for example [USN-8917-1](https://ubuntu.com/security/notices/USN-8917-1), and reboot where required. |

Both image smoke tests run `image-security-check` to verify the minimum versions
and the removal of the distrusted root from Ubuntu's and Node's CA bundles. This
is a regression check, not a complete vulnerability scan. Application-specific
certificate bundles, mounted environments and PHP installed after deployment
need separate updates. The host operator manages the kernel and NVIDIA driver.

Playwright **1.64.1** was the latest stable npm release at review time. Its
[browser manifest](https://github.com/microsoft/playwright/blob/v1.64.1/packages/playwright-core/browsers.json)
still pins Chromium **156.0.8078.4**, older than the patched Chrome stable build.
That bundled browser is retained for Playwright compatibility and is **not
claimed fully patched** by this refresh. `playwright-cli` defaults to the newer
Chrome channel, with the sandbox limitation described above. Update Playwright
and its bundled browsers when upstream ships a suitable release.

## Desktop defaults

`~/Desktop/AI-SETUP.md` asks an AI agent to review and install skills, Harness²
and agent-jsonl-compact. It covers untrusted instructions, configuration changes
and credential exposure. The startup hook copies the file from
`/usr/local/share/kasm-noble-ai-workspace/AI-SETUP.md` only when the desktop
destination does not exist. It leaves existing files and symlinks alone.

The top XFCE panel is configured with a Files (Nautilus) launcher and a digital
clock on the right side. The clock shows `%Y-%m-%d` above `%H:%M:%S`, so seconds
are always visible.

## Tool and browser updates

GitHub Actions rebuilds and tests both images daily before publishing them.
Each container also runs an updater at startup and every 24 hours. It refreshes
Node LTS, npm, Codex, Claude Code, OpenCode 2, Rust and cargo, uv, Herdr, agmsg,
agent-jsonl-compact, Playwright and Chrome. The full image also updates its
Chromium snapshot.

New versions apply to new processes; restart an open shell to use a new Node
version. Node LTS migration reinstalls global packages without npm lifecycle
scripts, so user-added packages that need build scripts may require a manual
rebuild. The updater does not restart the instance.

Before installing npm, Codex and Playwright updates, the updater checks their
public dependency names and versions against [OSV](https://osv.dev/). A known
malware advisory or an unavailable OSV service stops that npm update. Other
advisories are logged for review, and the installed tree is checked again.
The updater also applies targeted fixes for two vulnerable libraries bundled
with npm 12.2.1. These checks do not cover every tool or detect unknown malware,
compromised maintainers or malicious releases without an advisory.

`workspace-update-tools --once` runs the same updater on demand. Set
`AUTO_UPDATE_TOOLS=0` to disable the background worker. Its log is
`~/.local/state/kasm-workspace/tool-update.log`; failures are retried after one
hour. The updater checks release asset hashes against GitHub metadata. For
Chromium it checks the MD5 in Google's snapshot metadata and logs the SHA-256;
neither check is an independent publisher signature. It retains old Chromium
directories because running browsers may still need them.

Updates depend on network access, upstream availability, supported platforms
and passing tests. They are not instantaneous. Project-specific toolchain pins
take precedence, and the updater does not change the host kernel or project
virtual environments.

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

For a security rebuild, refresh the base and invalidate the APT layer explicitly:

```bash
docker build --pull --build-arg SECURITY_REFRESH="$(date -u +%Y%m%dT%H%M%SZ)" \
  --target test-standard -t kasm-noble-ai:security-test .
```

`--pull` alone does not rerun a cached APT layer if the base tag is unchanged.
CI passes one `SECURITY_REFRESH` value per workflow run/attempt to all test and
publish targets, refreshing packages once and reusing that layer within the run.
Custom full-image snapshots must set both `CHROMIUM_REVISION` and
`CHROMIUM_SHA256`; the build rejects an archive that does not match the checksum.
After the refreshed image is published, pull it and recreate containers to use
it; a Git push or restarting an existing container does not replace its image.
Back up any data stored outside persistent volumes before recreation.

The initial installation uses Dockerfile version pins as a fallback; the later
refresh stage upgrades the tools listed above. Other tools retain their pins.
The weekly canary also tests rolling base-image and agent versions. Docker
BuildKit cache mounts speed up rebuilds. GitHub Actions are pinned to reviewed
commit IDs; update those pins through a reviewed change.

## Connection

Expose `6901/tcp`, keep the inherited ENTRYPOINT, and pass `--wait` as its
argument. Set a strong `VNC_PW` environment variable, then open the mapped
port with `https://` and sign in as `kasm_user`.

By default, the VNC service uses TLS for direct TCP connections. When an HTTPS
reverse proxy terminates TLS before forwarding to port `6901`, set
`KASMVNC_REQUIRE_SSL=false` and expose `6901` as an HTTP service.

## KasmVNC fork validation

The [Noble integration package](https://github.com/yuki-inaho/KasmVNC/releases/tag/v1.5.2-noble-master-ae591980874c)
is built from the fork's development master; its package version does not mean
it is an official KasmVNC 1.5.2 release. It includes the web client built from
the fork's pinned submodule. The fork's CI checks the locked web dependencies,
source hashes, the libjpeg-turbo signature and four cache regressions with
AddressSanitizer and LeakSanitizer.

libjpeg-turbo and libwebp are linked into the server. Security fixes to those
libraries require a rebuilt KasmVNC package; updating Ubuntu packages alone
does not replace the bundled code. The fork checks those versions against OSV
weekly. Advisory checks cannot detect unknown vulnerabilities or malicious
code that has not been reported.

CI checks installed versions, HTTPS authentication, WebSocket connections,
keyboard input and two simultaneous viewers on the standard image. It also runs
build, smoke and security checks on both variants. It does not test all four
connection configurations. Japanese IME interaction and NVIDIA hardware acceptance still
require testing on a GPU host.
