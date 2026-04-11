## ADDED Requirements

### Requirement: ADR-016 ドキュメント作成
test-target の `--real-issues` モードに関する設計決定を ADR-016 として記録しなければならない（SHALL）。ADR は `plugins/twl/architecture/decisions/ADR-016-test-target-real-issues.md` に配置されなければならない（MUST）。

#### Scenario: ADR-016 ファイル作成
- **WHEN** issue #444 の受け入れ基準を満たす変更が加えられる
- **THEN** `plugins/twl/architecture/decisions/ADR-016-test-target-real-issues.md` が存在し、以下を含む: タイトル・Status・Context・3選択肢比較表・Decision・Consequences

### Requirement: 3選択肢比較表の記載
ADR-016 は専用リポ・実リポ test ラベル・mock GitHub API の 3 選択肢を比較する表を含まなければならない（MUST）。比較軸として隔離性・GitHub API 依存度・クリーンアップ複雑度を含まなければならない（SHALL）。

#### Scenario: 比較表の内容検証
- **WHEN** ADR-016 を読む
- **THEN** 3 戦略それぞれの隔離性・GitHub API 依存・クリーンアップ複雑度の評価と選定根拠が明記されている

### Requirement: co-self-improve 統合フロー図
ADR-016 は co-self-improve scenario-run モードと `--real-issues` モードの統合フローを含まなければならない（MUST）。フローは Step 1 への分岐追加として記述されなければならない（SHALL）。

#### Scenario: 統合フロー記載
- **WHEN** ADR-016 を読む
- **THEN** `--real-issues` 時のフロー（リポ作成→Issue起票→autopilot→observe→cleanup）が記載されている

### Requirement: クリーンアップ設計の記載
ADR-016 はテスト後の GitHub リソース（Issue/PR/branch）クリーンアップ設計を含まなければならない（MUST）。クリーンアップはテスト成功・失敗問わず実行されなければならない（SHALL）。

#### Scenario: クリーンアップ設計の記載
- **WHEN** ADR-016 を読む
- **THEN** PR クローズ・Issue クローズ・branch 削除の後処理フローが記載されている

### Requirement: リポジトリ管理の責務決定
ADR-016 はリポジトリ作成・管理の責務帰属（test-project-init 拡張 or 新規コマンド）を明記しなければならない（MUST）。

#### Scenario: 責務決定の記載
- **WHEN** ADR-016 を読む
- **THEN** `test-project-init --mode real-issues` 拡張として決定されたことと、その根拠が記載されている
