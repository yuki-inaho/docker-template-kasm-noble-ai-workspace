# syntax=docker/dockerfile:1.7

# ---------------------------------------------------------------------------
# Base image and pinned tool versions
# ---------------------------------------------------------------------------
ARG KASM_REPOSITORY=kasmweb/ubuntu-noble-nvidia
ARG KASM_VERSION=1.19.0
FROM ${KASM_REPOSITORY}:${KASM_VERSION} AS common

ARG KASM_REPOSITORY
ARG KASM_VERSION
ARG CHROMIUM_REVISION=1684548
ARG NODE_VERSION=22.23.2
ARG NPM_VERSION=12.2.0
ARG NVM_VERSION=v0.40.2
ARG POETRY_VERSION=1.8.5
ARG UV_VERSION=0.12.5
ARG RUST_VERSION=1.98.0
ARG JUST_VERSION=1.58.0
ARG JUST_SHA256=4a5cc2f53e6f0f8c59092a6cc38291eb729d46a7dd95d3ae582008881b84931d
ARG CODEX_VERSION=0.163.0
ARG CLAUDE_VERSION=2.1.306
ARG OPENCODE_VERSION=2.1.2
ARG PLAYWRIGHT_CLI_VERSION=0.1.22
ARG PLAYWRIGHT_VERSION=1.64.1
ARG RTK_VERSION=v1.0.1
ARG PIXI_VERSION=0.77.1
ARG PIXI_SHA256=5115a89a9189a2e4e7e8d2f04236a7be586d8f6091dfc9ea869fb3c4a52b6935
ARG HERDR_VERSION=v0.9.5
ARG HERDR_SHA256=14d9e8bc8b4a9e0118d77c32266f76d461f09b40342eb23752960bd89f59929d
ARG AGENT_JSONL_COMPACT_VERSION=v0.2.0
ARG AGENT_JSONL_COMPACT_SHA256=6b40ca9b8cc354cb3cc5cc3bf868fb1857981f61d20c625d9f5c8bd472aedf8b
ARG AGMSG_VERSION=v1.5.3
ARG AWSCLI_VERSION=2.38.3
ARG CLOUDFLARED_VERSION=2026.9.1
ARG CLOUDFLARED_SHA256=3be76adc4185d36a0bfb4c2dd8663292f0ed363797f2180333b513b43c81d419

LABEL org.opencontainers.image.title="Kasm Noble AI Workspace" \
      org.opencontainers.image.description="Ubuntu 24.04 KasmVNC desktop with CUDA, development tools, Japanese input, Codex CLI, Claude Code, OpenCode 2 with goal plugin, Playwright CLI and Chromium, Herdr, RTK, agmsg, cloudflared, Pixi, Poetry, uv, Rust, agent-jsonl-compact, VLC, gedit and AWS CLI" \
      org.opencontainers.image.base.name="${KASM_REPOSITORY}:${KASM_VERSION}"

USER root
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV DEBIAN_FRONTEND=noninteractive \
    HOME=/home/kasm-default-profile \
    XDG_CONFIG_HOME=/home/kasm-default-profile/.config \
    XDG_CACHE_HOME=/home/kasm-default-profile/.cache \
    XDG_DATA_HOME=/home/kasm-default-profile/.local/share \
    PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright \
    STARTUPDIR=/dockerstartup \
    WORKSPACE_DIR=/workspace \
    NVIDIA_DRIVER_CAPABILITIES=all

WORKDIR ${HOME}

# ---------------------------------------------------------------------------
# Stage 1: system packages, cloudflared, GitHub CLI, Japanese input, SSH
# ---------------------------------------------------------------------------
COPY --chmod=0755 scripts/install-system-packages.sh /opt/image-build/install-system-packages.sh

RUN set -x && \
    CLOUDFLARED_VERSION="${CLOUDFLARED_VERSION}" \
    CLOUDFLARED_SHA256="${CLOUDFLARED_SHA256}" \
    /opt/image-build/install-system-packages.sh

COPY --chmod=0755 scripts/configure-ibus-hotkeys.sh /opt/image-build/configure-ibus-hotkeys.sh

RUN set -x && /opt/image-build/configure-ibus-hotkeys.sh

# ---------------------------------------------------------------------------
# Stage 1b: AWS CLI v2 and the optional RunPod S3 wrapper
# ---------------------------------------------------------------------------
COPY --chmod=0755 scripts/install-awscli.sh scripts/aws-runpod.sh /opt/image-build/

RUN set -x && \
    AWSCLI_VERSION="${AWSCLI_VERSION}" /opt/image-build/install-awscli.sh && \
    install -m 0755 /opt/image-build/aws-runpod.sh /usr/local/bin/aws-runpod

# ---------------------------------------------------------------------------
# Stage 2: non-interactive apt, debconf preseed, SSH / Cloudflare defaults
# ---------------------------------------------------------------------------
COPY --chmod=0755 \
     scripts/configure-apt-noninteractive.sh \
     scripts/configure-remote-access.sh \
     scripts/kasm-remote-access.sh \
     /opt/image-build/

