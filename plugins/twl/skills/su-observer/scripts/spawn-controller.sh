#!/bin/bash
# spawn-controller.sh - su-observer 用の安全な controller 起動 wrapper
#
# Usage:
#   spawn-controller.sh <skill-name> <prompt-file> [cld-spawn extra args...]
#   spawn-controller.sh co-autopilot <prompt-file>                             # 正規運用: Pilot を 1 つ spawn
#   spawn-controller.sh feature-dev <issue-number> [--cd PATH] [cld-spawn extra args...]   # Issue #1644
#
# DEPRECATED: --with-chain --issue N（Pilot bypass 経路、#1650 で default-deny に変更）
#   co-autopilot <prompt-file> --with-chain --issue N [--project-dir DIR] [--autopilot-dir DIR]
#   escape hatch: SKIP_PILOT_GATE=1 SKIP_PILOT_REASON='<理由>' spawn-controller.sh co-autopilot ...
#   詳細: plugins/twl/skills/su-observer/refs/pitfalls-catalog.md §13.5
#
#   <skill-name>: co-explore / co-issue / co-architect / co-autopilot /
#                 co-project / co-utility / co-self-improve / feature-dev
#                 （"twl:" prefix あり/なし両対応）
#   <prompt-file>: プロンプト本文が入ったファイルパス（feature-dev は不使用）
#   <issue-number>: feature-dev のみ。対象 Issue 番号（正整数）
#
# 動作（co-* skill）:
#   1. skill 名を allow-list でバリデーション
#   2. prompt-file を読み、先頭に "/twl:<skill>\n" を prepend
#   3. --help / -h / --version / -v 等の invalid flag を弾く
#      （cld-spawn は *) break で positional 扱いし prompt に混入する）
#   4. --window-name 未指定時は wt-<skill>-<HHMMSS> を自動設定
#   5. cld-spawn を exec
#
# 動作（feature-dev、Issue #1644）:
#   1. ISSUE_NUMBER バリデーション（正整数）
#   2. 承認証跡 gate: .supervisor/feature-dev-request-<N>.json schema + TTL + Refined + parallel
#   3. atomic rename: 承認証跡を .supervisor/consumed/ に one-shot 消費
#   4. worktree: --cd 未指定時は $TWILL_ROOT/worktrees/fd-<N> を auto-create
#   5. hook: install-git-hooks.sh --worktree で pre-push hook を設置（main 直接 push を block）
#   6. FINAL_PROMPT: "/feature-dev:feature-dev #<N>" + provenance + MUST 注入
#   7. cld-spawn を exec（window=wt-fd-<N>、--cd <worktree>）
#   SKIP_LAYER2=1 で gate check のみバイパス（escape hatch、AC-4.6: 2 wave 維持）
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
# CLD_SPAWN_OVERRIDE 環境変数で test 時に mock に切り替え可能（Issue #1644）
CLD_SPAWN="${CLD_SPAWN_OVERRIDE:-$TWILL_ROOT/plugins/session/scripts/cld-spawn}"

# AC1: tmux window target を session:index 形式で解決するヘルパーを読み込む
# shellcheck source=/dev/null
source "$TWILL_ROOT/plugins/session/scripts/lib/tmux-resolve.sh"

# Issue #1346: SUPERVISOR_DIR パス検証（record-detection-gap.sh パターン準拠）
# shellcheck source=/dev/null
source "$TWILL_ROOT/plugins/twl/scripts/lib/supervisor-dir-validate.sh"
validate_supervisor_dir "${SUPERVISOR_DIR:-.supervisor}" || exit 1

# --- provenance section ヘルパー（Issue #1274）---
# Issue #1644: feature-dev early-exit path で使用するため、関数定義を冒頭に移動。
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

# ASCII reason のみを想定。UTF-8 マルチバイト文字は非印字バイト置換により破壊される可能性がある。
# 第1引数を受け取り ${1//[^[:print:]]/ } の結果を printf '%s' で出力する (改行なし)。
# 引数未指定または空文字の場合は空文字を出力する。
# デフォルト値展開は呼び出し元の責務 (例: "${VAR:-default}")。
_sanitize_skip_reason() {
  local _r="${1:-}"
  printf '%s' "${_r//[^[:print:]]/ }"
}

