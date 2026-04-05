## ADDED Requirements

### Requirement: --all による全 chain 一括操作

`chain generate --all` は deps.yaml 内の全 chain に対して指定操作（stdout / --write / --check）を実行しなければならない（SHALL）。

#### Scenario: --all で全 chain を stdout 出力
- **WHEN** `twl chain generate --all` を実行する
- **THEN** deps.yaml 内の全 chain の Template A/B/C を順次 stdout に出力する

#### Scenario: --all --write で全 chain を一括書き込み
- **WHEN** `twl chain generate --all --write` を実行する
- **THEN** 全 chain のテンプレートを対応ファイルに書き込む

#### Scenario: --all --check で全 chain を一括チェック
- **WHEN** `twl chain generate --all --check` を実行する
- **THEN** ファイルレベルのサマリー（chain ごとに ok/DRIFT）を表示し、末尾に全 diff をまとめて出力する

#### Scenario: chains が 0 件の場合
- **WHEN** deps.yaml に chains セクションが存在しない、または空の場合
- **THEN** `0 chains found` と表示し、exit code 0 で正常終了する

### Requirement: --all と chain name の排他制御

`--all` と chain name を同時に指定した場合、エラーとして処理しなければならない（MUST）。

#### Scenario: --all と chain name の同時指定
- **WHEN** `twl chain generate --all workflow-setup` を実行する
- **THEN** エラーメッセージを stderr に出力し、exit code 1 で終了する

### Requirement: --all も chain name もなしの場合のエラー

`--all` も chain name も指定されていない場合、usage エラーを返さなければならない（MUST）。

#### Scenario: 引数なし実行
- **WHEN** `twl chain generate` を引数なしで実行する
- **THEN** usage メッセージを表示し、exit code 非ゼロで終了する

### Requirement: --all --check のサマリー出力形式

`--all --check` はファイルレベルサマリーと全体サマリーを表示し、diff は末尾にまとめなければならない（SHALL）。

#### Scenario: 複数 chain で一部ドリフトあり
- **WHEN** 5 chain 中 2 chain にドリフトがある状態で `--all --check` を実行する
- **THEN** 各 chain のファイルごとに ok/DRIFT を表示し、`Summary: X/Y chains ok, Z files drifted in W chain.` と修正コマンドを案内し、末尾に diff をまとめる
