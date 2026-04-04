## Why

Worker終了後のクリーンアップ処理（tmux window削除 → worktree削除 → リモートブランチ削除）が `merge-gate-execute.sh` と `autopilot-phase-execute.md` に分散しており、Pilotが「worktreeを作成するが削除しない」という不一貫なライフサイクル管理になっている。これを Pilot 側に集約することで、worktreeのライフサイクル全体をPilotが統括する一貫したモデルを実現する。

## What Changes

- `scripts/merge-gate-execute.sh`: autopilot時のクリーンアップ処理（worktree削除 + リモートブランチ削除 + tmux kill-window）をスキップするIS_AUTOPILOT分岐を追加
- `scripts/autopilot-orchestrator.sh`: merge-gate成功後のクリーンアップステップ（tmux kill-window → worktree-delete.sh → git push --delete）を追加
- `commands/autopilot-phase-execute.md`: tmux kill-windowの重複呼び出しを排除

## Capabilities

### New Capabilities

- **Pilot-side cleanup**: autopilot実行時、merge-gate成功後にPilotが自律的にtmux window / worktree / リモートブランチを順次削除する
- **Cross-repo cleanup**: issue-{N}.jsonのrepo情報を参照し、クロスリポジトリIssueでも正しいリポジトリに対してcleanupを実行する
- **冪等なcleanup**: 既に削除済みのtmux window / worktreeへの操作を正常扱いし、各ステップの失敗を個別に警告して残りを続行する

### Modified Capabilities

- **merge-gate-execute.sh cleanup**: autopilot時はスキップ、非autopilot時は従来どおり動作（手動mergeフローを維持）

## Impact

- `scripts/merge-gate-execute.sh` — IS_AUTOPILOT分岐の追加（L125-145付近）
- `scripts/autopilot-orchestrator.sh` — merge-gate成功後のcleanupシーケンス追加
- `scripts/worktree-delete.sh` — Pilotからの呼び出し互換性確認（インターフェース変更なし）
- `commands/autopilot-phase-execute.md` — tmux kill-windowの重複排除
