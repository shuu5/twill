## ADDED Requirements

### Requirement: Controller 基本フロー動作確認

各 controller（co-issue, co-project, co-architect）の基本フローが独立セッションで正常に動作しなければならない（SHALL）。spawn/fork を使用して main worktree から独立セッションを起動し、各 controller を試行する。

#### Scenario: co-project 基本フロー検証
- **WHEN** 独立セッションから co-project を起動する
- **THEN** プロジェクト作成フローが正常に開始され、エラーなく完了する

#### Scenario: co-architect 基本フロー検証
- **WHEN** 独立セッションから co-architect を起動する
- **THEN** アーキテクチャ設計フローが正常に開始され、対話的に進行する

#### Scenario: co-issue 基本フロー検証
- **WHEN** 独立セッションから co-issue を起動する
- **THEN** Issue 作成フローが正常に開始され、要望から Issue への変換が行える

### Requirement: workflow-setup chain エンドツーエンド検証

workflow-setup chain が全ステップを正常に完了しなければならない（MUST）。init → worktree-create → project-board-status-update → crg-auto-build → opsx-propose → ac-extract → workflow-test-ready の順序で実行される。

#### Scenario: workflow-setup chain 正常完了
- **WHEN** Issue 番号を指定して workflow-setup を実行する
- **THEN** 全ステップが順に実行され、workflow-test-ready への遷移案内が表示される

#### Scenario: workflow-setup chain エラーハンドリング
- **WHEN** 依存 Issue が存在しない番号で workflow-setup を実行する
- **THEN** 適切なエラーメッセージが表示され、chain が安全に停止する

### Requirement: session-audit 品質基準

session-audit 実行時に confidence >= 70 の findings が 0 件でなければならない（SHALL）。これにより、プラグインの実動作品質が基準を満たしていることを確認する。

#### Scenario: session-audit PASS 条件
- **WHEN** 全 controller 検証完了後に session-audit を実行する
- **THEN** confidence >= 70 の findings が 0 件である

#### Scenario: session-audit findings 検出時
- **WHEN** session-audit で confidence >= 70 の findings が検出される
- **THEN** findings を Issue #44 コメントに記録し、対応 Issue を特定する

### Requirement: 検証結果レポート記録

全検証完了後、結果レポートを Issue #44 コメントに Markdown 形式で記録しなければならない（MUST）。各 controller ごとの結果セクション、workflow-setup chain の結果、session-audit の結果を含む。

#### Scenario: レポート記録
- **WHEN** 全検証タスクが完了する
- **THEN** Issue #44 コメントに構造化されたレポートが投稿される

#### Scenario: レポート内容の網羅性
- **WHEN** レポートを確認する
- **THEN** co-issue, co-project, co-architect, workflow-setup, session-audit の各結果が含まれている
