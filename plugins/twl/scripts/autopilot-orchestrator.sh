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
MAX_POLL="${DEV_AUTOPILOT_MAX_POLL:-360}"
MAX_NUDGE="${DEV_AUTOPILOT_MAX_NUDGE:-3}"
NUDGE_TIMEOUT="${DEV_AUTOPILOT_NUDGE_TIMEOUT:-30}"
POLL_INTERVAL=10

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

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan)          PLAN_FILE="$2"; shift 2 ;;
    --phase)         PHASE="$2"; shift 2 ;;
    --session)       SESSION_FILE="$2"; shift 2 ;;
    --project-dir)   PROJECT_DIR="$2"; shift 2 ;;
    --autopilot-dir) AUTOPILOT_DIR="$2"; shift 2 ;;
    --repos)         REPOS_JSON="$2"; shift 2 ;;
    --summary)       SUMMARY_MODE=true; shift ;;
    -h|--help)       usage; exit 0 ;;
    *) echo "Error: 不明なオプション: $1" >&2; exit 1 ;;
  esac
done

export AUTOPILOT_DIR

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
launch_worker() {
  local entry="$1"
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

  local launch_args=(
    --issue "$ISSUE"
    --project-dir "$PROJECT_DIR"
    --autopilot-dir "$AUTOPILOT_DIR"
    --worktree-dir "$worktree_dir"
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
  local window_name="ap-#${issue}"
  echo "[orchestrator] cleanup: Issue #${issue} — window/branch クリーンアップ" >&2

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

# 単一 Issue のポーリング
poll_single() {
  local entry="$1"
  resolve_issue_repo_context "$entry"
  local issue="$ISSUE"
  local window_name="ap-#${issue}"
  local poll_count=0

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
          return 0
        fi

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
            if [[ "$health_exit" -eq 1 && -z "$health_stderr" ]]; then
              if [[ "${NUDGE_COUNTS[$issue]:-0}" -lt "$MAX_NUDGE" ]]; then
                echo "[orchestrator] Issue #${issue}: health-check stall 検知 — 汎用 nudge" >&2
                tmux send-keys -t "$window_name" "" Enter 2>/dev/null || true
                NUDGE_COUNTS[$issue]=$(( ${NUDGE_COUNTS[$issue]:-0} + 1 ))
              else
                echo "[orchestrator] Issue #${issue}: health-check stall + nudge 上限到達 — failed" >&2
                python3 -m twl.autopilot.state write --type issue --issue "$issue" --role pilot \
                  --set "status=failed" \
                  --set 'failure={"message":"health_check_stall","step":"polling"}'
              fi
            fi
          fi
        fi
        ;;
    esac

    if [[ "$poll_count" -ge "$MAX_POLL" ]]; then
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
          [[ "$repo_id" == "_default" ]] && window_name="ap-#${issue_num}" || window_name="ap-${repo_id}-#${issue_num}"
          local crash_exit=0
          bash "$SCRIPTS_ROOT/crash-detect.sh" --issue "$issue_num" --window "$window_name" 2>/dev/null || crash_exit=$?
          if [[ "$crash_exit" -eq 2 ]]; then
            echo "[orchestrator] Issue #${issue_num}: ワーカークラッシュ検知" >&2
            continue
          fi

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
              if [[ "$health_exit" -eq 1 && -z "$health_stderr" ]]; then
                if [[ "${NUDGE_COUNTS[$issue_num]:-0}" -lt "$MAX_NUDGE" ]]; then
                  echo "[orchestrator] Issue #${issue_num}: health-check stall 検知 — 汎用 nudge" >&2
                  tmux send-keys -t "$window_name" "" Enter 2>/dev/null || true
                  NUDGE_COUNTS[$issue_num]=$(( ${NUDGE_COUNTS[$issue_num]:-0} + 1 ))
                else
                  echo "[orchestrator] Issue #${issue_num}: health-check stall + nudge 上限到達 — failed" >&2
                  python3 -m twl.autopilot.state write --type issue "${_state_read_repo_args[@]}" --issue "$issue_num" --role pilot \
                    --set "status=failed" \
                    --set 'failure={"message":"health_check_stall","step":"polling"}'
                fi
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
          [[ "$repo_id" == "_default" ]] && first_running_window="ap-#${issue_num}" || first_running_window="ap-${repo_id}-#${issue_num}"
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

check_and_nudge() {
  local issue="$1"
  local window_name="$2"
  local entry="${3:-_default:${issue}}"

  # nudge 上限チェック
  local count="${NUDGE_COUNTS[$issue]:-0}"
  if [[ "$count" -ge "$MAX_NUDGE" ]]; then
    return 0
  fi

  # Layer 1 (PostToolUse hook) との競合防止:
  # last_hook_nudge_at が NUDGE_TIMEOUT 以内なら tmux nudge をスキップ
  local last_hook_nudge_at
  last_hook_nudge_at=$(python3 -m twl.autopilot.state read --type issue --issue "$issue" --field last_hook_nudge_at 2>/dev/null || true)
  if [[ -n "$last_hook_nudge_at" ]]; then
    local hook_epoch now_epoch elapsed
    hook_epoch=$(date -u -d "$last_hook_nudge_at" +%s 2>/dev/null || echo "0")
    now_epoch=$(date -u +%s)
    elapsed=$(( now_epoch - hook_epoch ))
    if [[ "$elapsed" -lt "$NUDGE_TIMEOUT" ]]; then
      return 0
    fi
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
    # 停止パターンをチェックし、対応する次コマンドを送信
    local next_cmd
    if next_cmd="$(_nudge_command_for_pattern "$pane_output" "$issue" "$entry")"; then
      echo "[orchestrator] Issue #${issue}: chain 遷移停止検知 — nudge 送信 (${count}/${MAX_NUDGE})" >&2
      tmux send-keys -t "$window_name" "$next_cmd" Enter 2>/dev/null || true
      NUDGE_COUNTS[$issue]=$((count + 1))
      LAST_OUTPUT_HASH[$issue]="$current_hash"
      return 0
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
    echo "[orchestrator] Issue #${issue}: PR 番号またはブランチが取得できません — auto-merge.sh にフォールバック" >&2
    # auto-merge.sh は自身で PR 情報を解決可能な場合がある
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
  jq -n \
    --arg signal "PHASE_COMPLETE" \
    --argjson phase "$phase" \
    --argjson done "$(printf '%s\n' "${done_issues[@]+"${done_issues[@]}"}" | jq -R -s 'split("\n") | map(select(length > 0) | tonumber)')" \
    --argjson failed "$(printf '%s\n' "${failed_issues[@]+"${failed_issues[@]}"}" | jq -R -s 'split("\n") | map(select(length > 0) | tonumber)')" \
    --argjson skipped "$(printf '%s\n' "${skipped_issues[@]+"${skipped_issues[@]}"}" | jq -R -s 'split("\n") | map(select(length > 0) | tonumber)')" \
    --argjson changed_files "$(printf '%s\n' "${changed_files[@]+"${changed_files[@]}"}" | jq -R -s 'split("\n") | map(select(length > 0))')" \
    '{
      signal: $signal,
      phase: $phase,
      results: {
        done: $done,
        failed: $failed,
        skipped: $skipped
      },
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
archive_done_issues() {
  local issue
  for issue in "$@"; do
    local status
    status=$(python3 -m twl.autopilot.state read --type issue --issue "$issue" --field status 2>/dev/null || echo "")
    if [[ "$status" == "done" ]]; then
      if ! bash "$SCRIPTS_ROOT/chain-runner.sh" board-archive "$issue" 2>/dev/null; then
        echo "[orchestrator] Issue #${issue}: ⚠️ Board アーカイブに失敗しました（Phase 完了は続行）" >&2
      fi
      # OpenSpec change archive
      _archive_openspec_changes_for_issue "$issue"
    fi
  done
}

# Issue に紐づく openspec change を deltaspec archive で処理する
_archive_openspec_changes_for_issue() {
  local issue="$1"
  local root
  root="$(git rev-parse --show-toplevel 2>/dev/null || echo "")"
  if [[ -z "$root" ]]; then return 0; fi

  if ! command -v deltaspec >/dev/null 2>&1; then
    echo "[orchestrator] Issue #${issue}: ⚠️ deltaspec CLI が見つかりません — OpenSpec archive をスキップ" >&2
    return 0
  fi

  local changes_dir="$root/deltaspec/changes"
  if [[ ! -d "$changes_dir" ]]; then return 0; fi

  # .deltaspec.yaml の issue フィールドで対応 change を特定
  local found=false
  while IFS= read -r yaml_path; do
    local change_dir change_id
    change_dir="$(dirname "$yaml_path")"
    change_id="$(basename "$change_dir")"
    found=true
    if deltaspec archive --yes --skip-specs -- "$change_id"; then
      echo "[orchestrator] Issue #${issue}: OpenSpec archive 完了: ${change_id}"
    else
      echo "[orchestrator] Issue #${issue}: ⚠️ OpenSpec archive 失敗: ${change_id}（Phase 完了は続行）" >&2
    fi
  done < <(grep -rl "^issue: ${issue}$" "$changes_dir" --include=".deltaspec.yaml" 2>/dev/null || true)

  if [[ "$found" == "false" ]]; then
    echo "[orchestrator] Issue #${issue}: OpenSpec change が見つかりません（issue フィールド未設定または存在しない）" >&2
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
echo "[orchestrator] Phase ${PHASE} 開始" >&2

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
  generate_phase_report "$PHASE" "${ALL_ISSUE_NUMS[@]}"
  # 当該 Phase の Done アイテムのみを選択的にアーカイブ
  archive_done_issues "${ALL_ISSUE_NUMS[@]}"
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

# Step 4: Phase 完了レポート
ALL_ISSUE_NUMS=()
for entry in "${ISSUES_WITH_REPO[@]}"; do
  ALL_ISSUE_NUMS+=("${entry#*:}")
done
generate_phase_report "$PHASE" "${ALL_ISSUE_NUMS[@]}"

# Step 5: 当該 Phase の Done アイテムのみを選択的にアーカイブ
archive_done_issues "${ALL_ISSUE_NUMS[@]}"

echo "[orchestrator] Phase ${PHASE} 完了" >&2
