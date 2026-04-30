#!/bin/bash
# spawn-controller.sh - su-observer 用の安全な controller 起動 wrapper
#
# Usage:
#   spawn-controller.sh <skill-name> <prompt-file> [cld-spawn extra args...]
#   spawn-controller.sh co-autopilot <prompt-file> --with-chain --issue N [--project-dir DIR] [--autopilot-dir DIR]
#
#   <skill-name>: co-explore / co-issue / co-architect / co-autopilot /
#                 co-project / co-utility / co-self-improve
#                 （"twl:" prefix あり/なし両対応）
#   <prompt-file>: プロンプト本文が入ったファイルパス
#
# 動作:
#   1. skill 名を allow-list でバリデーション
#   2. prompt-file を読み、先頭に "/twl:<skill>\n" を prepend
#   3. --help / -h / --version / -v 等の invalid flag を弾く
#      （cld-spawn は *) break で positional 扱いし prompt に混入する）
#   4. --window-name 未指定時は wt-<skill>-<HHMMSS> を自動設定
#   5. cld-spawn を exec
#
# chain 連携モード（co-autopilot のみ）:
#   --with-chain  autopilot-launch.sh に委譲し state 初期化 + chain を起動する
#   --issue N     chain 連携時必須。Issue 番号
#   --project-dir DIR  省略時は bare repo 親ディレクトリを自動解決
#   --autopilot-dir DIR  省略時は project-dir から自動解決
#
# 背景: 本 wrapper は pitfalls-catalog.md 1.1-1.4 の失敗を防ぐ:
#   - --help 注入ミス
#   - /twl:<skill> 忘れ（skill invocation skip）
#   - window 名衝突
#   - prompt への文脈不足（呼び出し側で自主管理、本 wrapper は信じて prepend のみ）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# spawn-controller.sh は plugins/twl/skills/su-observer/scripts/ に置かれる
# cld-spawn は plugins/session/scripts/cld-spawn
TWILL_ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"
CLD_SPAWN="$TWILL_ROOT/plugins/session/scripts/cld-spawn"

if [[ ! -x "$CLD_SPAWN" ]]; then
  echo "Error: cld-spawn not executable at $CLD_SPAWN" >&2
  exit 2
fi

# --- 並列 spawn 可否チェック（§11.3, Issue #1116）---
# SKIP_PARALLEL_CHECK=1 で bypass 可（intervention 記録 MUST）
_PARALLEL_CHECK_LIB="$TWILL_ROOT/plugins/twl/scripts/lib/observer-parallel-check.sh"
if [[ "${SKIP_PARALLEL_CHECK:-0}" == "1" ]]; then
  echo "[spawn-controller] WARN: SKIP_PARALLEL_CHECK=1 — §11.3 チェックをスキップ（intervention-log に自動記録。SKIP_PARALLEL_REASON で理由を渡すこと）" >&2
  # 自動記録 (tech-debt #1135、fail-open ポリシー)
  {
    _supervisor_dir="${SUPERVISOR_DIR:-.supervisor}"
    mkdir -p "$_supervisor_dir"
    _reason="${SKIP_PARALLEL_REASON:-(reason not provided)}"
    _reason="${_reason//$'\n'/ }"
    printf '%s SKIP_PARALLEL_CHECK=1: %s\n' \
      "$(date -u +%FT%TZ)" \
      "$_reason" \
      >> "$_supervisor_dir/intervention-log.md"
  } || {
    echo "[spawn-controller] WARN: intervention-log append failed (continuing spawn)" >&2
    true
  }
elif [[ -f "$_PARALLEL_CHECK_LIB" ]]; then
  # shellcheck source=/dev/null
  source "$_PARALLEL_CHECK_LIB"
  _PARALLEL_CHECK_EXIT=0
  _check_parallel_spawn_eligibility || _PARALLEL_CHECK_EXIT=$?
  if [[ "$_PARALLEL_CHECK_EXIT" -eq 2 ]]; then
    echo "[spawn-controller] ERROR: 並列 spawn 禁止（必須条件欠落）— spawn を abort します" >&2
    exit 2
  elif [[ "$_PARALLEL_CHECK_EXIT" -eq 1 ]]; then
    echo "[spawn-controller] WARN: precondition 欠落 — ≤ 2 並列 degrade mode（spawn は続行）" >&2
  fi
fi
# --- チェック終了 ---

VALID_SKILLS=(co-explore co-issue co-architect co-autopilot co-project co-utility co-self-improve)

