# Vast.ai / RunPod テンプレート設定

以下では、公開済みイメージ名を `yukiinaho/kasm-noble-ai:latest` と表記します。固定バージョンを使う場合は `yukiinaho/kasm-noble-ai:1.0.0` のようなタグを指定してください。

## Vast.ai

| 項目 | 値 |
|---|---|
| Template Name | `Kasm Noble AI Workspace` |
| Template Description | `Ubuntu 24.04 + KasmVNC + CUDA + AI CLI development environment` |
| Image Path:Tag | `yukiinaho/kasm-noble-ai:latest` |
| Ports | `6901` / `TCP` |
| Launch Mode | `Docker ENTRYPOINT` |
| ENTRYPOINT Arguments | `--wait` |
| On-start Script | 空欄 |
| Container disk size | `60 GB`以上 |
| Volume size | 用途に応じて `120 GB`以上 |
| Volume mount path | `/workspace` |
| Extra Filters | `verified=true cpu_arch=amd64 cuda_vers>=12.6 reliability>=0.98` |

### Vast.ai環境変数

| Key | Value | 備考 |
|---|---|---|
| `VNC_PW` | 長いランダム値 | 必須。公開テンプレートには固定値を保存しないでください。 |
| `OPEN_BUTTON_PORT` | `6901` | VastのOpenボタン用です。イメージ側にも既定値があります。 |
| `NVIDIA_DRIVER_CAPABILITIES` | `all` | GPU描画およびCUDA利用向けです。 |
| `TZ` | `Asia/Tokyo` | 任意です。 |
| `WORKSPACE_CHOWN` | `1` | `/workspace`直下をUID 1000で書き込み可能にします。 |
| `ENABLE_JAPANESE_INPUT` | `1` | IBus/Mozcを有効にします。 |
| `AUTO_CD_WORKSPACE` | `1` | 新しい対話シェルを`/workspace`から開始します。 |
| `GIT_USER_NAME` | 任意 | 例: `Your Name`。イメージには個人情報を焼き込みません。 |
| `GIT_USER_EMAIL` | 任意 | 例: `you@example.com`。 |

ブラウザ接続先は、Vastが内部`6901/tcp`へ割り当てた外部ポートです。必ず`https://`で開いてください。

- ユーザー名: `kasm_user`
- パスワード: `VNC_PW`の値

## RunPod

| 項目 | 値 |
|---|---|
| Container image | `yukiinaho/kasm-noble-ai:latest` |
| Container disk | `60 GB`以上 |
| Volume disk | 用途に応じて `120 GB`以上 |
| Volume mount path | `/workspace` |
| Expose HTTP Ports | `6901` |
| Start command | 空欄。指定欄で引数が必要な場合のみ`--wait` |

### RunPod環境変数

`VNC_PW`、`NVIDIA_DRIVER_CAPABILITIES=all`、`TZ=Asia/Tokyo`を設定してください。Git情報は必要な場合だけ`GIT_USER_NAME`と`GIT_USER_EMAIL`で渡します。

## 初回起動後に手動で行う認証

認証情報、SSH秘密鍵、Claude/Codex設定、skillsはイメージに含めていません。

```bash
gh auth login --web
codex
claude
```

GitHubへSSH接続する場合は、起動後にご自身で鍵を生成・登録してください。公開イメージのビルド時に秘密鍵を作成すると、利用者間で同じ秘密鍵を共有する事故につながるため禁止です。
