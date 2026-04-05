## Why

Worker LLM が workflow chain 間の遷移（setup → test-ready → pr-cycle）で停止する。各 SKILL.md の最終ステップに明示的な autopilot 判定と次 workflow 呼び出し指示がないため、LLM が次の chain に進めない。

## What Changes

- `skills/workflow-setup/SKILL.md` の Step 4 に autopilot 判定 bash スニペットを追加し、`/twl:workflow-test-ready` 呼び出し指示を明示化
- `skills/workflow-test-ready/SKILL.md` の Step 4 に opsx-apply 実行後の autopilot 判定と `/twl:workflow-pr-cycle` 呼び出し指示を追加
- `commands/opsx-apply.md` の Step 3 から IS_AUTOPILOT 判定 + pr-cycle 呼び出しロジックを削除（遷移責務を SKILL.md 側に一元化）
- `commands/check.md` の無条件 `/twl:opsx-apply` 呼び出し指示を条件付きに修正（CRITICAL FAIL 時スキップ制御との競合解消）

## Capabilities

### New Capabilities

- workflow-setup → workflow-test-ready の自動遷移（autopilot セッション時）
- workflow-test-ready → workflow-pr-cycle の自動遷移（autopilot セッション時）

### Modified Capabilities

- workflow-setup Step 4: autopilot 判定ロジックを SKILL.md 側で明示的に保持
- workflow-test-ready Step 4: pr-cycle 遷移の責務を opsx-apply から移管
- opsx-apply: 実装フローに集中（遷移ロジック削除）
- check.md: CRITICAL FAIL 時に opsx-apply をスキップする条件分岐を追加

## Impact

- `skills/workflow-setup/SKILL.md`
- `skills/workflow-test-ready/SKILL.md`
- `commands/opsx-apply.md`
- `commands/check.md`
- autopilot セッションの chain 間遷移動作
