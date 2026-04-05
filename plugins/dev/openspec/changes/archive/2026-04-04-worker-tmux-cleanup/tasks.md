## 1. autopilot-orchestrator.sh: cleanup_worker 関数追加

- [x] 1.1 `cleanup_worker()` ヘルパー関数を orchestrator に追加する（tmux kill-window + state-read でブランチ取得 + remote branch delete）

## 2. autopilot-orchestrator.sh: poll_single の cleanup 追加

- [x] 2.1 `poll_single` の `done)` ケースで `cleanup_worker "$issue"` を呼んでから `return 0` する
- [x] 2.2 `poll_single` の `failed)` ケースで `cleanup_worker "$issue"` を呼んでから `return 0` する

## 3. autopilot-orchestrator.sh: poll_phase の cleanup 追加

- [x] 3.1 `poll_phase` の `done|failed)` ケースで初回検知時に `cleanup_worker "$issue"` を呼ぶ（重複呼び出しは冪等性で対応）
- [x] 3.2 タイムアウトループで `status=failed` を設定した各 issue に対して `cleanup_worker "$issue"` を呼ぶ

## 4. merge-gate-execute.sh: reject パスの window cleanup 追加

- [x] 4.1 `--reject` モードの `state-write.sh` 後に `tmux kill-window -t "ap-#${ISSUE}" 2>/dev/null || true` を追加
- [x] 4.2 `--reject-final` モードの `state-write.sh` 後に `tmux kill-window -t "ap-#${ISSUE}" 2>/dev/null || true` を追加

## 5. 動作確認

- [x] 5.1 `poll_single` done/failed パスのログ確認（`[orchestrator] cleanup:` ログが出ること）
- [x] 5.2 `merge-gate-execute.sh --reject` 実行後に tmux window が削除されることを確認
