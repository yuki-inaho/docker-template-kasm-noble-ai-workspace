# syntax=docker/dockerfile:1.7

ARG KASM_REPOSITORY=kasmweb/ubuntu-noble-nvidia
ARG KASM_VERSION=1.19.0
FROM ${KASM_REPOSITORY}:${KASM_VERSION} AS common

ARG KASM_REPOSITORY
ARG KASM_VERSION
ARG CHROMIUM_REVISION=1684548
ARG NODE_VERSION=22.23.2
ARG NVM_VERSION=v0.40.2
ARG POETRY_VERSION=1.8.5
ARG UV_VERSION=0.12.5
ARG RUST_VERSION=1.98.0
ARG JUST_VERSION=1.58.0
ARG JUST_SHA256=4a5cc2f53e6f0f8c59092a6cc38291eb729d46a7dd95d3ae582008881b84931d
ARG CODEX_VERSION=latest
ARG CLAUDE_VERSION=latest
ARG RTK_VERSION=v0.45.0

LABEL org.opencontainers.image.title="Kasm Noble AI Workspace" \
      org.opencontainers.image.description="Ubuntu 24.04 KasmVNC desktop with CUDA, development tools, Japanese input, Codex CLI, Claude Code, RTK, Poetry, uv and Rust" \
      org.opencontainers.image.base.name="${KASM_REPOSITORY}:${KASM_VERSION}"

USER root
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV DEBIAN_FRONTEND=noninteractive \
    HOME=/home/kasm-default-profile \
    XDG_CONFIG_HOME=/home/kasm-default-profile/.config \
    XDG_CACHE_HOME=/home/kasm-default-profile/.cache \
    XDG_DATA_HOME=/home/kasm-default-profile/.local/share \
    STARTUPDIR=/dockerstartup \
    WORKSPACE_DIR=/workspace \
    NVIDIA_DRIVER_CAPABILITIES=all

WORKDIR ${HOME}

COPY scripts/ /opt/image-build/

RUN chmod 0755 /opt/image-build/*.sh && \
    /opt/image-build/install-system-packages.sh

# Kasm copies /home/kasm-default-profile into /home/kasm-user on first start.
# User-scoped tools therefore have to be installed into the default profile.
# The upstream image already owns this profile as uid 1000. Do not use a
# recursive chown here: changing metadata for the whole profile duplicates its
# contents in a new image layer.
RUN test "$(stat -c '%u:%g' /home/kasm-default-profile)" = "1000:0" && \
    install -d -m 0755 -o 1000 -g 0 /opt/pyenv

USER 1000

RUN NODE_VERSION="${NODE_VERSION}" \
    NVM_VERSION="${NVM_VERSION}" \
    POETRY_VERSION="${POETRY_VERSION}" \
    UV_VERSION="${UV_VERSION}" \
    RUST_VERSION="${RUST_VERSION}" \
    JUST_VERSION="${JUST_VERSION}" \
    JUST_SHA256="${JUST_SHA256}" \
    CODEX_VERSION="${CODEX_VERSION}" \
    CLAUDE_VERSION="${CLAUDE_VERSION}" \
    RTK_VERSION="${RTK_VERSION}" \
    /opt/image-build/install-user-tools.sh

RUN /opt/image-build/configure-default-profile.sh

USER root

# Preserve Kasm's existing long-running custom startup script, then wrap it with
# our one-time runtime initialization. The original script must remain alive or
# Kasm will restart it continuously.
RUN install -m 0755 /opt/image-build/runtime-init.sh /dockerstartup/runtime-init.sh && \
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

# The default image keeps the browser supplied by the base image. Build it with
# `docker build --target standard ...` when an explicit target is preferable.
FROM common AS standard

# Chromium is an opt-in extension. Keeping it in a terminal stage lets clients
# that already have the standard image pull only this additional layer.
FROM standard AS full

ARG CHROMIUM_REVISION

USER root

COPY scripts/install-chromium.sh /tmp/install-chromium.sh

RUN chmod 0755 /tmp/install-chromium.sh && \
    CHROMIUM_REVISION="${CHROMIUM_REVISION}" /tmp/install-chromium.sh && \
    rm -f /tmp/install-chromium.sh

ENV IMAGE_VARIANT=full \
    CHROMIUM_NO_SANDBOX=1

LABEL org.opencontainers.image.description="Ubuntu 24.04 KasmVNC desktop with CUDA, development tools, Japanese input, Codex CLI, Claude Code, RTK, Poetry, uv, Rust and Chromium"

USER 1000

# These targets run during CI. They are separate from the published targets so
# the smoke-test layer is never included in a pulled image.
FROM standard AS test-standard

RUN HOME=/home/kasm-default-profile /usr/local/bin/image-smoke-test

FROM full AS test-full

RUN HOME=/home/kasm-default-profile /usr/local/bin/image-smoke-test

# Keep the lean standard target as the unqualified `docker build .` result.
FROM standard AS default
