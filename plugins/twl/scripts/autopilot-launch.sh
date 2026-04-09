#!/usr/bin/env bash
# autopilot-launch.sh - Worker（cld）を tmux window で起動する決定的スクリプト
# autopilot-launch.md から呼び出される。コンテキスト構築以外の全ロジックを担当。
set -euo pipefail

# --- SCRIPTS_ROOT 自動解決 (Task 1.3) ---
SCRIPTS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib/python-env.sh
source "${SCRIPTS_ROOT}/lib/python-env.sh"

# session-name.sh の読み込み（意味論的 window 命名）
_SESSION_NAME_SH="$(realpath -m "${SCRIPTS_ROOT}/../../session/scripts/session-name.sh")"
if [[ -f "$_SESSION_NAME_SH" ]]; then
  # shellcheck source=../../session/scripts/session-name.sh
  source "$_SESSION_NAME_SH"
fi

# window-manifest.sh の読み込み (Phase 2 / #290)
_WINDOW_MANIFEST_SH="$(realpath -m "${SCRIPTS_ROOT}/../../session/scripts/window-manifest.sh")"
if [[ -f "$_WINDOW_MANIFEST_SH" ]]; then
  # shellcheck source=../../session/scripts/window-manifest.sh
  source "$_WINDOW_MANIFEST_SH"
fi

# --- usage (Task 1.1) ---
usage() {
  cat <<EOF
Usage: $(basename "$0") --issue N --project-dir DIR --autopilot-dir DIR [OPTIONS]

Worker（cld）を tmux window で起動する。

Required:
  --issue N               Issue番号（正の整数）
  --project-dir DIR       プロジェクトディレクトリ（絶対パス）
  --autopilot-dir DIR     .autopilot ディレクトリ（絶対パス）

Optional:
  --model MODEL           cld のモデル指定（デフォルト: sonnet）
  --context TEXT          コンテキスト注入テキスト（--append-system-prompt に変換）
  --repo-owner OWNER      クロスリポジトリ: リポジトリ owner
  --repo-name NAME        クロスリポジトリ: リポジトリ name
  --repo-path PATH        クロスリポジトリ: リポジトリパス（絶対パス）
  --worktree-dir DIR      Worker 起動ディレクトリ（指定時は LAUNCH_DIR を上書き）
  -h, --help              このヘルプを表示

Exit codes:
  0: Worker 起動成功
  1: バリデーションエラー（state-write で failed を記録済み）
  2: 外部コマンド不在（cld / tmux）
EOF
}

# --- state-write failure ヘルパー ---
record_failure() {
  local message="$1" step="$2"
  local repo_arg=""
  if [[ -n "${REPO_ID:-}" ]]; then
    repo_arg="--repo $REPO_ID"
  fi
  local failure_json
  failure_json=$(jq -n --arg message "$message" --arg step "$step" \
    '{message: $message, step: $step}')
  # shellcheck disable=SC2086
  python3 -m twl.autopilot.state write --type issue --issue "$ISSUE" --role pilot $repo_arg \
    --set "status=failed" \
    --set "failure=$failure_json"
}

# --- フラグ引数パーサー (Task 1.2) ---
ISSUE=""
PROJECT_DIR=""
AUTOPILOT_DIR=""
MODEL="sonnet"
CONTEXT=""
REPO_OWNER=""
REPO_NAME=""
REPO_PATH=""
WORKTREE_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --issue) ISSUE="$2"; shift 2 ;;
    --project-dir) PROJECT_DIR="$2"; shift 2 ;;
    --autopilot-dir) AUTOPILOT_DIR="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --context) CONTEXT="$2"; shift 2 ;;
    --repo-owner) REPO_OWNER="$2"; shift 2 ;;
    --repo-name) REPO_NAME="$2"; shift 2 ;;
    --repo-path) REPO_PATH="$2"; shift 2 ;;
    --worktree-dir) WORKTREE_DIR="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Error: 不明なオプション: $1" >&2; exit 1 ;;
  esac
done

# --- 入力バリデーション (Task 1.4) ---

