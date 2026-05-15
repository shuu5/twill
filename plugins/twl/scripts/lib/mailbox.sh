#!/usr/bin/env bash
# mailbox.sh — file mailbox helper (Phase 1 PoC C2 2026-05-15、Phase 6 review fix 統合)
#
# 仕様: spawn-protocol.html §5 (mailbox.sh template)
# 不変条件: Inv T (mailbox atomic write)、Inv V (per-specialist scope)、Inv H-2 (hook independence)
# verified pattern: plugins/twl/scripts/lib/session-atomic-write.sh L41-50 (flock + mktemp + mv)
#
# 4 API (source して使う、bash script として独立実行は想定しない):
#   mailbox_emit <from> <to> <event> <detail_json>  — atomic write 1 line (JSON Lines)、flock -x
#   mailbox_read <mailbox-name>                     — 未読 mail を stdout、read-offset 更新、flock -x (read + offset 更新を atomic、Phase 6 review C-1 fix)
#   mailbox_drain <mailbox-name> <callback-fn>      — 未読 mail を callback に 1 件ずつ渡す、callback 存在確認 (Phase 6 review W-2 fix)
#   mailbox_archive <mailbox-name>                  — inbox.jsonl を archive/ に移動、空 inbox skip (Phase 6 review W-3 fix)
#
# mailbox path 規約 (spawn-protocol.html §4.1):
#   .mailbox/administrator/inbox.jsonl     — administrator
#   .mailbox/phaser-<phase>-<issue>/inbox.jsonl  — phaser scope (TWL_PHASER_NAME env で識別)
#   .mailbox/archive/inbox-<name>-<ts>.jsonl     — 7 日 retention archive

set -euo pipefail
MAILBOX_ROOT="${TWILL_MAILBOX_ROOT:-.mailbox}"

mailbox_emit() {
    local from="$1" to="$2" event="$3" detail="$4"
    local target_dir="$MAILBOX_ROOT/$to"
    mkdir -p "$target_dir"
    local lock_file="$target_dir/.lock"
    local inbox="$target_dir/inbox.jsonl"

    # JSON Lines 1 行 (jq -c で compact、改行なし、--argjson で detail を JSON object として受取)
    local line
    line=$(jq -nc \
        --arg from "$from" --arg to "$to" \
        --arg event "$event" --argjson detail "$detail" \
        --arg ts "$(date -Iseconds)" \
        '{from: $from, to: $to, ts: $ts, event: $event, detail: $detail}')

    # flock atomic append (timeout 10s、fd 9、verified pattern)
    (
        flock -x -w 10 9 || exit 1
        echo "$line" >> "$inbox"
    ) 9>>"$lock_file"
}

mailbox_read() {
    local mailbox="$1"
    local inbox="$MAILBOX_ROOT/$mailbox/inbox.jsonl"
    local offset_file="$MAILBOX_ROOT/$mailbox/.read-offset"
    local lock_file="$MAILBOX_ROOT/$mailbox/.lock"

    [ -f "$inbox" ] || return 0
    mkdir -p "$(dirname "$lock_file")"

    # Phase 6 review C-1 fix: flock -x で offset 取得 + tail + offset 更新を atomic に
    # (旧 -s shared lock では複数 reader race で offset 二重書き or 重複読み取り risk)
    (
        flock -x -w 10 9 || exit 1
        local from total
        from=$(cat "$offset_file" 2>/dev/null || echo 0)
        # offset 取得 → tail → 行数 count → offset 更新を全て exclusive lock 内で実行
        tail -n +$((from + 1)) "$inbox"
        total=$(wc -l < "$inbox")
        echo "$total" > "$offset_file"
    ) 9>>"$lock_file"
}

mailbox_drain() {
    local mailbox="$1" callback_fn="$2"

    # Phase 6 review W-2 fix: callback 存在確認 (未定義 function で silent skip 回避)
    if ! declare -f "$callback_fn" > /dev/null 2>&1; then
        echo "mailbox_drain: callback function '$callback_fn' not defined" >&2
        return 1
    fi

    mailbox_read "$mailbox" | while IFS= read -r line; do
        [ -z "$line" ] && continue
        "$callback_fn" "$line"
    done
}

mailbox_archive() {
    local mailbox="$1"
    local inbox="$MAILBOX_ROOT/$mailbox/inbox.jsonl"
    local archive_dir="$MAILBOX_ROOT/archive"

    # Phase 6 review W-3 fix: 空 inbox は archive skip (size > 0 check)
    [ -s "$inbox" ] || return 0

    mkdir -p "$archive_dir"
    local ts
    ts=$(date +%Y%m%dT%H%M%S)
    mv "$inbox" "$archive_dir/inbox-${mailbox}-${ts}.jsonl"
    rm -f "$MAILBOX_ROOT/$mailbox/.read-offset"
}
