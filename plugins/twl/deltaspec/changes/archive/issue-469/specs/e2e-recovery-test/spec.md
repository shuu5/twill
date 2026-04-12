## ADDED Requirements

### Requirement: orchestrator recovery E2E テスト

Worker が `workflow_done` を書かずに終了した場合に orchestrator が recovery を試みるシナリオを pytest integration test で検証しなければならない（SHALL）。テストは `tests/autopilot/test_nonterminal_chain_recovery.py` に配置し、CI で PASS すること（SHALL）。

#### Scenario: workflow_done 未書き込み時の resolve 失敗確認
- **WHEN** issue-N の state で `workflow_done=null` のまま `resolve_next_workflow --issue <N>` を呼ぶ
- **THEN** exit 非ゼロで終了し、stdout が空であることを確認できる

#### Scenario: workflow_done 書き込み後の resolve 成功確認
- **WHEN** `state write --set workflow_done=test-ready` で書き込んだ後に `resolve_next_workflow --issue <N>` を呼ぶ
- **THEN** exit 0 で `/twl:workflow-pr-verify` が stdout に出力される

#### Scenario: _nudge_command_for_pattern の実装完了パターン検知確認
- **WHEN** pane 出力文字列が `>>> 実装完了: issue-469` を含む状態で `_nudge_command_for_pattern` ロジックを評価する
- **THEN** state に `workflow_done=test-ready` が書かれ、`/twl:workflow-pr-verify #469` が返される
