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
CLI, Poetry, uv, Rust, Codex CLI, Claude Code, and RTK.

## Build

```bash
docker build --target standard -t yukiinaho/kasm-noble-ai:latest .
docker build --target full -t yukiinaho/kasm-noble-ai:full .
```

## Connection

Expose `6901/tcp`, keep the inherited ENTRYPOINT, and pass `--wait` as its
argument. Set a strong `VNC_PW` environment variable, then open the mapped
port with `https://` and sign in as `kasm_user`.
