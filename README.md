# Kasm Noble AI Workspace

An Ubuntu 24.04 KasmVNC desktop image for Docker and compatible container
platforms. It includes CUDA support, Japanese input, Chromium, GitHub CLI,
Poetry, uv, Rust, Codex CLI, Claude Code, and RTK.

## Build and publish

```bash
docker build \
  -t yukiinaho/kasm-noble-ai:1.0.0 \
  -t yukiinaho/kasm-noble-ai:latest \
  .

docker push yukiinaho/kasm-noble-ai:1.0.0
docker push yukiinaho/kasm-noble-ai:latest
```

The GitHub Actions workflow publishes the image on pushes to `main`, version
tags, and weekly scheduled builds. Add a Docker Hub access token with write
permission as the repository secret `DOCKERHUB_TOKEN` first.

## Run locally

```bash
docker run --rm -it --gpus all \
  -p 6901:6901 \
  -e VNC_PW='use-a-long-random-password' \
  -e TZ=Asia/Tokyo \
  -e NVIDIA_DRIVER_CAPABILITIES=all \
  -v kasm-workspace:/workspace \
  yukiinaho/kasm-noble-ai:1.0.0
```

Open `https://localhost:6901/` and sign in as `kasm_user` with the value of
`VNC_PW`. The first connection shows a self-signed-certificate warning.

## Container template

Use these settings in a private container template:

| Setting | Value |
| --- | --- |
| Image Path:Tag | `yukiinaho/kasm-noble-ai:1.0.0` |
| Ports | `6901` / TCP |
| Launch Mode | Docker ENTRYPOINT |
| ENTRYPOINT Arguments | `--wait` |
| On-start Script | empty |
| Container disk | at least 60 GB |
| Volume mount path | `/workspace` |

Set `VNC_PW` to a long random password and keep it in a secret. Recommended
environment variables are `OPEN_BUTTON_PORT=6901`,
`NVIDIA_DRIVER_CAPABILITIES=all`, `TZ=Asia/Tokyo`, `WORKSPACE_CHOWN=1`,
`ENABLE_JAPANESE_INPUT=1`, and `AUTO_CD_WORKSPACE=1`.

Open the external port mapped to container port `6901` using `https://`.

## First-run authentication

No credentials or SSH keys are included in the image. Authenticate inside the
desktop when needed:

```bash
gh auth login --web
codex
claude
```

Run `image-smoke-test` in the container to verify installed tools.
