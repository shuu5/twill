## Why

`session-state.sh` の `detect_state()` 関数が、Claude Code の LLM 実行中（`"esc to interrupt"` 表示時）に `input-waiting` を誤返却する。根本原因は `"bypass permissions"` と `"esc to interrupt"` を OR 条件で同一扱いしており、`"esc to interrupt"` が processing の証拠であるにもかかわらず `input-waiting` に分類される点にある。

## What Changes

- `plugins/session/scripts/session-state.sh` L158-166: OR 条件を 2 つの独立分岐に分離
  - `"bypass permissions"` のみ → `input-waiting`（権限承認プロンプト）
  - `"esc to interrupt"` のみ → `processing`（LLM 実行中）
  - 両方表示時 → `input-waiting`（bypass 優先）
  - processing indicator 否定チェック（L162）を削除
- `plugins/session/tests/session-state-input-waiting.bats`: テスト 4 件追加（計 16 件）

## Capabilities

### New Capabilities

なし

### Modified Capabilities

- **`detect_state()`**: `"esc to interrupt"` 単独表示時に `processing` を返すよう修正。`"bypass permissions"` 優先ロジックで同時表示ケースにも対応

## Impact

- `plugins/session/scripts/session-state.sh`: L158-166 のみ変更
- `plugins/session/tests/session-state-input-waiting.bats`: テスト 4 件追加
- `session-comm.sh`, `cld-spawn`, `cld-observe` 等の他 session scripts: 変更なし（`session-state.sh` のインターフェース文字列は不変、`processing` 返却増加はバグ修正の期待効果）
