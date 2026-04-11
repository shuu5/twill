## 1. workflow_done 読み取りの追加

- [ ] 1.1 `poll_issue()` の `status=running` ブランチ内で `workflow_done` フィールドを `python3 -m twl.autopilot.state read` で追加読み取りする
- [ ] 1.2 `workflow_done` が非空の場合に `inject_next_workflow()` を呼び出し、戻り値が 0 なら `check_and_nudge()` をスキップするロジックを追加する

## 2. inject_next_workflow() 関数の実装

- [ ] 2.1 `inject_next_workflow()` 関数をスクリプト内に追加する（引数: `issue`, `window_name`）
- [ ] 2.2 `resolve_next_workflow` CLI を呼び出して次の workflow skill を取得する
- [ ] 2.3 `pr-merge` が返された場合は inject せず `workflow_done` をクリアして return 0 する処理を追加する
- [ ] 2.4 `resolve_next_workflow` 失敗時の WARNING ログ出力と早期リターン（戻り値 1）を追加する

## 3. tmux pane 入力待ち確認の実装

- [ ] 3.1 `tmux capture-pane -p -t "$window_name"` を実行し末尾行に `> ` / `$ ` が存在するか確認するループ（最大3回、2秒間隔）を実装する
- [ ] 3.2 プロンプト未検出時の WARNING ログ出力と戻り値 1 での終了を実装する

## 4. inject の実行と後処理

- [ ] 4.1 `tmux send-keys -t "$window_name" "$next_skill\n" ""` で workflow skill を inject する
- [ ] 4.2 inject 後に `workflow_done` をクリア（`state write --role pilot --set "workflow_done=null"`）する
- [ ] 4.3 inject 履歴（`workflow_injected`, `injected_at`）を state に書き込む
- [ ] 4.4 `NUDGE_COUNTS[$issue]=0` でリセットする
- [ ] 4.5 `[orchestrator] Issue #${issue}: inject_next_workflow — $next_skill` ログを出力する

## 5. 動作確認

- [ ] 5.1 `workflow_done` が未設定の場合に既存動作が変わらないことを確認する（シェルスクリプトレベルの手動確認）
- [ ] 5.2 `pr-merge` ケースで inject がスキップされることを確認する
