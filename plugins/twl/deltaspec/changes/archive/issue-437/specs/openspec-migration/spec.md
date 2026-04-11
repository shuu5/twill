## MODIFIED Requirements

### Requirement: OpenSpec ファイルが DeltaSpec 標準形式に変換されていなければならない（SHALL）

`cli/twl/deltaspec/changes/` 内（`archive/` 含む）の全 `.openspec.yaml` ファイルは `.deltaspec.yaml` にリネームされ、`name` および `status` フィールドを持たなければならない（SHALL）。

#### Scenario: active changes のリネームと必須フィールド補完
- **WHEN** `cli/twl/deltaspec/changes/` 配下（`archive/` 除く）に `.openspec.yaml` が存在する
- **THEN** 各ファイルが `.deltaspec.yaml` にリネームされ、`name` フィールドと `status: pending` フィールドが存在すること

#### Scenario: archived changes のリネーム
- **WHEN** `cli/twl/deltaspec/changes/archive/` 配下に `.openspec.yaml` が存在する
- **THEN** 各ファイルが `.deltaspec.yaml` にリネームされること

### Requirement: 全 active changes が archive されていなければならない（SHALL）

変換後、16 件の active changes が `twl spec archive --yes` で `cli/twl/deltaspec/changes/archive/` に移動されなければならない（SHALL）。

#### Scenario: archive 後のアクティブ change ゼロ確認
- **WHEN** 全 active change に対して `twl spec archive --yes` を実行した後
- **THEN** `twl spec list`（`cli/twl` ディレクトリから実行）がエラーなく終了し、アクティブ change が 0 件と表示されること

#### Scenario: specs 統合
- **WHEN** `specs/` サブディレクトリを持つ change が archive される
- **THEN** その specs が `cli/twl/deltaspec/specs/` に統合されること（`specs/` を持たない changes は統合対象外でスキップが正常）

### Requirement: `.openspec.yaml` ファイルが残存していてはならない（SHALL）

移行完了後、`cli/twl/deltaspec/changes/`（`archive/` 含む）に `.openspec.yaml` ファイルが存在してはならない（SHALL）。

#### Scenario: 移行後の残存ファイルなし確認
- **WHEN** 全リネームと archive が完了した後
- **THEN** `find cli/twl/deltaspec/changes -name ".openspec.yaml"` が 0 件を返すこと
