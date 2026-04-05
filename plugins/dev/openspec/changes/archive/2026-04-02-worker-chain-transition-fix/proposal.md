## Why

autopilot Worker が workflow-setup → test-ready → pr-cycle の各 chain ステップ間で停止し、Pilot からの手動 nudge（tmux send-keys）がなければ次のステップに遷移しない。3/3 件で再現（2026-04-02 セッション 2666c5b9）。

根本原因は `workflow-test-ready/SKILL.md` に「chain 実行指示（MUST）」セクションが欠落していること。feedback 記憶「SKILL.md の chain 指示は全ステップ明示列挙必須」に違反している。workflow-setup と workflow-pr-cycle には同セクションが存在するが、test-ready のみ欠落。

## What Changes

- `workflow-test-ready/SKILL.md` に「chain 実行指示（MUST）」セクションを追加し、Step 1〜4 を `### Step N: name` 形式で明示列挙
- `check.md` にチェックポイント（MUST）セクションを追加し、PASS/FAIL 後の遷移を明確化
- `opsx-apply.md` のフロー制御を Step 形式に統一し、autopilot 判定ロジックを明確化

## Capabilities

### New Capabilities

- なし（既存機能の信頼性修正）

### Modified Capabilities

- **workflow-test-ready chain 遷移**: 曖昧な遷移指示を `### Step N: name` 形式の明示列挙に変更。Claude が各ステップ間で停止せず自動遷移する
- **check → opsx-apply 遷移**: check の PASS/FAIL 判定結果に基づく明確な遷移ルールを追加
- **opsx-apply → pr-cycle 遷移**: autopilot 判定ロジックを Step 形式で明確化

## Impact

- **変更対象ファイル**:
  - `skills/workflow-test-ready/SKILL.md` — chain 実行指示セクション追加
  - `commands/check.md` — チェックポイントセクション追加
  - `commands/opsx-apply.md` — フロー制御の Step 形式統一
- **影響範囲**: dev プラグインの workflow chain（autopilot 実行時のみ影響）
- **リスク**: 低。SKILL.md のドキュメント修正のみで、スクリプトやロジック変更なし
