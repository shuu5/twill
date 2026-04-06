## Context

`cleanup_worker` 関数（`scripts/autopilot-orchestrator.sh` L286-312）は Worker 完了後の後処理を担う。現在は `REPO_MODE` を考慮せず `worktree-delete.sh` を常に呼び出すため、standard repo（非 bare repo）では毎回警告が出る。

他スクリプト（`auto-merge.sh` L171-179、`merge-gate-execute.sh` L109-117）では `git rev-parse --git-dir` の出力で `REPO_MODE` を判定するパターンが確立済み。

## Goals / Non-Goals

**Goals:**
- `cleanup_worker` 内で `REPO_MODE` を自動判定し、`worktree` モード時のみ `worktree-delete.sh` を呼び出す
- standard repo では偽の警告が出ないようにする

**Non-Goals:**
- `cleanup_worker` のその他の動作（tmux window kill、リモートブランチ削除）を変更しない
- `REPO_MODE` をスクリプト全体のグローバル変数として管理する（関数内ローカル判定で十分）

## Decisions

**決定: 関数内でローカルに `REPO_MODE` を判定する**

理由: `cleanup_worker` は複数の呼び出し元から使われるが、オーケストレーター全体の `REPO_MODE` をグローバル管理する設計変更は本 Issue のスコープを超える。ローカル判定なら変更範囲が最小限（`cleanup_worker` 関数のみ）で済む。

実装パターン（既存コードと統一）:
```bash
local repo_mode
if [[ "$(git rev-parse --git-dir 2>/dev/null)" == ".git" ]]; then
  repo_mode="standard"
else
  repo_mode="worktree"
fi
```

`worktree-delete.sh` の呼び出しを `if [[ "$repo_mode" == "worktree" ]]; then ... fi` でガードする。

## Risks / Trade-offs

- **リスク**: `git rev-parse` の実行コンテキストが `cleanup_worker` 呼び出し時の CWD に依存する。ただし orchestrator は常に bare repo の main/ から実行されるため、実用上は問題なし。
- **トレードオフ**: 関数ごとに判定を繰り返すため、将来的にグローバル管理へ移行する際に修正箇所が増える可能性がある。現時点では最小変更優先。
