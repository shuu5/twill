## 1. autopilot-orchestrator.sh: _nudge_command_for_pattern に entry 引数追加

- [x] 1.1 `_nudge_command_for_pattern()` の引数を `(pane_output, issue, entry)` に拡張し、内部で `resolve_issue_repo_context "$entry"` を呼ぶ
- [x] 1.2 gh API fallback の `gh issue view` 呼び出しに `--repo "$ISSUE_REPO_OWNER/$ISSUE_REPO_NAME"` を条件付きで追加（ISSUE_REPO_OWNER が空でない場合のみ）

## 2. autopilot-orchestrator.sh: check_and_nudge に entry 引数追加

- [x] 2.1 `check_and_nudge()` の引数を `(issue, window_name, entry)` に拡張する
- [x] 2.2 `_nudge_command_for_pattern "$pane_output" "$issue" "$entry"` で entry を渡す

## 3. autopilot-orchestrator.sh: cleanup_worker に entry 引数追加

- [x] 3.1 `cleanup_worker()` の引数を `(issue, entry)` に拡張し、内部で `resolve_issue_repo_context "$entry"` を呼ぶ
- [x] 3.2 ISSUE_REPO_PATH が空でない場合は `git -C "$ISSUE_REPO_PATH" push origin --delete "$branch"` を使用する

## 4. autopilot-orchestrator.sh: poll_single を entry 受け取り型に変更

- [x] 4.1 `poll_single()` が `entry` を第1引数として受け取り、`resolve_issue_repo_context "$entry"` で issue を抽出する
- [x] 4.2 `cleanup_worker "$issue" "$entry"` で entry を渡す（done/failed/タイムアウト全ケース）
- [x] 4.3 `check_and_nudge "$issue" "$window_name" "$entry"` で entry を渡す

## 5. autopilot-orchestrator.sh: poll_phase を entry リスト受け取り型に変更

- [x] 5.1 `poll_phase()` が entry リストを受け取り、各 entry から issue を抽出する
- [x] 5.2 `cleanup_worker "$issue" "$entry"` で entry を渡す（done/failed/タイムアウト全ケース）
- [x] 5.3 `check_and_nudge "$issue" "$window_name" "$entry"` で entry を渡す
- [x] 5.4 main loop で `poll_single "${BATCH[0]}"` / `poll_phase "${BATCH[@]}"` に変更（BATCH_ISSUES の代わりに BATCH を使用）

## 6. orchestrator-nudge.bats: test double 拡張とテスト追加

- [x] 6.1 gh スタブ関数を `--repo` フラグ対応に拡張（spy として呼び出しを記録）
- [x] 6.2 is_quick fallback シナリオ（state に is_quick なし → gh API 呼び出し → ラベルあり/なし）のテストケース追加
- [x] 6.3 クロスリポ環境での `--repo` フラグ付き gh 呼び出し確認テスト追加
- [x] 6.4 デフォルトリポでの `--repo` なし呼び出し確認テスト追加
- [x] 6.5 `bats tests/bats/scripts/orchestrator-nudge.bats` で全件パス確認
