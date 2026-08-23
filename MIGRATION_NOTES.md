# 添付スクリプトからの移行対応表

このリポジトリは、添付された`storage_template.zip`のうち、通常起動後に実行していた開発環境セットアップをDockerビルドへ移したものです。

| 元の処理 | 生成物での実装 | 備考 |
|---|---|---|
| `install_apt.sh` | `scripts/install-system-packages.sh` | Ubuntu 24.04向けにパッケージ名を調整しました。 |
| `install_python_env.sh` | `scripts/install-user-tools.sh` | 公式Kasmイメージの`/opt/pyenv`を再利用し、Poetry、uv、Rust、just、pyenv-updateを追加します。 |
| `install_ai_clis.sh` | `scripts/install-user-tools.sh` | Node.js 22、Codex CLI、Claude Codeをビルド時に導入します。 |
| `install_chromium.sh` | `scripts/install-chromium.sh` | Chromium snapshotを`/opt/chromium`へ配置します。 |
| `claude-auto` / `codex-auto` | `scripts/configure-default-profile.sh` | Kasmユーザーの`.bashrc`へ重複なく追加します。 |
| RTKインストール | `scripts/install-user-tools.sh` | `RTK_VERSION`で固定可能です。 |
| GitHub CLI導入 | `scripts/install-system-packages.sh` | GitHub公式APTリポジトリを使用します。 |
| `sudo`利用 | `scripts/install-system-packages.sh` | 開発用の`kasm-user`へパスワードなし`sudo`を付与します。 |
| Gitの名前・メール | `scripts/runtime-init.sh` | `GIT_USER_NAME`、`GIT_USER_EMAIL`を起動時に反映します。公開イメージへ個人情報を固定しません。 |
| 日本語入力設定 | `scripts/configure-default-profile.sh`、`scripts/runtime-init.sh` | IBus/Mozc、自動起動、切替キー、日本語キーボード配列を設定します。 |
| `/workspace`での作業 | `scripts/runtime-init.sh` | 書込権限、デスクトップリンク、自動`cd`を設定します。 |

## 除外したもの

次は意図的にDockerイメージへ含めていません。

- `install_colmap.sh`
- COLMAP向けのBoost、FLANN、CGAL、SuiteSparse等の専用依存一式
- `copy_install_apt.sh`（`install_apt.sh`の旧版・重複）
- `install_glibc.sh`（実際のインストール処理がなく、Ubuntu 24.04のシステムglibcを使用するため）
- `skills/`以下
- `gh auth login --web`
- SSH秘密鍵の生成および`ssh-add`
- GitHubの`known_hosts`固定
- 個人のGitユーザー名・メールアドレスの焼き込み

## Ubuntu 24.04向けの主な変更

- `python3-distutils`は使用しません。
- `libncurses5-dev`と`libncursesw5-dev`は`libncurses-dev`へ整理しました。
- APT版FirefoxはSnap前提のため導入せず、ベースのChromeと追加のChromiumを使用します。
- `apt upgrade`はイメージレイヤー内で行わず、ベースイメージ更新後の再ビルドで更新します。
- Kasm標準の`/home/kasm-default-profile`へユーザー用ツールを導入し、初回起動時に`/home/kasm-user`へ展開される方式に合わせています。
