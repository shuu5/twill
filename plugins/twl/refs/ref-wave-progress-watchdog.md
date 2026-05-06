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
