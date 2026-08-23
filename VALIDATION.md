# 検証状況

生成時に次の静的・部分実行検証を実施しています。

- すべてのシェルスクリプトに対する`bash -n`
- `docker-compose.yml`とGitHub ActionsワークフローのYAML構文解析
- `configure-default-profile.sh`を隔離したテスト用HOMEで2回実行し、設定ブロックが重複しないことを確認
- `runtime-init.sh`を隔離したテスト用HOMEと`/workspace`相当ディレクトリで実行し、Git設定とデスクトップリンクが作成されることを確認
- COLMAP実装、添付skills、個人名・メールアドレス、秘密鍵・トークン形式が成果物へ混入していないことの検索
- Kasmの既存ENTRYPOINTを上書きせず、`CMD ["--wait"]`のみを指定していることの確認

この実行環境にはDocker、Podman、Buildahのいずれのビルドエンジンもないため、実イメージの`docker build`、APTパッケージ解決、外部インストーラーの実行、およびKasmVNCへのブラウザ接続試験は未実施です。GitHub ActionsまたはDockerが利用できる端末で最初のビルドを行い、起動後に次を実行してください。

```bash
image-smoke-test
```
