## ADDED Requirements

### Requirement: deps.yaml v3.0 skeleton

deps.yaml v3.0 を作成し、controller 4つ（co-autopilot, co-issue, co-project, co-architect）のエントリを含めなければならない（MUST）。

deps.yaml は ref-deps-format 形式に準拠し、以下を満たさなければならない（SHALL）:
- `version: "3.0"` を宣言する
- `plugin: dev` を宣言する
- `entry_points` に4つの controller パスを列挙する
- 各 controller に `type: controller`, `path`, `spawnable_by`, `description` を定義する

#### Scenario: deps.yaml の基本構造が正しい
- **WHEN** deps.yaml をパースする
- **THEN** `version` が "3.0"、`plugin` が "dev"、`entry_points` が4件存在する

#### Scenario: controller 4つが定義されている
- **WHEN** deps.yaml の `skills` セクションを検査する
- **THEN** `co-autopilot`, `co-issue`, `co-project`, `co-architect` の4エントリが存在し、全て `type: controller` である

### Requirement: co-* 命名規則の適用

全 controller は `co-{purpose}` 形式の命名でなければならない（MUST）。旧 `controller-{name}` 形式は使用してはならない（SHALL）。

#### Scenario: co-* 命名規則の遵守
- **WHEN** deps.yaml の controller エントリ名を検査する
- **THEN** 全てが `co-` プレフィックスで始まっている

#### Scenario: 旧命名の不在
- **WHEN** deps.yaml 全体を `controller-` で検索する
- **THEN** `controller-` プレフィックスのコンポーネント名が存在しない

### Requirement: loom check の通過

deps.yaml が `loom check` コマンドで pass しなければならない（MUST）。

#### Scenario: loom check が pass する
- **WHEN** `main/` ディレクトリで `loom check` を実行する
- **THEN** exit code が 0 で、エラーが報告されない

### Requirement: loom validate の通過

deps.yaml と SKILL.md の組み合わせが `loom validate` コマンドで新規 violation 0 件でなければならない（SHALL）。

#### Scenario: loom validate が新規 violation なしで完了する
- **WHEN** `main/` ディレクトリで `loom validate` を実行する
- **THEN** 新規 violation が 0 件である
