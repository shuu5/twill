#!/usr/bin/env bash
# session-resume-observer-check.sh - SessionStart hook: cld-observe-any 死活確認 + 自動再起動
# Issue #1147: SessionStart resume hook に cld-observe-any 死活確認 + 自動再起動

set -uo pipefail

# CWD を git toplevel に移動（SessionStart 時は任意 CWD の可能性あり）
cd "$(git rev-parse --show-toplevel)" || exit 1

SUPERVISOR_DIR="${SUPERVISOR_DIR:-.supervisor}"
SESSION_JSON="${SUPERVISOR_DIR}/session.json"

# session.json 不在 → observer 未起動 host = no-op
[[ ! -f "$SESSION_JSON" ]] && exit 0

# session.json から cld_observe_any フィールドを読み取る
PID=$(jq -r '.cld_observe_any.pid // empty' "$SESSION_JSON" 2>/dev/null || echo "")
PANE_ID=$(jq -r '.cld_observe_any.pane_id // empty' "$SESSION_JSON" 2>/dev/null || echo "")
SPAWN_CMD=$(jq -r '.cld_observe_any.spawn_cmd // empty' "$SESSION_JSON" 2>/dev/null || echo "")
LOCK_FILE=$(jq -r '.cld_observe_any.lock_path // "/tmp/cld-observe-any.lock"' "$SESSION_JSON" 2>/dev/null || echo "/tmp/cld-observe-any.lock")

# PID 未記録 → observer 未起動 = no-op
[[ -z "$PID" ]] && exit 0

# PID 生存確認: kill -0 で確認（生存なら exit 0）
if kill -0 "$PID" 2>/dev/null; then
    exit 0
fi

# PID 死亡 → lock ファイルをクリアして respawn を試みる
rm -f "$LOCK_FILE" "${LOCK_FILE}.pid"

# spawn_cmd が未記録の場合は再起動不能 → error log + exit 1
if [[ -z "$SPAWN_CMD" ]]; then
    echo "[session-resume-hook] ERROR: spawn_cmd が session.json に未記録。手動再起動が必要" >&2
    exit 1
fi

# pane の存在確認
PANE_EXISTS=false
if [[ -n "$PANE_ID" ]] && tmux list-panes -a -F "#{pane_id}" 2>/dev/null | grep -qx "$PANE_ID"; then
    PANE_EXISTS=true
fi

if [[ "$PANE_EXISTS" == "true" ]]; then
    # pane 存在 → tmux respawn-pane で再起動
    if tmux respawn-pane -k -t "$PANE_ID" "$SPAWN_CMD"; then
        # 新 PID を取得して session.json を更新
        new_pid=$(tmux display-message -t "$PANE_ID" -p '#{pane_pid}' 2>/dev/null || echo "")
        if [[ -f "$SESSION_JSON" && -n "$new_pid" ]]; then
            tmp_file=$(mktemp)
            jq --arg pid "$new_pid" \
               --arg started_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
               '.cld_observe_any.pid = ($pid | tonumber? // null) |
                .cld_observe_any.started_at = $started_at' \
               "$SESSION_JSON" > "$tmp_file" && mv "$tmp_file" "$SESSION_JSON" || rm -f "$tmp_file"
        fi
    else
        # respawn 失敗 → daemon-startup-failed.json を出力
        mkdir -p "${SUPERVISOR_DIR}/events"
        jq -n \
           --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
           --arg reason "tmux respawn-pane failed" \
           --arg pid_old "${PID:-}" \
           --argjson pid_new null \
           --arg error_log "tmux respawn-pane -k -t ${PANE_ID} failed with non-zero exit" \
           '{timestamp: $ts, reason: $reason, pid_old: $pid_old, pid_new: $pid_new, error_log: $error_log}' \
           > "${SUPERVISOR_DIR}/events/daemon-startup-failed.json"
    fi
else
    # pane 消失 → 再起動不能を記録して graceful exit
    mkdir -p "${SUPERVISOR_DIR}/events"
    jq -n \
       --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       --arg reason "pane not found" \
       --arg pane_id "${PANE_ID:-}" \
       '{timestamp: $ts, reason: $reason, pane_id: $pane_id}' \
       > "${SUPERVISOR_DIR}/events/daemon-restart-skipped.json"
fi
