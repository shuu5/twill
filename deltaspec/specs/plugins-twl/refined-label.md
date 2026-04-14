## Requirements

### Requirement: refined ラベル自動付与（Step 4.5）

`workflow-issue-lifecycle` の Step 4（round loop）と Step 5（arch-drift）の間に Step 4.5 を設けなければならない（SHALL）。Step 4.5 は round loop の完了状態と `quick_flag` を評価し、条件を満たす場合に `labels_hint` へ `"refined"` を追加しなければならない（SHALL）。

#### Scenario: 通常モードかつ round loop 正常完了時に refined を付与する

- **WHEN** `quick_flag=false` かつ round loop が `circuit_broken` でない状態で正常完了した
- **THEN** `labels_hint` に `"refined"` が追加される

#### Scenario: quick モードでは refined を付与しない

- **WHEN** `quick_flag=true` の場合
- **THEN** Step 4.5 はスキップされ、`labels_hint` に `"refined"` は追加されない

#### Scenario: circuit_broken 状態では refined を付与しない

- **WHEN** round loop が `circuit_broken` 状態で終了した
- **THEN** Step 4.5 はスキップされ、`labels_hint` に `"refined"` は追加されない

### Requirement: bats テストによる Step 4.5 検証

`workflow-issue-lifecycle.bats` に Step 4.5 の判定ロジックを検証するテストケースを追加しなければならない（SHALL）。

#### Scenario: 正常完了ケースのテスト

- **WHEN** `quick_flag=false` かつ `STATE` が `circuit_broken` でないロジックを実行する
- **THEN** `labels_hint` に `refined` が含まれることを `assert_output --partial "refined"` 等で検証する

#### Scenario: quick モードのテスト

- **WHEN** `quick_flag=true` でロジックを実行する
- **THEN** `labels_hint` に `refined` が含まれないことを検証する

#### Scenario: circuit_broken のテスト

- **WHEN** `STATE=circuit_broken` でロジックを実行する
- **THEN** `labels_hint` に `refined` が含まれないことを検証する
