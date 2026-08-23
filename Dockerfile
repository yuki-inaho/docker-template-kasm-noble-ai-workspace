# syntax=docker/dockerfile:1.7

ARG KASM_REPOSITORY=kasmweb/ubuntu-noble-nvidia
ARG KASM_VERSION=1.19.0
FROM ${KASM_REPOSITORY}:${KASM_VERSION}

ARG KASM_REPOSITORY
ARG KASM_VERSION
ARG CHROMIUM_REVISION=""
ARG NODE_VERSION=22
ARG NVM_VERSION=v0.40.2
ARG POETRY_VERSION=1.8.5
ARG CODEX_VERSION=latest
ARG RTK_VERSION=""

LABEL org.opencontainers.image.title="Kasm Noble AI Workspace" \
      org.opencontainers.image.description="Ubuntu 24.04 KasmVNC desktop with CUDA, development tools, Japanese input, Codex CLI, Claude Code, RTK, Chromium, Poetry, uv and Rust" \
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
    /opt/image-build/install-system-packages.sh && \
    CHROMIUM_REVISION="${CHROMIUM_REVISION}" /opt/image-build/install-chromium.sh

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
    CODEX_VERSION="${CODEX_VERSION}" \
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
    CHROMIUM_NO_SANDBOX=1 \
    NVIDIA_DRIVER_CAPABILITIES=all

WORKDIR /workspace
USER 1000

EXPOSE 6901/tcp
STOPSIGNAL SIGTERM

# ENTRYPOINT is intentionally inherited from the official Kasm image.
CMD ["--wait"]