RUN set -x && \
    /opt/image-build/configure-apt-noninteractive.sh && \
    /opt/image-build/configure-remote-access.sh

# ---------------------------------------------------------------------------
# Stage 3: user-scoped tool directories
#
# Kasm copies /home/kasm-default-profile into /home/kasm-user on first start.
# User-scoped tools therefore have to be installed into the default profile.
# The upstream image already owns this profile as uid 1000. Do not use a
# recursive chown here: changing metadata for the whole profile duplicates its
# contents in a new image layer.
# ---------------------------------------------------------------------------
RUN set -x && \
    test "$(stat -c '%u:%g' /home/kasm-default-profile)" = "1000:0" && \
    rm -rf /home/kasm-default-profile/.nvm && \
    install -d -m 0755 -o 1000 -g 0 \
      /opt/pyenv \
      /opt/ms-playwright \
      /home/kasm-default-profile/.nvm \
      /home/kasm-default-profile/.local \
      /home/kasm-default-profile/.local/bin \
      /home/kasm-default-profile/.cargo \
      /home/kasm-default-profile/.cargo/bin \
      /home/kasm-default-profile/.rustup

USER 1000

COPY --chmod=0755 scripts/install-user-tools.sh /opt/image-build/install-user-tools.sh

# ---------------------------------------------------------------------------
# Stage 4: stable toolchains (Node, npm, Poetry, uv, Rust, just)
#
# Stable, large toolchains go first. Updating the agent CLIs below therefore
# reuses this layer instead of reinstalling Rust, Node, Poetry, and uv.
# ---------------------------------------------------------------------------
RUN --mount=type=cache,target=/tmp/npm-cache,uid=1000,gid=0 \
    set -x && \
    NPM_CONFIG_CACHE=/tmp/npm-cache \
    NODE_VERSION="${NODE_VERSION}" \
    NPM_VERSION="${NPM_VERSION}" \
    NVM_VERSION="${NVM_VERSION}" \
    POETRY_VERSION="${POETRY_VERSION}" \
    UV_VERSION="${UV_VERSION}" \
    RUST_VERSION="${RUST_VERSION}" \
    JUST_VERSION="${JUST_VERSION}" \
    JUST_SHA256="${JUST_SHA256}" \
    /opt/image-build/install-user-tools.sh foundation

# ---------------------------------------------------------------------------
# Stage 5: agent CLIs (Codex, Claude Code, OpenCode 2 + goal plugin, Playwright)
#
# These CLIs intentionally track explicit release versions so an image tag is
# reproducible. The weekly canary overrides them with "latest".
# ---------------------------------------------------------------------------
RUN --mount=type=cache,target=/tmp/npm-cache,uid=1000,gid=0 \
    set -x && \
    NPM_CONFIG_CACHE=/tmp/npm-cache \
    CODEX_VERSION="${CODEX_VERSION}" \
    CLAUDE_VERSION="${CLAUDE_VERSION}" \
    OPENCODE_VERSION="${OPENCODE_VERSION}" \
    PLAYWRIGHT_CLI_VERSION="${PLAYWRIGHT_CLI_VERSION}" \
    PLAYWRIGHT_VERSION="${PLAYWRIGHT_VERSION}" \
    PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH}" \
    RTK_VERSION="${RTK_VERSION}" \
    /opt/image-build/install-user-tools.sh agents

# ---------------------------------------------------------------------------
# Stage 6: standalone workspace CLIs (Pixi, Herdr, agent-jsonl-compact, agmsg)
#
# These use pinned, checksum-verified prebuilt x86_64 binaries.
# ---------------------------------------------------------------------------
RUN set -x && \
    PIXI_VERSION="${PIXI_VERSION}" \
    PIXI_SHA256="${PIXI_SHA256}" \
    HERDR_VERSION="${HERDR_VERSION}" \
    HERDR_SHA256="${HERDR_SHA256}" \
    AGENT_JSONL_COMPACT_VERSION="${AGENT_JSONL_COMPACT_VERSION}" \
    AGENT_JSONL_COMPACT_SHA256="${AGENT_JSONL_COMPACT_SHA256}" \
    AGMSG_VERSION="${AGMSG_VERSION}" \
    /opt/image-build/install-user-tools.sh workspace

# ---------------------------------------------------------------------------
# Stage 7: default profile (bashrc, XFCE panel, Playwright CLI config)
# ---------------------------------------------------------------------------
COPY --chmod=0755 scripts/configure-default-profile.sh /opt/image-build/configure-default-profile.sh

RUN set -x && /opt/image-build/configure-default-profile.sh

USER root