# --- #1644: feature-dev gate checks（bash 実装、tools.py の Python 版と意味的等価）---
# 引数: $1 = ISSUE_NUMBER（正整数、呼び出し側で validate 済み）
# 効果: 全 gate を pass したら .supervisor/feature-dev-request-<N>.json を consumed/ に atomic rename
# Exit: gate fail → exit 1（呼び出しは return ではなく exit）。pass → 戻り値で続行
_fd_run_gate_checks() {
  local issue_number="$1"
  local sup_dir="${SUPERVISOR_DIR:-.supervisor}"
  local request_file="${sup_dir}/feature-dev-request-${issue_number}.json"

  # 1. request file 存在確認
  if [[ ! -f "$request_file" ]]; then
    echo "[spawn-controller] ERROR: feature-dev approval trail not found: $request_file" >&2
    echo "[spawn-controller] User must create .supervisor/feature-dev-request-<N>.json with" >&2
    echo "[spawn-controller]   {issue, requested_at, requested_by, ttl_seconds, intervention_id}" >&2
    exit 1
  fi

  # 2. JSON schema 検証（必須 field の存在確認）
  local required_fields=("issue" "requested_at" "requested_by" "ttl_seconds" "intervention_id")
  local field
  for field in "${required_fields[@]}"; do
    if ! jq -e --arg f "$field" 'has($f)' "$request_file" >/dev/null 2>&1; then
      echo "[spawn-controller] ERROR: approval trail missing field '$field' in $request_file" >&2
      exit 1
    fi
  done

  # 3. TTL check（ISO8601 → epoch → elapsed）
  local requested_at ttl_seconds req_epoch now elapsed
  requested_at=$(jq -r '.requested_at' "$request_file")
  ttl_seconds=$(jq -r '.ttl_seconds' "$request_file")
  if [[ ! "$ttl_seconds" =~ ^[0-9]+$ ]]; then
    echo "[spawn-controller] ERROR: approval trail ttl_seconds invalid: $ttl_seconds" >&2
    exit 1
  fi
  # 'Z' suffix を除去（GNU date と BSD date の両対応）
  local requested_at_norm="${requested_at%Z}"
  if req_epoch=$(date -u -d "${requested_at_norm}" +%s 2>/dev/null); then
    :
  elif req_epoch=$(date -u -j -f "%Y-%m-%dT%H:%M:%S" "${requested_at_norm}" +%s 2>/dev/null); then
    :
  else
    echo "[spawn-controller] ERROR: approval trail requested_at parse failed: '$requested_at'" >&2
    exit 1
  fi
  now=$(date -u +%s)
  elapsed=$((now - req_epoch))
  if [[ "$elapsed" -gt "$ttl_seconds" ]]; then
    echo "[spawn-controller] ERROR: approval trail TTL expired: elapsed=${elapsed}s > ttl_seconds=${ttl_seconds}s" >&2
    echo "[spawn-controller] Re-request user approval." >&2
    exit 1
  fi

  # 4. Status=Refined check（self shell-out — tools.py と同じ pattern）
  # NOTE: 親プロセスでは Status check が co-autopilot 専用 (--pre-check-issue) のため未実行。
  # feature-dev では明示的に self shell-out する必要がある（--check-refined-status は早期 exit）
  local refined_exit=0
  bash "$0" --check-refined-status "$issue_number" || refined_exit=$?
  if [[ "$refined_exit" -eq 2 ]]; then
    echo "[spawn-controller] ERROR: Status=Refined check failed for issue #${issue_number}" >&2
    exit 1
  fi

  # 5. parallel-spawn check
  # NOTE: 親プロセスは既に L228-259 で parallel check を実行済み。
  # exit 2 (DENY) なら親プロセスが L255 で exit 2 する → _fd_run_gate_checks には到達しない。
  # exit 1 (degrade) または exit 0 (OK) の場合のみここに到達する。
  # SKIP_PARALLEL_CHECK=1 の場合は _PARALLEL_CHECK_EXIT は未設定（既定 0 扱い）。
  # ここでは defensive check として `_PARALLEL_CHECK_EXIT == 2` のみ追加チェックする（通常到達不能）
  if [[ "${_PARALLEL_CHECK_EXIT:-0}" -eq 2 ]]; then
    echo "[spawn-controller] ERROR: parallel spawn denied for issue #${issue_number} (defense-in-depth)" >&2
    exit 1
  fi

  # 6. Atomic rename（one-shot 消費）— TOCTOU 対策で cld-spawn 前に実行
  local consumed_dir="${sup_dir}/consumed"
  mkdir -p "$consumed_dir"
  local ts
  ts=$(date +%s)
  local consumed_path="${consumed_dir}/feature-dev-request-${issue_number}-${ts}.json"

  # mv -n: 同 filesystem 内で atomic rename + no-clobber（並列呼び出しの 2 重消費を防ぐ）
  local mv_output mv_exit=0
  mv_output=$(mv -n "$request_file" "$consumed_path" 2>&1) || mv_exit=$?
  if [[ "$mv_exit" -ne 0 ]]; then
    if echo "$mv_output" | grep -qiE "cross.device|different.*file.*system|Invalid cross"; then
      # cross-filesystem fallback: cp + rm（race window あり、best effort）
      if ! cp "$request_file" "$consumed_path" 2>/dev/null; then
        echo "[spawn-controller] ERROR: approval consume copy failed (cross-fs)" >&2
        exit 1
      fi
      if ! rm "$request_file" 2>/dev/null; then
        rm -f "$consumed_path"
        echo "[spawn-controller] ERROR: approval consume unlink failed (cross-fs)" >&2
        exit 1
      fi
    elif [[ ! -f "$request_file" ]]; then
      # race: 別プロセスが既に消費
      echo "[spawn-controller] ERROR: approval trail already consumed by a parallel caller (race lost)" >&2
      exit 1
    else
      echo "[spawn-controller] ERROR: approval atomic rename failed: $mv_output" >&2
      exit 1
    fi
  fi

  echo "[spawn-controller] ✓ approval consumed: ${consumed_path}" >&2
}
# --- #1644: feature-dev gate checks ここまで ---

