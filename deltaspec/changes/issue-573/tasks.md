## 1. cld-spawn --env-file オプション追加

- [ ] 1.1 `cld-spawn` の引数パース部分に `--env-file PATH` オプションを追加（`ENV_FILE` 変数に格納）
- [ ] 1.2 `--env-file` のチルダ展開処理を追加（`ENV_FILE="${ENV_FILE/#\~/$HOME}"`）
- [ ] 1.3 `CLD_ENV_FILE` 環境変数のフォールバック処理を追加（`ENV_FILE="${ENV_FILE:-${CLD_ENV_FILE:-}}"`)
- [ ] 1.4 LAUNCHER 生成部分を修正し、`ENV_FILE` が指定されている場合に `source <env-file> 2>/dev/null || true` 行を挿入

## 2. issue-lifecycle-orchestrator.sh の修正

- [ ] 2.1 `issue-lifecycle-orchestrator.sh` の cld-spawn 呼び出し箇所を特定
- [ ] 2.2 cld-spawn 呼び出しに `--env-file ~/.secrets` を追加

## 3. テスト・検証

- [ ] 3.1 `--env-file ~/.secrets` を指定して起動した Worker セッションで環境変数が利用可能なことを確認
- [ ] 3.2 `CLD_ENV_FILE` 環境変数のみ設定した場合も同様に動作することを確認
- [ ] 3.3 env file 不在時にエラーにならないことを確認
- [ ] 3.4 `--env-file` / `CLD_ENV_FILE` 未指定時に既存動作が変わらないことを確認
