## REMOVED Requirements

### Requirement: architect-decompose コンポーネントの廃止

`architect-decompose` コンポーネントが deps.yaml および `commands/architect-decompose.md` から削除されなければならない（SHALL）。

#### Scenario: deps.yaml から architect-decompose エントリ削除

- **WHEN** `plugins/twl/deps.yaml` を確認する
- **THEN** `architect-decompose` キーが存在しない

#### Scenario: コマンドファイルの削除

- **WHEN** ファイルシステムを確認する
- **THEN** `plugins/twl/commands/architect-decompose.md` が存在しない

#### Scenario: twl check が orphan を検出しない

- **WHEN** `plugins/twl/` ディレクトリで `twl check` を実行する
- **THEN** violations=0、orphans=0 で終了する

### Requirement: architect-issue-create コンポーネントの廃止

`architect-issue-create` コンポーネントが deps.yaml および `commands/architect-issue-create.md` から削除されなければならない（SHALL）。

#### Scenario: deps.yaml から architect-issue-create エントリ削除

- **WHEN** `plugins/twl/deps.yaml` を確認する
- **THEN** `architect-issue-create` キーが存在しない

#### Scenario: コマンドファイルの削除

- **WHEN** ファイルシステムを確認する
- **THEN** `plugins/twl/commands/architect-issue-create.md` が存在しない
