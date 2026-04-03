## 1. merge-gate.md PASS セクション修正

- [x] 1.1 `commands/merge-gate.md` L94-100 の raw `gh pr merge --squash` を除去する
- [x] 1.2 `commands/merge-gate.md` L94-100 の `state-write --role pilot --set status=done` / `merged_at` を除去する
- [x] 1.3 autopilot 時の PASS フローを「`state-write --role worker --set status=merge-ready` + 停止メッセージ」に書き換える
- [x] 1.4 非 autopilot 時（Pilot）の PASS フローを `merge-gate-execute.sh` 呼び出し案内として記載する
- [x] 1.5 `grep "gh pr merge" commands/merge-gate.md` で 0 件になることを確認する

## 2. state-write.sh identity 検証追加

- [x] 2.1 `scripts/state-write.sh` に `--role pilot` + status フィールド更新時の identity 検証ブロックを追加する
- [x] 2.2 tmux window 名が `ap-#<数値>` パターンの場合にエラーで終了するロジックを実装する
- [x] 2.3 CWD が `*/worktrees/*` パターンの場合にエラーで終了するロジックを実装する
- [x] 2.4 Worker セッション（tmux/CWD 模擬）から `--role pilot --set status=done` を呼び出してエラーになることを手動確認する

## 3. auto-merge.sh Layer 1 拡張

- [x] 3.1 `scripts/auto-merge.sh` L95-96 の IS_AUTOPILOT 判定条件に `merge-ready` を追加する（`running` OR `merge-ready`）
- [x] 3.2 `scripts/auto-merge.sh` の `merge-ready` 状態でも既存の merge-ready 宣言フローを正しく実行することを確認する

## 4. merge-gate-execute.sh autopilot 判定追加

- [x] 4.1 `scripts/merge-gate-execute.sh` に既存 CWD/tmux ガード後の state-read ベース autopilot 判定ブロックを追加する
- [x] 4.2 `IS_AUTOPILOT` が true の場合でも merge-gate-execute.sh は Pilot セッションからの呼び出しとして merge を許可することを確認する（Pilot セッションは CWD/tmux ガードを通過するため）

## 5. 動作確認

- [x] 5.1 `commands/merge-gate.md` に `gh pr merge` / `--role pilot` が残存しないことを grep で確認する
- [x] 5.2 `scripts/state-write.sh --help` でオプション説明が正しく更新されていることを確認する
- [x] 5.3 `bash scripts/state-write.sh --type issue --issue 999 --role pilot --set status=done` を worktrees/ 配下から呼び出してエラーになることをテストする
