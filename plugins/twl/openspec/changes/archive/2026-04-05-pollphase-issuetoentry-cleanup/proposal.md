## Why

`poll_phase()` 内の `issue_to_entry` 連想配列は `issue_to_entry["$e"]="$e"` と自己参照マップ（キー=値）になっており、`issue_entry` 変数も常に `entry` と等しい値を返す冗長な変数である。これらを削除することで可読性を向上させる。

## What Changes

- `scripts/autopilot-orchestrator.sh` の `poll_phase()` から `issue_to_entry` 連想配列の宣言・代入・参照を削除
- `issue_entry` 変数を削除し、`cleanup_worker "$issue_num" "$issue_entry"` を `cleanup_worker "$issue_num" "$entry"` に変更

## Capabilities

### New Capabilities

なし。

### Modified Capabilities

- `poll_phase()` 関数: 冗長な変数・配列を除去した簡潔な実装

## Impact

- 影響ファイル: `scripts/autopilot-orchestrator.sh`（`poll_phase()` 関数 L342-L355 付近）
- API 変更なし
- 動作変更なし（同一ロジック）
