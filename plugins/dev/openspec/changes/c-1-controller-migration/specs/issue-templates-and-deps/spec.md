## ADDED Requirements

### Requirement: Issue テンプレート移植

co-issue が参照する Issue テンプレート（bug.md, feature.md）を refs/ ディレクトリに配置しなければならない（MUST）。テンプレートは旧 plugin のテンプレートをベースに、本プロジェクトの Issue 構造に適合させる（SHALL）。

- `refs/ref-issue-template-bug.md`: バグ報告テンプレート
- `refs/ref-issue-template-feature.md`: 機能要望テンプレート

#### Scenario: bug テンプレートの参照
- **WHEN** co-issue が Phase 3 の issue-structure で bug タイプの Issue を構造化する
- **THEN** refs/ref-issue-template-bug.md の構造に従って Issue body が生成される

#### Scenario: feature テンプレートの参照
- **WHEN** co-issue が Phase 3 の issue-structure で feature タイプの Issue を構造化する
- **THEN** refs/ref-issue-template-feature.md の構造に従って Issue body が生成される

## MODIFIED Requirements

### Requirement: deps.yaml controller 定義の更新

deps.yaml の skills セクションにおける 4 controllers の can_spawn 定義を、実装内容に合わせて更新しなければならない（MUST）。また Issue テンプレートを refs セクションに追加しなければならない（SHALL）。

具体的な更新内容:
- co-autopilot: can_spawn に script を追加（state-read, state-write 等の呼び出し）
- co-issue: can_spawn に atomic を追加（issue-create, issue-structure 等）
- deps.yaml refs セクションに ref-issue-template-bug, ref-issue-template-feature を追加

#### Scenario: loom validate パス
- **WHEN** deps.yaml 更新後に `loom validate` を実行する
- **THEN** バリデーションが PASS し、全コンポーネントの参照が正しく解決される

### Requirement: 内部参照の正確性

4 controllers の SKILL.md 内で参照する全コマンド・スクリプトは deps.yaml に定義済みのコンポーネントでなければならない（MUST）。未定義コンポーネントへの参照は禁止する（SHALL）。

#### Scenario: 未定義参照の検出
- **WHEN** SKILL.md 内で deps.yaml に未定義のコマンドを参照する
- **THEN** loom validate がエラーを報告する
