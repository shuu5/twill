## Why

Autopilot Worker は現在 PostToolUse / PostToolUseFailure の 2 hook のみを使用しているが、Claude Code は 24 種の hook イベントを提供している。特にヘッドレス Worker が AskUserQuestion で UI ブロックする問題、compaction 後の進捗消失、permission 拒否時の無限リトライが未対処であり、autopilot の安定性を損なっている。

## What Changes

- hooks/hooks.json に PreToolUse (AskUserQuestion 自動応答) を追加
- hooks/hooks.json に PostCompact (compaction 後チェックポイント保存) を追加
- hooks/hooks.json に PermissionRequest (permission 自動承認) を追加
- commands/autopilot-launch.md の Worker 環境変数に compaction 制御設定を追加
- PostCompact 用 hook スクリプトを scripts/hooks/ に追加

## Capabilities

### New Capabilities

- AskUserQuestion 自動応答: ヘッドレス Worker が AskUserQuestion tool を呼んだ際、PreToolUse hook が自動的に回答を注入し UI ブロックを回避
- PostCompact チェックポイント: compaction 発生後に autopilot 進捗状態を保存し、コンテキスト消失に備える
- PermissionRequest 自動承認: Worker の permission ダイアログを自動承認し、ヘッドレス実行を維持

### Modified Capabilities

- hooks/hooks.json: 既存の PostToolUse / PostToolUseFailure に加え、PreToolUse / PostCompact / PermissionRequest セクションを追加
- commands/autopilot-launch.md: Worker 起動時の環境変数設定を拡張

## Impact

- hooks/hooks.json: 新規 hook エントリ 3 件追加
- scripts/hooks/: 新規スクリプト追加（post-compact-checkpoint.sh）
- scripts/hooks/: 新規スクリプト追加（pre-tool-use-ask-user-question.sh）
- scripts/hooks/: 新規スクリプト追加（permission-request-auto-approve.sh）
- commands/autopilot-launch.md: Step 5 の環境変数ブロック変更
- deps.yaml: 新規 hook スクリプトの登録（必要に応じて）
