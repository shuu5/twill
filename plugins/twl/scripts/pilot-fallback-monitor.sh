#!/usr/bin/env bash
# pilot-fallback-monitor.sh — orchestrator unavailable 時の Pilot fallback daemon
#
# Issue #1128: BUDGET-LOW recovery で orchestrator killed 後の自動復旧
#   Bug A: Worker chain advancement の自動 inject（AC-1）
#   Bug C: PR merged 後 Worker window 即時 cleanup（AC-3）
#
# 設計制約（不変条件 M 準拠）:
#   - orchestrator unavailable 時のみ起動（alive 時は即終了）
#   - "chain 復旧" inject のみ許可（nudge は引き続き禁止）
#   - inject テキストは /twl:workflow-[a-z][a-z0-9-]* のみ（allow-list）
#   - Worker の直接実装代行は禁止（不変条件 K）
#
# Usage:
#   bash pilot-fallback-monitor.sh [OPTIONS]
#   bash pilot-fallback-monitor.sh --once --worker <window>                           # AC-2 テスト用
#   bash pilot-fallback-monitor.sh --once --cleanup --worker <window> --issue <N>     # AC-4 テスト用
#
# Options:
#   --once              1回ループして終了（daemon ループなし、テスト用）
#   --cleanup           PR merged cleanup モード（inject をスキップし cleanup のみ）
#   --worker <window>   対象 Worker window 名
#   --issue <N>         対象 Issue 番号
#   --autopilot-dir <d> .autopilot ディレクトリ（デフォルト: .autopilot）
#   --no-orchestrator-check  orchestrator alive チェックをスキップ（テスト用）

set -uo pipefail

# ---------------------------------------------------------------------------
# 定数（SLA 定義: POLL_INTERVAL × MAX_RETRY ≤ 30s）
# ---------------------------------------------------------------------------
POLL_INTERVAL=10
POLL_INTERVAL="${PILOT_FALLBACK_POLL_INTERVAL:-${POLL_INTERVAL}}"
MAX_RETRY=2
MAX_RETRY="${PILOT_FALLBACK_MAX_RETRY:-${MAX_RETRY}}"
# SLA 論理積: POLL_INTERVAL(10) × MAX_RETRY(2) = 20 ≤ 30s ✓

AUTOPILOT_DIR="${AUTOPILOT_DIR:-.autopilot}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
SESSION_DIR="$(cd "${SCRIPT_DIR}/../../session/scripts" 2>/dev/null && pwd || echo "")"

# PID file（daemon 多重起動防止）
PID_FILE="${AUTOPILOT_DIR}/pilot-fallback-monitor.pid"

# ---------------------------------------------------------------------------
# 引数パース
# ---------------------------------------------------------------------------
ONCE_MODE=false
CLEANUP_MODE=false
WORKER_WINDOW="${WORKER_WINDOW:-}"
ISSUE_NUM="${ISSUE_NUM:-}"
SKIP_ORCH_CHECK=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --once)              ONCE_MODE=true ;;
    --cleanup)           CLEANUP_MODE=true ;;
    --worker)            WORKER_WINDOW="${2:-}"; shift ;;
    --issue)             ISSUE_NUM="${2:-}"; shift ;;
    --autopilot-dir)     AUTOPILOT_DIR="${2:-}"; shift ;;
    --no-orchestrator-check) SKIP_ORCH_CHECK=true ;;
    *) echo "[pilot-fallback-monitor] WARN: unknown option: $1" >&2 ;;
  esac
  shift
done

# ---------------------------------------------------------------------------
# orchestrator alive チェック（不変条件 M: unavailable 時のみ動作）
# orchestrator alive 時は即終了
# ---------------------------------------------------------------------------
_is_orchestrator_alive() {
  local orch_pid
  orch_pid=$(cat "${AUTOPILOT_DIR}/orchestrator.pid" 2>/dev/null || echo "")
  if [[ "$orch_pid" =~ ^[1-9][0-9]*$ ]]; then
    kill -0 "$orch_pid" 2>/dev/null && return 0
  fi
  return 1
}

if [[ "$SKIP_ORCH_CHECK" != "true" ]] && _is_orchestrator_alive; then
  echo "[pilot-fallback-monitor] orchestrator alive — 自動停止（不変条件 M: unavailable 時のみ動作）" >&2
  exit 0
fi

# ---------------------------------------------------------------------------
# PID file 管理（daemon 多重起動防止）
# ---------------------------------------------------------------------------
mkdir -p "$(dirname "$PID_FILE")" 2>/dev/null || true

