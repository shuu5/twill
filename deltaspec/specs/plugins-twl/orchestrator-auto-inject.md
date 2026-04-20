## Requirements

### Requirement: current_step terminal 検知による次 workflow の自動 inject

orchestrator は Issue の `current_step` フィールドを監視し、terminal step を検知したら次の workflow skill を tmux inject しなければならない（SHALL）。これにより Worker が次 workflow を明示的に呼び出さなくても workflow chain が自動進行する（ADR-018）。

#### Scenario: ac-extract terminal 検知
- **WHEN** issue-{N}.json の `current_step` が `"ac-extract"` になる
- **THEN** `"/twl:workflow-test-ready #N"` が Worker の tmux pane に inject される

#### Scenario: post-change-apply terminal 検知
- **WHEN** issue-{N}.json の `current_step` が `"post-change-apply"` になる
- **THEN** `"/twl:workflow-pr-verify #N"` が Worker の tmux pane に inject される

#### Scenario: ac-verify terminal 検知
- **WHEN** issue-{N}.json の `current_step` が `"ac-verify"` になる
- **THEN** `"/twl:workflow-pr-fix #N"` が Worker の tmux pane に inject される

#### Scenario: warning-fix terminal 検知
- **WHEN** issue-{N}.json の `current_step` が `"warning-fix"` になる
- **THEN** `"/twl:workflow-pr-merge #N"` が Worker の tmux pane に inject される

### Requirement: TERMINAL_STEP_TO_NEXT_SKILL マッピング

`twl.autopilot.chain.TERMINAL_STEP_TO_NEXT_SKILL` が terminal step と次 workflow のマッピングを保持しなければならない（SHALL）。

#### Scenario: 現在のマッピング定義
- **WHEN** `TERMINAL_STEP_TO_NEXT_SKILL` を参照する
- **THEN** `ac-extract → workflow-test-ready`、`post-change-apply → workflow-pr-verify`、`ac-verify → workflow-pr-fix`、`warning-fix → workflow-pr-merge` の 4 エントリが存在する

### Requirement: non-terminal step では inject しない

`current_step` が terminal step でない場合、inject を行ってはならない（SHALL NOT）。`resolve_next_workflow.py` は exit 1 を返し、orchestrator は inject をスキップしてポーリングを継続する。

#### Scenario: non-terminal step でのポーリング継続
- **WHEN** issue-{N}.json の `current_step` が terminal step でない（例: `"board-status-update"`）
- **THEN** `resolve_next_workflow.py` が exit 1 を返し、inject は行われず次のポーリングサイクルへ進む

### Requirement: 重複 inject 防止（LAST_INJECTED_STEP）

同一の `current_step` に対して inject は 1 回のみ実行されなければならない（SHALL）。`LAST_INJECTED_STEP` 連想配列で inject 済みの step を追跡し、同一値への再 inject を防止する。

#### Scenario: 重複 inject のブロック
- **WHEN** 同一 issue で同一 `current_step` が再度検知される
- **THEN** `LAST_INJECTED_STEP` の記録により inject がスキップされる

### Requirement: quick Issue の ac-verify terminal 遷移

quick Issue（IS_QUICK=true）では workflow-test-ready を経由せず、Worker が直接実装 → commit → push → PR 作成 → ac-verify を実行し、`current_step=ac-verify` で停止しなければならない（SHALL）。orchestrator が `ac-verify` terminal を検知して `workflow-pr-fix` を inject する。

#### Scenario: quick Issue の自動遷移
- **WHEN** quick Issue の Worker が ac-verify を完了し `current_step=ac-verify` を state に書き込む
- **THEN** orchestrator が `current_step=ac-verify` を terminal として検知し、`"/twl:workflow-pr-fix #N"` を inject する
