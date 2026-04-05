## Why

#41 で deps.yaml calls 完全化を実施したが、一部の script 呼び出しが calls に未宣言のまま残存している。`loom orphans` で 29 Isolated + 2 Unused が検出され、SVG グラフにエッジが欠落している状態。依存グラフの正確性が損なわれ、dead code 判定やリファクタリング計画に支障が出る。

## What Changes

- co-autopilot → autopilot-plan の calls 宣言追加
- merge-gate → merge-gate-execute, merge-gate-init, merge-gate-issues の calls 宣言追加
- fix-phase → classify-failure, codex-review, create-harness-issue の実コード確認と必要に応じた calls 追加
- 13 commands の意図的孤立を deps.yaml で明示（`intentional_orphan: true`）
- dead code candidates（switchover, branch-create, check-db-migration）の判定と削除/残置
- SVG 再生成でエッジ欠落を解消

## Capabilities

### New Capabilities

- deps.yaml での意図的孤立の明示（`intentional_orphan: true` フィールド）

### Modified Capabilities

- co-autopilot: autopilot-plan への calls 宣言が追加され、依存グラフに反映
- merge-gate: merge-gate-execute/init/issues への calls 宣言が追加され、依存グラフに反映
- loom orphans: Isolated が意図的孤立のみに削減（29 → 推定13以下）

## Impact

- **deps.yaml**: calls セクションの追加・修正（co-autopilot, merge-gate, 必要に応じて fix-phase）
- **deps.yaml**: intentional_orphan フィールドの追加（13 commands + 該当 agents/scripts）
- **SVG/DOT**: 依存グラフの再生成（新しいエッジが描画される）
- **scripts/**: dead code 判定結果に応じて削除の可能性（switchover, branch-create, check-db-migration）
