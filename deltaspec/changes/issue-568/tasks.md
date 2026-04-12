## 1. スクリプト実装

- [x] 1.1 `plugins/twl/scripts/hooks/pre-bash-commit-validate.sh` を新規作成
- [x] 1.2 スクリプトに `$TOOL_INPUT_command` による `git commit` 検出ロジックを実装
- [x] 1.3 `TWL_SKIP_COMMIT_GATE=1` バイパスロジックを実装
- [x] 1.4 `cd plugins/twl` 後に `deps.yaml` 存在チェックを実装
- [x] 1.5 `twl --validate` 実行と exit code 制御（violations > 0 → exit 2、0 → exit 0）を実装

## 2. settings.json 更新

- [x] 2.1 `.claude/settings.json` の `hooks` オブジェクトに `PreToolUse` キーを追加
- [x] 2.2 matcher: Bash、command: `bash plugins/twl/scripts/hooks/pre-bash-commit-validate.sh`、timeout: 5000 のエントリを設定

## 3. deps.yaml 更新

- [x] 3.1 `plugins/twl/deps.yaml` の `scripts` セクションに `pre-bash-commit-validate` エントリを追加（path: `hooks/pre-bash-commit-validate.sh`、description 付き）
- [x] 3.2 `twl --check` で deps.yaml の整合性を確認

## 4. 動作確認

- [x] 4.1 deps.yaml に型ルール違反がある状態で `git commit` が exit 2 でブロックされることを確認
- [x] 4.2 deps.yaml に違反がない状態で `git commit` が通過することを確認
- [x] 4.3 `TWL_SKIP_COMMIT_GATE=1` 設定時にバイパスされることを確認
- [x] 4.4 `git status` などの `git commit` 以外のコマンドがスキップされることを確認
