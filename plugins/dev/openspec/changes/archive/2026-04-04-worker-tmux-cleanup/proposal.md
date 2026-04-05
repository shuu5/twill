## Why

autopilot Worker が done/failed になった後、`remain-on-exit on` の設定により tmux window が残存し、merge-gate-execute.sh を経由しないケース（手動 merge、reject、poll タイムアウト）ではリモートブランチも削除されない。これにより、セッション終了後に不要な window と branch がクリーンアップされずに蓄積される。

## What Changes

- `scripts/autopilot-orchestrator.sh`: `poll_single` / `poll_phase` の done/failed 検知後に tmux kill-window + remote branch delete を追加
- `scripts/merge-gate-execute.sh`: `--reject` / `--reject-final` モード時に tmux kill-window を追加

## Capabilities

### New Capabilities

- Worker が done/failed になった時点で tmux window `ap-#N` を自動削除
- merge 完了後にリモートブランチを自動削除（orchestrator 経由の場合）
- merge-gate reject 時にも tmux window を削除
- poll タイムアウト時にも tmux window を削除

### Modified Capabilities

- `autopilot-orchestrator.sh` の `poll_single`（done 検知）および `poll_phase`（done/failed 検知）にクリーンアップ処理を追加
- `merge-gate-execute.sh` の reject パスにクリーンアップ処理を追加

## Impact

- 影響ファイル: `scripts/autopilot-orchestrator.sh`, `scripts/merge-gate-execute.sh`
- スコープ外: `auto-merge.sh`, `co-autopilot SKILL.md`（変更不要）
- 不変条件 G（remain-on-exit on によるクラッシュ検知）は維持。明示的な kill-window で対応
