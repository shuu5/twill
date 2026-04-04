## ADDED Requirements

### Requirement: split 承認時の is_split_generated フラグ設定

Phase 3c Step 5 で split 提案がユーザーに承認された際、分割後に生成される各 Issue candidate に対して `is_split_generated: true` をコンテキストフラグとして設定しなければならない（SHALL）。このフラグは LLM コンテキスト内で管理し、Phase 4 まで保持される。

#### Scenario: split 承認後のフラグ設定

- **WHEN** Phase 3c Step 5 でユーザーが split 提案を承認し、新 Issue candidates が生成された
- **THEN** 生成された全 Issue candidate に `is_split_generated: true` が設定されていなければならない（SHALL）

#### Scenario: クロスリポ split は対象外

- **WHEN** `cross_repo_split = true` による子 Issue が生成された
- **THEN** 子 Issue には `is_split_generated` フラグを設定してはならない（SHALL NOT）

## MODIFIED Requirements

### Requirement: Phase 4 の refined ラベル付与条件に is_split_generated チェックを追加

Phase 4 での `refined` ラベル付与判定において、`REFINED_LABEL_OK=true` に加え `is_split_generated != true` の条件を満たす場合のみ `--label refined` を付与しなければならない（SHALL）。3つの作成経路（単一/複数/クロスリポ）すべてに適用する。

#### Scenario: 通常フロー（split なし）の refined 付与維持

- **WHEN** `--quick` 未使用かつ `REFINED_LABEL_OK=true` かつ `is_split_generated` が設定されていない Issue を作成する
- **THEN** `--label refined` が付与されなければならない（SHALL）

#### Scenario: split 生成 Issue への refined 非付与

- **WHEN** `is_split_generated: true` な Issue candidate を Phase 4 で作成する
- **THEN** `--label refined` は付与されてはならない（SHALL NOT）

#### Scenario: split 生成 Issue の recommended_labels 引き継ぎ

- **WHEN** `is_split_generated: true` な Issue candidate を Phase 4 で作成する
- **THEN** 親 Issue の `recommended_labels`（ctx/* 等）は `--label` 引数に含まれなければならない（SHALL）

### Requirement: openspec/changes/co-issue-refined-label/design.md の Decisions 更新

`openspec/changes/co-issue-refined-label/design.md` の「付与タイミング」Decisions セクションを実際の実装パターン（`REFINED_LABEL_OK` フラグ + 各経路個別対応）に合わせて更新しなければならない（SHALL）。「recommended_labels に refined を追加して既存のラベル付与ロジックに乗せる」という記述は削除されなければならない（SHALL）。

#### Scenario: design.md が実装を正確に反映

- **WHEN** `openspec/changes/co-issue-refined-label/design.md` を参照する
- **THEN** `REFINED_LABEL_OK` フラグの挙動と各作成経路での個別対応が正確に記述されていなければならない（SHALL）
