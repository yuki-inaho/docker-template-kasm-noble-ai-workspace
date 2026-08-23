# Kasm Noble AI Workspace

[![Docker build](https://github.com/yuki-inaho/docker-template-kasm-noble-ai-workspace/actions/workflows/build-and-push.yml/badge.svg?branch=main)](https://github.com/yuki-inaho/docker-template-kasm-noble-ai-workspace/actions/workflows/build-and-push.yml)

A custom Ubuntu 24.04 KasmVNC desktop image for Docker-based environments.

## Base Image

```text
kasmweb/ubuntu-noble-nvidia:1.19.0
```

This base image already includes Ubuntu 24.04, KasmVNC, XFCE, NVIDIA/CUDA,
Chrome, VS Code, sudo, Node.js 22, and pyenv.

This image adds Japanese input, Chromium, GitHub CLI, Poetry, uv, Rust, Codex
CLI, Claude Code, and RTK.

## Build

```bash
docker build -t yukiinaho/kasm-noble-ai:1.0.0 .
docker push yukiinaho/kasm-noble-ai:1.0.0
```

For GitHub Actions, create a Docker Hub personal access token with Read & Write
permission and save it as the repository secret `DOCKERHUB_TOKEN`.

## Connection

Expose `6901/tcp`, keep the image ENTRYPOINT, and pass `--wait` as its
argument. Set a strong `VNC_PW` environment variable, then open the mapped
port with `https://` and sign in as `kasm_user`.
