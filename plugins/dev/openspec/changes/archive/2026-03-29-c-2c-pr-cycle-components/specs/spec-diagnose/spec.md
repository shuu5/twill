## ADDED Requirements

### Requirement: テスト失敗の原因診断

テスト失敗を分析し、仕様誤り（Scenario 修正が必要）か実装誤り（コード修正が必要）かを判定しなければならない（SHALL）。

test-mapping.yaml を介して失敗テストを Scenario に紐付け、エラータイプを分類する。

#### Scenario: 仕様誤りの検出
- **WHEN** 同一 Scenario に紐づく複数テストが失敗し、AssertionError で期待値が一貫して異なる
- **THEN** `diagnosis: spec_error` を返し、Scenario 修正を推奨する

#### Scenario: 実装誤りの検出
- **WHEN** TypeError, ReferenceError, SyntaxError が発生している
- **THEN** `diagnosis: impl_error` を返し、コード修正を推奨する

#### Scenario: LLM 品質問題の検出
- **WHEN** コード自体のテストは全て PASS だが llm-eval-runner 結果に FAIL が含まれる
- **THEN** `diagnosis: llm_quality_issue` を返し、プロンプトチューニングを推奨する

#### Scenario: 判定不能
- **WHEN** 信頼度が 50 未満で仕様誤り・実装誤りどちらとも判断できない
- **THEN** `diagnosis: unknown` を返す

### Requirement: 診断専用（修正禁止）

診断結果の報告のみを行い、コードやスペックの修正を行ってはならない（MUST NOT）。

#### Scenario: 診断のみで終了
- **WHEN** 診断が完了する
- **THEN** JSON 形式の診断結果を出力し、ファイル修正は行わない

### Requirement: PR-cycle 連携

fix-phase から条件付きで呼び出された場合、診断結果に応じて自動修正の続行・中止を判断可能な情報を返さなければならない（SHALL）。

#### Scenario: spec_error 時の修正中止情報
- **WHEN** 診断結果が spec_error で fix-phase から呼び出されている
- **THEN** `recommended_action: 【人間確認】Scenario修正が必要です` を含める
