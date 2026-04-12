## Why

co-autopilot の Pilot が PHASE_COMPLETE 待機中に Worker の stall を検知できず、最大 120 分間 idle 化する。`grep PHASE_COMPLETE` ループのみで状態確認を行うため、Worker が `workflow_done` 未更新のまま停止しても Pilot が気づかない（Wave 3/5 で実観測）。

## What Changes

- `plugins/twl/skills/co-autopilot/SKILL.md`: PHASE_COMPLETE polling ループを能動的な state file 監視に置き換え
- `plugins/twl/scripts/autopilot-orchestrator.sh`: Worker stall 判定ロジック（`updated_at` stagnate 検知）を追加
- `cli/twl/src/twl/autopilot/orchestrator.py`: Phase 完了判定に Worker stall チェックを組み込む

## Capabilities

### New Capabilities

- **State file stagnate 検知**: Worker の `updated_at` が一定間隔（例: 10 分）以上更新されない場合を stall とみなす
- **能動的 Phase 状態確認ループ**: Pilot が 3-5 分間隔で state file と Worker window を自律的に確認
- **Stall 時の状況精査モード**: PHASE_COMPLETE timeout 後に自動再実行せず、Worker 状態を診断して適切なアクションを決定

### Modified Capabilities

- **PHASE_COMPLETE polling**: `grep` ループから state-driven polling に変更し、MAX_POLL を現実的な上限（例: 30 分）に短縮
- **orchestrator nudge**: hash 差分依存から `updated_at` 差分ベースの判定に切り替え

## Impact

- **対象ファイル**:
  - `plugins/twl/skills/co-autopilot/SKILL.md`
  - `plugins/twl/scripts/autopilot-orchestrator.sh`
  - `cli/twl/src/twl/autopilot/orchestrator.py`
- **依存関係**: Issue #469（Worker 側 non_terminal_chain_end）との組み合わせで完全停止 → 本 fix で Pilot 側の受け皿を整備
- **後方互換性**: polling パラメータ変更のみで既存の API・state schema への破壊的変更なし
