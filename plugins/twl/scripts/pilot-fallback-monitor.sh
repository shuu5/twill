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
# shellcheck source=./lib/tmux-window-kill.sh
source "${LIB_DIR}/tmux-window-kill.sh"

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
  safe_kill_window "$window"
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
# budget-pause.json の expected_reset_at + 5min を過ぎた場合に paused Worker を resume
# 不変条件 M との整合: orchestrator alive チェックの bypass 禁止。budget-pause 専用判定パスとして独立実装。
# jq/date を使用（python3 はテスト環境でスタブ化される可能性があるため使用しない）
# ---------------------------------------------------------------------------
_check_budget_auto_resume() {
  local budget_pause_file=".supervisor/budget-pause.json"
  [[ -f "$budget_pause_file" ]] || return 0

  # jq で JSON フィールドを抽出（python3 はテスト環境でスタブ化されるため jq を使用）
  local status expected_reset_at auto_resume_via paused_at cycle_min
  status=$(jq -r '.status // ""' "$budget_pause_file" 2>/dev/null || true)
  [[ "$status" == "paused" ]] || return 0

  expected_reset_at=$(jq -r '.expected_reset_at // ""' "$budget_pause_file" 2>/dev/null || true)
  auto_resume_via=$(jq -r '.auto_resume_via // ""' "$budget_pause_file" 2>/dev/null || true)
  paused_at=$(jq -r '.paused_at // ""' "$budget_pause_file" 2>/dev/null || true)
  cycle_min=$(jq -r '.cycle_reset_minutes_at_pause // 0' "$budget_pause_file" 2>/dev/null || true)

  # expected_reset_at が空の場合は paused_at + cycle_reset_minutes_at_pause から導出（不変条件 Q）
  if [[ -z "$expected_reset_at" && -n "$paused_at" && "$cycle_min" =~ ^[0-9]+$ && "$cycle_min" -gt 0 ]]; then
    local paused_epoch reset_epoch
    paused_epoch=$(date -d "${paused_at}" +%s 2>/dev/null || echo "")
    if [[ -n "$paused_epoch" ]]; then
      reset_epoch=$(( paused_epoch + cycle_min * 60 ))
      expected_reset_at=$(date -d "@${reset_epoch}" -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "")
    fi
  fi
  [[ -n "$expected_reset_at" ]] || return 0

  # expected_reset_at + 5min を過ぎているか確認（不変条件 Q: cycle reset + 5 分余裕）
  local reset_epoch resume_epoch now_epoch
  reset_epoch=$(date -d "${expected_reset_at}" +%s 2>/dev/null || echo "")
  [[ -n "$reset_epoch" && "$reset_epoch" =~ ^[0-9]+$ ]] || return 0
  resume_epoch=$(( reset_epoch + 5 * 60 ))
  now_epoch=$(date +%s)
  [[ "$now_epoch" -ge "$resume_epoch" ]] || return 0

  echo "[pilot-fallback-monitor] budget-pause auto-resume: expected_reset_at+5min 経過 — paused Worker を resume します (auto_resume_via=${auto_resume_via})" >&2

  # paused_workers を resume
  local workers_list
  workers_list=$(jq -r '.paused_workers[]? // empty' "$budget_pause_file" 2>/dev/null || true)
  if [[ -n "$workers_list" ]]; then
    while IFS= read -r worker_window; do
      [[ -n "$worker_window" ]] || continue
      # issue 番号を取得して inject（state read は python3 module だがスタブで対応済み）
      local issue_num
      issue_num=$(python3 -m twl.autopilot.state read --type window --window "$worker_window" --field issue 2>/dev/null || echo "")
      if [[ -n "$issue_num" ]]; then
        _inject_next_workflow "$worker_window" "$issue_num" || true
      fi
    done <<< "$workers_list"
  fi

  # budget-pause.json の status を resumed に更新（jq を使用）
  local tmp_file
  tmp_file=$(mktemp "${budget_pause_file}.XXXXXX")
  jq --arg resumed_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    '.status = "resumed" | .resumed_at = $resumed_at' \
    "$budget_pause_file" > "$tmp_file" 2>/dev/null && mv "$tmp_file" "$budget_pause_file" || rm -f "$tmp_file"
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
# budget-pause auto-resume チェック（不変条件 Q: expected_reset_at + 5min 経過で resume）
# 常に実行: --worker 指定時も含む（budget-pause 専用判定パスは独立実行）
_check_budget_auto_resume

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