usage() {
  cat >&2 <<EOF
Usage: $(basename "$0") <skill-name> <prompt-file> [cld-spawn extra args...]
       $(basename "$0") co-autopilot <prompt-file> --with-chain --issue N [--project-dir DIR] [--autopilot-dir DIR]

Valid skills: ${VALID_SKILLS[*]}
(Accepts with or without "twl:" prefix)

Example:
  $(basename "$0") co-explore /tmp/my-prompt.txt
  $(basename "$0") co-issue /tmp/issue-prompt.txt --timeout 90
  $(basename "$0") co-autopilot /tmp/ctx.txt --with-chain --issue 835
EOF
  exit 2
}

if [[ $# -lt 2 ]]; then
  usage
fi

SKILL="$1"
PROMPT_FILE="$2"
shift 2

# skill 名 normalize（"twl:" prefix 除去）
SKILL_NORMALIZED="${SKILL#twl:}"

# skill 名バリデーション
SKILL_FOUND=false
for s in "${VALID_SKILLS[@]}"; do
  if [[ "$SKILL_NORMALIZED" == "$s" ]]; then
    SKILL_FOUND=true
    break
  fi
done
if [[ "$SKILL_FOUND" == "false" ]]; then
  echo "Error: invalid skill name '$SKILL'." >&2
  echo "Valid: ${VALID_SKILLS[*]}" >&2
  exit 2
fi

# prompt file 存在確認
if [[ ! -f "$PROMPT_FILE" ]]; then
  echo "Error: prompt file not found: $PROMPT_FILE" >&2
  exit 2
fi

# --with-chain: co-autopilot chain 連携モード（autopilot-launch.sh に委譲）
WITH_CHAIN=false
CHAIN_ISSUE=""
CHAIN_PROJECT_DIR=""
CHAIN_AUTOPILOT_DIR=""
PASS_THROUGH_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-chain)    WITH_CHAIN=true; shift ;;
    --issue)         CHAIN_ISSUE="$2"; shift 2 ;;
    --project-dir)   CHAIN_PROJECT_DIR="$2"; shift 2 ;;
    --autopilot-dir) CHAIN_AUTOPILOT_DIR="$2"; shift 2 ;;
    *)               PASS_THROUGH_ARGS+=("$1"); shift ;;
  esac
done
set -- "${PASS_THROUGH_ARGS[@]+"${PASS_THROUGH_ARGS[@]}"}"

if [[ "$WITH_CHAIN" == "true" ]]; then
  cat >&2 <<'WARN'
WARN: --with-chain --issue は skill bypass 経路です（Pilot 不在で Worker 直接起動）。
  正規運用: spawn-controller.sh co-autopilot <prompt>（オプション無し）で Pilot を 1 つ spawn し、
            Pilot が複数 Issue の deps graph 計画と Worker 起動を担当する。
  詳細: plugins/twl/skills/su-observer/refs/pitfalls-catalog.md §13.5
