# Kasm Noble AI Workspace

Ubuntu 24.04のKasmVNCデスクトップを、Vast.ai・RunPod・通常のDockerで使用するためのカスタムイメージです。既存の公式Kasm GPUイメージへ必要な開発環境だけを追加する構成にしています。

## 採用したベースイメージ

既定値は次の公式Kasmイメージです。

```text
kasmweb/ubuntu-noble-nvidia:1.19.0
```

このベースにはUbuntu 24.04、KasmVNC、XFCE、NVIDIA/CUDA環境、Chrome、VS Code、sudo、Node.js 22、pyenvがすでに含まれています。本リポジトリでは、同じ機能を再構築せず、その上へ添付スクリプト相当の環境を追加します。

## 追加されるもの

- 一般的なビルド・Python開発パッケージ
- Emacs、Nautilus、Nomacs、tmux、htop
- 日本語フォント、IBus、Mozc、日本語キーボード設定
- GitHub CLI `gh`とOpenSSHクライアント
- `kasm-user`向けパスワードなし`sudo`（開発用コンテナ内のみ）
- Poetry 1.8.5、`poetry shell`
- `uv`
- Rust stable、Cargo、`just`
- pyenv-updateプラグイン
- Node.js 22、OpenAI Codex CLI
- Claude Code
- RTK
- Chromium snapshot
- `/workspace`へのデスクトップショートカット
- `claude-auto`と`codex-auto`のエイリアス

## 意図的に含めていないもの

- `install_colmap.sh`およびCOLMAP専用依存パッケージ
- `copy_install_apt.sh`（旧版・重複スクリプト）
- `install_glibc.sh`（Ubuntu 24.04のシステムglibcを使用するため）
- `memo.txt`
- 添付ZIP内の`skills/`
- `gh auth login`
- SSH鍵の生成、`ssh-add`、個人の`known_hosts`
- 固定のGitユーザー名・メールアドレス
- APIキー、アクセストークン、VNCパスワード
- Ubuntu 24.04でSnap前提となるAPT版Firefox

Chromeはベースイメージに含まれ、Chromiumも追加されるため、ブラウザ用途はこの2つで満たします。Kasm/Vast/RunPod環境との互換性を優先し、追加Chromiumは既定で`--no-sandbox`を使用します。実行環境側でChromium sandboxを利用できる場合は、`CHROMIUM_NO_SANDBOX=0`へ変更してください。

また、Dockerfile内では`apt upgrade`を実行しません。ベースタグを更新して再ビルドする方が、Kasm/CUDAの整合性を保ちやすいためです。

## ローカルビルド

```bash
docker build \
  --tag your-dockerhub-user/kasm-noble-ai:1.0.0 \
  .
```

バージョンを固定する場合はビルド引数を使用します。

```bash
docker build \
  --build-arg KASM_REPOSITORY=kasmweb/ubuntu-noble-nvidia \
  --build-arg KASM_VERSION=1.19.0 \
  --build-arg NODE_VERSION=22 \
  --build-arg POETRY_VERSION=1.8.5 \
  --build-arg CODEX_VERSION=latest \
  --build-arg RTK_VERSION=vX.Y.Z \
  --build-arg CHROMIUM_REVISION=1234567 \
  --tag your-dockerhub-user/kasm-noble-ai:1.0.0 \
  .
```

`RTK_VERSION`と`CHROMIUM_REVISION`を空にすると、ビルド時点の最新版を取得します。

Dockerfileの既定値は再現性を優先して固定タグ`1.19.0`です。定期的に公開するイメージでは、セキュリティ更新を取り込むためGitHub Actionsが`1.19.0-rolling-weekly`を使用します。ローカルでも同じ方針にする場合は、`--build-arg KASM_VERSION=1.19.0-rolling-weekly`を指定してください。

CUDA Toolkitをイメージ内に必要としない軽量構成では、公式デスクトップ版へ切り替えられます。

```bash
docker build \
  --build-arg KASM_REPOSITORY=kasmweb/ubuntu-noble-desktop \
  --build-arg KASM_VERSION=1.19.0 \
  --tag your-dockerhub-user/kasm-noble-ai:desktop \
  .
```

この構成でもKasmVNCデスクトップは利用できますが、CUDA Toolkitを必要とする処理には既定の`ubuntu-noble-nvidia`を使用してください。本リポジトリはChromium snapshotの都合により`linux/amd64`を対象とします。

## Docker Composeでの起動

```bash
cp .env.example .env
```

