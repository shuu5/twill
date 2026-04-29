#!/usr/bin/env bash
# session-init.sh: SupervisorSession の新規作成
# 処理: .supervisor/session.json 生成 + claude_session_id 取得 + twl audit on
# 環境変数:
#   SUPERVISOR_DIR (default: .supervisor): session.json 出力先

set -euo pipefail

SUPERVISOR_DIR="${SUPERVISOR_DIR:-.supervisor}"
mkdir -p "$SUPERVISOR_DIR"

# Claude Code session ID と tmux window 名を取得
PROJECT_HASH=$(pwd | sed 's|/|-|g')
CLAUDE_SESSION_ID_VAL=$(ls -t ~/.claude/projects/${PROJECT_HASH}/*.jsonl 2>/dev/null \
  | head -1 | xargs -r basename 2>/dev/null | sed 's|\.jsonl$||' || echo "")
OBSERVER_WINDOW_NAME=$(tmux display-message -p '#W' 2>/dev/null || echo "")

# 親プロセス (cld 本体) から --permission-mode を抽出（/proc/$PPID/cmdline 経由、self-pid ベース）
OBSERVER_MODE=""
if [[ -r "/proc/$PPID/cmdline" ]]; then
  OBSERVER_MODE=$(tr '\0' ' ' < "/proc/$PPID/cmdline" \
    | grep -oP '(?:--permission-mode\s+)\K\S+' || echo "")
fi

# session.json に書き込む
python3 -c "
import json, datetime, os, uuid
supervisor_dir = os.environ.get('SUPERVISOR_DIR', '.supervisor')
claude_session_id = os.environ.get('CLAUDE_SESSION_ID_VAL', '')
observer_window = os.environ.get('OBSERVER_WINDOW_NAME', '')
observer_mode = os.environ.get('OBSERVER_MODE', '')
session_file = os.path.join(supervisor_dir, 'session.json')
data = {
  'session_id': str(uuid.uuid4()),
  'claude_session_id': claude_session_id,
  'observer_window': observer_window,
  'mode': observer_mode,
  'status': 'active',
  'started_at': datetime.datetime.utcnow().isoformat() + 'Z'
}
json.dump(data, open(session_file, 'w'), indent=2)
print(f'[session-init] session.json 作成: {session_file}')
" CLAUDE_SESSION_ID_VAL="$CLAUDE_SESSION_ID_VAL" OBSERVER_WINDOW_NAME="$OBSERVER_WINDOW_NAME" OBSERVER_MODE="$OBSERVER_MODE"

# audit on（CLAUDE_SESSION_ID_VAL を run-id として使用）
if [[ -n "$CLAUDE_SESSION_ID_VAL" ]]; then
  twl audit on --run-id "$CLAUDE_SESSION_ID_VAL" 2>/dev/null || true
else
  twl audit on 2>/dev/null || true
fi

echo "[session-init] 初期化完了。claude_session_id=${CLAUDE_SESSION_ID_VAL:-<unknown>}"
