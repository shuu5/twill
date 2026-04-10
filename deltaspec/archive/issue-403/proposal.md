## Why

pr-verify chain に定義されている `phase-review`（Step 2）と `scope-judge`（Step 2.5）が chain 実行フレームワーク（chain-steps.sh、chain.py、chain-runner.sh）に未登録のため、specialist レビュー（code-reviewer、security-reviewer、issue-pr-alignment 等）が一度も実行されない。47件+16件の実績で phase-review checkpoint が正常記録されたことがなく、全 specialist レビューがスキップされた状態で PR がマージされ続けている。

## What Changes

- `plugins/twl/scripts/chain-steps.sh`: CHAIN_STEPS 配列に `phase-review` と `scope-judge` を pr-verify chain の正しい順序位置に追加
- `cli/twl/src/twl/autopilot/chain.py`: STEP_TO_WORKFLOW マッピングに `phase-review` → `pr-verify`、`scope-judge` → `pr-verify` を追加
- `plugins/twl/scripts/chain-runner.sh`: case 文に `phase-review` と `scope-judge` のハンドラを追加（既存の llm dispatch パターンに準拠）
- `cli/twl/tests/`: chain trace に phase-review の start/end イベントが記録されることを確認する自動テストを追加

## Capabilities

### New Capabilities

- pr-verify chain 実行時に `phase-review` ステップが正しく呼び出され、specialist 並列 spawn が実行される
- pr-verify chain 実行時に `scope-judge` ステップが正しく呼び出され、スコープ判定が実行される
- chain trace JSONL に phase-review/scope-judge の start/end イベントが記録される

### Modified Capabilities

- pr-verify chain のステップ遷移順序: prompt-compliance → ts-preflight → **phase-review** → **scope-judge** → pr-test → ac-verify

## Impact

- `plugins/twl/scripts/chain-steps.sh`: CHAIN_STEPS 配列の定義行
- `cli/twl/src/twl/autopilot/chain.py`: STEP_TO_WORKFLOW 辞書
- `plugins/twl/scripts/chain-runner.sh`: case "$step" ブロック
- `cli/twl/tests/`: chain trace 記録の自動テスト（新規追加または既存テスト拡張）
