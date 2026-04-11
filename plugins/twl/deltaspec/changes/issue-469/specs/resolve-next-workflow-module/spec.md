## ADDED Requirements

### Requirement: resolve_next_workflow モジュール

`cli/twl/src/twl/autopilot/resolve_next_workflow.py` を新規作成し、`python3 -m twl.autopilot.resolve_next_workflow --issue <N>` として呼び出せるモジュールを提供しなければならない（SHALL）。

このモジュールは state ファイルの `workflow_done`、`is_quick` フィールドを読み取り、`chain.ChainRunner.resolve_next_workflow()` に委譲して次の workflow skill 名を stdout に出力しなければならない（SHALL）。

#### Scenario: workflow_done=test-ready の場合に次 skill を返す
- **WHEN** issue-<N>.json の `workflow_done` が `"test-ready"` で `is_quick=false` の状態で `python3 -m twl.autopilot.resolve_next_workflow --issue <N>` を実行する
- **THEN** stdout に `/twl:workflow-pr-verify` が出力され exit 0 で終了する

#### Scenario: workflow_done=null の場合に失敗する
- **WHEN** issue-<N>.json の `workflow_done` が `null` または空の状態で `python3 -m twl.autopilot.resolve_next_workflow --issue <N>` を実行する
- **THEN** stdout は空で exit 非ゼロで終了する

#### Scenario: workflow_done=setup の場合に次 skill を返す
- **WHEN** issue-<N>.json の `workflow_done` が `"setup"` で `is_quick=false` の状態で `python3 -m twl.autopilot.resolve_next_workflow --issue <N>` を実行する
- **THEN** stdout に `/twl:workflow-test-ready` が出力され exit 0 で終了する
