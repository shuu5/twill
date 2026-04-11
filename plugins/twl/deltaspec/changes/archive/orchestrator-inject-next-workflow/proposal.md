## Why

ADR-014 の Pilot 駆動ループでは、Worker が workflow 完了時に `workflow_done` を state に書き込み、Orchestrator がこれを検知して次の workflow skill を tmux inject する必要がある。現状の Orchestrator は `workflow_done` を検知せず、次の workflow への遷移が自動化されていない。

## What Changes

- `plugins/twl/scripts/autopilot-orchestrator.sh` の `status=running` ブランチ内で `workflow_done` フィールドを読み取る処理を追加
- `inject_next_workflow()` 関数を新たに追加:
  - `resolve_next_workflow` CLI で次の workflow skill を決定
  - `tmux capture-pane` で入力待ち確認（最大3回、2秒間隔）
  - プロンプト検出後 `tmux send-keys` で inject
  - `workflow_done` をクリア（`state write --role pilot --set "workflow_done=null"`）
- inject 後に `workflow_injected`, `injected_at` を state に記録
- terminal workflow (`pr-merge`) の場合は inject せず既存 merge-gate フローに委譲
- inject 失敗時（3回リトライ後も未検出）は WARNING ログ + 10秒後再チェック
- inject 成功時に該当 Issue の `NUDGE_COUNTS` をリセット
- inject イベントを `[orchestrator]` プレフィックス形式でログ出力

## Capabilities

### New Capabilities

- **inject_next_workflow()**: Orchestrator が `workflow_done` を検知して次の workflow skill を tmux inject する中核関数
- **inject 安全機構**: tmux pane の入力待ち状態確認（最大3回リトライ）でリスクを低減
- **inject 履歴記録**: `workflow_injected`, `injected_at` フィールドでトレーサビリティを確保

### Modified Capabilities

- **polling ループの `status=running` ブランチ**: `workflow_done` フィールドを追加読み取りし、inject または merge-gate フローへ分岐

## Impact

- 影響ファイル: `plugins/twl/scripts/autopilot-orchestrator.sh`（単一ファイル変更）
- 依存: #335（`workflow_done` フィールド定義）、#337（`resolve_next_workflow` CLI）
- `check_and_nudge()` との共存: `workflow_done` があれば inject 優先 → `check_and_nudge` はスキップ（#345 で境界 nudge が削除されるまでの暫定動作）
