## ADDED Requirements

### Requirement: gh API fallback の test double 追加

`orchestrator-nudge.bats` の gh スタブ関数は `--repo` フラグを受け取り、対象リポの labels を返さなければならない（SHALL）。

#### Scenario: --repo フラグを受け取る gh スタブ
- **WHEN** bats の gh スタブが `issue view "$issue" --repo "owner/repo" --json labels ...` で呼ばれる
- **THEN** スタブが `--repo` 引数を無視せず、呼び出しを記録する（spy として機能する）

### Requirement: is_quick fallback テストケース追加

状態ファイルに is_quick がない場合に gh API fallback が呼ばれるシナリオを orchestrator-nudge.bats に追加しなければならない（SHALL）。

#### Scenario: 状態ファイルに is_quick がない場合の gh API fallback
- **WHEN** state-read.sh が is_quick フィールドに空文字を返す
- **THEN** `_nudge_command_for_pattern` が gh issue view を呼び出して quick ラベルを確認する

#### Scenario: gh API fallback で quick ラベルあり
- **WHEN** state に is_quick がなく、gh API が quick ラベルを返す
- **THEN** `_nudge_command_for_pattern` が test-ready 系 nudge をスキップする

#### Scenario: gh API fallback で quick ラベルなし
- **WHEN** state に is_quick がなく、gh API が quick ラベルを返さない
- **THEN** `_nudge_command_for_pattern` が通常の nudge パターンマッチングを継続する

### Requirement: クロスリポ環境での --repo フラグ付き gh 呼び出しテスト

クロスリポ entry を受け取った `_nudge_command_for_pattern()` が `--repo` フラグ付きで gh を呼ぶことを bats でテストしなければならない（SHALL）。

#### Scenario: クロスリポ環境での gh --repo 呼び出し確認
- **WHEN** entry が "_default" 以外（例: `loom:42`）で、state に is_quick がない
- **THEN** gh スタブが `--repo "owner/repo_name"` 付きで呼ばれたことを spy で確認できる

#### Scenario: デフォルトリポでの --repo なし呼び出し確認
- **WHEN** entry が `_default:42`
- **THEN** gh スタブが `--repo` なしで呼ばれたことを確認できる

### Requirement: 既存テストが全件パスする

`orchestrator-nudge.bats` の既存テストケースが全件パスしなければならない（SHALL）。

#### Scenario: 既存テストのパス確認
- **WHEN** `bats tests/bats/scripts/orchestrator-nudge.bats` を実行する
- **THEN** 新規追加テストを含む全テストが PASS する
