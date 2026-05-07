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

# AC1: tmux window target を session:index 形式で解決するヘルパーを読み込む
# shellcheck source=/dev/null
source "$TWILL_ROOT/plugins/session/scripts/lib/tmux-resolve.sh"

# Issue #1346: SUPERVISOR_DIR パス検証（record-detection-gap.sh パターン準拠）
# shellcheck source=/dev/null
source "$TWILL_ROOT/plugins/twl/scripts/lib/supervisor-dir-validate.sh"
validate_supervisor_dir "${SUPERVISOR_DIR:-.supervisor}" || exit 1

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
    _reason="${_reason//$'\r'/ }"
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
INTERACTIVE_FLAG=""  # --interactive: co-autopilot Plan 承認 menu opt-in (#1317)
PRE_CHECK_ISSUE=""   # --pre-check-issue N: co-autopilot spawn 前 Status=Refined check (#1516)
PASS_THROUGH_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-chain)       WITH_CHAIN=true; shift ;;
    --issue)            CHAIN_ISSUE="$2"; shift 2 ;;
    --project-dir)      CHAIN_PROJECT_DIR="$2"; shift 2 ;;
    --autopilot-dir)    CHAIN_AUTOPILOT_DIR="$2"; shift 2 ;;
    --interactive)      INTERACTIVE_FLAG="--interactive"; shift ;;
    --pre-check-issue)  PRE_CHECK_ISSUE="$2"; shift 2 ;;
    *)                  PASS_THROUGH_ARGS+=("$1"); shift ;;
  esac
done
set -- "${PASS_THROUGH_ARGS[@]+"${PASS_THROUGH_ARGS[@]}"}"

