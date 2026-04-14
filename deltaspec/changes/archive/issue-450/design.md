## Context

autopilot chain 遷移（setup → test-ready → pr-verify）の E2E テストが存在せず、Wave 1-5 で `non_terminal_chain_end` や PHASE_COMPLETE wait stall が発生していた。Issue #438 AC#5 の「手動テスト証跡」が PR diff に含まれていないことが本 Issue の起点。

既存のテストは以下の通り:
- `cli/twl/tests/autopilot/test_nonterminal_chain_recovery.py` — non_terminal_chain_end のリカバリをテスト
- `cli/twl/tests/autopilot/test_state.py` — state 読み書きをテスト
- `cli/twl/tests/test_resolve_next_workflow.py` — resolve_next_workflow のユニットテスト

E2E chain 遷移を通しで検証するテストが存在しない。

## Goals / Non-Goals

**Goals:**

- `cli/twl/tests/autopilot/test_chain_e2e_transition.py` を追加し、setup → test-ready → pr-verify の chain 遷移を E2E で検証する
  - `workflow_done=setup` 書き込み後に `resolve_next_workflow` が `workflow-test-ready` を返す
  - `workflow_done=test-ready` 書き込み後に `resolve_next_workflow` が `workflow-pr-verify` を返す
  - `workflow_done=pr-verify` で terminal になる（または次の workflow が空になる）
- PR コメントへの trace ログ添付方法をドキュメント化する（スクリプトではなく手順）
- inject-skip を検出するアサーションを含める

**Non-Goals:**

- tmux / claude CLI を実際に起動するシステムテスト（モックで代替）
- Issue #469 / #472 の root cause 修正（それらは別 Issue）
- 新規 CLI コマンドの追加

## Decisions

1. **テストスコープ**: `resolve_next_workflow` モジュールを単体で呼び出す integration test とする。tmux・gh・claude は不要。`twl.autopilot.state` の実ファイル I/O を `tmp_path` で行う
2. **inject-skip 検出**: `resolve_next_workflow` が空文字を返した場合を inject-skip とみなし、アサーションで `AssertionError` を発生させる
3. **trace ログ**: `.autopilot/trace/inject-*.log` の存在確認は実稼働依存のため、テストでは検証しない。PR コメントへの添付は手動フローとしてドキュメントに記載するのみ
4. **AC-3 (3 Issue 以上)**: 3 Issue を模した状態ファイルを作成し、それぞれの chain 遷移が成立することをパラメータ化テストで確認する

## Risks / Trade-offs

- **リスク**: `resolve_next_workflow` の内部実装が `deps.yaml` の meta_chains に依存しているため、deps.yaml 変更時にテストが壊れる可能性がある
  - **対策**: テストで使用する `deps.yaml` を fixture として tmp_path にコピーし、実際の deps.yaml を参照するのではなく独立させる
- **Trade-off**: システムレベル（tmux起動）の E2E は省略し、モジュールレベルの integration test に留める。完全な E2E は別途 Wave 実績で代替
