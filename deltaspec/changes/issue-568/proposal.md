## Why

deps.yaml の型ルール違反（can_spawn/spawnable_by/v3 schema）は `twl --validate` でしか検出できず、現状はコミット前に自動実行される仕組みがない。コミットを最終ゲートとして `--validate` を走らせることで、不整合な deps.yaml が main ブランチに入ることを防止する。

## What Changes

- `.claude/settings.json` に PreToolUse Bash hook を追加: `git commit` 実行前に `pre-bash-commit-validate.sh` を呼び出す
- 新規スクリプト `plugins/twl/scripts/hooks/pre-bash-commit-validate.sh` を作成: `twl --validate` を実行し、違反ありなら exit 2 でコミットをブロック
- `plugins/twl/deps.yaml` にスクリプトコンポーネントを追加
- `$TOOL_INPUT_command` による `git commit` 検出フォールバック（settings.json の `if` フィールド非サポート対応）
- `TWL_SKIP_COMMIT_GATE=1` 環境変数による無効化パス

## Capabilities

### New Capabilities

- **PreToolUse commit gate**: `git commit` 実行時に `twl --validate` が自動実行され、型ルール違反がある場合はコミットがブロックされる
- **スキップ機構**: `TWL_SKIP_COMMIT_GATE=1` 設定時はゲートをバイパス可能（Issue E 完了前の安全装置）

### Modified Capabilities

- **`.claude/settings.json`**: `hooks.PreToolUse` エントリが追加され、Bash tool 呼び出し時に commit validate hook が起動する

## Impact

- `.claude/settings.json` — `hooks` オブジェクトに `PreToolUse` キー追加
- `plugins/twl/scripts/hooks/pre-bash-commit-validate.sh` — 新規スクリプト (~30 行)
- `plugins/twl/deps.yaml` — `scripts` セクションにエントリ追加
- `twl --validate` コマンド: 既存コマンド、~0.4s の実行時間
