## ADDED Requirements

### Requirement: --check による Template A ドリフト検出

`chain generate <name> --check` は、chain 定義から生成した Template A とファイル上の現在の内容を正規化済みハッシュで比較し、不一致時に unified diff を表示しなければならない（SHALL）。

#### Scenario: チェックポイントが一致する場合
- **WHEN** `twl chain generate <name> --check` を実行し、全ファイルの Template A が生成結果と一致する
- **THEN** 各ファイルに `ok` ステータスを表示し、exit code 0 で終了する

#### Scenario: チェックポイントが不一致の場合
- **WHEN** `twl chain generate <name> --check` を実行し、いずれかのファイルで Template A が不一致
- **THEN** 不一致ファイルに `DRIFT` ステータスを表示し、unified diff を出力し、exit code 1 で終了する

#### Scenario: チェックポイントセクションが存在しない場合
- **WHEN** 対象ファイルに `## チェックポイント` / `## Checkpoint` セクションが存在しない
- **THEN** DRIFT として検出し、期待される内容を diff で表示する

### Requirement: --check の正規化処理

比較前に trailing whitespace 除去と改行コード統一（LF）を適用し、エディタ由来の偽陽性を排除しなければならない（MUST）。

#### Scenario: trailing whitespace の差異を無視
- **WHEN** ファイルの内容が trailing whitespace のみ異なる
- **THEN** `ok` と判定し、DRIFT を報告しない

#### Scenario: 改行コードの差異を無視
- **WHEN** ファイルの内容が CRLF と LF の違いのみ
- **THEN** `ok` と判定し、DRIFT を報告しない

### Requirement: --check と --write の排他制御

`--check` と `--write` を同時に指定した場合、エラーとして処理しなければならない（MUST）。

#### Scenario: --check と --write の同時指定
- **WHEN** `twl chain generate <name> --check --write` を実行する
- **THEN** エラーメッセージを stderr に出力し、exit code 1 で終了する
