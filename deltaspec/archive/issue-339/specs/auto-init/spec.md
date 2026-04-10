## ADDED Requirements

### Requirement: auto_init 判定

`change-propose` コマンドは、実行開始時に `auto_init` フラグを判定しなければならない（SHALL）。`auto_init=true` かつ Issue 番号が存在する場合、ユーザーへの質問なしに change-id を `issue-<N>` として確定しなければならない（SHALL）。

#### Scenario: auto_init=true のとき change-id を自動導出する
- **WHEN** state に `auto_init=true` が記録されており、Issue 番号 `N` が存在する
- **THEN** change-id を `issue-N` として確定し、Step 1 の対話をスキップする

#### Scenario: auto_init=false のとき既存フローを維持する
- **WHEN** state に `auto_init=false` が記録されている
- **THEN** 既存の Step 1 から処理を開始し、明確な入力がなければユーザーに質問する

### Requirement: deltaspec/ 自動初期化

`auto_init=true` のとき、`change-propose` コマンドは `deltaspec/` ディレクトリが存在しない場合でも `twl spec new` を成功させなければならない（SHALL）。

#### Scenario: deltaspec/ 未存在時に自動作成する
- **WHEN** `auto_init=true` かつ `deltaspec/` ディレクトリが存在しない
- **THEN** `twl spec new "issue-<N>"` の前に `mkdir -p deltaspec/` を実行し、正常に change ディレクトリを作成する

#### Scenario: 既存 change と衝突した場合に確認する
- **WHEN** `deltaspec/changes/issue-<N>/` が既に存在する
- **THEN** ユーザーに続行か新規作成かを確認してから処理を継続する

## MODIFIED Requirements

### Requirement: change-propose Step 1 の変更

既存の Step 1「明確な入力がない場合に質問する」は、`auto_init=false` 時のみ適用されなければならない（SHALL）。`auto_init=true` 時は Step 0 で change-id が確定済みのため Step 1 をスキップしなければならない（SHALL）。

#### Scenario: auto_init=true で Step 1 をスキップする
- **WHEN** `auto_init=true` で Step 0 が完了している
- **THEN** AskUserQuestion ツールを呼び出さずに Step 2 の `twl spec new` へ直接進む