# --- Status=Refined pre-check（#1516 — co-autopilot spawn 前 MUST）---
# --pre-check-issue N が指定された場合、Issue の Project Board Status を確認する。
# Status が Refined でない場合は error abort し、board-status-update を hint として出力。
if [[ -n "$PRE_CHECK_ISSUE" && "$SKILL_NORMALIZED" == "co-autopilot" ]]; then
  # CRITICAL fix: 整数バリデーション（CHAIN_ISSUE の ^[1-9][0-9]*$ パターン準拠）
  if [[ ! "$PRE_CHECK_ISSUE" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: --pre-check-issue の値は正整数である必要があります: ${PRE_CHECK_ISSUE}" >&2
    exit 2
  fi
  _board_number="${TWL_BOARD_NUMBER:-$(python3 -m twl.config get project-board.number 2>/dev/null || echo "")}"
  _board_owner="${TWL_BOARD_OWNER:-$(python3 -m twl.config get project-board.owner 2>/dev/null || echo "shuu5")}"
  if [[ -n "$_board_number" ]]; then
    # PRE_CHECK_ISSUE は上記で正整数バリデーション済み（python3 への展開は安全）
    _issue_status=$(gh project item-list "$_board_number" --owner "$_board_owner" --format json 2>/dev/null \
      | python3 -c "import json,sys; n=int('${PRE_CHECK_ISSUE}'); items=json.load(sys.stdin).get('items',[]); \
        match=[i.get('status','') for i in items if i.get('content',{}).get('number')==n]; \
        print(match[0] if match else '')" 2>/dev/null || echo "")
    # CRITICAL fix: Status != Refined を abort 条件とする（Todo のみではなく非 Refined 全般）
    if [[ -z "$_issue_status" ]]; then
      echo "[spawn-controller] WARN: --pre-check-issue: Issue #${PRE_CHECK_ISSUE} の Status を取得できませんでした（board 未登録または API エラー）。spawn を続行します。" >&2
    elif [[ "$_issue_status" != "Refined" ]]; then
      echo "[spawn-controller] ERROR: Issue #${PRE_CHECK_ISSUE} の Status=${_issue_status}（Refined でない）のため co-autopilot spawn を abort します。" >&2
      echo "[spawn-controller] HINT: 以下のコマンドで Status=Refined に遷移させてから再実行してください:" >&2
      echo "[spawn-controller]   bash \"$TWILL_ROOT/plugins/twl/scripts/chain-runner.sh\" board-status-update ${PRE_CHECK_ISSUE}" >&2
      echo "[spawn-controller]   または: board-status-update --status Refined を実行後に spawn-controller.sh を再実行" >&2
      exit 2
    fi
  else
    echo "[spawn-controller] WARN: --pre-check-issue: TWL_BOARD_NUMBER 未設定のため Status=Refined check をスキップ" >&2
  fi
fi
# --- pre-check ここまで ---

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

  # ★ #1155: wave-queue.json へ enqueue（IF-2）
  # CHAIN_WAVE_QUEUE_ENTRY が設定されている場合のみ実行（JSON 文字列で渡す）
  # 例: CHAIN_WAVE_QUEUE_ENTRY='{"wave":7,"issues":[1155],"spawn_cmd_argv":["bash","..."],"depends_on_waves":[6],"spawn_when":"all_current_wave_idle_completed"}'
  _wave_queue_file="${_supervisor_dir}/wave-queue.json"
  if [[ -n "${CHAIN_WAVE_QUEUE_ENTRY:-}" ]]; then
    if [[ ! -f "$_wave_queue_file" ]]; then
      # 初期化: current_wave は CHAIN_ISSUE を使う
      printf '{"version":1,"current_wave":%s,"queue":[]}\n' "${CHAIN_ISSUE:-0}" > "$_wave_queue_file" 2>/dev/null || true
    fi
    # エントリを queue に append（jq で安全に結合）
    {
      _updated=$(jq --argjson entry "$CHAIN_WAVE_QUEUE_ENTRY" '.queue += [$entry]' "$_wave_queue_file" 2>/dev/null)
      [[ -n "$_updated" ]] && printf '%s\n' "$_updated" > "$_wave_queue_file"
    } || {
      echo "[spawn-controller] WARN: wave-queue.json enqueue failed (continuing spawn)" >&2
    }
  fi

  # prompt-file の内容を --context として注入
  CHAIN_CONTEXT="$(cat "$PROMPT_FILE" 2>/dev/null || true)"
  CONTEXT_ARG=()
  [[ -n "$CHAIN_CONTEXT" ]] && CONTEXT_ARG=(--context "$CHAIN_CONTEXT")
  WINDOW_NAME="wt-${SKILL_NORMALIZED}-${CHAIN_ISSUE}"
  echo ">>> Monitor 再 arm 必要: ${WINDOW_NAME}"
  exec bash "$AUTOPILOT_LAUNCH_SH" \
    --issue "$CHAIN_ISSUE" \
    --project-dir "$CHAIN_PROJECT_DIR" \
    --autopilot-dir "$CHAIN_AUTOPILOT_DIR" \
    ${INTERACTIVE_FLAG:+"$INTERACTIVE_FLAG"} \
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

# --- provenance section ヘルパー（Issue #1274）---
_get_host_alias() {
  local f="${XDG_CONFIG_HOME:-$HOME/.config}/twl/host-aliases.json"
  [[ -f "$f" ]] && python3 -c "import json,socket,sys; d=json.load(open(sys.argv[1])); print(d.get(socket.gethostname(),''))" "$f" 2>/dev/null || true
}
_emit_provenance_section() {
  local a g="" p="" sfile="${SUPERVISOR_DIR:-.supervisor}/session.json"
  a="$(_get_host_alias)"
  g="$(git -C "$TWILL_ROOT" rev-parse --show-toplevel 2>/dev/null || true)"; g="${g//$'\n'/ }"
  p="${PREDECESSOR_HOST:-}"; [[ -z "$p" && -f "$sfile" ]] && p="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('predecessor_host',''))" "$sfile" 2>/dev/null || true)"; p="${p//$'\n'/ }"
  printf '## provenance (auto-injected)\n- host: %s (%s)\n- pwd: %s\n- predecessor: %s\n- timestamp: %s\n' \
    "$(hostname)" "$a" "$g" "$p" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
# --- provenance section ここまで ---

# provenance section を先に取得し、サイズガードの実効上限（EFFECTIVE_LIMIT）を調整
PROVENANCE="$(_emit_provenance_section)"
PROVENANCE_LINES=$(printf '%s\n' "$PROVENANCE" | wc -l)
echo "[spawn-controller] PROVENANCE_LINES=${PROVENANCE_LINES}" >&2

# /twl:<skill> を prompt 先頭に prepend
PROMPT_BODY="$(cat "$PROMPT_FILE")"

# size guard: §10 spawn prompt 最小化原則（MUST NOT）
PROMPT_LINE_COUNT=$(printf '%s\n' "$PROMPT_BODY" | wc -l)
EFFECTIVE_LIMIT=$((30 - PROVENANCE_LINES))
FORCE_LARGE=false
for arg in "$@"; do
  [[ "$arg" == "--force-large" ]] && FORCE_LARGE=true
done

if [[ "$FORCE_LARGE" == "false" && $PROMPT_LINE_COUNT -gt $EFFECTIVE_LIMIT ]]; then
  cat >&2 <<WARN
WARN: prompt size ${PROMPT_LINE_COUNT} lines exceeds recommended ${EFFECTIVE_LIMIT} lines (30 - ${PROVENANCE_LINES} provenance lines).
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

FINAL_PROMPT="/twl:${SKILL_NORMALIZED}${INTERACTIVE_FLAG:+ $INTERACTIVE_FLAG}
${PROVENANCE}
${PROMPT_BODY}"

# --window-name が明示されていなければ自動生成
HAS_WINDOW_NAME=false
for arg in "$@"; do
  if [[ "$arg" == "--window-name" ]]; then
    HAS_WINDOW_NAME=true
    break
  fi
done

WINDOW_NAME=""
WINDOW_NAME_ARG=()
if [[ "$HAS_WINDOW_NAME" == "false" ]]; then
  WINDOW_NAME="wt-${SKILL_NORMALIZED}-$(date +%H%M%S)"
  WINDOW_NAME_ARG=(--window-name "$WINDOW_NAME")
else
  prev_arg=""
  for arg in "$@"; do
    if [[ "$prev_arg" == "--window-name" ]]; then
      WINDOW_NAME="$arg"
      break
    fi
    prev_arg="$arg"
  done
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

  # AC2: _resolve_window_target で session:index 形式に解決（ambiguous リスクを排除）
  local resolved_target
  if ! resolved_target=$(_resolve_window_target "${observer_window}"); then
    # AC5: 解決失敗時は [spawn-controller] prefix 付きで stderr にログ出力（エラー詳細は _resolve_window_target が出力）
    echo "[spawn-controller] ERROR: _resolve_window_target '${observer_window}' 失敗" >&2
    return 1
  fi

  # AC3: fallback（bare ${observer_window}）は廃止。_resolve_window_target 失敗時は abort（上記参照）。
  # 理由: bare window 名での -t 指定は同名 window が複数セッションに存在する場合 ambiguous となり
  # 誤ったペインを操作するリスクがあるため、解決失敗時は安全側に倒して停止する。

  # 現在の pane 数を取得（AC2: 既存 4-pane 状態は split をスキップして watcher のみ再起動）
  local live_pane_count
  live_pane_count=$(tmux list-panes -t "${resolved_target}" 2>/dev/null | wc -l || echo 0)

  # _wait_pane_count: sync barrier — pane 数が min_count に達するまで最大 3 秒待機
  # タイムアウト時は WARN ログを出力して return 1（呼び出し元で abort）
  _wait_pane_count() {
    local target="$1" min_count="$2" retries=15
    while [[ "$retries" -gt 0 ]]; do
      live_pane_count=$(tmux list-panes -t "$target" 2>/dev/null | wc -l || echo 0)
      [[ "$live_pane_count" -ge "$min_count" ]] && return 0
      sleep 0.2; ((retries--))
    done
    echo "[spawn-controller] WARN: pane barrier timeout (target=${min_count}, actual=${live_pane_count})" >&2
    return 1
  }

  local spawn_cmd
  printf -v spawn_cmd 'env IDLE_COMPLETED_AUTO_KILL=%q bash %q --window %q' "${IDLE_COMPLETED_AUTO_KILL:-0}" "$cld_observe_any" "$observer_window"

  if [[ "$live_pane_count" -ge 4 ]]; then
    # AC2: 既存 4-pane 状態 — split をスキップして watcher を既存 pane 内で再起動
    echo "[spawn-controller] ✓ 既存 ${live_pane_count} pane 状態 — split をスキップ、watcher を pane 内で再起動"
    tmux respawn-pane -k -t "${resolved_target}.$((base+1))" "bash '$heartbeat_script'" 2>/dev/null || true
    tmux respawn-pane -k -t "${resolved_target}.$((base+2))" "bash '$budget_script'" 2>/dev/null || true
    tmux respawn-pane -k -t "${resolved_target}.$((base+3))" "$spawn_cmd" 2>/dev/null || true
  else
    # Step 1: horizontal split (左右) — 右カラムに heartbeat-watcher を起動
    if [[ "$live_pane_count" -lt 2 ]]; then
      tmux split-window -h -d -l 50% -t "${resolved_target}.${base}" -c "$cwd" "bash '$heartbeat_script'"
      # Sync barrier: pane 生成を確認してから次の split に進む（"can't find pane: N" 防止）
      _wait_pane_count "${resolved_target}" 2 || return 1
    fi

    # Step 2: vertical split — 右カラムを上下分割して budget-monitor を起動
    if [[ "$live_pane_count" -lt 3 ]]; then
      tmux split-window -v -d -l 67% -t "${resolved_target}.$((base+1))" -c "$cwd" "bash '$budget_script'"
      # Sync barrier: pane 生成を確認してから次の split に進む
      _wait_pane_count "${resolved_target}" 3 || return 1
    fi

    # Step 3: vertical split — 下段をさらに分割して cld-observe-any を起動（必須引数 --window 付き）
    if [[ "$live_pane_count" -lt 4 ]]; then
      tmux split-window -v -d -l 50% -t "${resolved_target}.$((base+2))" -c "$cwd" "$spawn_cmd"
    fi
  fi

  # cld-observe-any pane の PID・pane_id・spawn_cmd を session.json に記録
  # AC6: display-message も _resolve_window_target で解決した fully-qualified target を使う
  local obs_pane_id obs_pane_pid session_file
  session_file="${supervisor_dir}/session.json"
  obs_pane_id=$(tmux display-message -t "${resolved_target}.$((base+3))" -p '#{pane_id}' 2>/dev/null || echo "")
  obs_pane_pid=$(tmux display-message -t "${resolved_target}.$((base+3))" -p '#{pane_pid}' 2>/dev/null || echo "")
  if [[ -f "$session_file" && -n "$obs_pane_id" ]]; then
    local tmp_file
    tmp_file=$(mktemp)
    jq --arg pid "$obs_pane_pid" \
       --arg pane_id "$obs_pane_id" \
       --arg spawn_cmd "$spawn_cmd" \
       --arg started_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '.cld_observe_any.pid = ($pid | tonumber? // null) |
        .cld_observe_any.pane_id = $pane_id |
        .cld_observe_any.spawn_cmd = $spawn_cmd |
        .cld_observe_any.started_at = $started_at' \
       "$session_file" > "$tmp_file" && mv "$tmp_file" "$session_file" || rm -f "$tmp_file"
    echo "[spawn-controller] ✓ cld_observe_any metadata 記録: pane_id=${obs_pane_id} pid=${obs_pane_pid}"
  fi

  # pane 数を確認してログ出力
  local pane_count
  pane_count=$(tmux list-panes -t "${resolved_target}" 2>/dev/null | wc -l || echo "?")
  echo "[spawn-controller] ✓ observer window ${observer_window}: ${pane_count} pane layout を設定 (pane-base-index=${base})"
}

# cld-spawn 呼び出し（extra args を first, prompt を last に配置する必要あり — cld-spawn の option parse は先に終わり、残りが PROMPT になる）
# 空配列ガード: set -u 環境で "${arr[@]}" が unbound を起こすため ${arr[@]+...} 形式で保護
# co-autopilot（非 --with-chain）は exec を避けて pane setup を後続実行する
if [[ "$SKILL_NORMALIZED" == "co-autopilot" && "$WITH_CHAIN" == "false" ]]; then
  # cld-spawn は prompt inject 後すぐに 0 終了する。|| true で set -e を抑制し pane setup を必ず実行する
  echo ">>> Monitor 再 arm 必要: ${WINDOW_NAME}"
  "$CLD_SPAWN" "${WINDOW_NAME_ARG[@]+"${WINDOW_NAME_ARG[@]}"}" "$@" "$FINAL_PROMPT" || true
  _setup_observer_panes
else
  echo ">>> Monitor 再 arm 必要: ${WINDOW_NAME}"
  exec "$CLD_SPAWN" "${WINDOW_NAME_ARG[@]+"${WINDOW_NAME_ARG[@]}"}" "$@" "$FINAL_PROMPT"
fi
