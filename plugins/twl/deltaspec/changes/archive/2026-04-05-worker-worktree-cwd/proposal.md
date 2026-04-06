## Why

Worker の cld セッションが main/ から起動されるため、Claude Code の CWD リセット時に `git branch --show-current` が `main` を返し IS_AUTOPILOT=false となって chain が停止する。Worker を worktree ディレクトリから起動すれば CWD リセット後も正しいブランチで動作し続ける。

## What Changes

- `autopilot-orchestrator.sh`: Worker 起動前に Pilot 側で `worktree-create.sh` を実行し、worktree パスを `autopilot-launch.sh` に渡す
- `autopilot-launch.sh`: `--worktree-dir DIR` 引数を追加し LAUNCH_DIR を worktree パスに設定
- `skills/workflow-setup/SKILL.md`: Step 2（worktree-create）を除去（Pilot が事前作成済みのため）
- `scripts/chain-steps.sh`: Worker 側の chain 定義から `worktree-create` ステップを除去
- `architecture/domain/contexts/autopilot.md`: 不変条件B を「作成・削除ともに Pilot 専任」に更新
- `deps.yaml`: コンポーネント依存関係を更新
- `tests/`: chain-steps, invariants テストの期待値更新

## Capabilities

### New Capabilities

- Worker の cld セッションが worktree ディレクトリで起動される
- CWD リセット後も `git branch --show-current` が正しいブランチ名を返す（single repo / cross-repo 両方）

### Modified Capabilities

- worktree 作成タイミングが「Worker が chain で行う」→「Pilot が Worker 起動前に行う」に変更
- 既存 worktree がある場合のリトライ/再開が冪等に動作する

## Impact

- `scripts/autopilot-orchestrator.sh` — worktree-create 追加、worktree パス渡し
- `scripts/autopilot-launch.sh` — `--worktree-dir` 引数追加、LAUNCH_DIR 計算変更
- `skills/workflow-setup/SKILL.md` — worktree-create ステップ除去、推奨アクション分岐調整
- `scripts/chain-runner.sh` — worktree-create の Worker 内呼び出し調整
- `scripts/chain-steps.sh` — chain 定義変更
- `architecture/domain/contexts/autopilot.md` — 不変条件B 更新
- `deps.yaml` — コンポーネント依存関係の更新
- `tests/` — chain-runner-next-step.bats, autopilot-invariants.bats の期待値更新