if [[ "$ONCE_MODE" != "true" ]]; then
  if [[ -f "$PID_FILE" ]]; then
    existing_pid=$(cat "$PID_FILE" 2>/dev/null || echo "")
    if [[ "$existing_pid" =~ ^[1-9][0-9]*$ ]] && kill -0 "$existing_pid" 2>/dev/null; then
      echo "[pilot-fallback-monitor] 既存 daemon (PID $existing_pid) が実行中 — スキップ" >&2
      exit 0
    fi
  fi
  echo $$ > "$PID_FILE"
  trap 'rm -f "$PID_FILE"' EXIT
fi

# ---------------------------------------------------------------------------
# session-comm.sh 解決（PATH 優先でテスト stub を正しく検出）
# ---------------------------------------------------------------------------
_resolve_session_comm() {
  # PATH lookup 優先（STUB_BIN が PATH に追加されている場合にテスト stub を使用）
  local via_path
  via_path=$(command -v session-comm.sh 2>/dev/null || echo "")
  if [[ -n "$via_path" ]]; then
    echo "$via_path"
    return 0
  fi
  # フォールバック: SCRIPT_DIR からの相対パス
  if [[ -n "$SESSION_DIR" && -f "${SESSION_DIR}/session-comm.sh" ]]; then
    echo "${SESSION_DIR}/session-comm.sh"
    return 0
  fi
  echo ""
}

# ---------------------------------------------------------------------------
# observer-window-check.sh ライブラリ読み込み
# ---------------------------------------------------------------------------
_load_window_check_lib() {
  local lib="${LIB_DIR}/observer-window-check.sh"
  if [[ -f "$lib" ]]; then
    # shellcheck source=/dev/null
    source "$lib"
    return 0
  fi
  return 1
}

# ---------------------------------------------------------------------------
# inject 判定ロジック（AC-1）
# ---------------------------------------------------------------------------
_inject_next_workflow() {
  local window="$1"
  local issue="${2:-}"

  # NEXT_WORKFLOW env var: テスト用オーバーライド（production: 未設定）
  local next_skill="${NEXT_WORKFLOW:-}"

  if [[ -z "$next_skill" && -n "$issue" ]]; then
    # resolve_next_workflow で次 workflow を決定（ADR-018）
    local next_exit=0
    next_skill=$(python3 -m twl.autopilot.resolve_next_workflow --issue "$issue" 2>/dev/null) \
      || next_exit=$?
    if [[ "$next_exit" -ne 0 || -z "$next_skill" ]]; then
      echo "[pilot-fallback-monitor] Issue #${issue}: resolve_next_workflow 未解決 (exit=${next_exit})" >&2
      return 1
    fi
  fi

  if [[ -z "$next_skill" ]]; then
    echo "[pilot-fallback-monitor] WARN: next workflow 未解決 — スキップ" >&2
    return 1
  fi

  # allow-list バリデーション（コマンドインジェクション防止）
  local skill_safe="${next_skill//$'\n'/}"
  if [[ ! "$skill_safe" =~ ^/twl:workflow-[a-z][a-z0-9-]*$ ]]; then
    echo "[pilot-fallback-monitor] Issue #${issue}: 不正な skill '${skill_safe:0:100}' — スキップ" >&2
    return 1
  fi

  # session-comm.sh 解決（PATH 優先）
  local session_comm
  session_comm=$(_resolve_session_comm)
  if [[ -z "$session_comm" ]]; then
    echo "[pilot-fallback-monitor] WARN: session-comm.sh が見つからない" >&2
    return 1
  fi

  # session-comm.sh inject で workflow を注入
  echo "[pilot-fallback-monitor] Issue #${issue}: inject → ${skill_safe} → window=${window}" >&2
  bash "$session_comm" inject "$window" "$skill_safe" 2>/dev/null || {
    echo "[pilot-fallback-monitor] Issue #${issue}: inject 失敗" >&2
    return 1
  }

  echo "[pilot-fallback-monitor] Issue #${issue}: inject 完了 (${skill_safe})" >&2
  return 0
}

# ---------------------------------------------------------------------------
# PR merged 後の Worker window cleanup（AC-3）
# ---------------------------------------------------------------------------
_get_issue_pr() {
  local issue="$1"
  python3 -m twl.autopilot.state read --type issue --issue "$issue" --field pr 2>/dev/null || echo ""
}

