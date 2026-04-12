## 1. E2E chain 遷移 integration test 追加

- [ ] 1.1 `cli/twl/tests/autopilot/test_chain_e2e_transition.py` を新規作成する
- [ ] 1.2 `tmp_path` を使った state ファイル I/O のフィクスチャを実装する
- [ ] 1.3 `workflow_done=setup` → `resolve_next_workflow` → `workflow-test-ready` の遷移テストを実装する
- [ ] 1.4 `workflow_done=test-ready` → `resolve_next_workflow` → `workflow-pr-verify` の遷移テストを実装する
- [ ] 1.5 `workflow_done=pr-verify` → terminal (空返却) の遷移テストを実装する
- [ ] 1.6 3 Issue パラメータ化テスト（inject-skip = 0 の検証）を実装する

## 2. inject-skip 検出アサーション

- [ ] 2.1 `resolve_next_workflow` が空を返した場合に `AssertionError` を発生させるヘルパー関数を実装する
- [ ] 2.2 各遷移テストにアサーションを適用する

## 3. テスト実行確認

- [ ] 3.1 `pnpm test cli/twl/tests/autopilot/test_chain_e2e_transition.py` ですべてのテストがパスすることを確認する
- [ ] 3.2 既存テストのリグレッションがないことを確認する（`pnpm test cli/twl/tests/autopilot/`）
