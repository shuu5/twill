#!/usr/bin/env bash
# session-init.sh: SupervisorSession の新規作成
# 処理: .supervisor/session.json 生成 + claude_session_id 取得 + twl audit on
# 環境変数:
#   SUPERVISOR_DIR (default: .supervisor): session.json 出力先

set -euo pipefail

SUPERVISOR_DIR="${SUPERVISOR_DIR:-.supervisor}"
# パストラバーサル防止（step0-monitor-bootstrap.sh に合わせたバリデーション）
if [[ ! "$SUPERVISOR_DIR" =~ ^[a-zA-Z0-9._/=-]+$ ]] || [[ "$SUPERVISOR_DIR" == *..* ]]; then
  echo "[session-init] ERROR: SUPERVISOR_DIR に不正な文字または '..' が含まれています: $SUPERVISOR_DIR" >&2
  exit 1
fi
mkdir -p "$SUPERVISOR_DIR"

# Claude Code session ID と tmux window 名を取得
PROJECT_HASH=$(pwd | sed 's|/|-|g')
CLAUDE_SESSION_ID_VAL=$(ls -t ~/.claude/projects/${PROJECT_HASH}/*.jsonl 2>/dev/null \
  | head -1 | xargs -r basename 2>/dev/null | sed 's|\.jsonl$||' || echo "")
OBSERVER_WINDOW_NAME=$(tmux display-message -p '#W' 2>/dev/null || echo "")

# 親プロセス (cld 本体) から permission mode を抽出
# 優先順: SESSION_INIT_CMDLINE_OVERRIDE（テスト用後方互換）
#        → pgrep -f claude でプロセスツリーを辿る（bash subshell 対応 #1459）
#        → /proc/$PPID/cmdline フォールバック（既存動作）
# SESSION_INIT_PGREP_PROC_DIR: fake /proc ルート（テスト用、default: /proc）
_PROC_DIR="${SESSION_INIT_PGREP_PROC_DIR:-/proc}"
OBSERVER_MODE=""

_parse_cmdline_for_mode() {
  local cmdline="$1"
  if echo "$cmdline" | grep -q -- '--dangerously-skip-permissions'; then
    echo "bypass"
    return
  fi
  local raw=""
  raw=$(echo "$cmdline" | grep -oP '(?:--permission-mode )\K\S+' || echo "")
  case "$raw" in
    bypassPermissions) echo "bypass" ;;
    acceptEdits)       echo "auto" ;;
    auto|bypass|default|plan) echo "$raw" ;;
    *)                 echo "" ;;
  esac
}

if [[ -n "${SESSION_INIT_CMDLINE_OVERRIDE:-}" ]]; then
  OBSERVER_MODE=$(_parse_cmdline_for_mode "$SESSION_INIT_CMDLINE_OVERRIDE")
else
  # pgrep でプロセスツリーを辿って claude プロセスを検索
  _CLAUDE_PIDS=$(pgrep -f 'claude' 2>/dev/null || true)
  for _PID in $_CLAUDE_PIDS; do
    if [[ -r "${_PROC_DIR}/${_PID}/cmdline" ]]; then
      _CMD=$(tr '\0' ' ' < "${_PROC_DIR}/${_PID}/cmdline")
      _MODE=$(_parse_cmdline_for_mode "$_CMD")
      if [[ -n "$_MODE" ]]; then
        OBSERVER_MODE="$_MODE"
        break
      fi
    fi
  done
  # pgrep ヒットなし or mode 未検出: $PPID/cmdline にフォールバック（既存動作）
  if [[ -z "$OBSERVER_MODE" && -r "${_PROC_DIR}/$PPID/cmdline" ]]; then
    _PPID_CMD=$(tr '\0' ' ' < "${_PROC_DIR}/$PPID/cmdline")
    OBSERVER_MODE=$(_parse_cmdline_for_mode "$_PPID_CMD")
  fi
fi

[[ -z "$OBSERVER_MODE" ]] && echo "[session-init] WARN: permission mode が cmdline に見つかりません（mode は空文字で記録）" >&2 || true

# session.json に書き込む（env var prefix 形式で Python に変数を渡す）
CLAUDE_SESSION_ID_VAL="$CLAUDE_SESSION_ID_VAL" \
OBSERVER_WINDOW_NAME="$OBSERVER_WINDOW_NAME" \
OBSERVER_MODE="$OBSERVER_MODE" \
python3 -c "
import json, datetime, os, uuid, re, sys
supervisor_dir = os.environ.get('SUPERVISOR_DIR', '.supervisor')
claude_session_id = os.environ.get('CLAUDE_SESSION_ID_VAL', '')
observer_window = os.environ.get('OBSERVER_WINDOW_NAME', '')
observer_mode = os.environ.get('OBSERVER_MODE', '')
session_file = os.path.join(supervisor_dir, 'session.json')
_UUID_V4_RE = re.compile(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
if claude_session_id and not _UUID_V4_RE.match(claude_session_id):
    print(f'[session-init] WARN: invalid claude_session_id rejected: {claude_session_id}', file=sys.stderr)
    claude_session_id = ''
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
