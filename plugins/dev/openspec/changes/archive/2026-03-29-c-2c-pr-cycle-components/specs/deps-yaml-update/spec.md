## MODIFIED Requirements

### Requirement: deps.yaml に全 18 コンポーネントを登録

6 コンポーネント（ac-deploy-trigger, test-phase, auto-merge, pr-cycle-analysis, schema-update, spec-diagnose）を deps.yaml v3.0 に追加登録しなければならない（MUST）。

#### Scenario: 6 コンポーネントの deps.yaml 登録
- **WHEN** deps.yaml を検査する
- **THEN** 全 18 コンポーネントが commands セクションに定義されている

#### Scenario: 型とパスの正確性
- **WHEN** 各コンポーネントの deps.yaml エントリを検査する
- **THEN** type, path, spawnable_by, description が旧プラグインの設計と整合する

### Requirement: calls 関係の更新

merge-gate と workflow-pr-cycle の calls に不足コンポーネントを追加しなければならない（MUST）。

#### Scenario: merge-gate の calls に auto-merge 追加
- **WHEN** merge-gate の deps.yaml エントリを検査する
- **THEN** calls に `atomic: auto-merge` が含まれている

#### Scenario: workflow-pr-cycle の calls 更新
- **WHEN** workflow-pr-cycle の deps.yaml エントリを検査する
- **THEN** calls に ac-deploy-trigger, ac-verify, pr-cycle-analysis が含まれている

### Requirement: loom validate pass

deps.yaml の変更後に `loom validate` が pass しなければならない（MUST）。

#### Scenario: loom validate の実行
- **WHEN** 全コンポーネントの追加と COMMAND.md 作成が完了した後
- **THEN** `loom validate` が exit code 0 を返す
