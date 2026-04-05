## Why

autopilot-launch.md の Step 5 で tmux new-window コマンドを構築する際、AUTOPILOT_ENV と REPO_ENV がダブルクォートなしで展開されており、ISSUE_REPO_OWNER / ISSUE_REPO_NAME / PILOT_AUTOPILOT_DIR に入力バリデーションが存在しない。悪意のある値やスペースを含む値がシェルインジェクションを引き起こす可能性がある。

## What Changes

- ISSUE_REPO_OWNER / ISSUE_REPO_NAME に `^[a-zA-Z0-9_-]+$` パターンのバリデーションを追加（state-read.sh / merge-gate-execute.sh と同等）
- PILOT_AUTOPILOT_DIR にパストラバーサル防止バリデーションを追加
- AUTOPILOT_ENV / REPO_ENV の値を `printf '%q'` でクォートして安全に展開
- WINDOW_NAME に含まれる ISSUE 変数の数値バリデーション確認

## Capabilities

### New Capabilities

- autopilot-launch.md Step 5 のクロスリポジトリ変数に対する入力バリデーション

### Modified Capabilities

- AUTOPILOT_ENV / REPO_ENV の展開方式を printf '%q' クォート方式に変更
- バリデーション失敗時は state-write.sh で status=failed に遷移し、明確なエラーメッセージを出力

## Impact

- 変更対象: `commands/autopilot-launch.md`（Step 4〜5 の間にバリデーションステップ追加、Step 5 のクォート修正）
- 既存動作への影響: 正常な入力値では動作変更なし。不正な入力値でのみ早期エラーになる
- 依存: state-write.sh（エラー時の状態書き込みに使用、変更不要）
