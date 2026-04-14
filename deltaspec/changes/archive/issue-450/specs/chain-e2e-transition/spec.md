## ADDED Requirements

### Requirement: E2E chain 遷移 integration test

`cli/twl/tests/autopilot/test_chain_e2e_transition.py` を追加し、autopilot chain の setup → test-ready → pr-verify 遷移を検証しなければならない（SHALL）。

テストは以下を満たさなければならない（MUST）:
- `tmp_path` を使って実際の state ファイル I/O を行う
- tmux / gh / claude CLI を起動しない（モジュールレベルで完結する）
- 各 chain 遷移で inject-skip（resolve_next_workflow が空を返す）がないことを検証する

#### Scenario: setup 完了後に test-ready が次 workflow として返される
- **WHEN** issue の state に `workflow_done=setup` が書かれた状態で `resolve_next_workflow` が呼ばれる
- **THEN** 戻り値が `"/twl:workflow-test-ready"` または `"workflow-test-ready"` となる（inject-skip ではない）

#### Scenario: test-ready 完了後に pr-verify が次 workflow として返される
- **WHEN** issue の state に `workflow_done=test-ready` が書かれた状態で `resolve_next_workflow` が呼ばれる
- **THEN** 戻り値が `"/twl:workflow-pr-verify"` または `"workflow-pr-verify"` となる（inject-skip ではない）

#### Scenario: pr-verify 完了後は pr-fix が次 workflow となる（autopilot=true）
- **WHEN** issue の state に `workflow_done=pr-verify` が書かれ autopilot=true で `resolve_next_workflow` が呼ばれる
- **THEN** 戻り値が `"workflow-pr-fix"` となる（inject-skip ではない）

#### Scenario: pr-verify 完了後 autopilot=false では停止する
- **WHEN** issue の state に `workflow_done=pr-verify` が書かれ autopilot=false で `resolve_next_workflow` が呼ばれる
- **THEN** 戻り値が空文字となる（次 workflow なし、stop 条件）

#### Scenario: 3 Issue 以上の chain 遷移が成立する
- **WHEN** 3 件の異なる Issue（状態がそれぞれ setup / test-ready / pr-verify）に対して chain 遷移が評価される
- **THEN** inject-skip（空を返す）が 0 件である

### Requirement: inject-skip 検出アサーション

`resolve_next_workflow` が空文字を返した場合、テストが inject-skip として `AssertionError` を発生させなければならない（SHALL）。

#### Scenario: resolve_next_workflow が空を返した場合のテスト失敗
- **WHEN** `resolve_next_workflow` の戻り値が空文字である
- **THEN** テストが `AssertionError` で失敗し、inject-skip を報告する
