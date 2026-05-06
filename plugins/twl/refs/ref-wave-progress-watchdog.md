# wave-progress-watchdog.sh リファレンス (#1429)

Wave PR 進行を監視し、current_wave の全 Issue が merged された時点で次 Wave を自動 spawn するデーモン。

## 起動方法

```bash
# opt-in 起動（バックグラウンド）
WAVE_PROGRESS_WATCHDOG_ENABLED=1 \
  SUPERVISOR_DIR=.supervisor \
  bash plugins/twl/skills/su-observer/scripts/wave-progress-watchdog.sh &
```

su-observer が Wave N を spawn した直後に起動する。heartbeat-watcher.sh と同様、`&` でバックグラウンド実行する。

## 環境変数

| 変数 | デフォルト | 説明 |
|------|---------|------|
| `WAVE_PROGRESS_WATCHDOG_ENABLED` | `0` | **必須 opt-in フラグ**。`1` 以外は起動しない |
| `SUPERVISOR_DIR` | `.supervisor` | supervisor ディレクトリ |
| `WAVE_QUEUE_FILE` | `${SUPERVISOR_DIR}/wave-queue.json` | wave-queue.json パス |
| `POLL_INTERVAL_SEC` | `30` | イベント polling 間隔（秒） |
| `AUTO_NEXT_SPAWN_SCRIPT` | `${SCRIPT_DIR}/auto-next-spawn.sh` | spawn スクリプトパス |
| `AUTOPILOT_DIR` | `.autopilot` | autopilot ディレクトリ |

## lock / PID / cleanup

### lock ファイル

- パス: `.supervisor/locks/wave-progress-watchdog.lock`
- `flock -n` で非ブロッキング取得。取得失敗時（二重起動）は即 exit（skip）

### PID ファイル

- パス: `.supervisor/watcher-pid-wave-progress`
- context-budget-monitor.sh が `watcher-pid-*` パターンで参照して kill する互換形式
- SIGTERM/EXIT trap で自動削除

### 停止方法

```bash
# PID ファイルから kill
kill "$(cat .supervisor/watcher-pid-wave-progress)"

# または context-budget-monitor.sh が自動 kill（BUDGET_THRESHOLD 到達時）
```

## completed-flag の説明

- パス: `.supervisor/locks/wave-N-completed.flag`（N = wave 番号）
- wave N の spawn が完了したことを示す idempotency フラグ
- 同一 wave に対して auto-next-spawn.sh を 2 回以上呼び出すことを防ぐ
- 手動リセット: `rm .supervisor/locks/wave-N-completed.flag`

### #1447 変更点（--target-wave と flag set 責務の移管）

`wave-progress-watchdog.sh` の `_invoke_auto_next_spawn` から `_mark_wave_completed` 呼び出しを削除し、代わりに `--target-wave N` フラグを `auto-next-spawn.sh` に渡すようにした。flag set の責務が watchdog 側から spawn スクリプト側へ移管された。

- **flag set 主体**: `auto-next-spawn.sh` が dequeue 永続化成功直後（queue 書き込み後）に `touch wave-N-completed.flag` を実行する
- **skip 動作（第一防衛線）**: `--target-wave N` 指定時、dequeue 直前に `queue[0].wave == N` を再検証。不一致なら `exit 0`（副作用なし、介入ログに `target_wave_mismatch` を記録）
- **skip 動作（第二防衛線）**: dequeue 直前に `wave-N-completed.flag` の存在を再確認。既存なら `exit 0`（介入ログに `wave_already_completed` を記録）。watchdog 多重起動時の二重 dequeue を防ぐ
- **rollback 動作**: `exec` 失敗時（通常は到達しない）は queue を元に戻し、同時に flag も `rm -f` する（exec 失敗 → flag 残留による永久 skip を防止）
- **後方互換**: `--target-wave` 未指定時は従来通り（flag set / rm なし、無条件 dequeue）

## enable 後の動作確認手順

1. `WAVE_PROGRESS_WATCHDOG_ENABLED=1` を設定して起動
2. PID ファイルが作成されることを確認:
   ```bash
   cat .supervisor/watcher-pid-wave-progress
   ```
3. テスト用イベントファイルを作成して動作確認:
   ```bash
   # wave-queue.json で current_wave=1、wave=1 に issues=[100] がある状態で:
   touch .supervisor/events/wave-1-pr-merged-100.json
   # POLL_INTERVAL_SEC 秒後に auto-next-spawn.sh が呼ばれることを確認
   ```
4. ログ確認:
   ```bash
   # 起動直後の標準エラーに "[wave-progress-watchdog] 起動:" が出力される
   ```
5. 停止確認:
   ```bash
   kill "$(cat .supervisor/watcher-pid-wave-progress)"
   # PID ファイルが削除されることを確認
   ls .supervisor/watcher-pid-wave-progress  # → No such file
   ```
