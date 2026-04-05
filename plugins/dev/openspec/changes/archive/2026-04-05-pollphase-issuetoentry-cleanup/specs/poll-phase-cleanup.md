## MODIFIED Requirements

### Requirement: poll_phase の冗長変数削除

`poll_phase()` 関数内の `issue_to_entry` 連想配列と `issue_entry` 変数は冗長であるため削除しなければならない（SHALL）。`cleanup_worker` の呼び出しは `$entry` を直接使用しなければならない（SHALL）。

#### Scenario: issue_to_entry 配列が削除される
- **WHEN** `poll_phase()` 関数を参照する
- **THEN** `declare -A issue_to_entry` の宣言が存在しない

#### Scenario: issue_entry 変数が削除される
- **WHEN** `poll_phase()` 関数を参照する
- **THEN** `issue_entry` 変数への代入・参照が存在しない

#### Scenario: cleanup_worker が entry を直接使用する
- **WHEN** `cleanup_worker` が呼び出される
- **THEN** 第2引数として `$entry` が渡される（`$issue_entry` ではない）
