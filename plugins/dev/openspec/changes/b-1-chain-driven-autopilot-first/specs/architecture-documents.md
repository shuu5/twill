## ADDED Requirements

### Requirement: コンポーネントマッピング表

旧 dev plugin (claude-plugin-dev) の全コンポーネントと新 loom-plugin-dev の対応関係を `architecture/migration/component-mapping.md` に記載しなければならない（SHALL）。

マッピングは以下のカテゴリで分類する:
- **吸収**: 新コンポーネントに統合（名称変更含む）
- **削除**: 新アーキテクチャで不要
- **移植**: ロジック維持でインターフェース適応
- **新規**: 旧にない新コンポーネント

対象コンポーネント種別: controller, workflow, atomic, specialist, script, reference（MUST）。

#### Scenario: 全コンポーネント種別をカバー
- **WHEN** `architecture/migration/component-mapping.md` を確認する
- **THEN** controller, workflow, atomic, specialist, script, reference の全種別について旧→新マッピングが記載されている

#### Scenario: 吸収先が明確
- **WHEN** マッピング表で「吸収」カテゴリのコンポーネントを確認する
- **THEN** 各エントリに吸収先の新コンポーネント名と根拠が記載されている

### Requirement: B-3/C-4 スコープ境界定義

セッション構造変更（B-3 スコープ）とインターフェース適応（C-4 スコープ）の境界を `architecture/migration/scope-boundary.md` に定義しなければならない（SHALL）。

各コンポーネントがどちらのスコープに属するかを分類テーブルで明示する（MUST）。

#### Scenario: スコープの分類基準が明確
- **WHEN** `architecture/migration/scope-boundary.md` を確認する
- **THEN** B-3（セッション構造変更: autopilot-plan, init-session, phase-execute）と C-4（インターフェース適応）の分類基準が定義されている

#### Scenario: 全 script が分類済み
- **WHEN** スコープ境界テーブルを確認する
- **THEN** B-5（merge-gate 判定ロジック変更）を含む全 script に対してスコープが割り当てられている

### Requirement: Specialist 共通出力スキーマ仕様

specialist の共通出力スキーマの詳細仕様を `architecture/contracts/specialist-output-schema.md` に定義しなければならない（SHALL）。

JSON スキーマ定義、フィールド説明、few-shot 例（1 例）、消費側パースルールを含める（MUST）。

#### Scenario: JSON スキーマが完全定義
- **WHEN** `architecture/contracts/specialist-output-schema.md` を確認する
- **THEN** status (PASS/WARN/FAIL)、severity (CRITICAL/WARNING/INFO)、confidence (0-100)、findings の必須フィールドが全て定義されている

#### Scenario: few-shot 例が含まれる
- **WHEN** specialist-output-schema.md を確認する
- **THEN** PASS ケースと FAIL ケースの few-shot 例が各 1 つ以上含まれている

### Requirement: Model 割り当て表

specialist および controller の model 割り当てを `architecture/contracts/specialist-output-schema.md` の model セクションに記載しなければならない（SHALL）。

haiku/sonnet/opus の判定基準を明示する（MUST）。

#### Scenario: 全 specialist の model が指定
- **WHEN** model 割り当て表を確認する
- **THEN** haiku (構造チェック・パターンマッチ)、sonnet (コードレビュー・品質判断)、opus (controller/workflow) の分類基準と対象一覧が記載されている

### Requirement: Bare repo 構造検証ルール

bare repo + worktree の正規構造と検証条件を `architecture/domain/contexts/project-mgmt.md` に記載しなければならない（SHALL）。

セッション開始時の 3 検証条件（.bare/ 存在、main/.git がファイル、CWD が main/ 配下）を明文化する（MUST）。

#### Scenario: 検証条件が3件定義
- **WHEN** project-mgmt.md の bare repo 検証セクションを確認する
- **THEN** `.bare/` 存在、`main/.git` がファイル、CWD が `main/` 配下の 3 条件が記載されている

#### Scenario: 正規ディレクトリ構造が記載
- **WHEN** project-mgmt.md を確認する
- **THEN** `project-name/.bare/`, `project-name/main/`, `project-name/worktrees/` の構造が図示されている

### Requirement: Worktree ライフサイクル安全ルール

worktree の作成・使用・削除に関するライフサイクルルールを `architecture/domain/contexts/autopilot.md` に追記しなければならない（SHALL）。

「Worker は自分の worktree を削除しない。削除は常に Pilot が行う」の鉄則を含める（MUST）。

#### Scenario: Pilot/Worker の役割が明確
- **WHEN** autopilot.md の worktree ライフサイクルセクションを確認する
- **THEN** Worker は worktree 作成のみ、Pilot が merge 成功後に削除する旨が記載されている

#### Scenario: 不変条件 B との整合性
- **WHEN** worktree ライフサイクルルールを確認する
- **THEN** 不変条件 B（Worktree 削除 pilot 専任）と矛盾しない
