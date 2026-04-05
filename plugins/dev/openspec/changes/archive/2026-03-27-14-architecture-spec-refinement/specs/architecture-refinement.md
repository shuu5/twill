## MODIFIED Requirements

### Requirement: Vision 設計哲学境界の詳細化

vision.md に「機械 vs LLM」の判断境界を詳細に記述しなければならない（SHALL）。具体的には、機械に任せる操作（状態管理、バリデーション、シーケンシング）と LLM に任せる判断（レビュー品質、エラー診断、設計判断）の境界を明示する。Constraints に旧 plugin の複雑性ホットスポット回避策を明記し、Non-Goals に「技術スタック固有機能はコンパニオンプラグインの責務」を展開しなければならない（MUST）。

#### Scenario: 機械 vs LLM 境界の確認
- **WHEN** vision.md を読んだとき
- **THEN** 「機械に任せる操作」と「LLM に任せる判断」の具体例が列挙されている

#### Scenario: 旧 plugin 回避策の確認
- **WHEN** vision.md の Constraints セクションを読んだとき
- **THEN** 旧 plugin で問題となった複雑性ホットスポット（9 controller, 6種マーカー, --auto/--auto-merge 分岐等）の回避策が明記されている

### Requirement: Domain Model の Spawning 関係図

model.md に Controller 4つの spawning 関係を Mermaid 図で追加しなければならない（SHALL）。統一状態ファイル（issue-{N}.json, session.json）のスキーマを図に統合し、Chain 定義と実行フローの関係を図示しなければならない（MUST）。

#### Scenario: Controller spawning 関係の確認
- **WHEN** model.md の Mermaid 図を確認したとき
- **THEN** co-autopilot, co-issue, co-project, co-architect の4 controller が spawning できるコンポーネント種別（composite, atomic, specialist, reference）が図示されている

#### Scenario: 状態ファイルスキーマの統合確認
- **WHEN** model.md を読んだとき
- **THEN** issue-{N}.json と session.json のフィールド一覧が図またはテーブルとして含まれている

### Requirement: Glossary 旧→新用語対応表

glossary.md に旧 plugin 用語と新 plugin 用語の対応表を Markdown テーブルとして追加しなければならない（SHALL）。廃止された概念（--auto フラグ, 6種マーカーファイル, direct パス, controller 9種等）を「廃止」セクションとして記載しなければならない（MUST）。

#### Scenario: 旧→新対応表の存在確認
- **WHEN** glossary.md を読んだとき
- **THEN** 旧用語（例: controller-autopilot, .merge-ready マーカー, --auto フラグ）と新用語（例: co-autopilot, issue-{N}.json status, autopilot-first）の対応テーブルが存在する

#### Scenario: 廃止概念の記載確認
- **WHEN** glossary.md の「廃止」セクションを読んだとき
- **THEN** --auto, --auto-merge, 6種マーカーファイル（.done, .fail, .merge-ready 等）, direct パス, 9種 controller が廃止として記載されている

### Requirement: Context Key Entities と Mapping

各 contexts/*.md に Key Entities を具体的に列挙しなければならない（SHALL）。各 Context が担う controller/workflow/command のマッピングテーブルを追加しなければならない（MUST）。loom-integration.md には loom CLI コマンドと plugin コンポーネントの対応表を拡充しなければならない（SHALL）。

#### Scenario: Key Entities の列挙確認
- **WHEN** autopilot.md を読んだとき
- **THEN** Key Entities（issue-{N}.json, session.json, plan.yaml, AutopilotPlan, Phase 等）が具体的なファイル名・型名とともに列挙されている

#### Scenario: Controller/Workflow マッピングの確認
- **WHEN** 任意の contexts/*.md を読んだとき
- **THEN** その Context が担う controller, workflow, atomic command, specialist のマッピングテーブルが存在する

#### Scenario: Loom CLI 対応表の確認
- **WHEN** loom-integration.md を読んだとき
- **THEN** loom CLI コマンド（validate, check, chain, audit 等）と、それを使用する plugin コンポーネントの対応表が存在する

### Requirement: Phase 依存関係と Implementation Status

phases/01.md, 02.md に Issue 間の依存関係を完全記載しなければならない（SHALL）。loom CLI Issue（loom#31, loom#28 等）との依存も含めなければならない（MUST）。Implementation Status 列をテーブルに追加しなければならない（SHALL）。

#### Scenario: 依存関係の完全記載確認
- **WHEN** phases/01.md を読んだとき
- **THEN** 各 Issue の depends_on が具体的な Issue 番号で記載されており、loom リポジトリの Issue との依存も含まれている

#### Scenario: Implementation Status 列の確認
- **WHEN** phases/*.md のテーブルを確認したとき
- **THEN** 各 Issue に Status 列（Not Started / In Progress / Done 等）が存在する
