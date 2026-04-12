## MODIFIED Requirements

### Requirement: all-pass-check merge-ready 時に workflow_done=pr-merge を書き込む

`chain-runner.sh` の `step_all_pass_check()` は `status=merge-ready` を書き込む際に、`workflow_done=pr-merge` を同一の state write コマンド内で必ず書き込まなければならない（SHALL）。

#### Scenario: 正常終了時に workflow_done が書かれる

- **WHEN** `step_all_pass_check()` が `overall_result=PASS` で実行される
- **THEN** state に `status=merge-ready` と `workflow_done=pr-merge` が両方書き込まれ、コマンドが exit 0 で終了する

#### Scenario: state write 失敗時は exit 非ゼロで終了する

- **WHEN** `python3 -m twl.autopilot.state write` コマンドが非ゼロで終了する
- **THEN** `step_all_pass_check()` は `err` を出力して return 1 する（`workflow_done` は書かれない）

### Requirement: 失敗時は workflow_done を書かない

`step_all_pass_check()` が `overall_result=FAIL` で実行される場合、`workflow_done` フィールドを state に書いてはならない（MUST NOT）。`status=failed` のみを書き込み exit 1 で終了しなければならない（SHALL）。

#### Scenario: FAIL 時は status=failed のみが書かれる

- **WHEN** `step_all_pass_check()` が `overall_result=FAIL` で実行される
- **THEN** state に `status=failed` が書き込まれ、`workflow_done` フィールドは書き込まれず、コマンドが exit 1 で終了する

## ADDED Requirements

### Requirement: smoke テストで workflow_done=pr-merge の書き込みを確認する

`all-pass-check` の smoke テストを追加し、PASS 時に state の `workflow_done` フィールドが `pr-merge` になることを自動で確認しなければならない（SHALL）。

#### Scenario: smoke テストが workflow_done=pr-merge を検証する

- **WHEN** `all-pass-check PASS` を実行する smoke テストが走る
- **THEN** テスト完了後に state から `workflow_done` を読み取ると `pr-merge` が返り、テストが pass する
