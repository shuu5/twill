## 1. cleanup_worker に REPO_MODE 判定を追加

- [x] 1.1 `scripts/autopilot-orchestrator.sh` の `cleanup_worker` 関数内で `REPO_MODE` をローカル判定するコードを追加する
- [x] 1.2 `worktree-delete.sh` 呼び出しを `[[ "$repo_mode" == "worktree" ]]` 条件でガードする

## 2. 動作確認

- [x] 2.1 standard repo 環境で `cleanup_worker` を呼び出し、警告が出ないことを確認する（手動またはテスト）
- [x] 2.2 bare repo（worktree モード）環境で従来どおり `worktree-delete.sh` が呼ばれることを確認する
