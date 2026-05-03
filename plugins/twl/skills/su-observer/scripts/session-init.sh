#!/usr/bin/env bash
# session-init.sh: SupervisorSession の新規作成
# 処理: .supervisor/session.json 生成 + claude_session_id 取得 + twl audit on
# 環境変数:
#   SUPERVISOR_DIR (default: .supervisor): session.json 出力先

set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# shellcheck source=/dev/null
source "$_SCRIPT_DIR/../../../scripts/lib/supervisor-dir-validate.sh"
SUPERVISOR_DIR="${SUPERVISOR_DIR:-.supervisor}"
validate_supervisor_dir "$SUPERVISOR_DIR" || exit 1
mkdir -p "$SUPERVISOR_DIR"

# Claude Code session ID と tmux window 名を取得
PROJECT_HASH=$(pwd | sed 's|/|-|g')
CLAUDE_SESSION_ID_VAL=$(ls -t ~/.claude/projects/${PROJECT_HASH}/*.jsonl 2>/dev/null \
  | head -1 | xargs -r basename 2>/dev/null | sed 's|\.jsonl$||' || echo "")
OBSERVER_WINDOW_NAME=$(tmux display-message -p '#W' 2>/dev/null || echo "")

# 親プロセス (cld 本体) から permission mode を抽出（/proc/$PPID/cmdline 経由）
# SESSION_INIT_CMDLINE_OVERRIDE が設定されている場合はそちらを使用（テスト用）
OBSERVER_MODE=""
_CMDLINE_SRC="${SESSION_INIT_CMDLINE_OVERRIDE:-}"
if [[ -z "$_CMDLINE_SRC" && -r "/proc/$PPID/cmdline" ]]; then
  _CMDLINE_SRC=$(tr '\0' ' ' < "/proc/$PPID/cmdline")
fi
if [[ -n "$_CMDLINE_SRC" ]]; then
  if echo "$_CMDLINE_SRC" | grep -q -- '--dangerously-skip-permissions'; then
    # cld のデフォルト起動経路（PR #804 revert 後）
    OBSERVER_MODE="bypass"
  else
    _RAW_MODE=$(echo "$_CMDLINE_SRC" | grep -oP '(?:--permission-mode )\K\S+' || echo "")
    # 許可値のみを通過させる（ホワイトリスト）
    case "$_RAW_MODE" in
      bypassPermissions) OBSERVER_MODE="bypass" ;;
      acceptEdits)       OBSERVER_MODE="auto" ;;
      auto|bypass|default|plan) OBSERVER_MODE="$_RAW_MODE" ;;
      *)                 OBSERVER_MODE="" ;;
    esac
  fi
  [[ -z "$OBSERVER_MODE" ]] && echo "[session-init] WARN: permission mode が cmdline に見つかりません（mode は空文字で記録）" >&2 || true
fi

# session.json に書き込む（env var prefix 形式で Python に変数を渡す）
CLAUDE_SESSION_ID_VAL="$CLAUDE_SESSION_ID_VAL" \
OBSERVER_WINDOW_NAME="$OBSERVER_WINDOW_NAME" \
OBSERVER_MODE="$OBSERVER_MODE" \
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
  'started_at': datetime.datetime.utcnow().isoformat() + 'Z',
  'cld_observe_any': {
    'pid': None,
    'pane_id': None,
    'spawn_cmd': None,
    'started_at': None,
    'log_path': None,
    'lock_path': '/tmp/cld-observe-any.lock'
  }
}
json.dump(data, open(session_file, 'w'), indent=2)
print(f'[session-init] session.json 作成: {session_file}')
"

# audit on（CLAUDE_SESSION_ID_VAL を run-id として使用）
if [[ -n "$CLAUDE_SESSION_ID_VAL" ]]; then
  twl audit on --run-id "$CLAUDE_SESSION_ID_VAL" 2>/dev/null || true
else
  twl audit on 2>/dev/null || true
fi

echo "[session-init] 初期化完了。claude_session_id=${CLAUDE_SESSION_ID_VAL:-<unknown>}"
