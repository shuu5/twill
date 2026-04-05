## Why

静的検証（loom check/validate/deep-validate）は PASS しているが、各スキル・コマンド・チェーンが実際に正しく動作するかは未検証。spawn/fork/fork-cd + tmux を活用した独立セッションからの監査により、プラグインの実動作品質を確認する必要がある。

## What Changes

- co-issue, co-project, co-architect の基本フローを独立セッションで動作確認
- workflow-setup chain の実行確認（正常完了の検証）
- session-audit による実行品質の分析（confidence >= 70 の findings が 0 件であること）
- 検証結果レポートを Issue コメントに記録

## Capabilities

### New Capabilities

- 独立セッション（spawn/fork）からの controller ワークフロー動作検証
- workflow-setup chain のエンドツーエンド実行検証
- session-audit を用いた実行品質分析

### Modified Capabilities

- なし（既存コンポーネントの変更は含まない）

## Impact

- **対象**: co-issue, co-project, co-architect controller、workflow-setup chain
- **依存**: #43（テストスイート全 PASS が前提）、#45（co-issue バグ修正、先行推奨）
- **成果物**: 検証レポート（Issue #44 コメント）
- **コード変更**: なし（監査・検証タスクのため）
