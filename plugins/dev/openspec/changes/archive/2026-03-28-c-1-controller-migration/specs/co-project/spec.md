## ADDED Requirements

### Requirement: co-project SKILL.md 3モードルーティング実装

co-project の SKILL.md を stub から完全実装に置き換えなければならない（MUST）。architecture/domain/contexts/project-mgmt.md の設計定義に準拠し、旧 controller-project / controller-project-migrate / controller-project-snapshot の機能を create / migrate / snapshot の 3 モードに統合する。

SKILL.md は以下の構成を持たなければならない（SHALL）:

- Step 0: モード判定（引数またはユーザー入力から create / migrate / snapshot を判定）
- create モード: Step 1〜4（入力確認 → project-create → テンプレート Rich Mode → governance 適用 → 完了レポート）
- migrate モード: Step 1〜3（現在地確認 → project-migrate → governance 再適用 → 完了レポート）
- snapshot モード: Step 1〜5（入力確認 → snapshot-analyze → snapshot-classify → snapshot-generate → 完了レポート）

#### Scenario: create モード実行
- **WHEN** ユーザーが `create` モードで co-project を呼び出す
- **THEN** プロジェクト名・テンプレートタイプの確認後、project-create → governance 適用 → Board 作成が実行される

#### Scenario: migrate モード実行
- **WHEN** ユーザーが `migrate` モードで co-project を呼び出す
- **THEN** 現在のプロジェクト位置が確認され、project-migrate → governance 再適用が実行される

#### Scenario: snapshot モード実行
- **WHEN** ユーザーが `snapshot` モードで co-project を呼び出す
- **THEN** ソースプロジェクトの分析 → Tier 分類 → テンプレート生成が実行される

### Requirement: plugin 管理の co-project テンプレート統合

旧 controller-plugin の機能は co-project の `create` モードで `--type plugin` として吸収しなければならない（MUST）。plugin の保守は通常ワークフロー + loom CLI で行い、専用 controller を設けない（SHALL）。

#### Scenario: plugin テンプレートでのプロジェクト作成
- **WHEN** `create` モードで `--type plugin` が指定される
- **THEN** plugin テンプレートが適用され、通常のプロジェクト作成フローで plugin プロジェクトが構築される

### Requirement: create モードの Rich Mode 対応

create モードで manifest.yaml が存在するテンプレート（Rich Mode）を使用する場合、スタック情報テーブルの表示とコンテナ依存チェックを実行しなければならない（MUST）。

#### Scenario: Rich Mode テンプレートでの作成
- **WHEN** テンプレートに manifest.yaml が存在する
- **THEN** スタック情報テーブルが表示され、containers セクション存在時は container-dependency-check が実行される