# 必須引数チェック
if [[ -z "$ISSUE" || -z "$PROJECT_DIR" || -z "$AUTOPILOT_DIR" ]]; then
  echo "Error: --issue, --project-dir, --autopilot-dir は必須です" >&2
  usage >&2
  exit 1
fi

# ISSUE 数値バリデーション
if [[ ! "$ISSUE" =~ ^[1-9][0-9]*$ ]]; then
  echo "Error: --issue は正の整数で指定してください: $ISSUE" >&2
  exit 1
fi

# MODEL バリデーション（コマンドインジェクション防止）
if [[ ! "$MODEL" =~ ^[a-zA-Z0-9._-]+$ ]]; then
  echo "Error: --model の形式が正しくありません（許可パターン: ^[a-zA-Z0-9._-]+$）: $MODEL" >&2
  exit 1
fi

# REPO_ID 計算（クロスリポジトリ用）
REPO_ID=""
if [[ -n "$REPO_OWNER" && -n "$REPO_NAME" ]]; then
  REPO_ID="${REPO_OWNER}-${REPO_NAME}"
fi

# PROJECT_DIR 絶対パス検証 + パストラバーサル防止
if [[ "$PROJECT_DIR" != /* ]]; then
  echo "Error: --project-dir は絶対パスで指定してください: $PROJECT_DIR" >&2
  record_failure "invalid_project_dir" "launch_worker"
  exit 1
fi
if [[ "$PROJECT_DIR" =~ /\.\./ || "$PROJECT_DIR" =~ /\.\.$ ]]; then
  echo "Error: --project-dir にパストラバーサルは使用できません: $PROJECT_DIR" >&2
  record_failure "invalid_project_dir" "launch_worker"
  exit 1
fi

# AUTOPILOT_DIR 絶対パス検証 + パストラバーサル防止
if [[ "$AUTOPILOT_DIR" != /* ]]; then
  echo "Error: --autopilot-dir は絶対パスで指定してください: $AUTOPILOT_DIR" >&2
  record_failure "invalid_autopilot_dir" "launch_worker"
  exit 1
fi
if [[ "$AUTOPILOT_DIR" =~ /\.\./ || "$AUTOPILOT_DIR" =~ /\.\.$ ]]; then
  echo "Error: --autopilot-dir にパストラバーサルは使用できません: $AUTOPILOT_DIR" >&2
  record_failure "invalid_autopilot_dir" "launch_worker"
  exit 1
fi

# REPO_OWNER バリデーション
if [[ -n "$REPO_OWNER" ]]; then
  if [[ ! "$REPO_OWNER" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "Error: --repo-owner の形式が正しくありません（許可パターン: ^[a-zA-Z0-9_-]+$）: $REPO_OWNER" >&2
    record_failure "invalid_repo_owner" "launch_worker"
    exit 1
  fi
fi

# REPO_NAME バリデーション
if [[ -n "$REPO_NAME" ]]; then
  if [[ ! "$REPO_NAME" =~ ^[a-zA-Z0-9_.-]+$ ]]; then
    echo "Error: --repo-name の形式が正しくありません（許可パターン: ^[a-zA-Z0-9_.-]+$）: $REPO_NAME" >&2
    record_failure "invalid_repo_name" "launch_worker"
    exit 1
  fi
fi

# REPO_PATH バリデーション
if [[ -n "$REPO_PATH" ]]; then
  if [[ "$REPO_PATH" != /* ]]; then
    echo "Error: --repo-path は絶対パスで指定してください: $REPO_PATH" >&2
    record_failure "invalid_repo_path" "launch_worker"
    exit 1
  fi
  if [[ "$REPO_PATH" =~ /\.\./ || "$REPO_PATH" =~ /\.\.$ ]]; then
    echo "Error: --repo-path にパストラバーサルは使用できません: $REPO_PATH" >&2
    record_failure "invalid_repo_path" "launch_worker"
    exit 1
  fi
  if [[ ! -d "$REPO_PATH" ]]; then
    echo "Error: --repo-path が見つかりません: $REPO_PATH" >&2
    record_failure "repo_path_not_found" "launch_worker"
    exit 1
  fi
fi

# WORKTREE_DIR バリデーション（指定時のみ）
if [[ -n "$WORKTREE_DIR" ]]; then
  if [[ "$WORKTREE_DIR" != /* ]]; then
    echo "Error: --worktree-dir は絶対パスで指定してください: $WORKTREE_DIR" >&2
    record_failure "invalid_worktree_dir" "launch_worker"
    exit 1
  fi
  if [[ "$WORKTREE_DIR" =~ /\.\./ || "$WORKTREE_DIR" =~ /\.\.$ ]]; then
    echo "Error: --worktree-dir にパストラバーサルは使用できません: $WORKTREE_DIR" >&2
    record_failure "invalid_worktree_dir" "launch_worker"
    exit 1
  fi
  if [[ ! -d "$WORKTREE_DIR" ]]; then
    echo "Error: --worktree-dir が見つかりません: $WORKTREE_DIR" >&2
    record_failure "worktree_dir_not_found" "launch_worker"
    exit 1
  fi
fi

# --- cld パス解決 (Task 1.5) ---
CLD_PATH=$(command -v cld 2>/dev/null || true)
if [[ -z "$CLD_PATH" ]]; then
  echo "Error: cld が見つかりません" >&2
  record_failure "cld_not_found" "launch_worker"
  exit 2
fi

# --- issue state 初期化 (Task 1.6) ---
REPO_ARG=""
if [[ -n "$REPO_ID" ]]; then
  REPO_ARG="--repo $REPO_ID"
fi
# state-write.sh は AUTOPILOT_DIR 環境変数を参照するため export 必須
export AUTOPILOT_DIR
# shellcheck disable=SC2086
python3 -m twl.autopilot.state write --type issue --issue "$ISSUE" --role worker $REPO_ARG --init

# --- quick ラベル検出 ---
IS_QUICK_LAUNCH=false
GH_ISSUE_REPO_FLAG=""
if [[ -n "$REPO_OWNER" && -n "$REPO_NAME" ]]; then
  GH_ISSUE_REPO_FLAG="--repo ${REPO_OWNER}/${REPO_NAME}"
fi
# shellcheck disable=SC2086
if gh issue view "$ISSUE" $GH_ISSUE_REPO_FLAG --json labels --jq '.labels[].name' 2>/dev/null | grep -qxF "quick"; then
  IS_QUICK_LAUNCH=true
fi

# --- quick 指示をシステムプロンプトとして CONTEXT に追記 ---
if [[ "$IS_QUICK_LAUNCH" == "true" ]]; then
  QUICK_INSTRUCTION="[quick Issue] このIssueにはquickラベルが付いています。workflow-test-readyは実行してはいけません。直接実装→commit→push→PR作成（'source \"\${CLAUDE_PLUGIN_ROOT}/scripts/lib/pr-create-helper.sh\" && pr_create_with_closes \"${ISSUE}\" quick' を実行し、PR 本文に必ず 'Closes #${ISSUE}' を機械的に挿入する）→merge-gateのみを実行してください。"
  if [[ -n "$CONTEXT" ]]; then
    CONTEXT="${CONTEXT}

${QUICK_INSTRUCTION}"
  else
    CONTEXT="$QUICK_INSTRUCTION"
  fi
fi

# --- プロンプト構築 ---
WINDOW_NAME="ap-#${ISSUE}"  # 後で LAUNCH_DIR 確定後に上書きする
PROMPT="/twl:workflow-setup #${ISSUE}"

# --- LAUNCH_DIR 計算 (Task 1.7) ---
EFFECTIVE_PROJECT_DIR="$PROJECT_DIR"
if [[ -n "$REPO_PATH" ]]; then
  EFFECTIVE_PROJECT_DIR="$REPO_PATH"
fi

# --- Pre-create worktree for Worker (ADR-008: Pilot owns worktree lifecycle) ---
# bare repo かつ --worktree-dir 未指定時、Pilot が worktree を事前作成して Worker をそこで起動する。
# Worker の CWD が worktree になるため、deltaspec 等が main/ に書き込む汚染を防止する。
if [[ -z "$WORKTREE_DIR" ]] && [[ -d "$EFFECTIVE_PROJECT_DIR/.bare" ]]; then
  WT_OUTPUT=$(cd "$EFFECTIVE_PROJECT_DIR/main" && python3 -m twl.autopilot.worktree create "#${ISSUE}" 2>&1)
  WT_EXIT=$?
  if [[ $WT_EXIT -eq 0 ]]; then
    WORKTREE_DIR=$(echo "$WT_OUTPUT" | grep "^パス:" | sed 's/^パス: //')
  else
    # 既存 worktree を検索（再開時）
    WORKTREE_DIR=$(git --git-dir="$EFFECTIVE_PROJECT_DIR/.bare" worktree list 2>/dev/null | \
      grep "\[.*/${ISSUE}-" | awk '{print $1}' | head -1)
  fi
  if [[ -n "$WORKTREE_DIR" ]]; then
    echo "Worktree: $WORKTREE_DIR"
  fi
fi

# --worktree-dir が指定された場合（または上記で事前作成された場合）はその値を優先
if [[ -n "$WORKTREE_DIR" ]]; then
  LAUNCH_DIR="$WORKTREE_DIR"
elif [[ -d "$EFFECTIVE_PROJECT_DIR/.bare" ]]; then
  # fallback: bare repo で worktree 作成失敗時は main/ で起動
  LAUNCH_DIR="$EFFECTIVE_PROJECT_DIR/main"
else
  LAUNCH_DIR="$EFFECTIVE_PROJECT_DIR"
fi

# --- Trace path 計算 (Phase 3 / Layer 1 経験的監査) ---
# session.json から session_id を取得し、Worker に TWL_CHAIN_TRACE を渡す。
# session_id が取得できない場合はタイムスタンプベースの ID を使用する。
TRACE_SESSION_ID=""
if [[ -f "$AUTOPILOT_DIR/session.json" ]]; then
  TRACE_SESSION_ID=$(jq -r '.session_id // ""' "$AUTOPILOT_DIR/session.json" 2>/dev/null || echo "")
fi
if [[ -z "$TRACE_SESSION_ID" ]]; then
  TRACE_SESSION_ID=$(date -u +"%Y%m%d-%H%M%S")
fi
TRACE_PATH="${AUTOPILOT_DIR}/trace/${TRACE_SESSION_ID}/issue-${ISSUE}.jsonl"
mkdir -p "$(dirname "$TRACE_PATH")" 2>/dev/null || true

# --- AUTOPILOT_DIR / REPO_ENV 環境変数構築 (Task 1.8) ---
QUOTED_AUTOPILOT_DIR=$(printf '%q' "$AUTOPILOT_DIR")
AUTOPILOT_ENV="AUTOPILOT_DIR=${QUOTED_AUTOPILOT_DIR}"

QUOTED_TRACE_PATH=$(printf '%q' "$TRACE_PATH")
TRACE_ENV="TWL_CHAIN_TRACE=${QUOTED_TRACE_PATH}"

REPO_ENV=""
if [[ -n "$REPO_OWNER" && -n "$REPO_NAME" ]]; then
  QUOTED_REPO_OWNER=$(printf '%q' "$REPO_OWNER")
  QUOTED_REPO_NAME=$(printf '%q' "$REPO_NAME")
  REPO_ENV="REPO_OWNER=${QUOTED_REPO_OWNER} REPO_NAME=${QUOTED_REPO_NAME}"
fi

# --- WORKER_ISSUE_NUM 環境変数構築 ---
# resolve_issue_num Priority 0 として参照。並列 Phase で各 Worker が正しい Issue 番号を取得するために必要。
QUOTED_ISSUE=$(printf '%q' "$ISSUE")
WORKER_ISSUE_NUM_ENV="WORKER_ISSUE_NUM=${QUOTED_ISSUE}"

# --- PYTHONPATH 環境変数構築 ---
# Worker の cld セッション内で python3 -m twl.autopilot.* が動作するために必要
# bare repo 構造: PROJECT_DIR/.bare が存在 → main/ 配下に cli/twl/src がある
# 通常 repo 構造: PROJECT_DIR 直下に cli/twl/src がある
if [[ -d "$EFFECTIVE_PROJECT_DIR/.bare" ]]; then
  _TWL_SRC="${EFFECTIVE_PROJECT_DIR}/main/cli/twl/src"
else
  _TWL_SRC="${EFFECTIVE_PROJECT_DIR}/cli/twl/src"
fi
if [[ -d "$_TWL_SRC" ]]; then
  QUOTED_TWL_SRC=$(printf '%q' "$_TWL_SRC")
  PYTHONPATH_ENV="PYTHONPATH=${QUOTED_TWL_SRC}"
else
  PYTHONPATH_ENV=""
fi

# --- コンテキスト引数構築 (Task 1.9) ---
CONTEXT_ARGS=""
if [[ -n "$CONTEXT" ]]; then
  QUOTED_CONTEXT=$(printf '%q' "$CONTEXT")
  CONTEXT_ARGS="--append-system-prompt $QUOTED_CONTEXT"
fi

# --- 意味論的 window 命名（LAUNCH_DIR 確定後に生成）---
if declare -f generate_window_name > /dev/null 2>&1; then
  if ! WINDOW_NAME=$(generate_window_name ap "$LAUNCH_DIR" "$LAUNCH_DIR" 2>/dev/null); then
    WINDOW_NAME="ap-#${ISSUE}"
  fi
fi

# window 名を autopilot state に保存（orchestrator が参照するため）
# shellcheck disable=SC2086
python3 -m twl.autopilot.state write --type issue --issue "$ISSUE" --role pilot $REPO_ARG \
  --set "window=$WINDOW_NAME" 2>/dev/null || true

# --- tmux new-window + cld 起動 (Task 1.9) ---
QUOTED_CLD=$(printf '%q' "$CLD_PATH")
QUOTED_PROMPT=$(printf '%q' "$PROMPT")
# プロンプトは positional arg で渡す。-p/--print は禁止（非対話モードで即終了する）
tmux new-window -d -n "$WINDOW_NAME" -c "$LAUNCH_DIR" \
  "env ${AUTOPILOT_ENV} ${TRACE_ENV} ${REPO_ENV} ${WORKER_ISSUE_NUM_ENV} ${PYTHONPATH_ENV} $QUOTED_CLD --model $MODEL $CONTEXT_ARGS $QUOTED_PROMPT"

# --- クラッシュ検知フック設定 (Task 1.10) ---
tmux set-option -t "$WINDOW_NAME" remain-on-exit on
QUOTED_CRASH_CMD=$(printf '%q ' bash "$SCRIPTS_ROOT/crash-detect.sh" --issue "$ISSUE" --window "$WINDOW_NAME")
tmux set-hook -t "$WINDOW_NAME" pane-died "run-shell '$QUOTED_CRASH_CMD'"

# --- window-manifest 書き出し (Phase 2 / #290) ---
# tombstone hook は設定しない: pane-died は crash-detect.sh 用に設定済みであり
# set-hook は後発呼び出しで上書きになるため競合が発生する。
# autopilot window の tombstone は crash-detect.sh / worker 完了フローが担う。
# worktree_path は WORKTREE_DIR を優先使用し、未設定時は LAUNCH_DIR にフォールバック。
if declare -f manifest_append_entry > /dev/null 2>&1; then
  _WM_SESSION=$(tmux display-message -p '#{session_name}' 2>/dev/null || echo "main")
  _WM_INDEX=$(tmux list-windows -F '#{window_name} #{window_index}' 2>/dev/null \
    | awk -v n="$WINDOW_NAME" '$1==n {print $2; exit}')
  manifest_append_entry "$WINDOW_NAME" "$_WM_SESSION" "${_WM_INDEX:-0}" \
    "${WORKTREE_DIR:-$LAUNCH_DIR}" "$LAUNCH_DIR" "ap" 2>/dev/null || true
fi

echo "Worker 起動完了: Issue #$ISSUE (window=$WINDOW_NAME, model=$MODEL, dir=$LAUNCH_DIR)"
exit 0