# ---------------------------------------------------------------------------
# Stage 8: startup hooks and runtime wiring
#
# Preserve Kasm's existing long-running custom startup script, then wrap it with
# our one-time runtime initialization. The original script must remain alive or
# Kasm will restart it continuously.
# ---------------------------------------------------------------------------
COPY --chmod=0755 scripts/runtime-init.sh scripts/custom-startup.sh scripts/smoke-test.sh scripts/vnc-startup.sh /opt/image-build/

RUN set -x && \
    install -m 0755 /opt/image-build/runtime-init.sh /dockerstartup/runtime-init.sh && \
    install -m 0755 /dockerstartup/vnc_startup.sh /dockerstartup/vnc_startup.ssl.sh && \
    sed 's/[[:space:]]-sslOnly//g' /dockerstartup/vnc_startup.ssl.sh > /dockerstartup/vnc_startup.http.sh && \
    chmod 0755 /dockerstartup/vnc_startup.http.sh && \
    sed -i '/^[[:space:]]*require_ssl:/d' /etc/kasmvnc/kasmvnc.yaml && \
    sed -i '/^[[:space:]]*pem_key:/a\    require_ssl: false' /etc/kasmvnc/kasmvnc.yaml && \
    install -m 0755 /opt/image-build/vnc-startup.sh /dockerstartup/vnc_startup.sh && \
    if [[ ! -f /dockerstartup/custom_startup.base.sh ]]; then \
      if [[ -f /dockerstartup/custom_startup.sh ]]; then \
        mv /dockerstartup/custom_startup.sh /dockerstartup/custom_startup.base.sh; \
      else \
        printf '%s\n' '#!/usr/bin/env bash' 'while true; do sleep 3600; done' > /dockerstartup/custom_startup.base.sh; \
        chmod 0755 /dockerstartup/custom_startup.base.sh; \
      fi; \
    fi && \
    install -m 0755 /opt/image-build/custom-startup.sh /dockerstartup/custom_startup.sh && \
    install -m 0755 /opt/image-build/smoke-test.sh /usr/local/bin/image-smoke-test && \
    install -d -m 2775 -o 1000 -g 0 /workspace && \
    install -d -m 0755 -o 1000 -g 0 /home/kasm-user && \
    rm -rf /opt/image-build

ENV HOME=/home/kasm-user \
    XDG_CONFIG_HOME=/home/kasm-user/.config \
    XDG_CACHE_HOME=/home/kasm-user/.cache \
    XDG_DATA_HOME=/home/kasm-user/.local/share \
    PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright \
    WORKSPACE_DIR=/workspace \
    OPEN_BUTTON_PORT=6901 \
    ENABLE_JAPANESE_INPUT=1 \
    WORKSPACE_CHOWN=1 \
    AUTO_CD_WORKSPACE=1 \
    IMAGE_VARIANT=standard \
    NVIDIA_DRIVER_CAPABILITIES=all

WORKDIR /workspace
USER 1000

EXPOSE 6901/tcp
STOPSIGNAL SIGTERM

# ENTRYPOINT is intentionally inherited from the official Kasm image.
CMD ["--wait"]

# ---------------------------------------------------------------------------
# Published targets
# ---------------------------------------------------------------------------
# The default image keeps the Chrome supplied by the base image. It uses system
# Chrome for Playwright and installs the matching Playwright Chromium snapshot.
# VS Code is intentionally not installed: the desktop already ships gedit, VLC
# and a browser, and skipping the VS Code package keeps the image lean.
FROM common AS standard

# Chromium is an opt-in extension. Keeping it in a terminal stage lets clients
# that already have the standard image pull only this additional layer.
FROM standard AS full

ARG CHROMIUM_REVISION

USER root

COPY --chmod=0755 scripts/install-chromium.sh /tmp/install-chromium.sh

RUN set -x && \
    CHROMIUM_REVISION="${CHROMIUM_REVISION}" /tmp/install-chromium.sh && \
    rm -f /tmp/install-chromium.sh

ENV IMAGE_VARIANT=full \
    CHROMIUM_NO_SANDBOX=1

LABEL org.opencontainers.image.description="Ubuntu 24.04 KasmVNC desktop with CUDA, development tools, Japanese input, Codex CLI, Claude Code, OpenCode 2 with goal plugin, Playwright CLI and Chromium, Herdr, RTK, agmsg, cloudflared, Pixi, Poetry, uv, Rust, agent-jsonl-compact, VLC, gedit, AWS CLI and Chromium"

USER 1000

# ---------------------------------------------------------------------------
# CI test targets
#
# These targets run during CI. They are separate from the published targets so
# the smoke-test layer is never included in a pulled image.
# ---------------------------------------------------------------------------
FROM standard AS test-standard

RUN set -x && HOME=/home/kasm-default-profile /usr/local/bin/image-smoke-test

FROM full AS test-full

RUN set -x && HOME=/home/kasm-default-profile /usr/local/bin/image-smoke-test

# Keep the lean standard target as the unqualified `docker build .` result.
FROM standard AS default
