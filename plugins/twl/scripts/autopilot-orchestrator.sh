#!/usr/bin/env bash
# autopilot-orchestrator.sh - Pilot 側 Phase 実行オーケストレーター
#
# Phase ループ・ポーリング・merge-gate・window 管理・サマリー集計を
# 単一スクリプトで完結させる。LLM は判断のために使う。機械的にできることは機械に任せる。
#
# Usage:
#   bash autopilot-orchestrator.sh --plan plan.yaml --phase N --session session.json \
#     --project-dir DIR --autopilot-dir DIR [--repos JSON]
#   bash autopilot-orchestrator.sh --summary --session session.json --autopilot-dir DIR
set -euo pipefail

SCRIPTS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib/python-env.sh
source "${SCRIPTS_ROOT}/lib/python-env.sh"
# shellcheck source=./lib/deltaspec-helpers.sh
source "${SCRIPTS_ROOT}/lib/deltaspec-helpers.sh"
# shellcheck source=chain-steps.sh
source "${SCRIPTS_ROOT}/chain-steps.sh" 2>/dev/null || true

# --- session-state.sh 検出 ---
SESSION_STATE_CMD="${SESSION_STATE_CMD-$HOME/ubuntu-note-system/scripts/session-state.sh}"
if [[ -n "$SESSION_STATE_CMD" && "$SESSION_STATE_CMD" == /* && "$SESSION_STATE_CMD" != *..* && -x "$SESSION_STATE_CMD" ]]; then
  USE_SESSION_STATE=true
else
  USE_SESSION_STATE=false
fi

# --- 定数 ---
MAX_PARALLEL="${DEV_AUTOPILOT_MAX_PARALLEL:-4}"
if ! [[ "$MAX_PARALLEL" =~ ^[1-9][0-9]*$ ]]; then
  MAX_PARALLEL=4
fi
MAX_POLL="${DEV_AUTOPILOT_MAX_POLL:-720}"
MAX_NUDGE="${DEV_AUTOPILOT_MAX_NUDGE:-3}"
NUDGE_TIMEOUT="${DEV_AUTOPILOT_NUDGE_TIMEOUT:-30}"
POLL_INTERVAL=10
# stagnate 判定閾値（秒）: inject skip が連続してこの時間を超えたら WARN (#469, #472, #475 共通化）
AUTOPILOT_STAGNATE_SEC="${AUTOPILOT_STAGNATE_SEC:-600}"

# --- usage ---
usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Phase 実行モード:
  --plan FILE           plan.yaml パス（必須）
  --phase N             Phase 番号（必須）
  --session FILE        session.json パス（必須）
  --project-dir DIR     プロジェクトディレクトリ（必須）
  --autopilot-dir DIR   .autopilot ディレクトリ（必須）
  --repos JSON          クロスリポジトリ設定 JSON（省略可）

サマリーモード:
  --summary             サマリー集計モード
  --session FILE        session.json パス（必須）
  --autopilot-dir DIR   .autopilot ディレクトリ（必須）

共通:
  -h, --help            このヘルプを表示
EOF
}

# --- 引数パーサー ---
PLAN_FILE=""
PHASE=""
SESSION_FILE=""
PROJECT_DIR=""
AUTOPILOT_DIR=""
REPOS_JSON=""
SUMMARY_MODE=false
WORKER_MODEL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan)          PLAN_FILE="$2"; shift 2 ;;
    --phase)         PHASE="$2"; shift 2 ;;
    --session)       SESSION_FILE="$2"; shift 2 ;;
    --project-dir)   PROJECT_DIR="$2"; shift 2 ;;
    --autopilot-dir) AUTOPILOT_DIR="$2"; shift 2 ;;
    --repos)         REPOS_JSON="$2"; shift 2 ;;
    --summary)       SUMMARY_MODE=true; shift ;;
    --model)         WORKER_MODEL="$2"; shift 2 ;;
    -h|--help)       usage; exit 0 ;;
    *) echo "Error: 不明なオプション: $1" >&2; exit 1 ;;
  esac
done

export AUTOPILOT_DIR

# AUTOPILOT_DIR 未設定 warning
if [[ -z "$AUTOPILOT_DIR" ]]; then
  echo "WARN: AUTOPILOT_DIR が未設定です。state.py の fallback で自動解決を試みますが、bare sibling 構成では誤ったパスを参照する可能性があります。export AUTOPILOT_DIR=<.autopilot への絶対パス> を設定してください。" >&2
fi

# --- model 解決: CLI arg > plan.yaml > デフォルト（sonnet） ---
# plan.yaml の model フィールドは Phase 実行モードで PLAN_FILE が確定後に読み込む
# （SUMMARY_MODE では不要）
FALLBACK_MODEL="${DEV_AUTOPILOT_FALLBACK_MODEL:-opus}"
# WORKER_MODEL はモード分岐後に plan.yaml から補完される（下記）

# --- モード分岐 ---
if [[ "$SUMMARY_MODE" == "true" ]]; then
  # サマリーモードのバリデーション
  if [[ -z "$SESSION_FILE" || -z "$AUTOPILOT_DIR" ]]; then
    echo "Error: --summary には --session と --autopilot-dir が必須です" >&2
    exit 1
  fi
  for _varname in SESSION_FILE AUTOPILOT_DIR; do
    _val="${!_varname}"
    if [[ "$_val" != /* ]]; then
      echo "Error: --$(echo "$_varname" | tr '[:upper:]' '[:lower:]' | tr '_' '-') は絶対パスで指定してください: $_val" >&2
      exit 1
    fi
    if [[ "$_val" =~ /\.\./ || "$_val" =~ /\.\.$ ]]; then
      echo "Error: --$(echo "$_varname" | tr '[:upper:]' '[:lower:]' | tr '_' '-') にパストラバーサルは使用できません: $_val" >&2
      exit 1
    fi
  done
else
  # Phase 実行モードのバリデーション
  if [[ -z "$PLAN_FILE" || -z "$PHASE" || -z "$SESSION_FILE" || -z "$PROJECT_DIR" || -z "$AUTOPILOT_DIR" ]]; then
    echo "Error: --plan, --phase, --session, --project-dir, --autopilot-dir は必須です" >&2
    exit 1
  fi
  if ! [[ "$PHASE" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: --phase は正の整数で指定してください: $PHASE" >&2
    exit 1
  fi

  # パス安全性検証（autopilot-launch.sh と同じパターン）
  for _varname in PLAN_FILE SESSION_FILE PROJECT_DIR AUTOPILOT_DIR; do
    _val="${!_varname}"
    if [[ "$_val" != /* ]]; then
      echo "Error: --$(echo "$_varname" | tr '[:upper:]' '[:lower:]' | tr '_' '-') は絶対パスで指定してください: $_val" >&2
      exit 1
    fi
    if [[ "$_val" =~ /\.\./ || "$_val" =~ /\.\.$ ]]; then
      echo "Error: --$(echo "$_varname" | tr '[:upper:]' '[:lower:]' | tr '_' '-') にパストラバーサルは使用できません: $_val" >&2
      exit 1
    fi
  done
fi

# =============================================================================
# ユーティリティ関数
# =============================================================================

# Phase から Issue リストを取得（クロスリポジトリ形式 + レガシー形式対応）
# 出力: ISSUES_WITH_REPO 配列（"repo_id:number" 形式）
get_phase_issues() {
  local phase="$1"
  local plan_file="$2"

  ISSUES_WITH_REPO=()

  local phase_block
  phase_block=$(sed -n "/  - phase: ${phase}/,/  - phase:/p" "$plan_file")

  if echo "$phase_block" | grep -q '{ number:'; then
    # クロスリポジトリ形式
    while IFS= read -r line; do
      local num repo
      num=$(echo "$line" | grep -oP 'number:\s*\K\d+')
      repo=$(echo "$line" | grep -oP 'repo:\s*\K[a-zA-Z0-9_-]+')
      [[ -n "$num" ]] && ISSUES_WITH_REPO+=("${repo}:${num}")
    done <<< "$(echo "$phase_block" | grep '{ number:')"
    # 混合フォーマット時の bare int
    local bare_ints
    bare_ints=$(echo "$phase_block" | grep -P '^\s+- \d+$' | grep -oP '\d+' || true)
    for bi in $bare_ints; do
      ISSUES_WITH_REPO+=("_default:${bi}")
    done
  else
    # レガシー形式: bare integer
    local issues
    issues=$(echo "$phase_block" | grep -oP '    - \K\d+' || true)
    for issue in $issues; do
      ISSUES_WITH_REPO+=("_default:${issue}")
    done
  fi
}

# Worker の tmux window 名を解決する
# autopilot-launch.sh が state に保存した window 名を優先し、未設定時はレガシーパターンにフォールバック
resolve_worker_window() {
  local issue="$1"
  local repo_id="${2:-_default}"
  local -a _repo_args=()
  [[ "$repo_id" != "_default" ]] && _repo_args=(--repo "$repo_id")

  local name
  name=$(python3 -m twl.autopilot.state read --type issue "${_repo_args[@]}" --issue "$issue" --field window 2>/dev/null || echo "")
  if [[ -n "$name" ]]; then
    printf '%s' "$name"
    return
  fi

  # フォールバック: tmux window 名パターン検索
  local pattern
  if [[ "$repo_id" == "_default" ]]; then
    pattern="ap-.*[-i]${issue}[-]"
  else
    pattern="ap-${repo_id}-.*[-i]${issue}[-]"
  fi
  local found
  found=$(tmux list-windows -F '#{window_name}' 2>/dev/null | grep -E "$pattern" | head -1 || echo "")
  if [[ -n "$found" ]]; then
    printf '%s' "$found"
    return
  fi

  # パターン検索も失敗 → 空文字列（crash-detect スキップ）
  printf ''
}

# Issue のリポジトリコンテキストを解決
# 副作用: グローバル変数 ISSUE, ISSUE_REPO_ID, ISSUE_REPO_OWNER, ISSUE_REPO_NAME, ISSUE_REPO_PATH を上書きする
resolve_issue_repo_context() {
  local entry="$1"  # "repo_id:number"
  ISSUE="${entry#*:}"
  ISSUE_REPO_ID="${entry%%:*}"

  ISSUE_REPO_OWNER=""
  ISSUE_REPO_NAME=""
  ISSUE_REPO_PATH=""

  if [[ "$ISSUE_REPO_ID" != "_default" && -n "$REPOS_JSON" ]]; then
    ISSUE_REPO_OWNER=$(echo "$REPOS_JSON" | jq -r --arg k "$ISSUE_REPO_ID" '.[$k].owner // empty')
    ISSUE_REPO_NAME=$(echo "$REPOS_JSON" | jq -r --arg k "$ISSUE_REPO_ID" '.[$k].name // empty')
    ISSUE_REPO_PATH=$(echo "$REPOS_JSON" | jq -r --arg k "$ISSUE_REPO_ID" '.[$k].path // empty')
  fi
}

# skip/done フィルタリング
filter_active_issues() {
  ACTIVE_ISSUES=()
  local -a filtered_entries=()

  for entry in "${ISSUES_WITH_REPO[@]}"; do
    resolve_issue_repo_context "$entry"

    local status
    status=$(python3 -m twl.autopilot.state read --type issue --issue "$ISSUE" --field status 2>/dev/null || echo "")

    if [[ "$status" == "done" ]]; then
      echo "[orchestrator] Issue #${ISSUE}: skip (already done)" >&2
      continue
    fi

    if bash "$SCRIPTS_ROOT/autopilot-should-skip.sh" "$PLAN_FILE" "$ISSUE" 2>/dev/null; then
      echo "[orchestrator] Issue #${ISSUE}: skip (dependency failed)" >&2
      python3 -m twl.autopilot.state write --type issue --issue "$ISSUE" --role pilot \
        --set "status=failed" --set 'failure={"message":"dependency_failed","step":"skip"}' || true
      continue
    fi

    ACTIVE_ISSUES+=("$ISSUE")
    filtered_entries+=("$entry")
  done

  ACTIVE_ENTRIES=("${filtered_entries[@]+"${filtered_entries[@]}"}")
}

# Worker を起動
# 引数: entry [model_override]
launch_worker() {
  local entry="$1"
  local model_override="${2:-}"
  resolve_issue_repo_context "$entry"

  # --- 不変条件 B: worktree 作成は Pilot 専任 ---
  # Worker 起動前に worktree を作成し、worktree パスを --worktree-dir で渡す
  local effective_project_dir="$PROJECT_DIR"
  if [[ -n "$ISSUE_REPO_PATH" ]]; then
    effective_project_dir="$ISSUE_REPO_PATH"
  fi

  local worktree_dir=""
  # 既存 worktree の確認（冪等性: branch が state に記録済みの場合）
  local -a _repo_args=()
  [[ "$ISSUE_REPO_ID" != "_default" ]] && _repo_args=(--repo "$ISSUE_REPO_ID")
  local existing_branch
  existing_branch=$(python3 -m twl.autopilot.state read --type issue "${_repo_args[@]}" --issue "$ISSUE" --field branch 2>/dev/null || echo "")
  # ブランチ名バリデーション（パストラバーサル防止、cleanup_worker と同一パターン）
  if [[ -n "$existing_branch" && "$existing_branch" =~ ^[a-zA-Z0-9._/\-]+$ ]]; then
    local candidate_dir="$effective_project_dir/worktrees/$existing_branch"
    if [[ -d "$candidate_dir" ]]; then
      worktree_dir="$candidate_dir"
      echo "[orchestrator] Issue #${ISSUE}: 既存 worktree を使用: $worktree_dir" >&2
    fi
  fi

  # 既存 worktree が見つからない場合は Python モジュールで作成
  if [[ -z "$worktree_dir" ]]; then
    local create_args=("#${ISSUE}")
    if [[ -n "$ISSUE_REPO_PATH" ]]; then
      create_args+=(--repo-path "$ISSUE_REPO_PATH")
    fi
    if [[ -n "$ISSUE_REPO_OWNER" && -n "$ISSUE_REPO_NAME" ]]; then
      create_args+=(-R "${ISSUE_REPO_OWNER}/${ISSUE_REPO_NAME}")
    fi
    local wt_output
    wt_output=$(python3 -m twl.autopilot.worktree create "${create_args[@]}" 2>&1) || {
      echo "[orchestrator] Issue #${ISSUE}: worktree 作成失敗: $wt_output" >&2
      python3 -m twl.autopilot.state write --type issue --issue "$ISSUE" --role pilot \
        --set "status=failed" \
        --set 'failure={"message":"worktree_create_failed","step":"launch_worker"}' || true
      return 1
    }
    # 改行のみ除去（スペースはパスの一部になり得るため tr -d '\n' を使用）
    worktree_dir=$(echo "$wt_output" | grep "^パス: " | head -1 | sed 's/^パス: //' | tr -d '\n')
    # worktree_dir のバリデーション（絶対パス + パストラバーサル防止）
    if [[ -z "$worktree_dir" || "$worktree_dir" != /* || "$worktree_dir" =~ /\.\./ || "$worktree_dir" =~ /\.\.$ || ! -d "$worktree_dir" ]]; then
      echo "[orchestrator] Issue #${ISSUE}: worktree パスを取得できません: $wt_output" >&2
      python3 -m twl.autopilot.state write --type issue --issue "$ISSUE" --role pilot \
        --set "status=failed" \
        --set 'failure={"message":"worktree_path_resolve_failed","step":"launch_worker"}' || true
      return 1
    fi
    echo "[orchestrator] Issue #${ISSUE}: worktree 作成完了: $worktree_dir" >&2
  fi

  # CRG graph DB symlink（main の DB を参照、#532）
  local _crg_main="${effective_project_dir}/main/.code-review-graph"
  [[ -d "$_crg_main" && ! -e "$worktree_dir/.code-review-graph" ]] && ln -sf "$_crg_main" "$worktree_dir/.code-review-graph"

  local effective_model="${model_override:-${WORKER_MODEL:-sonnet}}"
  local launch_args=(
    --issue "$ISSUE"
    --project-dir "$PROJECT_DIR"
    --autopilot-dir "$AUTOPILOT_DIR"
    --worktree-dir "$worktree_dir"
    --model "$effective_model"
  )

  if [[ -n "$ISSUE_REPO_OWNER" && -n "$ISSUE_REPO_NAME" ]]; then
    launch_args+=(--repo-owner "$ISSUE_REPO_OWNER" --repo-name "$ISSUE_REPO_NAME")
  fi
  if [[ -n "$ISSUE_REPO_PATH" ]]; then
    launch_args+=(--repo-path "$ISSUE_REPO_PATH")
  fi

  bash "$SCRIPTS_ROOT/autopilot-launch.sh" "${launch_args[@]}"
}

# Worker 完了後のクリーンアップ（tmux window kill + remote branch delete）
cleanup_worker() {
  local issue="$1"
  local entry="${2:-_default:${issue}}"
  local repo_id="${entry%%:*}"
  local window_name
  window_name=$(resolve_worker_window "$issue" "$repo_id")
  echo "[orchestrator] cleanup: Issue #${issue} — window/branch クリーンアップ" >&2

  # terminal guard: status が非 terminal なら force-fail（Issue #295）
  local -a _cw_state_args=()
  [[ "$repo_id" != "_default" ]] && _cw_state_args=(--repo "$repo_id")
  local _cw_status
  _cw_status=$(python3 -m twl.autopilot.state read --type issue "${_cw_state_args[@]}" --issue "$issue" --field status 2>/dev/null || echo "")
  case "$_cw_status" in
    merge-ready|done|failed|conflict) ;;
    *)
      echo "[orchestrator] WARNING: cleanup_worker for Issue #${issue} with non-terminal status=${_cw_status}. Force-failing." >&2
      python3 -m twl.autopilot.state write --type issue "${_cw_state_args[@]}" --issue "$issue" --role pilot \
        --set "status=failed" \
        --set 'failure={"message":"non_terminal_at_cleanup","step":"orchestrator-cleanup"}' || true
      ;;
  esac

  # Step 1: tmux window を先に終了（Worker がworktreeで動作していない状態を保証してから削除）
  tmux kill-window -t "$window_name" 2>/dev/null || true

  # REPO_MODE 自動判定（mergegate.py と同一パターン）
  local repo_mode _git_dir
  _git_dir=$(git rev-parse --git-dir 2>/dev/null || echo "")
  if [[ "$_git_dir" == ".git" || -z "$_git_dir" ]]; then
    repo_mode="standard"
  else
    repo_mode="worktree"
  fi

  local branch
  branch=$(python3 -m twl.autopilot.state read --type issue --issue "$issue" --field branch 2>/dev/null || echo "")
  # ブランチ名バリデーション（コマンドインジェクション防止）
  if [[ -n "$branch" && "$branch" =~ ^[a-zA-Z0-9._/\-]+$ ]]; then
    # Step 2: worktree削除（ローカルブランチ込み）— bare repo（worktreeモード）のみ実行
    if [[ "$repo_mode" == "worktree" ]]; then
      bash "$SCRIPTS_ROOT/worktree-delete.sh" "$branch" 2>/dev/null || \
        echo "[orchestrator] Issue #${issue}: ⚠️ worktree削除失敗（クリーンアップは続行）" >&2
    fi

    # Step 3: リモートブランチ削除（クロスリポ対応）
    resolve_issue_repo_context "$entry"
    # ISSUE_REPO_PATH パストラバーサル防止: 絶対パスかつ ".." を含まないことを確認
    if [[ -n "$ISSUE_REPO_PATH" && "$ISSUE_REPO_PATH" == /* && "$ISSUE_REPO_PATH" != *..* ]]; then
      git -C "$ISSUE_REPO_PATH" push origin --delete "$branch" 2>/dev/null || true
    else
      git push origin --delete "$branch" 2>/dev/null || true
    fi
  fi
}

# health-check fallback 処理（poll_single / poll_phase 共通）
# 引数:
#   $1: issue 番号
#   $2: window_name
#   $3: entry（launch_worker 用）
#   $4: health_exit（health-check.sh の終了コード）
#   $5: health_stderr（health-check.sh の stderr 出力）
#   $6...: state read 追加引数（クロスリポ用 --repo REPO_ID など）
handle_health_check_fallback() {
  local issue="$1"
  local window_name="$2"
  local entry="$3"
  local health_exit="$4"
  local health_stderr="$5"
  shift 5
  local -a state_repo_args=("$@")

  if [[ "$health_exit" -eq 3 ]]; then
    # API overload stall: fallback to different model (1 回のみ)
    local fallback_count
    fallback_count=$(python3 -m twl.autopilot.state read --type issue "${state_repo_args[@]}" --issue "$issue" --field fallback_count 2>/dev/null || echo "0")
    fallback_count="${fallback_count:-0}"
    if [[ "$fallback_count" -ge 1 ]]; then
      echo "[orchestrator] Issue #${issue}: API overload stall + fallback 上限到達 — failed" >&2
      python3 -m twl.autopilot.state write --type issue "${state_repo_args[@]}" --issue "$issue" --role pilot \
        --set "status=failed" \
        --set 'failure={"message":"api_overload_stall_no_fallback","step":"polling"}' || true
    else
      echo "[orchestrator] Issue #${issue}: API overload — fallback to ${FALLBACK_MODEL} (attempt 1/1)" >&2
      tmux kill-window -t "$window_name" 2>/dev/null || true
      python3 -m twl.autopilot.state write --type issue "${state_repo_args[@]}" --issue "$issue" --role pilot \
        --set "fallback_count=1" || true
      launch_worker "$entry" "$FALLBACK_MODEL" || \
        echo "[orchestrator] Issue #${issue}: fallback Worker 起動失敗" >&2
    fi
  elif [[ "$health_exit" -eq 1 && -z "$health_stderr" ]]; then
    if [[ "${NUDGE_COUNTS[$issue]:-0}" -lt "$MAX_NUDGE" ]]; then
      echo "[orchestrator] Issue #${issue}: health-check stall 検知 — 汎用 nudge" >&2
      tmux send-keys -t "$window_name" "" Enter 2>/dev/null || true
      NUDGE_COUNTS[$issue]=$(( ${NUDGE_COUNTS[$issue]:-0} + 1 ))
    else
      echo "[orchestrator] Issue #${issue}: health-check stall + nudge 上限到達 — failed" >&2
      python3 -m twl.autopilot.state write --type issue "${state_repo_args[@]}" --issue "$issue" --role pilot \
        --set "status=failed" \
        --set 'failure={"message":"health_check_stall","step":"polling"}'
    fi
  fi
}

# rate-limit パターン検知（pane 出力から rate limit/overloaded/429 を検出）
# 戻り値: 0=検知, 1=未検知
detect_rate_limit() {
  local window_name="$1"
  local pane_output
  pane_output=$(tmux capture-pane -t "$window_name" -p -S -20 2>/dev/null || true)
  [[ -z "$pane_output" ]] && return 1
  echo "$pane_output" | grep -qiP 'rate.limit|overloaded|429|too.many.requests' && return 0
  return 1
}

# 単一 Issue のポーリング
poll_single() {
  local entry="$1"
  resolve_issue_repo_context "$entry"
  local issue="$ISSUE"
  local window_name
  window_name=$(resolve_worker_window "$issue" "$ISSUE_REPO_ID")
  local poll_count=0
  local rate_limit_resets=0
  local max_rate_limit_resets=3

  while true; do
    # session-state.sh 利用時: wait で効率的にポーリング
    if [[ "$USE_SESSION_STATE" == "true" ]]; then
      "$SESSION_STATE_CMD" wait "$window_name" exited --timeout "$POLL_INTERVAL" 2>/dev/null || true
    else
      sleep "$POLL_INTERVAL"
    fi
    poll_count=$((poll_count + 1))

    local status
    status=$(python3 -m twl.autopilot.state read --type issue --issue "$issue" --field status 2>/dev/null || echo "")

    case "$status" in
      done)
        echo "[orchestrator] Issue #${issue}: 完了" >&2
        cleanup_worker "$issue" "$entry"
        return 0 ;;
      failed)
        echo "[orchestrator] Issue #${issue}: 失敗" >&2
        cleanup_worker "$issue" "$entry"
        return 0 ;;
      merge-ready)
        echo "[orchestrator] Issue #${issue}: merge-ready" >&2
        return 0 ;;
      conflict)
        echo "[orchestrator] Issue #${issue}: コンフリクト検出 — Pilot のリベース待ち" >&2
        return 0 ;;
      running)
        # クラッシュ検知
        local crash_exit=0
        bash "$SCRIPTS_ROOT/crash-detect.sh" --issue "$issue" --window "$window_name" 2>/dev/null || crash_exit=$?
        if [[ "$crash_exit" -eq 2 ]]; then
          echo "[orchestrator] Issue #${issue}: ワーカークラッシュ検知" >&2
          cleanup_worker "$issue" "$entry"
          return 0
        fi

        # current_step terminal 検知 → inject（ADR-018: workflow_done 廃止）
        # inject 済みステップは LAST_INJECTED_STEP でローカルトラッキングして重複防止
        local inject_matched=0
        local _cur_step
        _cur_step=$(python3 -m twl.autopilot.state read --type issue --issue "$issue" --field current_step 2>/dev/null || echo "")
        if [[ -n "$_cur_step" && "${LAST_INJECTED_STEP[$issue]:-}" != "$_cur_step" ]]; then
          if inject_next_workflow "$issue" "$window_name"; then
            LAST_INJECTED_STEP[$issue]="$_cur_step"
            inject_matched=1
          fi
        fi

        if [[ "$inject_matched" -eq 0 ]]; then
          # chain 遷移停止検知 + nudge（パターンマッチ優先）
          local nudge_matched=0
          check_and_nudge "$issue" "$window_name" "$entry" && nudge_matched=1 || true

          # health-check（check_and_nudge でカバーできない stall を補完検知）
          # POLL_INTERVAL=10s × HEALTH_CHECK_INTERVAL=6 = 60s 毎に実行
          if [[ "$nudge_matched" -eq 0 ]]; then
            local hc_counter="${HEALTH_CHECK_COUNTER[$issue]:-0}"
            HEALTH_CHECK_COUNTER[$issue]=$((hc_counter + 1))
            if (( HEALTH_CHECK_COUNTER[$issue] % ${HEALTH_CHECK_INTERVAL:-6} == 0 )); then
              local health_stderr health_exit=0
              health_stderr=$(bash "$SCRIPTS_ROOT/health-check.sh" --issue "$issue" --window "$window_name" 2>&1 1>/dev/null) || health_exit=$?
              # API overload fallback 時は poll_count をリセット
              [[ "$health_exit" -eq 3 ]] && poll_count=0
              handle_health_check_fallback "$issue" "$window_name" "$entry" "$health_exit" "$health_stderr"
            fi
          fi
        fi
        ;;
    esac

    if [[ "$poll_count" -ge "$MAX_POLL" ]]; then
      # rate-limit 検知時はカウンターリセットして継続（上限あり）
      if [[ "$rate_limit_resets" -lt "$max_rate_limit_resets" ]] && detect_rate_limit "$window_name"; then
        rate_limit_resets=$((rate_limit_resets + 1))
        echo "[orchestrator] Issue #${issue}: rate-limit 検知 — ポーリングカウンターリセット（${poll_count}→0, reset ${rate_limit_resets}/${max_rate_limit_resets}）" >&2
        poll_count=0
        continue
      fi
      echo "[orchestrator] Issue #${issue}: タイムアウト（${MAX_POLL}回×${POLL_INTERVAL}秒）" >&2
      python3 -m twl.autopilot.state write --type issue --issue "$issue" --role pilot \
        --set "status=failed" \
        --set 'failure={"message":"poll_timeout","step":"polling"}'
      cleanup_worker "$issue" "$entry"
      return 0
    fi
  done
}

# Phase 全体のポーリング（並列モード）
poll_phase() {
  local -a entries=("$@")
  local poll_count=0
  local rate_limit_resets=0
  local max_rate_limit_resets=3
  local -A cleaned_up=()
  # entry 形式（"repo_id:issue_num"）のままリストを構築（クロスリポ衝突防止）
  local -a issue_list=()
  for e in "${entries[@]}"; do
    issue_list+=("$e")
  done

  while true; do
    local all_resolved=true

    for entry in "${issue_list[@]}"; do
      local repo_id="${entry%%:*}"
      local issue_num="${entry#*:}"
      local status
      local -a _state_read_repo_args=()
      [[ "$repo_id" != "_default" ]] && _state_read_repo_args=(--repo "$repo_id")
      status=$(python3 -m twl.autopilot.state read --type issue "${_state_read_repo_args[@]}" --issue "$issue_num" --field status 2>/dev/null || echo "")

      case "$status" in
        done|failed)
          if [[ -z "${cleaned_up[$entry]:-}" ]]; then
            cleanup_worker "$issue_num" "$entry"
            cleaned_up[$entry]=1
          fi
          continue ;;
        merge-ready|conflict)
          continue ;;
        running)
          all_resolved=false
          local window_name
          window_name=$(resolve_worker_window "$issue_num" "$repo_id")
          local crash_exit=0
          bash "$SCRIPTS_ROOT/crash-detect.sh" --issue "$issue_num" --window "$window_name" 2>/dev/null || crash_exit=$?
          if [[ "$crash_exit" -eq 2 ]]; then
            echo "[orchestrator] Issue #${issue_num}: ワーカークラッシュ検知" >&2
            continue
          fi

          # current_step terminal 検知 → inject（ADR-018: workflow_done 廃止）
          local inject_matched=0
          local _cur_step_p
          _cur_step_p=$(python3 -m twl.autopilot.state read --type issue "${_state_read_repo_args[@]}" --issue "$issue_num" --field current_step 2>/dev/null || echo "")
          if [[ -n "$_cur_step_p" && "${LAST_INJECTED_STEP[$issue_num]:-}" != "$_cur_step_p" ]]; then
            if inject_next_workflow "$issue_num" "$window_name"; then
              LAST_INJECTED_STEP[$issue_num]="$_cur_step_p"
              inject_matched=1
            fi
          fi

          if [[ "$inject_matched" -eq 0 ]]; then
            # chain 遷移停止検知 + nudge（パターンマッチ優先）
            local nudge_matched=0
            check_and_nudge "$issue_num" "$window_name" "$entry" && nudge_matched=1 || true

            # health-check（check_and_nudge でカバーできない stall を補完検知）
            if [[ "$nudge_matched" -eq 0 ]]; then
              local hc_counter="${HEALTH_CHECK_COUNTER[$issue_num]:-0}"
              HEALTH_CHECK_COUNTER[$issue_num]=$((hc_counter + 1))
              if (( HEALTH_CHECK_COUNTER[$issue_num] % ${HEALTH_CHECK_INTERVAL:-6} == 0 )); then
                local health_stderr health_exit=0
                health_stderr=$(bash "$SCRIPTS_ROOT/health-check.sh" --issue "$issue_num" --window "$window_name" 2>&1 1>/dev/null) || health_exit=$?
                handle_health_check_fallback "$issue_num" "$window_name" "$entry" "$health_exit" "$health_stderr" "${_state_read_repo_args[@]}"
              fi
            fi
          fi
          ;;
        *)
          all_resolved=false ;;
      esac
    done

    [[ "$all_resolved" == "true" ]] && break

    poll_count=$((poll_count + 1))
    if [[ "$poll_count" -ge "$MAX_POLL" ]]; then
      # running な Worker のいずれかで rate-limit 検知時はカウンターリセット
      local rate_limited=false
      for entry in "${issue_list[@]}"; do
        local repo_id="${entry%%:*}"
        local issue_num="${entry#*:}"
        local -a _state_read_repo_args=()
        [[ "$repo_id" != "_default" ]] && _state_read_repo_args=(--repo "$repo_id")
        local status
        status=$(python3 -m twl.autopilot.state read --type issue "${_state_read_repo_args[@]}" --issue "$issue_num" --field status 2>/dev/null || echo "")
        if [[ "$status" == "running" ]]; then
          local wn
          wn=$(resolve_worker_window "$issue_num" "$repo_id")
          if detect_rate_limit "$wn"; then
            echo "[orchestrator] Phase: Issue #${issue_num} で rate-limit 検知 — ポーリングカウンターリセット（${poll_count}→0）" >&2
            rate_limited=true
            break
          fi
        fi
      done
      if [[ "$rate_limited" == "true" && "$rate_limit_resets" -lt "$max_rate_limit_resets" ]]; then
        rate_limit_resets=$((rate_limit_resets + 1))
        echo "[orchestrator] Phase: rate-limit リセット（${poll_count}→0, reset ${rate_limit_resets}/${max_rate_limit_resets}）" >&2
        poll_count=0
        continue
      fi
      echo "[orchestrator] Phase: タイムアウト — 未完了 Issue を failed に変換" >&2
      for entry in "${issue_list[@]}"; do
        local repo_id="${entry%%:*}"
        local issue_num="${entry#*:}"
        local -a _state_read_repo_args=()
        [[ "$repo_id" != "_default" ]] && _state_read_repo_args=(--repo "$repo_id")
        local status
        status=$(python3 -m twl.autopilot.state read --type issue "${_state_read_repo_args[@]}" --issue "$issue_num" --field status 2>/dev/null || echo "")
        if [[ "$status" == "running" ]]; then
          python3 -m twl.autopilot.state write --type issue "${_state_read_repo_args[@]}" --issue "$issue_num" --role pilot \
            --set "status=failed" \
            --set 'failure={"message":"poll_timeout","step":"polling"}'
          cleanup_worker "$issue_num" "$entry"
        fi
      done
      break
    fi

    # wait / sleep
    if [[ "$USE_SESSION_STATE" == "true" ]]; then
      local first_running_window=""
      for entry in "${issue_list[@]}"; do
        local repo_id="${entry%%:*}"
        local issue_num="${entry#*:}"
        local -a _state_read_repo_args=()
        [[ "$repo_id" != "_default" ]] && _state_read_repo_args=(--repo "$repo_id")
        local status
        status=$(python3 -m twl.autopilot.state read --type issue "${_state_read_repo_args[@]}" --issue "$issue_num" --field status 2>/dev/null || echo "")
        if [[ "$status" == "running" ]]; then
          first_running_window=$(resolve_worker_window "$issue_num" "$repo_id")
          break
        fi
      done
      if [[ -n "$first_running_window" ]]; then
        "$SESSION_STATE_CMD" wait "$first_running_window" exited --timeout "$POLL_INTERVAL" 2>/dev/null || true
      else
        sleep "$POLL_INTERVAL"
      fi
    else
      sleep "$POLL_INTERVAL"
    fi
  done
}

# =============================================================================
# chain 遷移停止検知 + 自動 nudge
# =============================================================================

# nudge カウントを管理する連想配列
declare -A NUDGE_COUNTS=()
declare -A LAST_OUTPUT_HASH=()
declare -A HEALTH_CHECK_COUNTER=()
declare -A RESOLVE_FAIL_COUNT=()    # AC-3: RESOLVE_FAILED 連続カウント（issue ごと）
declare -A RESOLVE_FAIL_FIRST_TS=() # AC-3: 連続開始タイムスタンプ（秒）
declare -A LAST_INJECTED_STEP=()    # ADR-018: inject 済み current_step（重複 inject 防止）

# chain 停止パターン → 次コマンドマッピング
# パターンが一致した場合: exit 0 + 次コマンドを stdout（空文字 = 空 Enter）
# パターン不一致の場合: exit 1
_nudge_command_for_pattern() {
  local pane_output="$1"
  local issue="$2"
  local entry="${3:-_default:${issue}}"

  # quick Issue の場合は test-ready 系 nudge をスキップ
  local is_quick=""
  is_quick=$(python3 -m twl.autopilot.state read --type issue --issue "$issue" --field is_quick 2>/dev/null || true)
  if [[ -z "$is_quick" ]]; then
    # fallback: gh API で quick ラベルを直接確認
    # クロスリポ対応: entry から ISSUE_REPO_OWNER/ISSUE_REPO_NAME を解決し --repo フラグを付与
    resolve_issue_repo_context "$entry"
    local -a gh_flags=()
    if [[ -n "$ISSUE_REPO_OWNER" && -n "$ISSUE_REPO_NAME" ]]; then
      gh_flags+=(--repo "$ISSUE_REPO_OWNER/$ISSUE_REPO_NAME")
    fi
    if gh issue view "$issue" "${gh_flags[@]}" --json labels --jq '.labels[].name' 2>/dev/null | grep -qxF "quick"; then
      is_quick="true"
    else
      is_quick="false"
    fi
  fi

  if [[ "$is_quick" == "true" ]]; then
    if echo "$pane_output" | grep -qP "setup chain 完了|workflow-test-ready.*で次に進めます"; then
      return 1
    fi
  fi

  if echo "$pane_output" | grep -qP "setup chain 完了"; then
    echo "/twl:workflow-test-ready #${issue}"
  elif echo "$pane_output" | grep -qP ">>> 提案完了"; then
    echo ""
  elif echo "$pane_output" | grep -qP ">>> 実装完了: issue-\d+"; then
    # AC-2 fallback: change-apply 完了後の pr-verify inject（ADR-018: current_step ベース）
    # post-change-apply が terminal step として設定されている場合は inject_next_workflow が自動処理するため
    # ここではパターンマッチ fallback として直接 inject する
    echo "/twl:workflow-pr-verify #${issue}"
  elif echo "$pane_output" | grep -qP "テスト準備.*完了"; then
    echo "/twl:workflow-pr-verify #${issue}"
  elif echo "$pane_output" | grep -qP "workflow-pr-verify.*完了"; then
    echo "/twl:workflow-pr-fix #${issue}"
  elif echo "$pane_output" | grep -qP "workflow-pr-fix.*完了"; then
    echo "/twl:workflow-pr-merge #${issue}"
  elif echo "$pane_output" | grep -qP "PR マージ.*完了|workflow-pr-merge.*完了"; then
    echo ""
  elif echo "$pane_output" | grep -qP "workflow-test-ready.*で次に進めます"; then
    echo "/twl:workflow-test-ready #${issue}"
  else
    return 1
  fi
}

# inject_next_workflow: workflow_done を検知して次の workflow skill を tmux inject する
# 引数: issue, window_name
# 戻り値: 0=inject 成功 or pr-merge 委譲、1=失敗（タイムアウト / resolve 失敗 / バリデーション失敗）
inject_next_workflow() {
  local issue="$1"
  local window_name="$2"

  # --- trace ログファイル ---
  mkdir -p "${AUTOPILOT_DIR}/trace" 2>/dev/null || true  # SUMMARY_MODE 等での再利用を考慮して関数内でも保証
  local _trace_log="${AUTOPILOT_DIR}/trace/inject-$(date -u +%Y%m%d).log"
  local _trace_ts
  _trace_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # --- resolve_next_workflow CLI で次の workflow を決定 ---
  local next_skill next_skill_exit=0
  next_skill=$(python3 -m twl.autopilot.resolve_next_workflow --issue "$issue" 2>/dev/null) || next_skill_exit=$?
  if [[ "$next_skill_exit" -ne 0 || -z "$next_skill" ]]; then
    echo "[orchestrator] Issue #${issue}: WARNING: resolve_next_workflow 失敗 — inject スキップ" >&2
    echo "[${_trace_ts}] issue=${issue} skill=RESOLVE_FAILED result=skip reason=\"resolve_next_workflow exit=${next_skill_exit}\"" >> "$_trace_log" 2>/dev/null || true

    # --- AC-3: stagnate 検知（RESOLVE_FAILED 連続カウント） ---
    local _fail_count="${RESOLVE_FAIL_COUNT[$issue]:-0}"
    local _now
    _now=$(date +%s 2>/dev/null || echo 0)
    if [[ "$_fail_count" -eq 0 ]]; then
      RESOLVE_FAIL_FIRST_TS[$issue]="$_now"
    fi
    RESOLVE_FAIL_COUNT[$issue]=$(( _fail_count + 1 ))
    local _elapsed=$(( _now - ${RESOLVE_FAIL_FIRST_TS[$issue]:-_now} ))
    if (( _elapsed >= AUTOPILOT_STAGNATE_SEC )); then
      echo "[orchestrator] WARN: issue=${issue} stagnate detected (RESOLVE_FAILED ${RESOLVE_FAIL_COUNT[$issue]} 回, ${_elapsed}s >= AUTOPILOT_STAGNATE_SEC=${AUTOPILOT_STAGNATE_SEC})" >&2
      echo "[${_trace_ts}] issue=${issue} skill=RESOLVE_FAILED result=stagnate elapsed=${_elapsed}s count=${RESOLVE_FAIL_COUNT[$issue]}" >> "$_trace_log" 2>/dev/null || true
    fi

    return 1
  fi
  # inject 成功時は RESOLVE_FAIL カウントをリセット
  RESOLVE_FAIL_COUNT[$issue]=0
  RESOLVE_FAIL_FIRST_TS[$issue]=""

  # --- allow-list バリデーション（コマンドインジェクション防止） ---
  # 許可: /twl:workflow-<kebab> 形式、または pr-merge（terminal workflow として別処理）
  local _skill_safe
  _skill_safe="${next_skill//$'\n'/}"  # 改行除去（ログインジェクション防止）
  if [[ "$_skill_safe" == "pr-merge" || "$_skill_safe" == "/twl:workflow-pr-merge" ]]; then
    # terminal workflow: inject せず merge-gate フローに委譲（ADR-018: workflow_done クリア不要）
    echo "[orchestrator] Issue #${issue}: pr-merge 検出 — inject スキップ、merge-gate フローに委譲" >&2
    echo "[${_trace_ts}] issue=${issue} skill=pr-merge result=skip reason=\"terminal workflow, delegated to merge-gate\"" >> "$_trace_log" 2>/dev/null || true
    return 0
  fi
  if [[ ! "$_skill_safe" =~ ^/twl:workflow-[a-z][a-z0-9-]*$ ]]; then
    echo "[orchestrator] Issue #${issue}: WARNING: 不正な workflow skill '${_skill_safe:0:200}' — inject スキップ" >&2
    echo "[${_trace_ts}] issue=${issue} skill=INVALID result=skip reason=\"invalid skill name\"" >> "$_trace_log" 2>/dev/null || true
    return 1
  fi

  # --- tmux pane 入力待ち確認（最大3回、2秒間隔） ---
  # #522: Claude Code は Unicode prompt `❯` を使い、最終行に status bar が来ることがある。
  # bash regex の文字クラスに `>` を直接書くとシンタックスエラーになるため変数経由で渡す。
  # 末尾 6 行を走査することで status bar 行を skip して prompt 行を発見する。
  local _prompt_re='[>$❯][[:space:]]*$'
  local prompt_found=0
  local pane_tail
  for _i in 1 2 3; do
    pane_tail=$(tmux capture-pane -t "$window_name" -p 2>/dev/null | tail -6 || true)
    while IFS= read -r _line; do
      if [[ "$_line" =~ $_prompt_re ]]; then
        prompt_found=1
        break
      fi
    done <<< "$pane_tail"
    if [[ "$prompt_found" -eq 1 ]]; then
      break
    fi
    sleep 2
  done

  if [[ "$prompt_found" -eq 0 ]]; then
    echo "[orchestrator] Issue #${issue}: WARNING: inject タイムアウト — ${POLL_INTERVAL:-10}秒後に再チェック" >&2
    echo "[${_trace_ts}] issue=${issue} skill=${_skill_safe} result=timeout reason=\"prompt not found after 3 retries\"" >> "$_trace_log" 2>/dev/null || true
    return 1
  fi

  # --- inject 実行（バリデーション済みの _skill_safe を使用） ---
  echo "[orchestrator] Issue #${issue}: inject_next_workflow — ${_skill_safe}" >&2
  local _send_err
  _send_err=$(tmux send-keys -t "$window_name" "$_skill_safe" Enter 2>&1) || {
    _send_err="${_send_err//$'\n'/ }"  # ログインジェクション防止（改行除去）
    echo "[orchestrator] Issue #${issue}: WARNING: tmux send-keys 失敗 — ${_send_err}" >&2
    local _err_ts
    _err_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "[${_err_ts}] issue=${issue} skill=${_skill_safe} result=error reason=\"tmux send-keys failed: ${_send_err}\"" >> "$_trace_log" 2>/dev/null || true
    return 1
  }

  # --- trace ログ: inject 成功（タイムスタンプを inject 完了後に再取得） ---
  local _success_ts
  _success_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  echo "[${_success_ts}] issue=${issue} skill=${_skill_safe} result=success" >> "$_trace_log" 2>/dev/null || true

  # --- inject 履歴記録（ADR-018: workflow_done クリアを廃止、workflow_injected で追跡）---
  local injected_at
  injected_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  python3 -m twl.autopilot.state write --type issue --issue "$issue" --role pilot \
    --set "workflow_injected=${_skill_safe}" \
    --set "injected_at=${injected_at}" 2>/dev/null || true

  # --- NUDGE_COUNTS リセット ---
  NUDGE_COUNTS[$issue]=0

  return 0
}

check_and_nudge() {
  local issue="$1"
  local window_name="$2"
  local entry="${3:-_default:${issue}}"

  # nudge 上限チェック
  local count="${NUDGE_COUNTS[$issue]:-0}"
  if [[ "$count" -ge "$MAX_NUDGE" ]]; then
    return 0
  fi

  # tmux capture-pane で最新出力を取得
  local pane_output
  pane_output=$(tmux capture-pane -t "$window_name" -p -S -5 2>/dev/null || true)
  if [[ -z "$pane_output" ]]; then
    return 0
  fi

  # 出力のハッシュで変化を検知
  local current_hash
  current_hash=$(echo "$pane_output" | md5sum | cut -d' ' -f1)
  local last_hash="${LAST_OUTPUT_HASH[$issue]:-}"

  if [[ "$current_hash" == "$last_hash" ]]; then
    local next_cmd
    if next_cmd="$(_nudge_command_for_pattern "$pane_output" "$issue" "$entry")" && [[ -n "$next_cmd" ]]; then
      echo "[orchestrator] Issue #${issue}: chain 遷移停止検知 — nudge 送信 (${count}/${MAX_NUDGE})" >&2
      tmux send-keys -t "$window_name" "$next_cmd" Enter 2>/dev/null || true
      NUDGE_COUNTS[$issue]=$((count + 1))
      LAST_OUTPUT_HASH[$issue]="$current_hash"
    fi
  fi

  LAST_OUTPUT_HASH[$issue]="$current_hash"
  return 0
}

# =============================================================================
# merge-gate 実行
# =============================================================================

run_merge_gate() {
  local entry="$1"
  local repo_id="${entry%%:*}"
  local issue="${entry#*:}"
  local -a _state_read_repo_args=()
  [[ "$repo_id" != "_default" ]] && _state_read_repo_args=(--repo "$repo_id")

  # PR 番号とブランチを state から取得
  local pr_number branch
  pr_number=$(python3 -m twl.autopilot.state read --type issue "${_state_read_repo_args[@]}" --issue "$issue" --field pr 2>/dev/null || echo "")
  branch=$(python3 -m twl.autopilot.state read --type issue "${_state_read_repo_args[@]}" --issue "$issue" --field branch 2>/dev/null || echo "")

  if [[ -z "$pr_number" || -z "$branch" ]]; then
    echo "[orchestrator] Issue #${issue}: PR 番号またはブランチが取得できません — mergegate.py の実行をスキップ" >&2
    # PR 情報が不足しているため mergegate.py を実行できない（auto-merge.sh は呼び出さない）
    return 1
  fi

  echo "[orchestrator] Issue #${issue}: merge-gate 実行 (PR #${pr_number})" >&2

  export ISSUE="$issue"
  export PR_NUMBER="$pr_number"
  export BRANCH="$branch"

  # exit code の明示的ハンドリング:
  #   0 = merge 成功 + Issue CLOSED 確認済み
  #   1 = merge 失敗 (conflict / push error 等)
  #   2 = merge 成功だが Issue close 失敗 (status=failed に遷移済み)
  local rc=0
  python3 -m twl.autopilot.mergegate 2>&1 || rc=$?
  case "$rc" in
    0)
      echo "[orchestrator] Issue #${issue}: merge 成功" >&2
      ;;
    2)
      echo "[orchestrator] Issue #${issue}: Issue close 失敗で escalate (status=failed)" >&2
      ;;
    *)
      echo "[orchestrator] Issue #${issue}: merge 失敗 (exit=${rc})" >&2
      ;;
  esac
  return "$rc"
}

# =============================================================================
# Phase 完了レポート生成
# =============================================================================

generate_phase_report() {
  local phase="$1"
  shift
  local -a all_issues=("$@")

  local -a done_issues=() failed_issues=() skipped_issues=()

  for issue in "${all_issues[@]}"; do
    local status
    status=$(python3 -m twl.autopilot.state read --type issue --issue "$issue" --field status 2>/dev/null || echo "")
    case "$status" in
      done) done_issues+=("$issue") ;;
      failed) failed_issues+=("$issue") ;;
      *) skipped_issues+=("$issue") ;;
    esac
  done

  # changed_files の収集（done Issue の worktree から）
  local -a changed_files=()
  for issue in "${done_issues[@]}"; do
    local cf
    cf=$(python3 -m twl.autopilot.state read --type issue --issue "$issue" --field changed_files 2>/dev/null || echo "")
    if [[ -n "$cf" && "$cf" != "null" ]]; then
      while IFS= read -r f; do
        [[ -n "$f" ]] && changed_files+=("$f")
      done <<< "$(echo "$cf" | jq -r '.[]' 2>/dev/null || true)"
    fi
  done

  # JSON レポート出力
  # skipped_archives: archive_done_issues が fail-closed で skip した Issue 番号（滞留検知用、Issue #138）
  jq -n \
    --arg signal "PHASE_COMPLETE" \
    --argjson phase "$phase" \
    --argjson done "$(printf '%s\n' "${done_issues[@]+"${done_issues[@]}"}" | jq -R -s 'split("\n") | map(select(length > 0) | tonumber)')" \
    --argjson failed "$(printf '%s\n' "${failed_issues[@]+"${failed_issues[@]}"}" | jq -R -s 'split("\n") | map(select(length > 0) | tonumber)')" \
    --argjson skipped "$(printf '%s\n' "${skipped_issues[@]+"${skipped_issues[@]}"}" | jq -R -s 'split("\n") | map(select(length > 0) | tonumber)')" \
    --argjson skipped_archives "$(printf '%s\n' "${SKIPPED_ARCHIVES[@]+"${SKIPPED_ARCHIVES[@]}"}" | jq -R -s 'split("\n") | map(select(length > 0) | tonumber)')" \
    --argjson changed_files "$(printf '%s\n' "${changed_files[@]+"${changed_files[@]}"}" | jq -R -s 'split("\n") | map(select(length > 0))')" \
    '{
      signal: $signal,
      phase: $phase,
      results: {
        done: $done,
        failed: $failed,
        skipped: $skipped
      },
      skipped_archives: $skipped_archives,
      changed_files: $changed_files
    }'
}

# =============================================================================
# サマリー生成
# =============================================================================

generate_summary() {
  local issues_dir="${AUTOPILOT_DIR}/issues"

  if [[ ! -d "$issues_dir" ]]; then
    echo '{"error": "issues directory not found"}' >&2
    exit 1
  fi

  local -a all_done=() all_failed=() all_skipped=()
  local total=0

  for issue_file in "$issues_dir"/issue-*.json; do
    [[ -f "$issue_file" ]] || continue
    total=$((total + 1))

    local issue_num status
    issue_num=$(basename "$issue_file" | grep -oP '\d+')
    status=$(jq -r '.status // "unknown"' "$issue_file")

    case "$status" in
      done) all_done+=("$issue_num") ;;
      failed) all_failed+=("$issue_num") ;;
      *) all_skipped+=("$issue_num") ;;
    esac
  done

  jq -n \
    --arg signal "SUMMARY" \
    --argjson total "$total" \
    --argjson done_count "${#all_done[@]}" \
    --argjson failed_count "${#all_failed[@]}" \
    --argjson skipped_count "${#all_skipped[@]}" \
    --argjson done "$(printf '%s\n' "${all_done[@]+"${all_done[@]}"}" | jq -R -s 'split("\n") | map(select(length > 0) | tonumber)')" \
    --argjson failed "$(printf '%s\n' "${all_failed[@]+"${all_failed[@]}"}" | jq -R -s 'split("\n") | map(select(length > 0) | tonumber)')" \
    --argjson skipped "$(printf '%s\n' "${all_skipped[@]+"${all_skipped[@]}"}" | jq -R -s 'split("\n") | map(select(length > 0) | tonumber)')" \
    '{
      signal: $signal,
      total: $total,
      results: {
        done: { count: $done_count, issues: $done },
        failed: { count: $failed_count, issues: $failed },
        skipped: { count: $skipped_count, issues: $skipped }
      }
    }'
}

# Phase 内の Done Issue のみを選択的にアーカイブする
# 他 Phase・手動 Issue はアーカイブ対象外（仕様: specs/phase-selective-archive）
# 引数: issue 番号リスト（スペース区切り）
#
# fail-closed: ローカル status=done かつ GitHub Issue state=CLOSED の両方を満たす場合のみ archive
# 空文字 (取得失敗) も "CLOSED でない" として skip 扱い（Issue #138）
# skip された Issue は SKIPPED_ARCHIVES グローバル配列に追加される（滞留検知用）
SKIPPED_ARCHIVES=()
archive_done_issues() {
  local issue
  for issue in "$@"; do
    local status
    status=$(python3 -m twl.autopilot.state read --type issue --issue "$issue" --field status 2>/dev/null || echo "")
    if [[ "$status" != "done" ]]; then
      continue
    fi

    # NEW: GitHub Issue state 二重チェック (fail-closed)
    local gh_state
    gh_state=$(gh issue view "$issue" --json state -q .state 2>/dev/null || echo "")
    if [[ "$gh_state" != "CLOSED" ]]; then
      if [[ -z "$gh_state" ]]; then
        echo "[orchestrator] Issue #${issue}: ⚠️ GitHub state 取得失敗 — fail-closed で archive をスキップ" >&2
      else
        echo "[orchestrator] Issue #${issue}: ⚠️ ローカル state=done だが GitHub state=${gh_state} — archive をスキップ" >&2
      fi
      echo "[orchestrator] Issue #${issue}: 手動 close または autopilot state 修正が必要です" >&2
      SKIPPED_ARCHIVES+=("$issue")
      continue
    fi

    if ! bash "$SCRIPTS_ROOT/chain-runner.sh" board-archive "$issue" 2>/dev/null; then
      echo "[orchestrator] Issue #${issue}: ⚠️ Board アーカイブに失敗しました（Phase 完了は続行）" >&2
    fi
    # DeltaSpec change archive
    _archive_deltaspec_changes_for_issue "$issue"
  done
}

# Issue に紐づく deltaspec change を deltaspec archive で処理する
_archive_deltaspec_changes_for_issue() {
  local issue="$1"
  local root
  root="$(git rev-parse --show-toplevel 2>/dev/null || echo "")"
  if [[ -z "$root" ]]; then return 0; fi

  if ! command -v twl >/dev/null 2>&1; then
    echo "[orchestrator] Issue #${issue}: ⚠️ twl CLI が見つかりません — DeltaSpec archive をスキップ" >&2
    return 0
  fi

  # config.yaml を持つ deltaspec root を探索（lib/deltaspec-helpers.sh の resolve_deltaspec_root に委譲）
  local ds_root
  ds_root="$(resolve_deltaspec_root "$root")" || true
  local changes_dir="$ds_root/deltaspec/changes"
  if [[ ! -d "$changes_dir" ]]; then return 0; fi

  # issue を引数で受け取ることで動的スコープへの依存を排除
  _do_archive() {
    local yaml_path="$1" _issue="$2"
    local change_dir change_id
    change_dir="$(dirname "$yaml_path")"
    change_id="$(basename "$change_dir")"
    found=true
    if twl spec archive --yes -- "$change_id"; then
      echo "[orchestrator] Issue #${_issue}: DeltaSpec archive 完了（specs 統合済み）: ${change_id}"
    else
      echo "[orchestrator] Issue #${_issue}: ⚠️ WARNING: specs 統合失敗。--skip-specs でリトライ: ${change_id}" >&2
      if twl spec archive --yes --skip-specs -- "$change_id"; then
        echo "[orchestrator] Issue #${_issue}: DeltaSpec archive 完了（specs 統合スキップ）: ${change_id}"
      else
        echo "[orchestrator] Issue #${_issue}: ⚠️ DeltaSpec archive 失敗: ${change_id}（Phase 完了は続行）" >&2
      fi
    fi
  }

  # プライマリ: .deltaspec.yaml の issue フィールドで対応 change を特定
  # 複数の change が一致する場合は全て archive する（1 issue に複数 change がある正規ケース）
  local found=false
  while IFS= read -r yaml_path; do
    _do_archive "$yaml_path" "$issue"
  done < <(grep -rl "^issue: ${issue}$" "$changes_dir" --include=".deltaspec.yaml" 2>/dev/null || true)

  # フォールバック1: name: issue-<N> パターンで検索（issue フィールドなしの change 対応）
  if [[ "$found" == "false" ]]; then
    while IFS= read -r yaml_path; do
      _do_archive "$yaml_path" "$issue"
    done < <(grep -rl "^name: issue-${issue}$" "$changes_dir" --include=".deltaspec.yaml" 2>/dev/null || true)
  fi

  # フォールバック2: ディレクトリ名パターンで検索（name フィールドもない旧形式の change 対応）
  if [[ "$found" == "false" ]]; then
    local legacy_yaml="${changes_dir}/issue-${issue}/.deltaspec.yaml"
    if [[ -f "$legacy_yaml" ]]; then
      _do_archive "$legacy_yaml" "$issue"
    fi
  fi

  if [[ "$found" == "false" ]]; then
    echo "[orchestrator] Issue #${issue}: DeltaSpec change が見つかりません（issue フィールド未設定または存在しない）" >&2
  fi
}

# =============================================================================
# メイン実行
# =============================================================================

if [[ "$SUMMARY_MODE" == "true" ]]; then
  generate_summary
  exit 0
fi

# --- Phase 実行 ---
mkdir -p "$AUTOPILOT_DIR/logs"
mkdir -p "$AUTOPILOT_DIR/trace"

# model 解決: CLI arg > plan.yaml > デフォルト（sonnet）
if [[ -z "$WORKER_MODEL" && -f "$PLAN_FILE" ]]; then
  _plan_model=$(grep '^model:' "$PLAN_FILE" | head -1 | sed 's/^model:[[:space:]]*//' | tr -d '"' | tr -d "'" || echo "")
  if [[ -n "$_plan_model" && "$_plan_model" =~ ^[a-zA-Z0-9._-]+$ ]]; then
    WORKER_MODEL="$_plan_model"
  fi
fi
if [[ -z "$WORKER_MODEL" ]]; then
  WORKER_MODEL="sonnet"
fi

echo "[orchestrator] Phase ${PHASE} 開始" >&2
# --- trace: PID と起動時刻を記録 ---
_orch_started_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
echo "[${_orch_started_at}] orchestrator_pid=$$ phase=${PHASE} started_at=${_orch_started_at}" >> "${AUTOPILOT_DIR}/trace/orchestrator-phase-${PHASE}.log" 2>/dev/null || true

# Step 1: Phase 内 Issue リスト取得
get_phase_issues "$PHASE" "$PLAN_FILE"

if [[ ${#ISSUES_WITH_REPO[@]} -eq 0 ]]; then
  echo "[orchestrator] Phase ${PHASE}: Issue なし" >&2
  generate_phase_report "$PHASE"
  exit 0
fi

# Step 2: skip/done フィルタリング
filter_active_issues

if [[ ${#ACTIVE_ISSUES[@]} -eq 0 ]]; then
  echo "[orchestrator] Phase ${PHASE}: 全 Issue が skip/done" >&2
  # 全 Issue 番号を取得してレポート生成
  ALL_ISSUE_NUMS=()
  for entry in "${ISSUES_WITH_REPO[@]}"; do
    ALL_ISSUE_NUMS+=("${entry#*:}")
  done
  # 先に archive を実行（SKIPPED_ARCHIVES をレポートに含めるため）
  archive_done_issues "${ALL_ISSUE_NUMS[@]}"
  generate_phase_report "$PHASE" "${ALL_ISSUE_NUMS[@]}"
  exit 0
fi

# Step 3: batch 分割 + 実行
TOTAL=${#ACTIVE_ENTRIES[@]}
for ((BATCH_START=0; BATCH_START < TOTAL; BATCH_START += MAX_PARALLEL)); do
  BATCH=("${ACTIVE_ENTRIES[@]:$BATCH_START:$MAX_PARALLEL}")
  BATCH_ISSUES=()

  # Worker 起動
  BATCH_LAUNCHED_ENTRIES=()
  for entry in "${BATCH[@]}"; do
    resolve_issue_repo_context "$entry"
    local_issue="$ISSUE"

    status=$(python3 -m twl.autopilot.state read --type issue --issue "$local_issue" --field status 2>/dev/null || echo "")
    if [[ "$status" == "done" ]]; then
      continue
    fi

    echo "[orchestrator] Issue #${local_issue}: Worker 起動" >&2
    launch_worker "$entry" || {
      echo "[orchestrator] Issue #${local_issue}: Worker 起動失敗（スキップ）" >&2
      continue
    }
    BATCH_ISSUES+=("$local_issue")
    BATCH_LAUNCHED_ENTRIES+=("$entry")
  done

  if [[ ${#BATCH_LAUNCHED_ENTRIES[@]} -eq 0 ]]; then
    continue
  fi

  # ポーリング（entry を渡してリポコンテキストを伝搬）
  if [[ ${#BATCH_LAUNCHED_ENTRIES[@]} -eq 1 ]]; then
    poll_single "${BATCH_LAUNCHED_ENTRIES[0]}"
  else
    poll_phase "${BATCH_LAUNCHED_ENTRIES[@]}"
  fi

  # poll ループ終了後: 非 terminal Issue を検出して cleanup_worker 経由で force-fail（Issue #295）
  for _pt_entry in "${BATCH_LAUNCHED_ENTRIES[@]}"; do
    _pt_issue="${_pt_entry#*:}"
    _pt_repo="${_pt_entry%%:*}"
    _pt_rargs=()
    [[ "$_pt_repo" != "_default" ]] && _pt_rargs=(--repo "$_pt_repo")
    _pt_status=$(python3 -m twl.autopilot.state read --type issue "${_pt_rargs[@]}" --issue "$_pt_issue" --field status 2>/dev/null || echo "")
    case "$_pt_status" in
      merge-ready|done|failed|conflict) ;;
      *)
        echo "[orchestrator] WARNING: Issue #${_pt_issue} has non-terminal status=${_pt_status} after poll. Triggering cleanup." >&2
        cleanup_worker "$_pt_issue" "$_pt_entry"
        ;;
    esac
  done

  # merge-ready の Issue に対して merge-gate を順次実行
  # issue → entry マッピング構築（クロスリポ cleanup_worker 呼び出し用）
  declare -A _batch_issue_to_entry=()
  for _e in "${BATCH_LAUNCHED_ENTRIES[@]}"; do
    _batch_issue_to_entry["${_e#*:}"]="$_e"
  done

  for issue in "${BATCH_ISSUES[@]}"; do
    _entry="${_batch_issue_to_entry[$issue]:-_default:${issue}}"
    _repo_id="${_entry%%:*}"
    _repo_args=()
    [[ "$_repo_id" != "_default" ]] && _repo_args=(--repo "$_repo_id")
    status=$(python3 -m twl.autopilot.state read --type issue "${_repo_args[@]}" --issue "$issue" --field status 2>/dev/null || echo "")
    if [[ "$status" == "merge-ready" ]]; then
      run_merge_gate "$_entry" || true  # set -euo pipefail 環境でのオーケストレーター終了を防止
      # merge-gate 後: status に応じて Pilot 側でクリーンアップを集約実行（不変条件B）
      _status_after=$(python3 -m twl.autopilot.state read --type issue "${_repo_args[@]}" --issue "$issue" --field status 2>/dev/null || echo "")
      if [[ "$_status_after" == "done" ]]; then
        # merge 成功: 全リソースをクリーンアップ
        cleanup_worker "$issue" "$_entry"
      elif [[ "$_status_after" == "failed" ]]; then
        # reject-final（確定失敗）: worktree とリモートブランチも解放（不変条件B）
        _retry=$(python3 -m twl.autopilot.state read --type issue "${_repo_args[@]}" --issue "$issue" --field retry_count 2>/dev/null || echo "0")
        # failure.reason を確認: merge_gate_rejected_final は retry_count 0 でも確定失敗（#229）
        _failure_reason=$(python3 -m twl.autopilot.state read --type issue "${_repo_args[@]}" --issue "$issue" --field failure.reason 2>/dev/null || echo "")
        if [[ "${_retry:-0}" -ge 1 ]] || [[ "$_failure_reason" == "merge_gate_rejected_final" ]]; then
          cleanup_worker "$issue" "$_entry"
        fi
      fi
    fi
  done
  unset _batch_issue_to_entry
done

# Step 4: 当該 Phase の Done アイテムのみを選択的にアーカイブ
# fail-closed で skip された Issue は SKIPPED_ARCHIVES に集約される
ALL_ISSUE_NUMS=()
for entry in "${ISSUES_WITH_REPO[@]}"; do
  ALL_ISSUE_NUMS+=("${entry#*:}")
done
archive_done_issues "${ALL_ISSUE_NUMS[@]}"

# Step 5: Phase 完了レポート（skipped_archives を含む）
generate_phase_report "$PHASE" "${ALL_ISSUE_NUMS[@]}"

echo "[orchestrator] Phase ${PHASE} 完了" >&2
