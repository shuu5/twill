## ADDED Requirements

### Requirement: ディレクトリ/ファイルの実 rename

`rename_component()` は、path フィールドが示すファイルの親ディレクトリに old_name が含まれる場合、ディレクトリを new_name に rename しなければならない（SHALL）。実行順序はディレクトリ rename → deps.yaml 書き戻しでなければならない（MUST）。

#### Scenario: ディレクトリ rename の実行
- **WHEN** `loom rename controller-project co-project` を実行し、`skills/controller-project/` ディレクトリが存在する
- **THEN** `skills/controller-project/` が `skills/co-project/` に rename される

#### Scenario: 移動先ディレクトリが既に存在
- **WHEN** `loom rename controller-project co-project` を実行し、`skills/co-project/` が既に存在する
- **THEN** エラーメッセージを表示して中断する（既存ディレクトリを上書きしない）

#### Scenario: ディレクトリが存在しない場合のスキップ
- **WHEN** `loom rename some-cmd new-cmd` を実行し、path が `commands/some-cmd.md`（ディレクトリではなくファイル直接）で親ディレクトリに old_name を含まない
- **THEN** ディレクトリ rename はスキップされ、正常に完了する

#### Scenario: dry-run でのディレクトリ変更表示
- **WHEN** `loom rename controller-project co-project --dry-run` を実行し、ディレクトリ移動が必要な場合
- **THEN** ディレクトリ移動が `directory: skills/controller-project/ → skills/co-project/` 形式でプレビュー表示される

### Requirement: rename 失敗時のロールバック

ディレクトリ rename 後に deps.yaml 書き戻しが失敗した場合、ディレクトリを元の位置に戻さなければならない（MUST）。

#### Scenario: deps.yaml 書き戻し失敗時のロールバック
- **WHEN** ディレクトリ rename は成功したが deps.yaml の書き戻しで例外が発生した
- **THEN** ディレクトリが元の位置に戻され、エラーメッセージが表示される
