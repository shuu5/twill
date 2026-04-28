#!/usr/bin/env bash
# chain-runner.sh - 機械的 chain ステップを bash で直接実行
# Usage: bash chain-runner.sh <step-name> [args...]
#
# Worker のトークン消費を削減するため、LLM 判断不要なステップを
# bash で直接実行する。手動実行パスは既存 command.md が担当。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# =====================================================================
# Compaction Recovery: chain ステップ順序定義（SSOT: scripts/chain-steps.sh）
# =====================================================================
# shellcheck source=./chain-steps.sh
source "${SCRIPT_DIR}/chain-steps.sh"
# shellcheck source=./lib/python-env.sh
source "${SCRIPT_DIR}/lib/python-env.sh"
# shellcheck source=./lib/gh-read-content.sh
source "${SCRIPT_DIR}/lib/gh-read-content.sh"
# shellcheck source=./resolve-issue-num.sh
source "${SCRIPT_DIR}/resolve-issue-num.sh"

# =====================================================================
# PYTHONPATH 検証ガード（Issue #227）
# python 呼び出し前に twl モジュールが import 可能か検証し、
# 失敗時は python-env.sh を再 source して修復を試みる
# =====================================================================
_twl_python_verified=false
ensure_pythonpath() {
  if [[ "$_twl_python_verified" == "true" ]]; then
    return 0
  fi
  if python3 -c "import twl" 2>/dev/null; then
    _twl_python_verified=true
    return 0
  fi
  echo "[chain-runner] WARN: twl モジュール import 失敗。PYTHONPATH 再設定を試行..." >&2
  # python-env.sh を再 source（フォールバックチェーンが走る）
  # shellcheck source=./lib/python-env.sh
  source "${SCRIPT_DIR}/lib/python-env.sh"
  if python3 -c "import twl" 2>/dev/null; then
    _twl_python_verified=true
    return 0
  fi
  echo "[chain-runner] ERROR: twl モジュールが import できません。PYTHONPATH=${PYTHONPATH:-<unset>}" >&2
  return 1
}

# =====================================================================
# 共通ユーティリティ関数
# =====================================================================

# worktree のプロジェクトルートを解決
resolve_project_root() {
  local root
  # tier 1: 現 CWD から rev-parse
  root=$(git rev-parse --show-toplevel 2>/dev/null) || root=""
  if [[ -n "$root" ]]; then
    echo "$root"
    return 0
  fi
  # tier 2: script 位置から rev-parse（Worker CWD が git 管理外でも救済）
  # cd 失敗時は 2>/dev/null で抑制し || script_root="" に収束 → tier 3 へ。
  # BASH_SOURCE[0] 未設定時（非 bash 実行等）は dirname が "." を返して cd が CWD に留まり
  # git rev-parse が tier 1 と同結果を返す。CWD 非 git なら失敗 → tier 3 へ（安全）。
  local script_root
  script_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null) || script_root=""
  if [[ -n "$script_root" ]]; then
    echo "$script_root"
    return 0
  fi
  # tier 3: fallback 失敗 → stderr + return 1（pwd 誤採用を構造的に不可能化）
  echo "[chain-runner] FATAL: resolve_project_root failed (cwd=$(pwd), script=${BASH_SOURCE[0]})" >&2
  return 1
}