# --- #1635: --check-refined-status サブコマンド（cld-spawn / parallel check 不要のため早期分岐）---
# MCP tool (twl_spawn_feature_dev) および feature-dev gate（#1644 で bash 移植）から shell out して
# Issue Status=Refined のみを検証する。co-autopilot 用の --pre-check-issue (後段) と同等ロジックの早期サブコマンド版。
# parallel check を経由しないことで intervention-log の SKIP_PARALLEL_CHECK 汚染を回避する。
# exit 0 = Refined / exit 2 = not Refined or invalid input / exit 0 (fail-open) = TWL_BOARD_NUMBER 未設定
if [[ "${1:-}" == "--check-refined-status" ]]; then
  _RS_ISSUE="${2:-}"
  if [[ ! "$_RS_ISSUE" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: --check-refined-status の値は正整数である必要があります: ${_RS_ISSUE}" >&2
    exit 2
  fi
  _rs_board_number="${TWL_BOARD_NUMBER:-$(python3 -m twl.config get project-board.number 2>/dev/null || echo "")}"
  _rs_board_owner="${TWL_BOARD_OWNER:-$(python3 -m twl.config get project-board.owner 2>/dev/null || echo "shuu5")}"
  if [[ -n "$_rs_board_owner" && ! "$_rs_board_owner" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "[spawn-controller] WARN: --check-refined-status: TWL_BOARD_OWNER 不正、Status check をスキップ（fail-open）" >&2
    exit 0
  fi
  if [[ -z "$_rs_board_number" ]]; then
    echo "[spawn-controller] WARN: --check-refined-status: TWL_BOARD_NUMBER 未設定、Status check をスキップ（fail-open）" >&2
    exit 0
  fi
  _rs_issue_status=$(gh project item-list "$_rs_board_number" --owner "$_rs_board_owner" --format json 2>/dev/null \
    | python3 -c "import json,sys; n=int('${_RS_ISSUE}'); items=json.load(sys.stdin).get('items',[]); \
      match=[i.get('status','') for i in items if i.get('content',{}).get('number')==n]; \
      print(match[0] if match else '')" 2>/dev/null || echo "")
  if [[ -z "$_rs_issue_status" ]]; then
    echo "[spawn-controller] WARN: --check-refined-status: Issue #${_RS_ISSUE} の Status を取得できませんでした（board 未登録または API エラー）。fail-open します" >&2
    exit 0
  fi
  if [[ "$_rs_issue_status" != "Refined" ]]; then
    echo "[spawn-controller] DENY: Issue #${_RS_ISSUE} Status must be Refined (current: ${_rs_issue_status})" >&2
    echo "[spawn-controller] HINT: /twl:co-issue refine #${_RS_ISSUE} を spawn してください（唯一の正規経路）" >&2
    echo "[spawn-controller] HINT: bash \"$TWILL_ROOT/plugins/twl/scripts/spawn-controller.sh\" co-issue \"refine #${_RS_ISSUE}\"" >&2
    echo "[spawn-controller] (MUST NOT: chain-runner.sh board-status-update を co-issue Phase 4 外から直接実行しない)" >&2
    exit 2
  fi
  exit 0
fi
# --- #1635 --check-refined-status ここまで ---

if [[ ! -x "$CLD_SPAWN" ]]; then
  echo "Error: cld-spawn not executable at $CLD_SPAWN" >&2
  exit 2
fi

# --- 並列 spawn 可否チェック（§11.3, Issue #1116; SU-4 ≤10 並列 OK, observer 計数外, #1560）---
# SKIP_PARALLEL_CHECK=1 で bypass 可（intervention 記録 MUST）
_PARALLEL_CHECK_LIB="$TWILL_ROOT/plugins/twl/scripts/lib/observer-parallel-check.sh"
if [[ "${SKIP_PARALLEL_CHECK:-0}" == "1" ]]; then
  echo "[spawn-controller] WARN: SKIP_PARALLEL_CHECK=1 — §11.3 チェックをスキップ（intervention-log に自動記録。SKIP_PARALLEL_REASON で理由を渡すこと）" >&2
  # 自動記録 (tech-debt #1135、fail-open ポリシー)
  {
    _supervisor_dir="${SUPERVISOR_DIR:-.supervisor}"
    mkdir -p "$_supervisor_dir"
    _reason="$(_sanitize_skip_reason "${SKIP_PARALLEL_REASON:-(reason not provided)}")"
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

# --- #1635: --check-parallel-only サブコマンド ---
# MCP tool (twl_spawn_feature_dev) から shell out して並列チェック結果のみを返す。
# 上の parallel check (L75-86) は既に実行済みのため、その exit code をそのまま返す。
# 引数 <ISSUE_NUM> はログ目的のみ（fn 自体は global state check）。
# exit 0 = OK / exit 1 = degrade mode（warn 出ているが続行可）/ exit 2 = DENY（既に L82 で exit）
# NOTE: --check-refined-status は cld-spawn / parallel check 不要のため L48 直後に分岐済み
if [[ "${1:-}" == "--check-parallel-only" ]]; then
  exit "${_PARALLEL_CHECK_EXIT:-0}"
fi
# --- #1635 --check-parallel-only ここまで ---

VALID_SKILLS=(co-explore co-issue co-architect co-autopilot co-project co-utility co-self-improve feature-dev)

usage() {
  cat >&2 <<EOF
Usage: $(basename "$0") <skill-name> <prompt-file> [cld-spawn extra args...]
       $(basename "$0") co-autopilot <prompt-file>                              # 正規運用: Pilot を 1 つ spawn
       $(basename "$0") feature-dev <issue-number> [--cd PATH] [cld-spawn extra args...]   # Issue #1644
       $(basename "$0") --check-refined-status <ISSUE_NUM>  # Issue #1635: Status=Refined チェックのみ実行
       $(basename "$0") --check-parallel-only <ISSUE_NUM>   # Issue #1635: 並列 spawn チェックのみ実行

Valid skills: ${VALID_SKILLS[*]}
(Accepts with or without "twl:" prefix)

DEPRECATED: --with-chain --issue N は Pilot bypass 経路です (#1650 で default-deny 化)。
  正規運用: co-autopilot <prompt>（--with-chain なし）で Pilot を spawn してください。
  escape hatch: SKIP_PILOT_GATE=1 SKIP_PILOT_REASON='<理由>' を設定してください。

Example:
  $(basename "$0") co-explore /tmp/my-prompt.txt
  $(basename "$0") co-issue /tmp/issue-prompt.txt --timeout 90
  $(basename "$0") co-autopilot /tmp/ctx.txt
  $(basename "$0") feature-dev 1644 --model claude-opus-4-7 --timeout 120
  $(basename "$0") --check-refined-status 1635
  $(basename "$0") --check-parallel-only 1635
EOF
  exit 2
}

if [[ $# -lt 2 ]]; then
  usage
fi

SKILL="$1"
shift 1

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

# Issue #1644: feature-dev は ISSUE_NUMBER を 2nd 引数として受け取る（PROMPT_FILE ではない）
# 既存 6 controller は <skill> <prompt-file> 形式で不変
if [[ "$SKILL_NORMALIZED" == "feature-dev" ]]; then
  ISSUE_NUMBER="${1:-}"
  shift 1
  if [[ ! "$ISSUE_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: feature-dev requires a positive integer issue number as the second arg, got: '${ISSUE_NUMBER:-}'" >&2
    exit 2
  fi
  PROMPT_FILE=""  # feature-dev は prompt file 不使用（後続コードでの参照を防ぐ）
else
  PROMPT_FILE="${1:-}"
  shift 1
  # prompt file 存在確認
  if [[ ! -f "$PROMPT_FILE" ]]; then
    echo "Error: prompt file not found: $PROMPT_FILE" >&2
    exit 2
  fi
fi

# --- #1644: feature-dev early-exit path ---
# co-* skills の通常フロー（PROMPT_FILE 読み込み・size guard・FINAL_PROMPT 構築）と異なる処理が必要のため、
# ここで分岐して exec cld-spawn まで完結させる。
if [[ "$SKILL_NORMALIZED" == "feature-dev" ]]; then
  # feature-dev 専用引数パース
  FD_WORKTREE_PATH=""  # --cd <path>: 指定時は worktree auto-create をスキップ
  FD_PASS_ARGS=()      # cld-spawn への透過引数（--model, --timeout 等）
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --cd)  FD_WORKTREE_PATH="${2:-}"; shift 2 ;;
      *)     FD_PASS_ARGS+=("$1"); shift ;;
    esac
  done

  # 残り引数（PASS_ARGS）に invalid flag が含まれていないか検査
  for arg in "${FD_PASS_ARGS[@]+"${FD_PASS_ARGS[@]}"}"; do
    case "$arg" in
      --help|-h|--version|-v)
        cat >&2 <<EOF
Error: '$arg' は cld-spawn の有効な option ではなく、prompt として誤注入される。
指定しないこと。
EOF
        exit 2
        ;;
    esac
  done

  # Gate checks（SKIP_LAYER2=1 で bypass、AC-4.6: 2 wave 維持）
  if [[ "${SKIP_LAYER2:-0}" == "1" ]]; then
    _skip_reason="$(_sanitize_skip_reason "${SKIP_LAYER2_REASON:-未設定}")"
    echo "[spawn-controller] WARN: SKIP_LAYER2=1 — feature-dev gate checks bypassed (issue=${ISSUE_NUMBER}, reason=${_skip_reason})" >&2
    {
      _sup_dir="${SUPERVISOR_DIR:-.supervisor}"
      mkdir -p "$_sup_dir"
      printf '%s SKIP_LAYER2=1 bypass: feature-dev issue=%s, reason=%s\n' \
        "$(date -u +%FT%TZ)" \
        "$ISSUE_NUMBER" \
        "$_skip_reason" \
        >> "$_sup_dir/intervention-log.md"
    } || {
      echo "[spawn-controller] WARN: intervention-log append failed (continuing spawn)" >&2
      true
    }
  else
    _fd_run_gate_checks "$ISSUE_NUMBER"
  fi

  # Worktree: --cd 未指定時は auto-create（idempotent: 既存ならスキップ）
  if [[ -z "$FD_WORKTREE_PATH" ]]; then
    FD_BRANCH="fd-${ISSUE_NUMBER}"
    FD_WORKTREE_PATH="$TWILL_ROOT/worktrees/$FD_BRANCH"
    if [[ ! -d "$FD_WORKTREE_PATH" ]]; then
      echo "[spawn-controller] worktree 作成中: ${FD_WORKTREE_PATH} (branch=${FD_BRANCH})" >&2
      git -C "$TWILL_ROOT" worktree add -b "$FD_BRANCH" "$FD_WORKTREE_PATH" main \
        || { echo "[spawn-controller] ERROR: git worktree add failed" >&2; exit 1; }
      echo "[spawn-controller] ✓ worktree 作成完了: ${FD_WORKTREE_PATH}" >&2
    else
      echo "[spawn-controller] worktree 既存: ${FD_WORKTREE_PATH} (作成スキップ)" >&2
    fi
  fi

  # Hook 設置（pre-push: main への push を block、per-worktree core.hooksPath 方式）
  _install_script="$TWILL_ROOT/plugins/twl/scripts/install-git-hooks.sh"
  if [[ -x "$_install_script" ]]; then
    bash "$_install_script" --worktree "$FD_WORKTREE_PATH" >&2 || \
      echo "[spawn-controller] WARN: pre-push hook install failed (続行)" >&2
  fi

  # FINAL_PROMPT 構築（skill prefix + provenance + MUST 注入）
  _fd_provenance="$(_emit_provenance_section)"
  FINAL_PROMPT_FD="/feature-dev:feature-dev #${ISSUE_NUMBER}
${_fd_provenance}

MUST: worktree 内で作業すること（main 直接編集禁止）。全変更は PR 経由で merge する。
MUST: main への直接 push は禁止（pre-push hook が block）。bypass は --no-verify （ユーザー裁量）のみ。"

  # window 名は --window-name 明示が無ければ wt-fd-<N> を使用
  FD_WINDOW_NAME="wt-fd-${ISSUE_NUMBER}"
  HAS_WINDOW_NAME_FD=false
  for arg in "${FD_PASS_ARGS[@]+"${FD_PASS_ARGS[@]}"}"; do
    if [[ "$arg" == "--window-name" ]]; then HAS_WINDOW_NAME_FD=true; break; fi
  done
  WINDOW_ARG_FD=()
  [[ "$HAS_WINDOW_NAME_FD" == "false" ]] && WINDOW_ARG_FD=(--window-name "$FD_WINDOW_NAME")

  echo ">>> Monitor 再 arm 必要: ${FD_WINDOW_NAME}"
  exec "$CLD_SPAWN" \
    --cd "$FD_WORKTREE_PATH" \
    "${WINDOW_ARG_FD[@]+"${WINDOW_ARG_FD[@]}"}" \
    "${FD_PASS_ARGS[@]+"${FD_PASS_ARGS[@]}"}" \
    "$FINAL_PROMPT_FD"
fi
# --- #1644: feature-dev early-exit path ここまで ---

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
# Status が Refined でない場合は error abort し、/twl:co-issue refine #N を hint として出力。
# NOTE: feature-dev 用には #1635 で別 path (--check-refined-status) を提供（feature-dev は
# 先頭の SKIP_LAYER2 fallback 分岐 L130 で exit するため、ここに到達しない）。
if [[ -n "$PRE_CHECK_ISSUE" && "$SKILL_NORMALIZED" == "co-autopilot" ]]; then
  # CRITICAL fix: 整数バリデーション（CHAIN_ISSUE の ^[1-9][0-9]*$ パターン準拠）
  if [[ ! "$PRE_CHECK_ISSUE" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: --pre-check-issue の値は正整数である必要があります: ${PRE_CHECK_ISSUE}" >&2
    exit 2
  fi
  _board_number="${TWL_BOARD_NUMBER:-$(python3 -m twl.config get project-board.number 2>/dev/null || echo "")}"
  _board_owner="${TWL_BOARD_OWNER:-$(python3 -m twl.config get project-board.owner 2>/dev/null || echo "shuu5")}"
  # WARNING fix: TWL_BOARD_OWNER 形式検証（^[A-Za-z0-9._-]+$）
  if [[ -n "$_board_owner" && ! "$_board_owner" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "[spawn-controller] WARN: --pre-check-issue: TWL_BOARD_OWNER の値が不正です（^[A-Za-z0-9._-]+$）。Status check をスキップします。" >&2
    _board_number=""
  fi
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
      echo "[spawn-controller]   /twl:co-issue refine #${PRE_CHECK_ISSUE} を spawn してください（唯一の正規経路）" >&2
      echo "[spawn-controller]   bash \"$TWILL_ROOT/plugins/twl/skills/su-observer/scripts/spawn-controller.sh\" co-issue \"refine #${PRE_CHECK_ISSUE}\"" >&2
      echo "[spawn-controller]   (MUST NOT: chain-runner.sh board-status-update を co-issue Phase 4 外から直接実行しない。emergency bypass は --bypass-status-gate + PR description 記載)" >&2
      exit 2
    fi
  else
    echo "[spawn-controller] WARN: --pre-check-issue: TWL_BOARD_NUMBER 未設定のため Status=Refined check をスキップ" >&2
  fi
fi
# --- pre-check ここまで ---

if [[ "$WITH_CHAIN" == "true" ]]; then
  # #1650: default-deny gate — SKIP_PILOT_GATE=1 + SKIP_PILOT_REASON='...' の escape hatch 以外は exit 2
  # ADR-037 SKIP_ISSUE_GATE と同じ pattern (SKIP_REASON 必須)
  if [[ "${SKIP_PILOT_GATE:-0}" == "1" ]]; then
    _skip_pilot_reason="${SKIP_PILOT_REASON:-}"
    if [[ -z "$_skip_pilot_reason" ]]; then
      cat >&2 <<'DENY'
ERROR: SKIP_PILOT_GATE=1 を使う場合は SKIP_PILOT_REASON を必ず指定してください。
  例: SKIP_PILOT_GATE=1 SKIP_PILOT_REASON='緊急対応: Wave U.audit-fix hotfix' spawn-controller.sh co-autopilot <prompt> --with-chain --issue N
  詳細: plugins/twl/skills/su-observer/refs/pitfalls-catalog.md §13.5
DENY
      exit 2
    fi
    _skip_pilot_reason="$(_sanitize_skip_reason "$_skip_pilot_reason")"
    echo "[spawn-controller] WARN: SKIP_PILOT_GATE=1 — --with-chain --issue gate bypassed (issue=${CHAIN_ISSUE:-?}, reason=${_skip_pilot_reason})" >&2
    {
      _sup_dir="${SUPERVISOR_DIR:-.supervisor}"
      mkdir -p "$_sup_dir"
      printf '%s SKIP_PILOT_GATE=1: %s\n' \
        "$(date -u +%FT%TZ)" \
        "$_skip_pilot_reason" \
        >> "$_sup_dir/intervention-log.md"
    } || {
      echo "[spawn-controller] WARN: intervention-log append failed (continuing spawn)" >&2
      true
    }
  else
    cat >&2 <<'DENY'
ERROR: --with-chain --issue は Pilot bypass 経路です（Worker が main で直接起動し、main push 事故の原因になります）。
  再現コマンド: spawn-controller.sh co-autopilot <prompt> --with-chain --issue N
  正規運用: spawn-controller.sh co-autopilot <prompt>（--with-chain なし）で Pilot を 1 つ spawn し、
            Pilot が deps graph に基づく Wave 計画と Worker 起動を担当する。
  回避が必要な場合: SKIP_PILOT_GATE=1 SKIP_PILOT_REASON='<理由>' を設定してください。
  詳細: plugins/twl/skills/su-observer/refs/pitfalls-catalog.md §13.5
  関連: bug-4 (Wave U.Y main 直接 push d6cb9859), #1644 ADR-041
DENY
    exit 2
  fi
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

# NOTE: _get_host_alias / _emit_provenance_section は冒頭（Issue #1644 で feature-dev path 用に移動）で定義済み

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
