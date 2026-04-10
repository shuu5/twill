## ADDED Requirements

### Requirement: twl spec new による issue フィールド自動付与

`twl spec new` コマンドは、name が `issue-\d+` パターンにマッチする場合、生成する `.deltaspec.yaml` に `issue: <N>` フィールドを自動的に追加しなければならない（SHALL）。

#### Scenario: issue-N パターンの name で spec new を実行する
- **WHEN** `twl spec new "issue-123"` を実行する
- **THEN** `deltaspec/changes/issue-123/.deltaspec.yaml` に `issue: 123` フィールドが含まれる

#### Scenario: 非 issue パターンの name では issue フィールドを付与しない
- **WHEN** `twl spec new "add-user-auth"` を実行する
- **THEN** `deltaspec/changes/add-user-auth/.deltaspec.yaml` に `issue:` フィールドが含まれない

## MODIFIED Requirements

### Requirement: orchestrator sh 版の archive フォールバック検索

`autopilot-orchestrator.sh` の `_archive_deltaspec_changes_for_issue()` は、`issue:` フィールドによるプライマリ検索が 0 件だった場合、`name: issue-<N>` パターンによるフォールバック検索を実行しなければならない（SHALL）。

#### Scenario: issue フィールドなしの change を name パターンでフォールバック検出する
- **WHEN** `.deltaspec.yaml` に `issue:` フィールドがなく `name: issue-<N>` が存在する
- **THEN** orchestrator が当該 change を archive 対象として検出し、`twl spec archive` を実行する

#### Scenario: issue フィールドありの change はプライマリ検索で検出する
- **WHEN** `.deltaspec.yaml` に `issue: <N>` フィールドが存在する
- **THEN** orchestrator がフォールバックなしにプライマリ検索で当該 change を検出する

### Requirement: orchestrator Python 版の archive フォールバック検索

`cli/twl/src/twl/autopilot/orchestrator.py` の `_archive_deltaspec_changes()` は、`issue:` フィールドによるプライマリ検索が 0 件だった場合、`name: issue-<N>` パターンによるフォールバック検索を実行しなければならない（SHALL）。

#### Scenario: Python orchestrator が name パターンで change を検出する
- **WHEN** `.deltaspec.yaml` に `issue:` フィールドがなく `name: issue-<N>` が含まれる
- **THEN** Python orchestrator が当該 change を archive 対象として処理する

#### Scenario: 両方のパターンが一致しても二重 archive しない
- **WHEN** `.deltaspec.yaml` に `issue: <N>` と `name: issue-<N>` の両方が存在する
- **THEN** orchestrator は当該 change を 1 回のみ archive する
