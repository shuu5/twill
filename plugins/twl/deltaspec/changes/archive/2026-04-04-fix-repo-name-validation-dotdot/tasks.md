## 1. バリデーション修正

- [x] 1.1 `scripts/autopilot-plan-board.sh` L89 の正規表現を `^[a-zA-Z0-9_][a-zA-Z0-9_.-]*$` に変更する
- [x] 1.2 バリデーション直後に `[[ "$cross_name" == ".." || "$cross_name" == "." ]] && continue` を追加する

## 2. 動作確認

- [x] 2.1 `cross_name='..'` が拒否されることを手動で確認する
- [x] 2.2 `cross_name='.'` が拒否されることを手動で確認する
- [x] 2.3 有効なリポジトリ名（`my-repo`, `repo.js`, `repo_v2`）が通過することを確認する
