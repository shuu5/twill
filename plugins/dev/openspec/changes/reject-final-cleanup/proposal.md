## Why

`merge-gate --reject-final`（確定失敗判定）後、orchestratorのループで`status=failed`かつ`retry_count>=2`の条件下でも`cleanup_worker`が呼ばれないため、worktreeとリモートブランチが残存し続ける。これによりディスク領域の無駄遣いとブランチ汚染が発生する。

## What Changes

- `scripts/autopilot-orchestrator.sh`のmerge-gate後ループに、`status=failed`かつ`retry_count>=2`の場合に`cleanup_worker`を呼ぶ処理を追加する

## Capabilities

### New Capabilities

- `--reject-final`後の確定失敗時にも`cleanup_worker`が呼ばれ、worktreeとリモートブランチが自動削除される

### Modified Capabilities

- `autopilot-orchestrator.sh`のmerge-gate後処理ロジック：`status=failed`パスでもクリーンアップを実行するよう拡張

## Impact

- **変更ファイル**: `scripts/autopilot-orchestrator.sh`
- **影響範囲**: autopilot実行時のfailureハンドリングのみ。正常系・通常失敗（retry対象）には影響なし
- **依存**: `cleanup_worker`関数（既存）、`state-read.sh`（`retry_count`読み取り）
