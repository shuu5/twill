## MODIFIED Requirements

### Requirement: Supervisor カテゴリ定義

vision.md の Controller 操作カテゴリ表は Supervisor カテゴリを持たなければならない（SHALL）。
Meta-cognitive カテゴリは Supervisor カテゴリに置き換えられなければならない（MUST）。

#### Scenario: Supervisor カテゴリが表に存在する
- **WHEN** `plugins/twl/architecture/vision.md` の Controller 操作カテゴリ表を参照したとき
- **THEN** `Supervisor` 行が存在し、`su-observer` が該当コンポーネントとして記載されている

#### Scenario: Meta-cognitive 行が存在しない
- **WHEN** `plugins/twl/architecture/vision.md` の Controller 操作カテゴリ表を参照したとき
- **THEN** `Meta-cognitive` 行が存在しない

### Requirement: co-observer 表記の除去

Constraints セクションの controller 一覧から `co-observer` を除去しなければならない（MUST）。
controller 数の記述は実際の controller 数と一致しなければならない（SHALL）。

#### Scenario: controller 一覧に co-observer が含まれない
- **WHEN** `plugins/twl/architecture/vision.md` の Constraints セクションを参照したとき
- **THEN** controller 一覧に `co-observer` が含まれず、su-observer は Supervisor 型として別途記載されている

#### Scenario: controller 数の整合性
- **WHEN** `plugins/twl/architecture/vision.md` の Constraints セクションを参照したとき
- **THEN** controller 数の記述（例: 「Controller は6つ」）が実際の controller 数（co-observer を除いた数）と一致している

### Requirement: su-observer の型的位置づけ明示

su-observer は Supervisor 型であることが vision.md に明示されなければならない（SHALL）。

#### Scenario: su-observer が Supervisor カテゴリに分類される
- **WHEN** Controller 操作カテゴリ表の Supervisor カテゴリを参照したとき
- **THEN** su-observer が該当コンポーネントとして記載されている

#### Scenario: su-observer が controller 一覧に含まれない
- **WHEN** Constraints セクションの controller 一覧を参照したとき
- **THEN** su-observer は controller 一覧には含まれず、Supervisor カテゴリで管理されている