WARN
  if [[ "$SKILL_NORMALIZED" != "co-autopilot" ]]; then
    echo "Error: --with-chain は co-autopilot のみで有効です。" >&2
    exit 2
  fi
  if [[ -z "$CHAIN_ISSUE" ]]; then
    echo "Error: --with-chain には --issue N が必須です。" >&2
    exit 2
  fi
  if [[ ! "$CHAIN_ISSUE" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: --issue の値は正整数である必要があります: ${CHAIN_ISSUE}" >&2
    exit 2
  fi

  # autopilot-launch.sh パス解決（AUTOPILOT_LAUNCH_SH 環境変数でテスト時に上書き可能）
  AUTOPILOT_LAUNCH_SH="${AUTOPILOT_LAUNCH_SH:-$TWILL_ROOT/plugins/twl/scripts/autopilot-launch.sh}"
  if [[ ! -x "$AUTOPILOT_LAUNCH_SH" ]]; then
    echo "Error: autopilot-launch.sh not executable at $AUTOPILOT_LAUNCH_SH" >&2
    exit 2
  fi

  # プロジェクト・autopilot ディレクトリ自動解決
  [[ -z "$CHAIN_PROJECT_DIR" ]] && CHAIN_PROJECT_DIR="$TWILL_ROOT"
  if [[ -z "$CHAIN_AUTOPILOT_DIR" ]]; then
    if [[ -d "$CHAIN_PROJECT_DIR/.bare" ]]; then
      CHAIN_AUTOPILOT_DIR="$CHAIN_PROJECT_DIR/main/.autopilot"
    else
      CHAIN_AUTOPILOT_DIR="$CHAIN_PROJECT_DIR/.autopilot"
    fi
  fi

  # wave-N-task-ids.json / wave-N-watcher-pids.json を初期化（#1052）
  # wave-collect の自動停止ロジックが参照するファイルをここで作成する
  _supervisor_dir="$(dirname "$CHAIN_AUTOPILOT_DIR")/.supervisor"
  mkdir -p "$_supervisor_dir" 2>/dev/null || true
  _task_ids_file="${_supervisor_dir}/wave-${CHAIN_ISSUE}-task-ids.json"
  _watcher_pids_file="${_supervisor_dir}/wave-${CHAIN_ISSUE}-watcher-pids.json"
  if [[ ! -f "$_task_ids_file" ]]; then
    printf '{"wave":%s,"monitor_task_ids":[]}\n' "$CHAIN_ISSUE" > "$_task_ids_file" 2>/dev/null || true
  fi
  if [[ ! -f "$_watcher_pids_file" ]]; then
    printf '{"wave":%s,"watcher_pids":[]}\n' "$CHAIN_ISSUE" > "$_watcher_pids_file" 2>/dev/null || true
  fi

  # prompt-file の内容を --context として注入
  CHAIN_CONTEXT="$(cat "$PROMPT_FILE" 2>/dev/null || true)"
  CONTEXT_ARG=()
  [[ -n "$CHAIN_CONTEXT" ]] && CONTEXT_ARG=(--context "$CHAIN_CONTEXT")

  exec bash "$AUTOPILOT_LAUNCH_SH" \
    --issue "$CHAIN_ISSUE" \
    --project-dir "$CHAIN_PROJECT_DIR" \
    --autopilot-dir "$CHAIN_AUTOPILOT_DIR" \
    "${CONTEXT_ARG[@]+"${CONTEXT_ARG[@]}"}"
fi

# 残り引数に invalid flag が含まれていないか検査
# cld-spawn は *) break で positional として扱うため、誤 flag は prompt に混入する
for arg in "$@"; do
  case "$arg" in
    --help|-h|--version|-v)
      cat >&2 <<EOF
Error: '$arg' は cld-spawn の有効な option ではなく、prompt として誤注入される。
指定しないこと。

有効な cld-spawn option:
  --cd DIR, --env-file PATH, --window-name NAME, --timeout N,
  --model MODEL, --force-new
EOF
      exit 2
      ;;
  esac
done

# /twl:<skill> を prompt 先頭に prepend
PROMPT_BODY="$(cat "$PROMPT_FILE")"

# size guard: §10 spawn prompt 最小化原則（MUST NOT）
PROMPT_LINE_COUNT=$(printf '%s\n' "$PROMPT_BODY" | wc -l)
FORCE_LARGE=false
for arg in "$@"; do
  [[ "$arg" == "--force-large" ]] && FORCE_LARGE=true
done

if [[ "$FORCE_LARGE" == "false" && $PROMPT_LINE_COUNT -gt 30 ]]; then
  cat >&2 <<WARN
WARN: prompt size ${PROMPT_LINE_COUNT} lines exceeds recommended 30 lines.
§10 spawn prompt 最小化原則: skill 自律取得可能な情報を prompt に転記しないこと。
詳細: plugins/twl/skills/su-observer/refs/pitfalls-catalog.md §10
suppress する場合: --force-large + prompt 冒頭に REASON: 行
WARN
fi

# --force-large を cld-spawn に渡さない（set -u 安全な ${arr[@]+...} 形式）
NEW_ARGS=()
for arg in "$@"; do
  [[ "$arg" == "--force-large" ]] && continue
  NEW_ARGS+=("$arg")
done
set -- "${NEW_ARGS[@]+"${NEW_ARGS[@]}"}"

FINAL_PROMPT="/twl:${SKILL_NORMALIZED}
${PROMPT_BODY}"

# --window-name が明示されていなければ自動生成
HAS_WINDOW_NAME=false
for arg in "$@"; do
  if [[ "$arg" == "--window-name" ]]; then
    HAS_WINDOW_NAME=true
    break
  fi
done

WINDOW_NAME_ARG=()
if [[ "$HAS_WINDOW_NAME" == "false" ]]; then
  WINDOW_NAME_ARG=(--window-name "wt-${SKILL_NORMALIZED}-$(date +%H%M%S)")
fi

# _setup_observer_panes: observer window を 4 pane layout に分割し watcher を起動する
# 呼び出し: _setup_observer_panes <observer_window> [fallback_pane_base]
#   observer_window: 対象の tmux window 名（未指定時は .supervisor/session.json から取得）
#   fallback_pane_base: pane-base-index 取得失敗時のフォールバック値（default: 0）
# レイアウト: 左 50% (observer) | 右上 1/3 (heartbeat) / 右中 1/3 (budget) / 右下 1/3 (cldobs)
_setup_observer_panes() {
  local observer_window="${1:-}"
  local fallback_pane_base="${2:-0}"
  local supervisor_dir="${SUPERVISOR_DIR:-.supervisor}"

  if [[ -z "$observer_window" ]]; then
    local session_file="$supervisor_dir/session.json"
    if [[ -f "$session_file" ]]; then
      observer_window=$(python3 - "$session_file" <<'PYEOF' 2>/dev/null || echo ""
import json, sys
d = json.load(open(sys.argv[1]))
print(d.get('observer_window', ''))
PYEOF
)
    fi
  fi

  if [[ -z "$observer_window" ]]; then
    echo "[spawn-controller] WARN: observer_window が未検出 — pane split をスキップ" >&2
    return 0
  fi

  # orphan watcher cleanup
  pkill -f "heartbeat-watcher.sh" 2>/dev/null || true
  pkill -f "budget-monitor-watcher.sh" 2>/dev/null || true
  pkill -f "cld-observe-any" 2>/dev/null || true

  # pane-base-index auto-detect（環境差異を吸収）
  local base
  base=$(tmux show-options -gv pane-base-index 2>/dev/null || echo "$fallback_pane_base")

  local cwd
  cwd="$(pwd)"
  local heartbeat_script="$SCRIPT_DIR/heartbeat-watcher.sh"
  local budget_script="$SCRIPT_DIR/budget-monitor-watcher.sh"
  local cld_observe_any="$TWILL_ROOT/plugins/session/scripts/cld-observe-any"

  # Step 1: horizontal split (左右) — 右カラムに heartbeat-watcher を起動
  tmux split-window -h -d -l 50% -t "${observer_window}:1.${base}" -c "$cwd" "bash '$heartbeat_script'" || \
    tmux split-window -h -d -l 50% -t "${observer_window}" -c "$cwd" "bash '$heartbeat_script'"

  # Step 2: vertical split — 右カラムを上下分割して budget-monitor を起動
  tmux split-window -v -d -l 67% -t "${observer_window}:1.$((base+1))" -c "$cwd" "bash '$budget_script'" || \
    tmux split-window -v -d -t "${observer_window}:1.$((base+1))" -c "$cwd" "bash '$budget_script'"

  # Step 3: vertical split — 下段をさらに分割して cld-observe-any を起動
  tmux split-window -v -d -l 50% -t "${observer_window}:1.$((base+2))" -c "$cwd" "bash '$cld_observe_any'" || \
    tmux split-window -v -d -t "${observer_window}:1.$((base+2))" -c "$cwd" "bash '$cld_observe_any'"

  # pane 数を確認してログ出力
  local pane_count
  pane_count=$(tmux list-panes -t "$observer_window" 2>/dev/null | wc -l || echo "?")
  echo "[spawn-controller] ✓ observer window ${observer_window}: ${pane_count} pane layout を設定 (pane-base-index=${base})"
}

# cld-spawn 呼び出し（extra args を first, prompt を last に配置する必要あり — cld-spawn の option parse は先に終わり、残りが PROMPT になる）
# 空配列ガード: set -u 環境で "${arr[@]}" が unbound を起こすため ${arr[@]+...} 形式で保護
# co-autopilot（非 --with-chain）は exec を避けて pane setup を後続実行する
if [[ "$SKILL_NORMALIZED" == "co-autopilot" && "$WITH_CHAIN" == "false" ]]; then
  # cld-spawn は prompt inject 後すぐに 0 終了する。|| true で set -e を抑制し pane setup を必ず実行する
  "$CLD_SPAWN" "${WINDOW_NAME_ARG[@]+"${WINDOW_NAME_ARG[@]}"}" "$@" "$FINAL_PROMPT" || true
  _setup_observer_panes
else
  exec "$CLD_SPAWN" "${WINDOW_NAME_ARG[@]+"${WINDOW_NAME_ARG[@]}"}" "$@" "$FINAL_PROMPT"
fi
