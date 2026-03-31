## Why

単一リポジトリ（bare repo）で co-autopilot を実行すると、Worker プロセスに `AUTOPILOT_DIR` 環境変数が伝搬されず、Worker が `IS_AUTOPILOT=false` と誤判定する。これにより Worker の state-read.sh が正しい `.autopilot/` ディレクトリを参照できず、autopilot 制御が破綻する。

## What Changes

- `commands/autopilot-launch.md` Step 5: `AUTOPILOT_ENV` を単一リポジトリでも常に設定するよう修正。`PILOT_AUTOPILOT_DIR` が空の場合は `$PROJECT_DIR/.autopilot` をデフォルト使用
- `commands/autopilot-phase-execute.md` の `resolve_issue_repo_context()`: 単一リポジトリ時に `AUTOPILOT_DIR` を明示的な絶対パスで設定（LLM コンテキスト依存を排除）

## Capabilities

### New Capabilities

- なし（既存機能のバグ修正）

### Modified Capabilities

- 単一リポジトリ時の autopilot Worker 環境変数注入: `AUTOPILOT_DIR` が常に Worker の tmux 環境に設定される
- `resolve_issue_repo_context()` の単一リポジトリ分岐: `PILOT_AUTOPILOT_DIR` を `${PROJECT_DIR}/.autopilot` として明示設定（`$AUTOPILOT_DIR` の LLM コンテキスト依存を排除）

## Impact

- **直接影響**: `commands/autopilot-launch.md`、`commands/autopilot-phase-execute.md`
- **間接影響**: Worker 側の `state-read.sh` 呼び出しが正しい `.autopilot/` を参照するようになる
- **リスク**: クロスリポジトリ時の既存動作に影響しないことの確認が必要
