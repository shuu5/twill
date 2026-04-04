## 1. auto-merge.sh 新設

- [x] 1.1 `scripts/auto-merge.sh` を作成: 引数解析（--issue, --pr, --branch）+ usage + バリデーション
- [x] 1.2 Layer 2 CWD ガード実装（merge-gate-execute.sh のパターン流用）
- [x] 1.3 Layer 3 tmux window ガード実装（ap-#N パターン検出）
- [x] 1.4 Layer 1 IS_AUTOPILOT 判定実装（state-read.sh 呼び出し）
- [x] 1.5 Layer 4 フォールバックガード実装（git worktree list → main worktree → .autopilot/issue-{N}.json 確認）
- [x] 1.6 IS_AUTOPILOT=true 時のハンドリング（state-write.sh で merge-ready 遷移 + exit 0）
- [x] 1.7 非 autopilot 時の squash merge 実装（gh pr merge --squash）
- [x] 1.8 非 autopilot 時の worktree 削除 + ブランチ削除（cleanup）
- [x] 1.9 非 autopilot 時の OpenSpec archive（存在時のみ）

## 2. auto-merge.md 簡素化

- [x] 2.1 `commands/auto-merge.md` を script 呼び出しのみに書き換え

## 3. テスト

- [x] 3.1 Layer 2 CWD ガードのテスト
- [x] 3.2 Layer 3 tmux window ガードのテスト
- [x] 3.3 Layer 1 IS_AUTOPILOT 判定のテスト（running → merge-ready）
- [x] 3.4 Layer 4 フォールバックガードのテスト
- [x] 3.5 非 autopilot 正常 merge のテスト
- [x] 3.6 引数バリデーションのテスト

## 4. 関連 Issue コメント

- [x] 4.1 #119 に「auto-merge を script 化対象に追加」のコメント投稿
