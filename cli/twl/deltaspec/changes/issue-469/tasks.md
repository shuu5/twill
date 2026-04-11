## 1. resolve_next_workflow モジュール作成

- [ ] 1.1 `cli/twl/src/twl/autopilot/resolve_next_workflow.py` を新規作成する（`--issue <N>` 引数で state 読み取り → `chain.ChainRunner.resolve_next_workflow` 呼び出し → stdout 出力）
- [ ] 1.2 `workflow_done=null` / 空文字の場合に exit 非ゼロで終了することを確認する
- [ ] 1.3 既存の `test_resolve_next_workflow.py` が引き続き PASS することを `pytest` で確認する

## 2. orchestrator fallback パターン追加

- [ ] 2.1 `plugins/twl/scripts/autopilot-orchestrator.sh` の `_nudge_command_for_pattern()` に `>>> 実装完了: issue-<N>` パターンを追加する（state write + コマンド返却）
- [ ] 2.2 `AUTOPILOT_STAGNATE_SEC` 環境変数をファイル上部で宣言し、RESOLVE_FAILED 連続カウントの閾値として使用する
- [ ] 2.3 連続 RESOLVE_FAILED が閾値を超えた場合に `[orchestrator] WARN: stagnate` を出力するロジックを追加する

## 3. E2E テスト追加

- [ ] 3.1 `cli/twl/tests/autopilot/test_nonterminal_chain_recovery.py` を新規作成し、以下のシナリオを実装する:
  - `workflow_done=null` → `resolve_next_workflow` が exit 非ゼロ
  - `workflow_done=test-ready` → `resolve_next_workflow` が `/twl:workflow-pr-verify` を返す
  - `_nudge_command_for_pattern` が `>>> 実装完了` を検知すると state write + コマンド返却
- [ ] 3.2 `pytest cli/twl/tests/autopilot/test_nonterminal_chain_recovery.py` が PASS することを確認する

## 4. 検証・クリーンアップ

- [ ] 4.1 `pytest cli/twl/tests/` で全テストが PASS することを確認する
- [ ] 4.2 `twl check` でプラグイン構造整合性を確認する
