## ADDED Requirements

### Requirement: chain-runner.sh ステップ実行前の進行位置記録
chain-runner.sh は各ステップを実行する前に、`state-write.sh` を通じて `current_step` を issue-{N}.json に記録しなければならない（SHALL）。記録は冪等でなければならず、同じステップが複数回実行されても安全でなければならない（SHALL）。

#### Scenario: ステップ実行前の current_step 記録
- **WHEN** chain-runner.sh がステップ `<step_id>` を実行する直前
- **THEN** issue-{N}.json の `current_step` フィールドが `<step_id>` に更新される

#### Scenario: state-write.sh による Worker ロール書き込み許可
- **WHEN** Worker ロールが `state-write.sh --set "current_step=<step>"` を呼び出す
- **THEN** `current_step` がホワイトリストに含まれているため書き込みが許可される

### Requirement: compaction-resume.sh による完了済みステップスキップ判定
`compaction-resume.sh <ISSUE_NUM> <step_id>` は、指定ステップが完了済みかどうかを exit code で返さなければならない（SHALL）。完了済みの場合は exit 1、要実行の場合は exit 0 を返さなければならない（SHALL）。

#### Scenario: 完了済みステップのスキップ判定
- **WHEN** `compaction-resume.sh 129 worktree-create` を呼び出し、current_step が `board-status-update` 以降を示している
- **THEN** exit 1 が返り、worktree-create はスキップ可能と判定される

#### Scenario: 未完了ステップの実行判定
- **WHEN** `compaction-resume.sh 129 opsx-propose` を呼び出し、current_step が `opsx-propose` を示している
- **THEN** exit 0 が返り、opsx-propose は実行が必要と判定される
