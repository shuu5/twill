# Session Schema Reference

observer daemon およびsession管理が使用するJSONスキーマ定義。

## observer-daemon-heartbeat.json（Issue #1154）

`${SUPERVISOR_DIR}/observer-daemon-heartbeat.json` に `cld-observe-any` が 60 秒毎に atomic write する heartbeat ファイル。

### スキーマ

```json
{
  "writer": "cld-observe-any",
  "pid": 12345,
  "last_update": 1746000000,
  "host": "thinkpad",
  "version": "abc1234",
  "interval_sec": 60,
  "cycle_count": 42
}
```

### フィールド定義

| フィールド | 型 | 必須 | 説明 |
|-----------|-----|------|------|
| `writer` | string | ✓ | 常に `"cld-observe-any"`。`observer-parallel-check.sh` の writer 検証に使用 |
| `pid` | integer | ✓ | daemon プロセス PID (`$$`)。pgrep 結果との突合に使用 |
| `last_update` | integer | ✓ | epoch 秒（`date +%s`）。stale 判定の基準値 |
| `host` | string | ✓ | ホスト名（`$HOSTNAME`）。デバッグ用 |
| `version` | string | ✓ | git commit short hash。startup 時 1 回 capture（毎 cycle subprocess 回避） |
| `interval_sec` | integer | ✓ | 実際の heartbeat 周期秒（`HEARTBEAT_INTERVAL_SEC` の値） |
| `cycle_count` | integer | ✓ | メインループの累積 cycle 数。"daemon は生きているが loop が hang" の区別に使用 |

### 書き出しパターン（atomic write）

```bash
_emit_daemon_heartbeat() {
    local tmp_file
    tmp_file=$(mktemp "${SUPERVISOR_DIR}/observer-daemon-heartbeat.json.tmp.XXXXXX") || return 0
    printf '{"writer":"cld-observe-any","pid":%d,...}\n' ... > "$tmp_file" 2>/dev/null \
        || { rm -f "$tmp_file"; return 0; }
    mv "$tmp_file" "${CLD_OBSERVE_ANY_HEARTBEAT_PATH}" 2>/dev/null || rm -f "$tmp_file"
    return 0
}
```

tmpfile は `TMPFILES` に追加しない（`cleanup()` の rm 不在ファイル呼び出し回避）。

### 関連 env vars

| 変数 | 側 | デフォルト | 用途 |
|------|-----|----------|------|
| `HEARTBEAT_INTERVAL_SEC` | cld-observe-any | `60` | 周期（bats では `1` に短縮） |
| `CLD_OBSERVE_ANY_HEARTBEAT_PATH` | cld-observe-any | `${SUPERVISOR_DIR}/observer-daemon-heartbeat.json` | 書き出し先 override |
| `OBSERVER_PARALLEL_CHECK_DAEMON_HEARTBEAT_PATH` | observer-parallel-check.sh | `${SUPERVISOR_DIR}/observer-daemon-heartbeat.json` | 読み取り先 override |
| `OBSERVER_DAEMON_HEARTBEAT_STALE_SEC` | observer-parallel-check.sh | `120` | stale 閾値 override |
| `SUPERVISOR_DIR` | 両方 | `${PWD}/.supervisor` (daemon) / `.supervisor` (check) | base dir override |
