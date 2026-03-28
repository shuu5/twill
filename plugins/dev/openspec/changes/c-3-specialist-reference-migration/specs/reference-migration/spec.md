## ADDED Requirements

### Requirement: loom sync 対象 reference の移植

loom sync-docs 対象の 4 references を refs/ に移植しなければならない（SHALL）。対象: ref-types, ref-practices, ref-deps-format, ref-architecture。各ファイル先頭に同期マーカー `<!-- Synced from loom docs/ — do not edit directly -->` を付与すること（MUST）。

#### Scenario: loom sync 対象ファイルの作成
- **WHEN** ref-types を移植する
- **THEN** refs/ref-types.md が作成され、先頭に同期マーカーが存在し、frontmatter に `type: reference` が宣言されている

#### Scenario: loom sync-docs --check の通過
- **WHEN** 4 ファイル全ての移植が完了した
- **THEN** `loom sync-docs --check` がエラーなしで通過する

### Requirement: プラグイン固有 reference の移植

プラグイン固有の 4 references を refs/ に移植しなければならない（SHALL）。対象: ref-architecture-spec, ref-project-model, ref-dci, self-improve-format。

#### Scenario: プラグイン固有 reference の作成
- **WHEN** ref-dci を移植する
- **THEN** refs/ref-dci.md が作成され、frontmatter に `name: dev:ref-dci`, `type: reference` が宣言されている

### Requirement: Baseline reference の移植

3 つの baseline references をフラット配置で refs/ に移植しなければならない（MUST）。対象: baseline-coding-style, baseline-security-checklist, baseline-input-validation。旧 `refs/baseline/` サブディレクトリ構造から `refs/baseline-*.md` のフラット配置に変更すること（SHALL）。

#### Scenario: baseline のフラット配置
- **WHEN** baseline/coding-style.md を移植する
- **THEN** refs/baseline-coding-style.md として作成され、サブディレクトリは使用されていない

#### Scenario: specialist からの baseline 参照が有効
- **WHEN** worker-code-reviewer が baseline-coding-style を参照する
- **THEN** Glob パターン `**/refs/baseline-coding-style.md` で参照可能である

### Requirement: deps.yaml refs セクション登録

全 11 references を deps.yaml の refs セクションに登録しなければならない（MUST）。各エントリは以下のフィールドを含むこと（SHALL）:

- `type: reference`
- `path`: `refs/<name>.md`
- `description`: 1 行説明

#### Scenario: reference の deps.yaml 登録
- **WHEN** 全 11 references の deps.yaml 登録が完了した
- **THEN** refs セクションに 15 エントリが存在する（既存 4 + 新規 11）

#### Scenario: loom validate が通過
- **WHEN** 全 reference の登録が完了した
- **THEN** `loom validate` がエラーなしで通過する