`.env`の`VNC_PW`を必ず変更した後、起動します。

```bash
docker compose up --build -d
```

ブラウザで次を開きます。

```text
https://localhost:6901/
```

ログイン情報は次のとおりです。

```text
User: kasm_user
Password: .envのVNC_PW
```

自己署名証明書の警告が表示されるため、接続先が正しいことを確認して続行してください。

## docker run例

```bash
docker run --rm -it \
  --gpus all \
  --shm-size=1g \
  -p 6901:6901 \
  -e VNC_PW='replace-with-a-long-random-password' \
  -e TZ=Asia/Tokyo \
  -e NVIDIA_DRIVER_CAPABILITIES=all \
  -e GIT_USER_NAME='Your Name' \
  -e GIT_USER_EMAIL='you@example.com' \
  -v kasm-workspace:/workspace \
  your-dockerhub-user/kasm-noble-ai:1.0.0
```

## Vast.ai / RunPod

画面ごとの入力値は[TEMPLATE_SETTINGS.md](TEMPLATE_SETTINGS.md)にまとめています。重要点は次のとおりです。

- KasmのENTRYPOINTを維持する
- Vast.aiでは`Docker ENTRYPOINT`を選択する
- 内部HTTPポートは`6901/tcp`
- `/workspace`へ永続ボリュームをマウントする
- 起動スクリプトは空欄
- `VNC_PW`はインスタンスごとにSecretまたは環境変数で渡す

## 起動後の認証

イメージにはCLI本体だけが含まれます。認証は利用者ごとに行います。

```bash
gh auth login --web
codex
claude
```

GitHubへSSH接続する場合は、コンテナ起動後にSSH鍵を生成し、GitHubへ公開鍵を登録してください。秘密鍵をDockerレイヤーへ保存しないでください。

## 危険権限エイリアス

添付コマンドに合わせて、次のエイリアスを追加しています。

```bash
claude-auto
codex-auto
```

両方とも確認やサンドボックスを弱めるオプションを使用します。信頼できないリポジトリ、外部入力を含む作業、重要な認証情報がある環境では使用しないでください。

本イメージは起動後の追加導入を行いやすくするため、`kasm-user`へパスワードなし`sudo`も付与します。ホスト権限を直接与えるものではありませんが、コンテナ内の管理者権限には相当します。外部公開時は強い`VNC_PW`を設定し、不要なポートを公開しないでください。

## Git設定

公開イメージへ個人情報を焼き込まないため、名前とメールアドレスは起動時環境変数で設定します。

```text
GIT_USER_NAME=Your Name
GIT_USER_EMAIL=you@example.com
```

環境変数を使わない場合は、起動後に通常どおり設定できます。

```bash
git config --global user.name 'Your Name'
git config --global user.email 'you@example.com'
```

## 日本語入力

既定ではIBus/Mozcを起動し、次の切り替えキーを設定します。

- 半角/全角
- Super+Space
- Ctrl+Space

不要な場合は起動環境変数を変更します。

```text
ENABLE_JAPANESE_INPUT=0
```

## 動作確認

コンテナ内のターミナルで次を実行します。

```bash
image-smoke-test
```

主要CLI、Chromium、日本語入力関連コマンド、NVIDIAランタイムの有無を確認します。

## Docker HubへのGitHub Actions公開

`.github/workflows/build-and-push.yml`を含めています。GitHubへこのリポジトリをpushすると、`main`、タグ、毎週の定期実行で次へ公開します。ワークフローではKasmの`1.19.0-rolling-weekly`を利用します。

```text
yukiinaho/kasm-noble-ai:latest
```

リポジトリの GitHub Actions secrets に、Docker Hub で作成した読み書き用アクセストークンを `DOCKERHUB_TOKEN` として登録してください。Docker Hubリポジトリ `yukiinaho/kasm-noble-ai` は Public にします。ベースイメージが大きいため、ワークフローではGitHub Actionsランナーの不要なSDKを削除して空き容量を確保します。それでも容量不足になる場合は、ディスク容量の大きいセルフホストランナーを使用してください。

## Docker Hubへ手動公開

```bash
docker login
docker push your-dockerhub-user/kasm-noble-ai:1.0.0
```

このリポジトリでは次を使用します。

```bash
docker push yukiinaho/kasm-noble-ai:1.0.0
docker push yukiinaho/kasm-noble-ai:latest
```

Vast.aiまたはRunPodのテンプレートには、push済みの完全なイメージ名を指定してください。
