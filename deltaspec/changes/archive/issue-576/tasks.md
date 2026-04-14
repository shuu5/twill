## 1. TWILL_REPO_ROOT export 追加

- [x] 1.1 `autopilot-orchestrator.sh` の `launch_worker()` 内、`effective_project_dir` 確定直後（line 276 付近）に `export TWILL_REPO_ROOT="${PROJECT_DIR}"` を追加する

## 2. CRG symlink ロジック変更

- [x] 2.1 CRG symlink 参照先を `${TWILL_REPO_ROOT}/main/.code-review-graph` に変更する（`effective_project_dir` → `TWILL_REPO_ROOT`）
- [x] 2.2 `_is_main` 判定を文字列比較（末尾スラッシュ strip 付き）に変更する
- [x] 2.3 `realpath` ベースの `_is_main` 判定コード（旧 line 328）を削除する

## 3. 動作確認

- [x] 3.1 feature worktree で CRG symlink が `${TWILL_REPO_ROOT}/main/.code-review-graph` を指すことを確認する
- [x] 3.2 main worktree に対して CRG symlink が作成されないことを確認する