# AUTOPILOT_DIR を解決（env var 優先、未設定時は main worktree から推定）
resolve_autopilot_dir() {
  if [[ -n "${AUTOPILOT_DIR:-}" ]]; then
    echo "$AUTOPILOT_DIR"
    return
  fi
  # main ブランチの worktree を探す（bare / null-HEAD エントリをスキップ）
  local main_wt
  main_wt=$(git worktree list --porcelain | awk '
    /^worktree /{ wt=substr($0,10) }
    /^HEAD 0{40}$/{ wt="" }
    /^bare$/{ wt="" }
    /^branch refs\/heads\/main$/{ if(wt!="") { print wt; exit } }
  ')
  if [[ -z "$main_wt" ]]; then
    # main ブランチが見つからない場合は最初の real worktree
    main_wt=$(git worktree list --porcelain | awk '
      /^worktree /{ wt=substr($0,10) }
      /^HEAD 0{40}$/{ wt="" }
      /^bare$/{ wt="" }
      /^branch /{ if(wt!="") { print wt; exit } }
    ')
  fi
  echo "${main_wt:-.}/.autopilot"
}

# =====================================================================
# Trace Event (Phase 3 / Layer 1 経験的監査)
# =====================================================================
# _resolve_path: 互換性のあるパス解決ヘルパー（issue-1041/1042 follow-up）
# GNU realpath は --canonicalize-missing をサポートするが BSD realpath (macOS)
# は非互換。下記 4 段 fallback で symlink 解決を試みる:
#   Tier 1: GNU realpath --canonicalize-missing (Linux)
#   Tier 2: greadlink -f (macOS coreutils via homebrew)
#   Tier 3: python3 os.path.realpath (POSIX 互換)
#   Tier 4: 失敗時は return 1（呼び出し元で安全側拒否）
# stdout に解決済みパスを出力。成功は return 0、失敗は return 1。
_resolve_path() {
  local p="$1"
  local resolved
  if resolved=$(realpath --canonicalize-missing "$p" 2>/dev/null) && [[ -n "$resolved" ]]; then
    echo "$resolved"; return 0
  fi
  if resolved=$(greadlink -f "$p" 2>/dev/null) && [[ -n "$resolved" ]]; then
    echo "$resolved"; return 0
  fi
  if resolved=$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$p" 2>/dev/null) && [[ -n "$resolved" ]]; then
    echo "$resolved"; return 0
  fi
  return 1
}

# TWL_CHAIN_TRACE 環境変数が設定されている場合、step の start/end を
# JSON Lines 形式で append する。設定がなければノーオペ（後方互換）。
trace_event() {
  local step="$1" phase="$2" exit_code="${3:-}"
  [[ -z "${TWL_CHAIN_TRACE:-}" ]] && return 0
  local trace_file="$TWL_CHAIN_TRACE"
  # パストラバーサル拒否（相対パスのみ意味あり、絶対パスは下記 _resolve_path で正規化される）
  case "$trace_file" in
    *..*) return 0 ;;
  esac
  # 絶対パス検証（issue-1015）: /tmp・TMPDIR・AUTOPILOT_DIR 配下のみ許可
  if [[ "$trace_file" = /* ]]; then
    # symlink TOCTOU 対策（issue-1041, macOS 互換: H1 follow-up）:
    # _resolve_path で symlink を解決してから検証。解決失敗時は安全側に倒して書き込み拒否
    local resolved_trace
    resolved_trace=$(_resolve_path "$trace_file") || return 0
    trace_file="$resolved_trace"
    local _ok=0
    [[ "$trace_file" == /tmp/* ]] && _ok=1
    if [[ "$_ok" -eq 0 && -n "${TMPDIR:-}" ]]; then
      # TMPDIR 自体が symlink である可能性に備えて resolve（macOS 互換性等）
      local _tmp_resolved
      _tmp_resolved=$(_resolve_path "${TMPDIR%/}") || _tmp_resolved="${TMPDIR%/}"
      [[ "$trace_file" == "${_tmp_resolved}/"* ]] && _ok=1
    fi
    if [[ "$_ok" -eq 0 && -n "${AUTOPILOT_DIR:-}" ]]; then
      local _ap="${AUTOPILOT_DIR%/}"
      [[ "$_ap" != /* ]] && _ap="${PWD}/${_ap}"
      # AUTOPILOT_DIR 自体が symlink を含む可能性に備えて resolve
      local _ap_resolved
      _ap_resolved=$(_resolve_path "$_ap") || _ap_resolved="$_ap"
      # AUTOPILOT_DIR 信頼性検証（issue-1042）: 攻撃者が AUTOPILOT_DIR=/etc 等を設定して
      # ホワイトリストを拡張する攻撃を防ぐため、信頼できる親ディレクトリ
      # (/tmp・TMPDIR・$HOME) 配下の場合のみ AUTOPILOT_DIR ホワイトリストを適用する
      local _autopilot_trusted=0
      [[ "$_ap_resolved" == /tmp/* ]] && _autopilot_trusted=1
      if [[ "$_autopilot_trusted" -eq 0 && -n "${TMPDIR:-}" ]]; then
        local _tmp_trust_resolved
        _tmp_trust_resolved=$(_resolve_path "${TMPDIR%/}") || _tmp_trust_resolved="${TMPDIR%/}"
        [[ "$_ap_resolved" == "${_tmp_trust_resolved}/"* ]] && _autopilot_trusted=1
      fi
      if [[ "$_autopilot_trusted" -eq 0 && -n "${HOME:-}" ]]; then
        local _home_trust_resolved
        _home_trust_resolved=$(_resolve_path "${HOME%/}") || _home_trust_resolved="${HOME%/}"
        [[ "$_ap_resolved" == "${_home_trust_resolved}/"* ]] && _autopilot_trusted=1
      fi
      # H2 (#1042 follow-up): AUTOPILOT_DIR 構造検証
      # 攻撃者が AUTOPILOT_DIR=$HOME/twl-evil 等を設定して書き込み許可を拡張する攻撃を
      # 防ぐため、basename が ".autopilot" のディレクトリのみ信頼する。
      # resolve_autopilot_dir() の挙動（env var 優先、未設定時は ${main_wt}/.autopilot）と
      # 整合する正規パターンに限定する。
      if [[ "$_autopilot_trusted" -eq 1 ]]; then
        local _ap_basename
        _ap_basename=$(basename "$_ap_resolved")
        if [[ "$_ap_basename" != ".autopilot" ]]; then
          _autopilot_trusted=0
        fi
      fi
      if [[ "$_autopilot_trusted" -eq 1 ]]; then
        [[ "$trace_file" == "${_ap_resolved}/"* ]] && _ok=1
      fi
    fi
    [[ "$_ok" -eq 0 ]] && return 0
  fi
  # 親ディレクトリ作成（失敗してもサイレント）
  mkdir -p "$(dirname "$trace_file")" 2>/dev/null || return 0
  local ts
  ts=$(date -Iseconds 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")
  if command -v jq >/dev/null 2>&1; then
    jq -nc \
      --arg step "$step" \
      --arg phase "$phase" \
      --arg ts "$ts" \
      --arg exit_code "$exit_code" \
      --arg pid "$$" \
      '{step: $step, phase: $phase, ts: $ts, exit_code: (if $exit_code == "" then null else ($exit_code | tonumber? // null) end), pid: ($pid | tonumber)}' \
      >> "$trace_file" 2>/dev/null || true
  else
    local exit_field
    if [[ -z "$exit_code" ]]; then exit_field="null"; else exit_field="$exit_code"; fi
    printf '{"step":"%s","phase":"%s","ts":"%s","exit_code":%s,"pid":%s}\n' \
      "$step" "$phase" "$ts" "$exit_field" "$$" >> "$trace_file" 2>/dev/null || true
  fi
}

# 成功出力
ok() {
  local step="$1"; shift
  echo "✓ ${step}: $*"
}

# スキップ出力
skip() {
  local step="$1"; shift
  echo "⚠️ ${step}: $*"
}

# エラー出力（stderr）
err() {
  local step="$1"; shift
  echo "✗ ${step}: $*" >&2
}

# Compaction Recovery: current_step を issue-{N}.json に記録
# 引数: step_id（記録するステップ名）
# issue_num はブランチ名から自動抽出。取得できない場合はサイレントスキップ
#
# #890: last_heartbeat_at も同時更新することで、updated_at が他書込経路で
# 更新されたとしても "実際に chain step 境界を通過した" タイムスタンプを
# orchestrator stagnation 判定が正確に読めるようにする。
record_current_step() {
  local step_id="${1:-}"
  [[ -z "$step_id" ]] && return 0
  # step_id の形式を検証（英数字とハイフンのみ許可）
  [[ "$step_id" =~ ^[a-z0-9-]+$ ]] || return 0
  local issue_num
  issue_num="$(resolve_issue_num)"
  [[ -z "$issue_num" ]] && return 0
  # PYTHONPATH 検証（Issue #227）
  ensure_pythonpath || return 0
  local now_utc
  now_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  # record current_step + last_heartbeat_at via Python state module (#890)
  python3 -m twl.autopilot.state write --autopilot-dir "$(resolve_autopilot_dir)" --type issue --issue "$issue_num" --role worker \
    --set "current_step=${step_id}" \
    --set "last_heartbeat_at=${now_utc}" 2>/dev/null || true
}

# =====================================================================
# Step 実装
# =====================================================================

# Issue の labels を取得する（Issue 番号が正の整数の場合のみ）
fetch_labels() {
  local issue_num="${1:-}"
  [[ -n "$issue_num" ]] && [[ "$issue_num" =~ ^[0-9]+$ ]] || { echo ""; return 0; }
  gh issue view "$issue_num" --json labels --jq '.labels[].name' 2>/dev/null || echo ""
}

# --- autopilot-detect: autopilot 状態を eval 可能な key=value 形式で出力 ---
step_autopilot_detect() {
  local issue_num
  issue_num="$(resolve_issue_num)"
  if [[ -z "$issue_num" ]]; then
    echo "IS_AUTOPILOT=false"
    return 0
  fi
  local autopilot_status
  autopilot_status="$(python3 -m twl.autopilot.state read --autopilot-dir "$(resolve_autopilot_dir)" --type issue --issue "$issue_num" --field status 2>/dev/null || echo "")"
  if [[ "$autopilot_status" == "running" ]]; then
    echo "IS_AUTOPILOT=true"
  else
    echo "IS_AUTOPILOT=false"
  fi
}

# --- init: 開発状態判定 ---

# Usage: step_init [issue_num]
step_init() {
  record_current_step "init"
  local issue_num="${1:-}"
  local branch
  branch="$(git branch --show-current 2>/dev/null || echo "detached")"

  local _labels
  _labels="$(fetch_labels "$issue_num")"
  local is_direct
  is_direct="$(echo "$_labels" | grep -qxF "scope/direct" && echo "true" || echo "false")"

  # is_direct を state に永続化（state ファイルが存在する場合のみ）
  if [[ -n "$issue_num" ]] && [[ "$issue_num" =~ ^[0-9]+$ ]]; then
    python3 -m twl.autopilot.state write --autopilot-dir "$(resolve_autopilot_dir)" --type issue --issue "$issue_num" --role worker --set "is_direct=$is_direct" 2>/dev/null || true
  fi

  # ブランチ判定
  if [[ "$branch" == "main" || "$branch" == "master" ]]; then
    jq -n --arg branch "$branch" '{"recommended_action":"worktree","branch":$branch}'
    ok "init" "recommended_action=worktree (branch=$branch)"
    return 0
  fi

  # scope/direct ラベル → direct
  if [[ "$is_direct" == "true" ]]; then
    jq -n --arg branch "$branch" --argjson is_direct "$is_direct" '{"recommended_action":"direct","branch":$branch,"is_direct":$is_direct}'
    ok "init" "recommended_action=direct (scope/direct label)"
    if [[ -n "$issue_num" ]] && [[ "$issue_num" =~ ^[0-9]+$ ]]; then
      python3 -m twl.autopilot.state write --autopilot-dir "$(resolve_autopilot_dir)" --type issue --issue "$issue_num" --role worker --set "mode=direct" 2>/dev/null || true
    fi
    return 0
  fi

  # AC2: export SNAPSHOT_DIR per-issue（step_init で確定: SSOT）
  if [[ -n "$issue_num" ]] && [[ "$issue_num" =~ ^[0-9]+$ ]]; then
    local root
    root="$(resolve_project_root)"
    export SNAPSHOT_DIR="$root/.dev-session/issue-${issue_num}"
  fi

  jq -n --arg branch "$branch" '{"recommended_action":"implement","branch":$branch}'
  ok "init" "recommended_action=implement (branch=$branch)"
}

# --- worktree-create: Python モジュールラッパー ---
# ADR-008: autopilot 時は Pilot が事前作成済みのためスキップ
step_worktree_create() {
  record_current_step "worktree-create"
  local branch
  branch="$(git branch --show-current 2>/dev/null || echo "main")"
  if [[ "$branch" != "main" && "$branch" != "master" ]]; then
    ok "worktree-create" "既に worktree 内（branch=$branch）— スキップ"
    return 0
  fi
  # AC-3: post-create refspec 自動設定（重複防止のため --replace-all を使用）
  # twl.autopilot.worktree create は "パス: <path>" を stdout に出力するためキャプチャする
  local create_output new_wt_path
  create_output=$(python3 -m twl.autopilot.worktree create "$@")
  echo "$create_output"
  new_wt_path=$(echo "$create_output" | grep "^パス: " | sed 's/^パス: //')
  if [[ -n "$new_wt_path" && -d "$new_wt_path" ]]; then
    git -C "$new_wt_path" config --replace-all remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*' 2>/dev/null || true
  fi
  ok "worktree-create" "完了"
}

# --- board-status-update: Project Board Status 更新 ---
step_board_status_update() {
  record_current_step "board-status-update"
  local issue_num="${1:-}"
  local target_status="${2:-In Progress}"

  # 引数なし or 空 → スキップ
  if [[ -z "$issue_num" ]]; then
    return 0
  fi

  # 正の整数チェック
  if ! [[ "$issue_num" =~ ^[0-9]+$ ]]; then
    return 0
  fi

  # project スコープ確認
  if ! gh project list --owner @me --limit 1 >/dev/null 2>&1; then
    skip "board-status-update" "gh auth refresh -s project が必要"
    return 0
  fi

  local final_num final_id owner repo_name repo _resolve_json
  _resolve_json=$(python3 -m twl.autopilot.github resolve-project 2>/dev/null) || _resolve_json=""
  if [[ -z "$_resolve_json" ]]; then
    skip "board-status-update" "リンクされた Project なし"
    return 0
  fi
  final_num=$(echo "$_resolve_json" | jq -r '.project_num')
  final_id=$(echo "$_resolve_json" | jq -r '.project_id')
  owner=$(echo "$_resolve_json" | jq -r '.owner')
  repo_name=$(echo "$_resolve_json" | jq -r '.repo_name')
  repo=$(echo "$_resolve_json" | jq -r '.repo_fullname')

  # Issue を Project に追加
  local item_id
  item_id=$(gh project item-add "$final_num" --owner "$owner" \
    --url "https://github.com/$repo/issues/$issue_num" --format json 2>/dev/null \
    | jq -r '.id') || {
    skip "board-status-update" "Issue 追加失敗"
    return 0
  }

  # Status フィールドの target_status オプション ID を取得
  local fields status_field_id status_option_id
  fields=$(gh project field-list "$final_num" --owner "$owner" --format json 2>/dev/null) || {
    skip "board-status-update" "フィールド取得失敗"
    return 0
  }
  status_field_id=$(echo "$fields" | jq -r '.fields[] | select(.name == "Status") | .id')
  status_option_id=$(echo "$fields" | jq --raw-output --arg status "${target_status}" '.fields[] | select(.name == "Status") | .options[] | select(.name == $status) | .id')

  if [[ -z "$status_field_id" || -z "$status_option_id" ]]; then
    skip "board-status-update" "Status フィールドまたは $target_status オプションが見つからない"
    return 0
  fi

  gh project item-edit --id "$item_id" --project-id "$final_id" \
    --field-id "$status_field_id" --single-select-option-id "$status_option_id" 2>/dev/null || {
    skip "board-status-update" "Status 更新失敗"
    return 0
  }

  ok "board-status-update" "Project Board Status → $target_status (#$issue_num)"
}

# --- board-archive: Project Board アイテムをアーカイブ ---
# 用途: autopilot Phase 完了処理（autopilot-orchestrator.sh）から呼び出される。
# merge-gate-execute.sh からは呼び出されない（merge 後は board-status-update "Done" で Done 遷移し、
# Archive は autopilot Phase 完了時に一括処理する設計）。
step_board_archive() {
  record_current_step "board-archive"
  local issue_num="${1:-}"

  # 引数なし or 空 → スキップ
  if [[ -z "$issue_num" ]]; then
    return 0
  fi

  # 正の整数チェック
  if ! [[ "$issue_num" =~ ^[0-9]+$ ]]; then
    return 0
  fi

  # NEW: GitHub state 二重チェック (fail-closed, Issue #138)
  # 空文字 (取得失敗) も "CLOSED でない" として skip 扱いにする
  local gh_state
  gh_state=$(gh issue view "$issue_num" --json state -q .state 2>/dev/null || echo "")
  if [[ "$gh_state" != "CLOSED" ]]; then
    if [[ -z "$gh_state" ]]; then
      skip "board-archive" "Issue #${issue_num} の GitHub state 取得失敗 — fail-closed で archive をスキップ"
    else
      skip "board-archive" "Issue #${issue_num} が GitHub 上で ${gh_state} — archive をスキップ"
    fi
    return 0
  fi

  # project スコープ確認
  if ! gh project list --owner @me --limit 1 >/dev/null 2>&1; then
    skip "board-archive" "gh auth refresh -s project が必要"
    return 0
  fi

  local final_num owner _resolve_json2
  _resolve_json2=$(python3 -m twl.autopilot.github resolve-project 2>/dev/null) || _resolve_json2=""
  if [[ -z "$_resolve_json2" ]]; then
    skip "board-archive" "リンクされた Project なし"
    return 0
  fi
  final_num=$(echo "$_resolve_json2" | jq -r '.project_num')
  owner=$(echo "$_resolve_json2" | jq -r '.owner')

  # アイテム ID 取得
  local item_id
  item_id=$(gh project item-list "$final_num" --owner "$owner" --format json --limit 200 2>/dev/null \
    | jq -r --argjson n "$issue_num" '.items[] | select(.content.number == $n and .content.type == "Issue") | .id' 2>/dev/null) || true

  if [[ -z "$item_id" ]]; then
    skip "board-archive" "アイテムIDが取得できませんでした — スキップ"
    return 0
  fi

  # アーカイブ実行
  if gh project item-archive "$final_num" --owner "$owner" --id "$item_id" 2>/dev/null; then
    ok "board-archive" "Board アイテムをアーカイブしました (#$issue_num)"
  else
    skip "board-archive" "アーカイブに失敗しました — スキップ"
  fi
  return 0
}

# --- ac-extract: AC 抽出 ---
step_ac_extract() {
  record_current_step "ac-extract"
  local snapshot_dir="${1:-}"
  local issue_num
  issue_num="$(resolve_issue_num)"

  if [[ -z "$issue_num" ]]; then
    skip "ac-extract" "Issue 番号なし — スキップ"
    return 0
  fi

  if [[ -z "$snapshot_dir" ]]; then
    local root
    root="$(resolve_project_root)"
    snapshot_dir="$root/.dev-session/issue-${issue_num}"
  fi
  mkdir -p "$snapshot_dir"

  local output_file="$snapshot_dir/01.5-ac-checklist.md"

  # 冪等: 既存なら skip
  if [[ -f "$output_file" ]] && [[ -s "$output_file" ]]; then
    ok "ac-extract" "既存 AC チェックリストを使用"
    return 0
  fi

  local ac_output
  ac_output=$(python3 -m twl.autopilot.github extract-ac "$issue_num" 2>/dev/null) && {
    printf '%s\n\n%s\n' "## 受け入れ基準（Issue #${issue_num}）" "$ac_output" > "$output_file"
    ok "ac-extract" "AC 抽出完了 (Issue #$issue_num)"
  } || {
    echo "AC セクションなし — スキップ" > "$output_file"
    skip "ac-extract" "AC セクションなし — スキップ"
  }
}

# --- arch-ref: architecture/ コンテキスト抽出 ---
step_arch_ref() {
  record_current_step "arch-ref"
  local issue_num="${1:-}"
  if [[ -z "$issue_num" ]]; then
    issue_num="$(resolve_issue_num)"
  fi

  if [[ -z "$issue_num" ]]; then
    skip "arch-ref" "Issue 番号なし — スキップ"
    return 0
  fi

  # 数値検証（インジェクション防止）
  if ! [[ "$issue_num" =~ ^[0-9]+$ ]]; then
    err "arch-ref" "不正な Issue 番号: $issue_num"
    return 1
  fi

  # Issue body + comments から arch-ref タグを検索（content-reading ポリシー: gh_read_issue_full 経由）
  local combined
  combined=$(gh_read_issue_full "$issue_num" 2>/dev/null || echo "")

  if ! echo "$combined" | grep -q '<!-- arch-ref-start -->'; then
    skip "arch-ref" "タグなし — スキップ"
    return 0
  fi

  # タグ間のパスを抽出
  local paths
  paths=$(echo "$combined" \
    | sed -n '/<!-- arch-ref-start -->/,/<!-- arch-ref-end -->/p' \
    | grep -oP 'architecture/[^\s<]+' \
    | head -5)

  local count=0
  while IFS= read -r path; do
    [[ -z "$path" ]] && continue

    # パストラバーサル拒否
    if echo "$path" | grep -q '\.\.'; then
      echo "⚠️ パストラバーサル拒否: $path" >&2
      continue
    fi

    local root
    root="$(resolve_project_root)"
    if [[ -f "$root/$path" ]]; then
      echo "$path"
      ((count++))
    else
      echo "⚠️ ファイル不在: $path" >&2
    fi
  done <<< "$paths"

  if [[ $count -gt 0 ]]; then
    ok "arch-ref" "${count} 件のパスを抽出"
  else
    skip "arch-ref" "有効なパスなし"
  fi
}

# --- next-step: current_step から次ステップ名を返す ---
# Usage: step_next_step <issue_num> <current_step> [--json]
# stdout に次ステップ名を出力（全完了時は "done"）
# --json フラグ: {"step":"<name>","type":"<runner|llm>","command":"<path>"} 形式で出力
# NOTE: クエリコマンドのため record_current_step は呼ばない（chain 状態を変更しない）
step_next_step() {
  local issue_num="${1:-}"
  local current_step="${2:-}"
  local output_json=false
  [[ "${3:-}" == "--json" ]] && output_json=true

  # 引数バリデーション
  if [[ -z "$issue_num" ]] || [[ ! "$issue_num" =~ ^[0-9]+$ ]]; then
    echo "ERROR: issue_num は正の整数で指定してください" >&2
    return 1
  fi

  # current_step が引数未指定の場合は state から取得
  if [[ -z "$current_step" ]]; then
    current_step="$(python3 -m twl.autopilot.state read --autopilot-dir "$(resolve_autopilot_dir)" --type issue --issue "$issue_num" --field current_step 2>/dev/null || echo "")"
  fi

  # mode を state から取得（存在しない場合は空文字列）
  local mode
  mode="$(python3 -m twl.autopilot.state read --autopilot-dir "$(resolve_autopilot_dir)" --type issue --issue "$issue_num" --field mode 2>/dev/null || echo "")"

  # current_step のインデックスを探す
  local found=false
  for step in "${CHAIN_STEPS[@]}"; do
    if [[ "$found" == "true" ]]; then
      # mode=direct かつ DIRECT_SKIP_STEPS に含まれるステップはスキップ
      if [[ "$mode" == "direct" ]] && printf '%s\n' "${DIRECT_SKIP_STEPS[@]}" | grep -qxF "$step"; then
        continue
      fi
      if $output_json; then
        local _dispatch_mode="${CHAIN_STEP_DISPATCH[$step]:-runner}"
        local _command_path="${CHAIN_STEP_COMMAND[$step]:-}"
        if command -v jq >/dev/null 2>&1; then
          jq -nc --arg step "$step" --arg type "$_dispatch_mode" --arg command "$_command_path" \
            '{step: $step, type: $type, command: $command}'
        else
          echo "{\"step\":\"${step}\",\"type\":\"${_dispatch_mode}\",\"command\":\"${_command_path}\"}"
        fi
      else
        echo "$step"
      fi
      return 0
    fi
    [[ "$step" == "$current_step" ]] && found=true
  done

  # current_step が未設定またはリスト外 → 先頭ステップを返す
  if [[ "$found" == "false" ]]; then
    echo "${CHAIN_STEPS[0]}"
    return 0
  fi

  # 全ステップ完了
  echo "done"
}

# --- dispatch-info: ステップの dispatch_mode と command パスを返す ---
# Usage: chain-runner.sh dispatch-info <step_name>
# stdout に JSON {"step":"<name>","type":"<runner|llm>","command":"<path>"} を出力
step_dispatch_info() {
  local step_name="${1:-}"
  if [[ -z "$step_name" ]]; then
    echo "ERROR: step name required" >&2
    return 1
  fi
  local dispatch_mode="${CHAIN_STEP_DISPATCH[$step_name]:-runner}"
  local command_path="${CHAIN_STEP_COMMAND[$step_name]:-}"
  if command -v jq >/dev/null 2>&1; then
    jq -nc \
      --arg step "$step_name" \
      --arg type "$dispatch_mode" \
      --arg command "$command_path" \
      '{step: $step, type: $type, command: $command}'
  else
    echo "{\"step\":\"${step_name}\",\"type\":\"${dispatch_mode}\",\"command\":\"${command_path}\"}"
  fi
}

# --- llm-delegate: LLM ステップの開始を chain-runner に記録 ---
# Usage: chain-runner.sh llm-delegate <step_name> [issue_num]
# LLM が特定のステップを実行し始める前に呼ぶ。current_step と llm_delegated_at を記録する。
# compaction 復帰時に chain-runner の状態から正確にリカバリできる。
step_llm_delegate() {
  local step_name="${1:-}"
  local issue_num="${2:-$(resolve_issue_num 2>/dev/null || echo "")}"
  if [[ -z "$step_name" ]]; then
    echo "ERROR: step name required" >&2
    return 1
  fi
  [[ "$step_name" =~ ^[a-z0-9-]+$ ]] || { echo "ERROR: invalid step name" >&2; return 1; }
  local dispatch_mode="${CHAIN_STEP_DISPATCH[$step_name]:-runner}"
  if [[ "$dispatch_mode" != "llm" ]]; then
    echo "WARN: ${step_name} の dispatch_mode は '${dispatch_mode}'（llm ではありません）" >&2
  fi
  local ts ts_utc
  ts=$(date -Iseconds 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")
  ts_utc=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # #890 + #891 (実 e2e で発覚): LLM step は step_<name> ではなく llm-delegate 経由で
  # 実行されるため、last_heartbeat_at 更新 (#890) と ac_verify_call_count インクリメント
  # (#891) を step_llm_delegate にも実装する必要がある。
  if [[ -n "$issue_num" ]]; then
    # 基本 write: current_step + llm_delegated_at + last_heartbeat_at (#890 fix)
    python3 -m twl.autopilot.state write \
      --autopilot-dir "$(resolve_autopilot_dir)" \
      --type issue --issue "$issue_num" --role worker \
      --set "current_step=${step_name}" \
      --set "llm_delegated_at=${ts}" \
      --set "last_heartbeat_at=${ts_utc}" \
      2>/dev/null || true

    # #891 fix: ac-verify LLM delegate 時に call_count safety net を発火
    if [[ "$step_name" == "ac-verify" ]]; then
      local _max_retry="${DEV_AUTOPILOT_AC_VERIFY_MAX_RETRY:-1}"
      local _call_count
      _call_count=$(python3 -m twl.autopilot.state read --autopilot-dir "$(resolve_autopilot_dir)" --type issue --issue "$issue_num" --field ac_verify_call_count 2>/dev/null || echo "0")
      [[ -z "$_call_count" || ! "$_call_count" =~ ^[0-9]+$ ]] && _call_count=0
      local _new_count=$((_call_count + 1))
      python3 -m twl.autopilot.state write --autopilot-dir "$(resolve_autopilot_dir)" --type issue --issue "$issue_num" --role worker \
        --set "ac_verify_call_count=${_new_count}" 2>/dev/null || true

      if (( _new_count > _max_retry + 1 )); then
        echo "[chain-runner] ac-verify call_count=${_new_count} > max=$((_max_retry + 1)) — ac_verify_llm_timeout で failed に確定 (Issue #$issue_num)" >&2
        local _failure
        _failure=$(printf '{"reason":"ac_verify_llm_timeout","retry_count":%d,"step":"ac-verify"}' "$((_new_count - 1))")
        python3 -m twl.autopilot.state write --autopilot-dir "$(resolve_autopilot_dir)" --type issue --issue "$issue_num" --role worker \
          --set "status=failed" \
          --set "failure=${_failure}" 2>/dev/null || true
        err "llm-delegate" "ac-verify LLM timeout retry 上限超過 (call_count=${_new_count}) — failed 確定"
        return 2
      fi
    fi
  else
    record_current_step "$step_name"
  fi
  ok "llm-delegate" "${step_name} → LLM 実行委譲"
}

# --- llm-complete: LLM ステップの完了を chain-runner に記録 ---
# Usage: chain-runner.sh llm-complete <step_name> [issue_num]
# LLM がステップを完了した後に呼ぶ。llm_completed_at を記録する。
step_llm_complete() {
  local step_name="${1:-}"
  local issue_num="${2:-$(resolve_issue_num 2>/dev/null || echo "")}"
  if [[ -z "$step_name" ]]; then
    echo "ERROR: step name required" >&2
    return 1
  fi
  [[ "$step_name" =~ ^[a-z0-9-]+$ ]] || { echo "ERROR: invalid step name" >&2; return 1; }
  local ts ts_utc
  ts=$(date -Iseconds 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")
  ts_utc=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  if [[ -n "$issue_num" ]]; then
    # #890 fix: LLM step 完了時も chain 境界通過として heartbeat を更新する
    python3 -m twl.autopilot.state write \
      --autopilot-dir "$(resolve_autopilot_dir)" \
      --type issue --issue "$issue_num" --role worker \
      --set "llm_completed_at=${ts}" \
      --set "last_heartbeat_at=${ts_utc}" \
      2>/dev/null || true
  fi
  ok "llm-complete" "${step_name} 完了"
}

# --- chain-status: 全ステップの進捗状態を一覧表示 ---
# Usage: chain-runner.sh chain-status [issue_num]
# 各ステップの状態（done/running/pending/skipped）と dispatch_mode を表示
step_chain_status() {
  local issue_num="${1:-$(resolve_issue_num 2>/dev/null || echo "")}"
  if [[ -z "$issue_num" ]]; then
    echo "ERROR: issue_num が取得できません" >&2
    return 1
  fi

  local current_step
  current_step="$(python3 -m twl.autopilot.state read \
    --autopilot-dir "$(resolve_autopilot_dir)" \
    --type issue --issue "$issue_num" --field current_step 2>/dev/null || echo "")"

  local mode
  mode="$(python3 -m twl.autopilot.state read \
    --autopilot-dir "$(resolve_autopilot_dir)" \
    --type issue --issue "$issue_num" --field mode 2>/dev/null || echo "")"

  echo "chain-status: Issue #${issue_num} (mode=${mode:-none}, current=${current_step:-none})"
  echo "---"

  local found_current=false
  for step in "${CHAIN_STEPS[@]}"; do
    local dispatch_mode="${CHAIN_STEP_DISPATCH[$step]:-runner}"
    local type_label="[${dispatch_mode}]"

    if [[ "$mode" == "direct" ]] && printf '%s\n' "${DIRECT_SKIP_STEPS[@]}" | grep -qxF "$step"; then
      echo "  ⊘ ${step} ${type_label} (skipped/direct)"
      continue
    fi

    if [[ "$found_current" == "true" ]]; then
      echo "  ○ ${step} ${type_label} (pending)"
      continue
    fi

    if [[ "$step" == "$current_step" ]]; then
      echo "  ▶ ${step} ${type_label} (running)"
      found_current=true
      continue
    fi

    echo "  ✓ ${step} ${type_label} (done)"
  done
}

# --- ts-preflight: TypeScript 機械的検証 ---
step_ts_preflight() {
  record_current_step "ts-preflight"
  local root
  root="$(resolve_project_root)"

  if [[ ! -f "$root/tsconfig.json" ]]; then
    ok "ts-preflight" "PASS (TypeScript プロジェクトではない — スキップ)"
    return 0
  fi

  local failed=false results=""

  # 型チェック
  if ! (cd "$root" && npx tsc --noEmit 2>&1); then
    failed=true
    results+="tsc FAIL; "
  fi

  # lint（eslint 設定がある場合のみ）
  if [[ -f "$root/.eslintrc" || -f "$root/.eslintrc.js" || -f "$root/.eslintrc.json" || -f "$root/eslint.config.js" ]]; then
    if ! (cd "$root" && npx eslint . 2>&1); then
      failed=true
      results+="eslint FAIL; "
    fi
  fi

  # ビルド（build スクリプトがある場合のみ）
  if [[ -f "$root/package.json" ]] && jq -e '.scripts.build' "$root/package.json" >/dev/null 2>&1; then
    if ! (cd "$root" && npm run build 2>&1); then
      failed=true
      results+="build FAIL; "
    fi
  fi

  if $failed; then
    skip "ts-preflight" "FAIL ($results)"
    return 1
  else
    ok "ts-preflight" "PASS"
  fi
}

# --- prompt-compliance: refined_by ハッシュ整合性検証 ---
step_prompt_compliance() {
  record_current_step "prompt-compliance"

  # 変更された .md ファイルを検出（origin/main との diff、追加・変更のみ）
  local changed_md
  changed_md=$(git diff --name-only --diff-filter=AM origin/main -- '*.md' 2>/dev/null)

  if [[ -z "$changed_md" ]]; then
    ok "prompt-compliance" "PASS (.md 変更なし — スキップ)"
    return 0
  fi

  # ref-prompt-guide.md 自体が変更された場合: 全コンポーネントが stale になるため WARN
  if echo "$changed_md" | grep -q 'refs/ref-prompt-guide\.md'; then
    ok "prompt-compliance" "WARN (ref-prompt-guide.md 変更検出 — 全コンポーネントの refined_by が stale。Tier 2 audit を推奨)"
    return 0
  fi

  # twl --audit --section 7 --format json で prompt_compliance 項目を取得
  local result
  result=$(twl --audit --section 7 --format json 2>/dev/null)

  local stale_count error_count
  stale_count=$(echo "$result" | jq '[.items[] | select(.severity == "warning")] | length' 2>/dev/null || echo 0)
  error_count=$(echo "$result" | jq '[.items[] | select(.severity == "error")] | length' 2>/dev/null || echo 0)

  if [[ "$error_count" -gt 0 ]]; then
    skip "prompt-compliance" "FAIL (refined_by フォーマット不正: ${error_count} 件)"
    return 1
  elif [[ "$stale_count" -gt 0 ]]; then
    ok "prompt-compliance" "WARN (stale: ${stale_count} 件 — twl refine で更新推奨)"
    return 0
  else
    ok "prompt-compliance" "PASS"
    return 0
  fi
}

# --- pr-test: テスト実行 ---
step_pr_test() {
  record_current_step "pr-test"
  local root
  root="$(resolve_project_root)"
  local exit_code=0

  # テストランナー検出 + 実行
  if [[ -f "$root/tests/run-all.sh" ]]; then
    (cd "$root" && bash tests/run-all.sh 2>&1) || exit_code=$?
  elif [[ -f "$root/package.json" ]] && jq -e '.scripts.test' "$root/package.json" >/dev/null 2>&1; then
    if command -v pnpm &>/dev/null; then
      (cd "$root" && pnpm test 2>&1) || exit_code=$?
    else
      (cd "$root" && npm test 2>&1) || exit_code=$?
    fi
  elif [[ -f "$root/pytest.ini" || -f "$root/pyproject.toml" ]]; then
    (cd "$root" && pytest 2>&1) || exit_code=$?
  elif ls "$root/tests/scenarios/"*.test.sh >/dev/null 2>&1; then
    for test_file in "$root/tests/scenarios/"*.test.sh; do
      (cd "$root" && bash "$test_file" 2>&1) || exit_code=$?
    done
  else
    skip "pr-test" "WARN (テストファイルなし)"
    return 0
  fi

  if [[ $exit_code -eq 0 ]]; then
    ok "pr-test" "PASS"
  else
    skip "pr-test" "FAIL (exit code: $exit_code)"
    return 1
  fi
}

# --- ac-verify: AC↔diff/test 整合性チェック（LLM ステップマーカー） ---
# 機械的処理は行わない。current_step を記録し、LLM 側で commands/ac-verify.md を
# Read → 実行する旨を通知するのみ。判定結果は ac-verify.json checkpoint に書かれる。
step_ac_verify() {
  record_current_step "ac-verify"
  local issue_num
  issue_num="$(resolve_issue_num)"
  if [[ -z "$issue_num" ]]; then
    skip "ac-verify" "Issue 番号なし — スキップ"
    return 0
  fi

  # #891: ac-verify call count で retry safety net。orchestrator が stagnation 検知で
  # ac-verify を再 inject するのは許容（retry 1 回まで）。max+1 を超えた呼出で
  # LLM stall が回復不能と判断し、status=failed, failure.reason=ac_verify_llm_timeout に確定。
  ensure_pythonpath || true
  local _max_retry="${DEV_AUTOPILOT_AC_VERIFY_MAX_RETRY:-1}"  # retry 上限（default 1 = 最大 2 回呼出）
  local _call_count
  _call_count=$(python3 -m twl.autopilot.state read --autopilot-dir "$(resolve_autopilot_dir)" --type issue --issue "$issue_num" --field ac_verify_call_count 2>/dev/null || echo "0")
  [[ -z "$_call_count" || ! "$_call_count" =~ ^[0-9]+$ ]] && _call_count=0
  local _new_count=$((_call_count + 1))
  python3 -m twl.autopilot.state write --autopilot-dir "$(resolve_autopilot_dir)" --type issue --issue "$issue_num" --role worker \
    --set "ac_verify_call_count=${_new_count}" 2>/dev/null || true

  if (( _new_count > _max_retry + 1 )); then
    echo "[chain-runner] ac-verify call_count=${_new_count} > max=$((_max_retry + 1)) — ac_verify_llm_timeout で failed に確定 (Issue #$issue_num)" >&2
    local _failure
    _failure=$(printf '{"reason":"ac_verify_llm_timeout","retry_count":%d,"step":"ac-verify"}' "$((_new_count - 1))")
    # worker role で書込（step_ac_verify は worktree 内で実行されるため、
    # role=pilot だと不変条件 C で拒否される）
    python3 -m twl.autopilot.state write --autopilot-dir "$(resolve_autopilot_dir)" --type issue --issue "$issue_num" --role worker \
      --set "status=failed" \
      --set "failure=${_failure}" 2>/dev/null || true
    err "ac-verify" "LLM timeout retry 上限超過 (call_count=${_new_count}) — failed 確定"
    return 2  # force-exit: 呼び出し元は通常の LLM step 遷移を行わない
  fi

  echo "[chain-runner] ac-verify は LLM ステップです。(call_count=${_new_count}/$((_max_retry + 1)))" >&2
  echo "[chain-runner] commands/ac-verify.md を Read して実行してください。" >&2
  echo "[chain-runner] 入力: AC checklist + PR diff + pr-test checkpoint" >&2
  echo "[chain-runner] 出力: .autopilot/checkpoints/ac-verify.json (merge-gate が読む)" >&2
  ok "ac-verify" "LLM ステップへ遷移 (Issue #$issue_num)"
}

# --- all-pass-check: 全パス判定 ---
# --- record-pr: PR 作成直後に pr フィールドを state に書き込む (#668) ---
# all-pass-check への一点集中を解消し、PR 番号を確実に記録する。
# Worker が gh pr create 直後に呼ぶ。all-pass-check がスキップされても pr が記録される。
step_record_pr() {
  local issue_num
  issue_num="$(resolve_issue_num)"
  [[ -z "$issue_num" ]] && { ok "record-pr" "non-autopilot — スキップ"; return 0; }

  ensure_pythonpath || { err "record-pr" "PYTHONPATH 設定不可"; return 1; }

  local _pr_num _branch
  _pr_num=$(gh pr view --json number -q '.number' 2>/dev/null || echo "")
  _branch=$(git branch --show-current 2>/dev/null || echo "")

  if [[ -z "$_pr_num" ]] || ! [[ "$_pr_num" =~ ^[0-9]+$ ]]; then
    skip "record-pr" "PR 番号取得不可 — スキップ"
    return 0
  fi

  if ! python3 -m twl.autopilot.state write --autopilot-dir "$(resolve_autopilot_dir)" \
    --type issue --issue "$issue_num" --role worker \
    --set "pr=$_pr_num" --set "branch=$_branch" >&2; then
    err "record-pr" "state write 失敗"
    return 1
  fi

  ok "record-pr" "PR #${_pr_num} を state に記録 (branch=${_branch})"
}

step_all_pass_check() {
  record_current_step "all-pass-check"
  # 引数: step_results を JSON 形式で受け取る（stdin or 引数）
  local issue_num
  issue_num="$(resolve_issue_num)"

  # 結果は呼び出し側（SKILL.md）が判定して引数で渡す
  local overall_result="${1:-PASS}"

  if [[ -z "$issue_num" ]]; then
    if [[ "$overall_result" == "PASS" ]]; then
      ok "all-pass-check" "PASS (non-autopilot)"
    else
      skip "all-pass-check" "FAIL (non-autopilot)"
    fi
    return 0
  fi

  # PYTHONPATH 検証（Issue #227: all-pass-check は状態書き込みに必須）
  ensure_pythonpath || { err "all-pass-check" "PYTHONPATH 設定不可"; return 1; }

  # autopilot 配下判定
  local autopilot_status
  autopilot_status=$(python3 -m twl.autopilot.state read --autopilot-dir "$(resolve_autopilot_dir)" --type issue --issue "$issue_num" --field status 2>/dev/null || echo "")
  local is_autopilot=false
  [[ "$autopilot_status" == "running" ]] && is_autopilot=true

  if [[ "$overall_result" == "PASS" ]]; then
    local _cr_branch _cr_pr
    _cr_branch=$(git branch --show-current 2>/dev/null || echo "")
    _cr_pr=$(gh pr view --json number -q '.number' 2>/dev/null || echo "")
    if ! python3 -m twl.autopilot.state write --autopilot-dir "$(resolve_autopilot_dir)" --type issue --issue "$issue_num" --role worker --set "status=merge-ready" --set "pr=$_cr_pr" --set "branch=$_cr_branch" >&2; then
      err "all-pass-check" "state write merge-ready 失敗"
      return 1
    fi
    if $is_autopilot; then
      ok "all-pass-check" "PASS — autopilot 配下: merge-ready 宣言。Pilot による merge-gate を待機"
    else
      ok "all-pass-check" "PASS — merge-ready"
    fi
  else
    if ! python3 -m twl.autopilot.state write --autopilot-dir "$(resolve_autopilot_dir)" --type issue --issue "$issue_num" --role worker --set "status=failed" >&2; then
      err "all-pass-check" "state write failed 失敗"
      return 1
    fi
    skip "all-pass-check" "FAIL — status=failed"
    return 1
  fi
}

# --- pr-cycle-report: 結果レポート構造化集約 ---
step_pr_cycle_report() {
  record_current_step "pr-cycle-report"
  # 引数: PR_NUM, レポート内容は stdin から受け取る
  local pr_num="${1:-}"

  if [[ -z "$pr_num" ]]; then
    pr_num=$(gh pr view --json number -q '.number' 2>/dev/null || echo "")
  fi

  if [[ -z "$pr_num" ]]; then
    skip "pr-cycle-report" "PR 番号なし — スキップ"
    return 0
  fi

  # 数値検証（引数注入防止）
  if ! [[ "$pr_num" =~ ^[0-9]+$ ]]; then
    err "pr-cycle-report" "不正な PR 番号: $pr_num"
    return 1
  fi

  # stdin からレポート本文を読み取り
  local report=""
  if [[ ! -t 0 ]]; then
    report=$(cat)
  fi

  if [[ -z "$report" ]]; then
    skip "pr-cycle-report" "レポート内容なし"
    return 0
  fi

  gh pr comment "$pr_num" --body "$report" 2>/dev/null || {
    skip "pr-cycle-report" "PR コメント投稿失敗"
    return 0
  }

  ok "pr-cycle-report" "PR #$pr_num にレポート投稿"
}

# --- pr-comment-findings: specialist findings を PR コメントとして投稿 ---
# merge-gate 実行後に呼び出し、COMBINED_FINDINGS を Markdown テーブルで永続化する。
# 引数: なし（checkpoint から自動取得）
step_pr_comment_findings() {
  record_current_step "pr-comment-findings"
  ensure_pythonpath || return 1

  local pr_num
  pr_num=$(gh pr view --json number -q '.number' 2>/dev/null || echo "")
  if [[ -z "$pr_num" ]] || ! [[ "$pr_num" =~ ^[0-9]+$ ]]; then
    skip "pr-comment-findings" "PR 番号なし — スキップ"
    return 0
  fi

  # checkpoint から findings 取得（merge-gate, ac-verify, phase-review を統合）
  # 注: --autopilot-dir は使わず、checkpoint.py のデフォルト解決（git rev-parse）に任せる。
  # merge-gate.md 等の write もデフォルト解決を使うため、同一 worktree 内で read/write が一致する。
  # 各 Worker は独自の worktree を持つため並列安全。
  local mg_findings ac_findings pr_findings combined_findings
  mg_findings=$(python3 -m twl.autopilot.checkpoint read --step merge-gate --field findings 2>/dev/null || echo "[]")
  ac_findings=$(python3 -m twl.autopilot.checkpoint read --step ac-verify --field findings 2>/dev/null || echo "[]")
  pr_findings=$(python3 -m twl.autopilot.checkpoint read --step phase-review --field findings 2>/dev/null || echo "[]")
  combined_findings=$(jq -s 'add // []' <(echo "$mg_findings") <(echo "$ac_findings") <(echo "$pr_findings") 2>/dev/null || echo "[]")

  local mg_status
  mg_status=$(python3 -m twl.autopilot.checkpoint read --step merge-gate --field status 2>/dev/null || echo "UNKNOWN")

  # findings テーブル構築
  local findings_count
  findings_count=$(echo "$combined_findings" | jq 'length' 2>/dev/null || echo "0")

  local critical_count warning_count info_count
  critical_count=$(echo "$combined_findings" | jq '[.[] | select(.severity == "CRITICAL")] | length' 2>/dev/null || echo "0")
  warning_count=$(echo "$combined_findings" | jq '[.[] | select(.severity == "WARNING")] | length' 2>/dev/null || echo "0")
  info_count=$(echo "$combined_findings" | jq '[.[] | select(.severity == "INFO")] | length' 2>/dev/null || echo "0")

  # --- findings テンプレート (#655) ---
  # severity 別にグループ化。Reviewer/File:Line/Finding/Confidence カラム。
  local body
  body="## Specialist Review Findings"$'\n\n'
  body+="**Summary**: ${critical_count} CRITICAL / ${warning_count} WARNING / ${info_count} INFO (total ${findings_count})"$'\n\n'

  if [[ "$findings_count" -gt 0 ]]; then
    local sev
    for sev in CRITICAL WARNING INFO; do
      local sev_findings sev_count
      sev_findings=$(echo "$combined_findings" | jq -c "[.[] | select(.severity == \"$sev\")]" 2>/dev/null || echo "[]")
      sev_count=$(echo "$sev_findings" | jq 'length' 2>/dev/null || echo "0")
      if [[ "$sev_count" -gt 0 ]]; then
        body+="### ${sev} (${sev_count})"$'\n\n'
        body+="| Reviewer | File:Line | Finding | Conf |"$'\n'
        body+="|----------|-----------|---------|------|"$'\n'
        body+=$(echo "$sev_findings" | jq -r '.[] | "| \(.source // "-") | \(.file // "-"):\(.line // "-") | \(.message[:150]) | \(.confidence // "-") |"' 2>/dev/null || echo "| - | - | parse error | - |")
        body+=$'\n\n'
      fi
    done
  else
    body+="全 specialist が findings なしで完了。"$'\n\n'
  fi

  body+="**Decision**: ${mg_status}"

  gh pr comment "$pr_num" --body "$body" 2>/dev/null || {
    skip "pr-comment-findings" "PR コメント投稿失敗"
    return 0
  }

  ok "pr-comment-findings" "PR #${pr_num} に findings コメント投稿 (${findings_count} findings)"
}

# --- pr-comment-fix-summary: fix サマリを PR コメントとして投稿 ---
# workflow-pr-fix 完了後に呼び出し。stdin から fix サマリを受け取る。
# 引数: なし
step_pr_comment_fix_summary() {
  record_current_step "pr-comment-fix-summary"

  local pr_num
  pr_num=$(gh pr view --json number -q '.number' 2>/dev/null || echo "")
  if [[ -z "$pr_num" ]] || ! [[ "$pr_num" =~ ^[0-9]+$ ]]; then
    skip "pr-comment-fix-summary" "PR 番号なし — スキップ"
    return 0
  fi

  # --- fix report テンプレート (#655) ---
  # stdin から JSON 配列を読み取り、Fixed/Deferred/Acknowledged に分類。
  # JSON 形式: [{"finding":"...","action":"fixed|deferred|acknowledged","detail":"...","tech_debt":true|false}]
  local raw_input=""
  if [[ ! -t 0 ]]; then
    raw_input=$(cat)
  fi

  local body="## Fix Report"$'\n\n'

  # JSON parse を試行。失敗時は raw テキストとして扱う
  if echo "$raw_input" | jq empty 2>/dev/null && [[ -n "$raw_input" ]]; then
    local fixed_items deferred_items ack_items
    fixed_items=$(echo "$raw_input" | jq -c '[.[] | select(.action == "fixed")]' 2>/dev/null || echo "[]")
    deferred_items=$(echo "$raw_input" | jq -c '[.[] | select(.action == "deferred")]' 2>/dev/null || echo "[]")
    ack_items=$(echo "$raw_input" | jq -c '[.[] | select(.action == "acknowledged")]' 2>/dev/null || echo "[]")

    local fc dc ac
    fc=$(echo "$fixed_items" | jq 'length' 2>/dev/null || echo "0")
    dc=$(echo "$deferred_items" | jq 'length' 2>/dev/null || echo "0")
    ac=$(echo "$ack_items" | jq 'length' 2>/dev/null || echo "0")

    body+="**Summary**: ${fc} fixed / ${dc} deferred / ${ac} acknowledged"$'\n\n'

    if [[ "$fc" -gt 0 ]]; then
      body+="### Fixed"$'\n\n'
      body+="| Finding | Detail |"$'\n'
      body+="|---------|--------|"$'\n'
      body+=$(echo "$fixed_items" | jq -r '.[] | "| \((.finding // "-")[:100]) | \((.detail // "-")[:100]) |"' 2>/dev/null)
      body+=$'\n\n'
    fi

    if [[ "$dc" -gt 0 ]]; then
      body+="### Deferred (tech-debt candidates)"$'\n\n'
      body+="| Finding | Reason | Tech-Debt |"$'\n'
      body+="|---------|--------|-----------|"$'\n'
      body+=$(echo "$deferred_items" | jq -r '.[] | "| \((.finding // "-")[:100]) | \((.detail // "-")[:100]) | \(if .tech_debt then "候補" else "-" end) |"' 2>/dev/null)
      body+=$'\n\n'
    fi

    if [[ "$ac" -gt 0 ]]; then
      body+="### Acknowledged (no action needed)"$'\n\n'
      body+="| Finding | Reason |"$'\n'
      body+="|---------|--------|"$'\n'
      body+=$(echo "$ack_items" | jq -r '.[] | "| \((.finding // "-")[:100]) | \((.detail // "-")[:100]) |"' 2>/dev/null)
      body+=$'\n\n'
    fi
  elif [[ -n "$raw_input" ]]; then
    # 非 JSON: raw テキストをそのまま使用（後方互換）
    body+="${raw_input}"$'\n\n'
  else
    body+="No findings required fixing."$'\n\n'
  fi

  gh pr comment "$pr_num" --body "$body" 2>/dev/null || {
    skip "pr-comment-fix-summary" "PR コメント投稿失敗"
    return 0
  }

  ok "pr-comment-fix-summary" "PR #${pr_num} に fix サマリ投稿"
}

# --- pr-comment-final: 最終判定を PR コメントとして投稿 ---
# workflow-pr-merge 完了直前に呼び出し。全 checkpoint を読み取り最終判定を投稿。
# 引数: MERGED|REJECTED|FAILED
step_pr_comment_final() {
  record_current_step "pr-comment-final"
  ensure_pythonpath || return 1

  local final_result="${1:-UNKNOWN}"
  local pr_num
  pr_num=$(gh pr view --json number -q '.number' 2>/dev/null || echo "")
  if [[ -z "$pr_num" ]] || ! [[ "$pr_num" =~ ^[0-9]+$ ]]; then
    skip "pr-comment-final" "PR 番号なし — スキップ"
    return 0
  fi

  # checkpoint.py のデフォルト解決に任せる（write と同一 worktree 内で一致させる）
  local ac_status pr_test_status e2e_status mg_status
  ac_status=$(python3 -m twl.autopilot.checkpoint read --step ac-verify --field status 2>/dev/null || echo "N/A")
  pr_test_status=$(python3 -m twl.autopilot.checkpoint read --step pr-test --field status 2>/dev/null || echo "N/A")
  e2e_status=$(python3 -m twl.autopilot.checkpoint read --step e2e-screening --field status 2>/dev/null || echo "N/A")
  mg_status=$(python3 -m twl.autopilot.checkpoint read --step merge-gate --field status 2>/dev/null || echo "N/A")

  local body="## Merge Gate Final"$'\n\n'
  body+="- ac-verify: ${ac_status}"$'\n'
  body+="- pr-test: ${pr_test_status}"$'\n'
  body+="- e2e-screening: ${e2e_status}"$'\n'
  body+="- merge-gate: ${mg_status}"$'\n\n'

  case "$final_result" in
    MERGED)  body+="**Result**: Merged via squash merge." ;;
    REJECTED) body+="**Result**: REJECTED — manual intervention required." ;;
    *)       body+="**Result**: ${final_result}" ;;
  esac

  gh pr comment "$pr_num" --body "$body" 2>/dev/null || {
    skip "pr-comment-final" "PR コメント投稿失敗"
    return 0
  }

  ok "pr-comment-final" "PR #${pr_num} に最終判定投稿 (${final_result})"
}

# --- auto-merge: スカッシュマージ実行（scripts/auto-merge.sh ラッパー） ---
step_auto_merge() {
  record_current_step "auto-merge"
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local auto_merge_script="$script_dir/auto-merge.sh"
  if [[ ! -x "$auto_merge_script" ]]; then
    err "auto-merge" "scripts/auto-merge.sh が見つからないか実行不可"
    return 1
  fi
  if "$auto_merge_script" "$@"; then
    ok "auto-merge" "auto-merge.sh 完了"
    # #897-C: auto-merge 成功時に audit snapshot を自動取得
    # .autopilot/ 配下の checkpoints/issues/trace を audit dir に永続化し、
    # 後続の worktree 削除で消失する中間成果物を保全する。
    _audit_snapshot_autopilot
  else
    local rc=$?
    err "auto-merge" "auto-merge.sh 失敗 (exit=$rc)"
    return $rc
  fi
}

# #897-C: audit snapshot hook
# auto-merge 完了時に .autopilot/ を audit dir 配下にコピー
# audit が非 active な場合は silent no-op（regression 防止）
_audit_snapshot_autopilot() {
  local autopilot_dir issue_num label
  autopilot_dir="$(resolve_autopilot_dir 2>/dev/null || echo "")"
  issue_num="$(resolve_issue_num 2>/dev/null || echo "")"
  if [[ -z "$autopilot_dir" ]] || [[ ! -d "$autopilot_dir" ]]; then
    return 0
  fi
  if [[ -z "$issue_num" ]]; then
    label="autopilot-merged"
  else
    label="issue-${issue_num}"
  fi
  if python3 -m twl.autopilot.audit snapshot --source-dir "$autopilot_dir" --label "$label" >/dev/null 2>&1; then
    echo "[chain-runner] audit snapshot: label=$label (source=$autopilot_dir)"
  fi
}

# --- run-chain-generate: feature branch の twl バイナリ経由で chain generate を実行 ---
# Issue #379: meta_generate.py 変更時に stale キャッシュで実行されるのを防ぐ。
# インストール済み twl ではなく <repo_root>/cli/twl/twl を直接呼び出すことで、
# twl wrapper が PYTHONPATH を feature branch の cli/twl/src に設定する。
#
# 使い方: run_chain_generate [--write] [--check] [--all] [chain_name]
run_chain_generate() {
  local root
  root="$(resolve_project_root)"
  local local_twl="$root/cli/twl/twl"
  if [[ -x "$local_twl" ]]; then
    "$local_twl" chain generate "$@"
  else
    # フォールバック: インストール済み twl を使用（PYTHONPATH が設定されていれば正常動作）
    twl chain generate "$@"
  fi
}

# --- check: 準備確認 ---
step_check() {
  record_current_step "check"
  local root
  root="$(resolve_project_root)"
  local has_fail=false

  # テスト（monorepo 対応: $root/tests/, $root/*/tests/, $root/*/*/tests/ を走査）
  local test_found=false
  local _test_dir
  for _test_dir in "$root/tests" "$root"/*/tests "$root"/*/*/tests; do
    if find "$_test_dir" \( -name "*.sh" -o -name "*.bats" -o -name "*.test.*" -o -name "*.R" -o -name "*.py" \) -print -quit 2>/dev/null | grep -q .; then
      test_found=true
      break
    fi
  done
  if $test_found; then
    echo "Tests: PASS"
  else
    echo "Tests: FAIL (テストファイルなし)"
    has_fail=true
  fi

  # CI/CD
  if ls "$root/.github/workflows/"*.yml >/dev/null 2>&1; then
    echo "CI/CD: PASS"
  else
    echo "CI/CD: WARN (ワークフローなし)"
  fi

  # 変更ファイル
  local changes
  changes=$(cd "$root" && git status --porcelain | wc -l)
  echo "Changes: $changes files"

  if $has_fail; then
    skip "check" "FAIL 項目あり"
    return 1
  else
    ok "check" "準備完了"
  fi
}

# =====================================================================
# ディスパッチャ
# =====================================================================

main() {
  # --trace <path> フラグ前処理（Phase 3 / Layer 1 経験的監査）
  # 環境変数 TWL_CHAIN_TRACE と等価。フラグは複数回指定不可。
  while [[ "${1:-}" == --trace || "${1:-}" == --trace=* ]]; do
    if [[ "$1" == --trace=* ]]; then
      TWL_CHAIN_TRACE="${1#--trace=}"
      shift
    else
      if [[ -z "${2:-}" ]]; then
        echo "ERROR: --trace にはパスを指定してください" >&2
        exit 1
      fi
      TWL_CHAIN_TRACE="$2"
      shift 2
    fi
    export TWL_CHAIN_TRACE
  done

  local step="${1:-}"
  if [[ -z "$step" ]]; then
    echo "Usage: chain-runner.sh [--trace <path>] <step-name> [args...]" >&2
    echo "Steps: init, worktree-create, board-status-update, project-board-status-update, board-archive," >&2
    echo "       ac-extract, arch-ref, next-step, ts-preflight, pr-test, ac-verify," >&2
    echo "       all-pass-check, pr-cycle-report, auto-merge, check, autopilot-detect," >&2
    echo "       record-current-step <step>" >&2
    exit 1
  fi
  shift

  trace_event "$step" "start"

  local _main_rc=0
  set +e
  case "$step" in
    init)                step_init "$@" ;;
    worktree-create)     step_worktree_create "$@" ;;
    board-status-update) step_board_status_update "$@" ;;
    project-board-status-update) step_board_status_update "$@" ;;
    board-archive)       step_board_archive "$@" ;;
    ac-extract)          step_ac_extract "$@" ;;
    arch-ref)            step_arch_ref "$@" ;;
    test-scaffold)       record_current_step "test-scaffold"; ok "test-scaffold" "LLM スキル実行（chain-runner はステップ記録のみ）" ;;
    next-step)           step_next_step "$@" ;;
    dispatch-info)       step_dispatch_info "$@" ;;
    llm-delegate)        step_llm_delegate "$@" ;;
    llm-complete)        step_llm_complete "$@" ;;
    chain-status)        step_chain_status "$@" ;;
    prompt-compliance)   step_prompt_compliance "$@" ;;
    ts-preflight)        step_ts_preflight "$@" ;;
    phase-review)        record_current_step "phase-review"; ok "phase-review" "LLM スキル実行（chain-runner はステップ記録のみ）" ;;
    scope-judge)         record_current_step "scope-judge";  ok "scope-judge"  "LLM スキル実行（chain-runner はステップ記録のみ）" ;;
    record-current-step) [[ -z "${1:-}" ]] && { echo "ERROR: record-current-step requires step name" >&2; exit 1; }; record_current_step "$1"; ok "record-current-step" "current_step=$1 を記録" ;;
    pr-test)             step_pr_test "$@" ;;
    ac-verify)           step_ac_verify "$@" ;;
    all-pass-check)      step_all_pass_check "$@" ;;
    record-pr)           step_record_pr "$@" ;;
    pr-cycle-report)     step_pr_cycle_report "$@" ;;
    auto-merge)          step_auto_merge "$@" ;;
    pr-comment-findings) step_pr_comment_findings "$@" ;;
    pr-comment-fix-summary) step_pr_comment_fix_summary "$@" ;;
    pr-comment-final)    step_pr_comment_final "$@" ;;
    check)               step_check "$@" ;;
    autopilot-detect)    step_autopilot_detect "$@" ;;
    resolve-issue-num)   resolve_issue_num ;;
    resolve-project-root) resolve_project_root ;;
    *)
      echo "ERROR: 未知のステップ: $step" >&2
      echo "利用可能: init, worktree-create, board-status-update, project-board-status-update," >&2
      echo "         board-archive, ac-extract, arch-ref, next-step, prompt-compliance, ts-preflight," >&2
      echo "         phase-review, scope-judge, record-current-step <step>, pr-test, ac-verify, all-pass-check," >&2
      echo "         pr-cycle-report, auto-merge, pr-comment-findings, pr-comment-fix-summary," >&2
      echo "         pr-comment-final, check, autopilot-detect, resolve-issue-num," >&2
      echo "         dispatch-info, llm-delegate, llm-complete, chain-status," >&2
      echo "         resolve-project-root" >&2
      exit 1
      ;;
  esac
  _main_rc=$?
  set -e

  trace_event "$step" "end" "$_main_rc"

  # Worker terminal status 検証ガード (Issue #131)
  # chain main 終端（=all-pass-check ステップ完了後）で issue-{N}.json の
  # status が terminal 集合 {merge-ready, done, failed, conflict} に含まれている
  # ことを検証。AUTOPILOT_DIR 設定時のみ作動し、非 autopilot フローには影響しない。
  if [[ "$step" == "all-pass-check" && -n "${AUTOPILOT_DIR:-}" ]]; then
    local _guard_issue_num
    _guard_issue_num="$(resolve_issue_num 2>/dev/null || echo "")"
    if [[ -n "$_guard_issue_num" ]]; then
      bash "${SCRIPT_DIR}/worker-terminal-guard.sh" "$_guard_issue_num" || _main_rc=$?
    fi
  fi

  return $_main_rc
}

main "$@"