_is_pr_merged() {
  local pr_num="${1:-}"
  local gh_output

  if [[ "$pr_num" =~ ^[1-9][0-9]*$ ]]; then
    gh_output=$(gh pr view "$pr_num" --json state 2>/dev/null || echo "")
  else
    # PR 番号不明時は current branch の PR を確認（テスト環境では stub が MERGED を返す）
    gh_output=$(gh pr view --json state 2>/dev/null || echo "")
  fi

  # stub（{"state":"MERGED"}）と実 gh CLI 出力の両方を包含する判定
  [[ "$gh_output" == *"MERGED"* ]]
}

_cleanup_worker_window() {
  local window="$1"

  # _check_window_alive を使用（pitfalls §4.9 準拠: has-session 不使用, list-windows 使用）
  if ! _load_window_check_lib; then
    echo "[pilot-fallback-monitor] WARN: observer-window-check.sh ライブラリ不在" >&2
    return 1
  fi

  if ! _check_window_alive "$window"; then
    echo "[pilot-fallback-monitor] window '${window}' は既に gone — スキップ" >&2
    return 0
  fi

  echo "[pilot-fallback-monitor] PR merged: window '${window}' を kill します" >&2
  tmux kill-window -t "$window" 2>/dev/null || true
  echo "[pilot-fallback-monitor] window '${window}' を kill しました" >&2
  return 0
}

# ---------------------------------------------------------------------------
# 単一 Worker に対する1ループ処理
# ---------------------------------------------------------------------------
_process_worker() {
  local window="${1:-}"
  local issue="${2:-}"

  if [[ -z "$window" ]]; then
    return 0
  fi

  if [[ "$CLEANUP_MODE" == "true" ]]; then
    # PR merged cleanup モード（AC-3）
    local pr_num=""
    if [[ -n "$issue" ]]; then
      pr_num=$(_get_issue_pr "$issue")
    fi
    if _is_pr_merged "$pr_num"; then
      _cleanup_worker_window "$window"
    fi
    return 0
  fi

  # inject モード（AC-1）: resolve → inject
  _inject_next_workflow "$window" "$issue" || true
}

# ---------------------------------------------------------------------------
# 全 ap-* Worker に対してスキャン
# ---------------------------------------------------------------------------
_scan_all_workers() {
  local issues_dir="${AUTOPILOT_DIR}/issues"
  if [[ ! -d "$issues_dir" ]]; then
    echo "[pilot-fallback-monitor] WARN: ${issues_dir} が存在しない" >&2
    return 0
  fi

  for issue_json in "${issues_dir}"/issue-[0-9]*.json; do
    [[ -f "$issue_json" ]] || continue
    local issue
    issue=$(basename "$issue_json" | sed 's/issue-//;s/\.json//')
    [[ "$issue" =~ ^[0-9]+$ ]] || continue

    local status window pr_num
    status=$(python3 -m twl.autopilot.state read --type issue --issue "$issue" --field status 2>/dev/null || echo "")
    window=$(python3 -m twl.autopilot.state read --type issue --issue "$issue" --field window 2>/dev/null || echo "")

    [[ -z "$window" || -z "$status" ]] && continue
    [[ "$status" == "done" || "$status" == "failed" ]] && continue

    # PR merged cleanup チェック（AC-3）
    if [[ "$status" == "merge-ready" ]]; then
      pr_num=$(_get_issue_pr "$issue")
      if _is_pr_merged "$pr_num"; then
        _cleanup_worker_window "$window"
        continue
      fi
    fi

    # inject チェック（AC-1）
    _inject_next_workflow "$window" "$issue" || true
  done
}

# ---------------------------------------------------------------------------
# メインループ
# ---------------------------------------------------------------------------
if [[ -n "$WORKER_WINDOW" ]]; then
  _process_worker "$WORKER_WINDOW" "$ISSUE_NUM"
else
  _scan_all_workers
fi

if [[ "$ONCE_MODE" != "true" ]]; then
  # daemon ループ（本番モード）— orchestrator 復活時に自動停止
  while true; do
    if [[ "$SKIP_ORCH_CHECK" != "true" ]] && _is_orchestrator_alive; then
      echo "[pilot-fallback-monitor] orchestrator 復活を検知 — daemon 停止" >&2
      exit 0
    fi
    sleep "$POLL_INTERVAL"
    if [[ -n "$WORKER_WINDOW" ]]; then
      _process_worker "$WORKER_WINDOW" "$ISSUE_NUM"
    else
      _scan_all_workers
    fi
  done
fi
