## Context

loom-plugin-dev は静的検証（loom check/validate/deep-validate）を備えているが、各 controller（co-issue, co-project, co-architect）と workflow-setup chain の実動作は未検証。spawn/fork/fork-cd で独立セッションを起動し、実際のワークフローを試行して品質を確認する。

依存: #43（テストスイート全 PASS）が前提、#45（co-issue バグ修正）が先行推奨。

## Goals / Non-Goals

**Goals:**

- co-issue, co-project, co-architect の基本フローが独立セッションで正常動作することを確認
- workflow-setup chain がエンドツーエンドで正常完了することを確認
- session-audit で confidence >= 70 の findings が 0 件であることを確認
- 検証結果を Issue #44 コメントにレポートとして記録

**Non-Goals:**

- 監査フレームワークの自動化・コード化
- 新規スキル・コマンドの追加
- 既存コンポーネントのコード変更

## Decisions

1. **検証方法**: spawn/fork で独立 tmux セッションを起動し、各 controller を手動試行する。自動化スクリプトは作成しない（Non-Goal）
2. **検証順序**: workflow-setup chain → co-project → co-architect → co-issue の順。workflow-setup は他の controller の前提となるため最初に検証
3. **品質基準**: session-audit の confidence >= 70 findings が 0 件を PASS 条件とする
4. **レポート形式**: Issue #44 コメントに Markdown 形式で記録。各 controller ごとに結果セクションを設ける

## Risks / Trade-offs

- **手動検証の再現性**: 自動化しないため、検証手順の再現性は低い。ただし、本 Issue のスコープでは一度きりの検証で十分
- **#45 未完了時の co-issue 検証**: co-issue にバグがある場合、検証が失敗する可能性がある。その場合は findings として記録し、#45 で対応
- **セッション環境差異**: 独立セッションは main worktree から起動するため、worktree 内の変更は反映されない。検証対象は main にマージ済みのコードに限定
