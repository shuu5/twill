#!/usr/bin/env bash
# spec-review-orchestrator.sh — Bash ループで N Issue の spec-review を並列実行
#
# LLM ループを排除し、各 Issue に独立した tmux cld セッションを Bash for ループで spawn する。
# autopilot-orchestrator.sh の「tmux new-window + ポーリング」パターンを流用。
#
# Usage:
#   bash spec-review-orchestrator.sh --issues-dir DIR --output-dir DIR
#
# Environment:
#   MAX_PARALLEL  バッチあたり最大並列セッション数（デフォルト: 3）
#   POLL_INTERVAL ポーリング間隔（秒、デフォルト: 10）

set -euo pipefail

SCRIPTS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MAX_PARALLEL="${MAX_PARALLEL:-3}"
if ! [[ "$MAX_PARALLEL" =~ ^[1-9][0-9]*$ ]]; then
  MAX_PARALLEL=3
fi
POLL_INTERVAL="${POLL_INTERVAL:-10}"
MAX_POLL="${MAX_POLL:-360}"

# --- 使い方 ---
usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

  --issues-dir DIR    入力: issue-*.json ファイルが存在するディレクトリ（必須）
  --output-dir DIR    出力: issue-*-result.txt を書き出すディレクトリ（必須）
  -h, --help          このヘルプを表示

Environment:
  MAX_PARALLEL   バッチあたり最大並列セッション数（デフォルト: 3）
  POLL_INTERVAL  ポーリング間隔（秒、デフォルト: 10）
EOF
}

# --- 引数パーサー ---
ISSUES_DIR=""
OUTPUT_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --issues-dir) ISSUES_DIR="$2"; shift 2 ;;
    --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
    -h|--help)    usage; exit 0 ;;
    *) echo "Error: 不明なオプション: $1" >&2; exit 1 ;;
  esac
done

# --- バリデーション ---
if [[ -z "$ISSUES_DIR" || -z "$OUTPUT_DIR" ]]; then
  echo "Error: --issues-dir と --output-dir は必須です" >&2
  usage
  exit 1
fi

for _dir in ISSUES_DIR OUTPUT_DIR; do
  _val="${!_dir}"
  if [[ "$_val" != /* ]]; then
    echo "Error: --$(echo "$_dir" | tr '[:upper:]' '[:lower:]' | tr '_' '-') は絶対パスで指定してください: $_val" >&2
    exit 1
  fi
  if [[ "$_val" =~ /\.\./ || "$_val" =~ /\.\.$ ]]; then
    echo "Error: --$(echo "$_dir" | tr '[:upper:]' '[:lower:]' | tr '_' '-') にパストラバーサルは使用できません: $_val" >&2
    exit 1
  fi
done

if [[ ! -d "$ISSUES_DIR" ]]; then
  echo "Error: --issues-dir が存在しません: $ISSUES_DIR" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

# --- cld 存在確認 ---
CLD_PATH=$(command -v cld 2>/dev/null || true)
if [[ -z "$CLD_PATH" ]]; then
  echo "Error: cld が見つかりません" >&2
  exit 1
fi

# --- Issue JSON ファイル収集 ---
mapfile -t ISSUE_FILES < <(ls -1 "${ISSUES_DIR}"/issue-*.json 2>/dev/null | sort)
TOTAL="${#ISSUE_FILES[@]}"

if [[ "$TOTAL" -eq 0 ]]; then
  echo "Error: --issues-dir に issue-*.json ファイルが見つかりません: $ISSUES_DIR" >&2
  exit 1
fi

echo "[spec-review-orchestrator] Issue 数: ${TOTAL}, MAX_PARALLEL: ${MAX_PARALLEL}"

# --- セッション初期化 ---
bash "${SCRIPTS_ROOT}/spec-review-session-init.sh" "$TOTAL"

# =============================================================================
# tmux ウィンドウ名ユーティリティ
# =============================================================================

window_name_for_file() {
  local file="$1"
  local basename
  basename="$(basename "$file" .json)"
  echo "sr-${basename}"
}

issue_num_from_file() {
  local file="$1"
  basename "$file" .json | grep -oP '\d+' | head -1
}

# =============================================================================
# セッション spawn
# =============================================================================

spawn_session() {
  local issue_file="$1"
  local issue_num
  issue_num="$(issue_num_from_file "$issue_file")"
  local window_name
  window_name="$(window_name_for_file "$issue_file")"
  local result_file="${OUTPUT_DIR}/issue-${issue_num}-result.txt"

  # 既に結果ファイルが存在する場合はスキップ
  if [[ -f "$result_file" ]]; then
    echo "[spec-review-orchestrator] Issue #${issue_num}: 結果ファイル既存 — スキップ" >&2
    return 0
  fi

  # 既存ウィンドウがあれば kill
  tmux kill-window -t "$window_name" 2>/dev/null || true

  # Issue データ読み込み（環境変数経由で安全に渡す — インライン展開によるインジェクション防止）
  local issue_body scope_files related_issues is_quick
  issue_body="$(ISSUE_FILE="$issue_file" python3 -c "
import json, os
d = json.load(open(os.environ['ISSUE_FILE']))
print(d.get('body', ''))
" 2>/dev/null || echo "")"
  scope_files="$(ISSUE_FILE="$issue_file" python3 -c "
import json, os
d = json.load(open(os.environ['ISSUE_FILE']))
print('\n'.join(d.get('scope_files', [])))
" 2>/dev/null || echo "")"
  related_issues="$(ISSUE_FILE="$issue_file" python3 -c "
import json, os
d = json.load(open(os.environ['ISSUE_FILE']))
print('\n'.join(str(x) for x in d.get('related_issues', [])))
" 2>/dev/null || echo "")"
  is_quick="$(ISSUE_FILE="$issue_file" python3 -c "
import json, os
d = json.load(open(os.environ['ISSUE_FILE']))
print(str(d.get('is_quick_candidate', False)).lower())
" 2>/dev/null || echo "false")"

  # プロンプトをテンポラリファイルに書き出す
  # - tmux に文字列として渡す際の POSIX sh 非互換問題を回避
  # - printf '%q' の bash 固有エスケープ ($'...') が sh で誤動作するリスクを排除
  local prompt_file
  prompt_file="$(mktemp /tmp/.spec-review-prompt-XXXXXX.txt)"
  # ISSUE_FILE 書き込み（変数値をそのまま書き出し、シェル展開なし）
  printf '%s\n' "Issue #${issue_num} の spec-review を実行してください。" > "$prompt_file"
  printf '\n' >> "$prompt_file"
  printf '%s\n' "入力データ:" >> "$prompt_file"
  printf '- issue_body: %s\n' "$issue_body" >> "$prompt_file"
  printf '- scope_files: %s\n' "$scope_files" >> "$prompt_file"
  printf '- related_issues: %s\n' "$related_issues" >> "$prompt_file"
  printf '- is_quick_candidate: %s\n' "$is_quick" >> "$prompt_file"
  printf '\n' >> "$prompt_file"
  printf '%s\n' "/twl:issue-spec-review を実行し、全 specialist の結果が揃ったら以下のファイルに結果を書き出して完了してください:" >> "$prompt_file"
  printf '%s\n' "$result_file" >> "$prompt_file"
  printf '\n' >> "$prompt_file"
  printf '%s\n' "書き出す内容: specialist_results の全文（JSON または Markdown 形式）" >> "$prompt_file"

  # ラッパースクリプトを作成して tmux に渡す
  # - printf '%q' によるエスケープをファイルへの書き出しに使用（tmux 引数には使用しない）
  # - tmux には "bash /path/to/wrapper.sh" のみ渡す（POSIX sh 非互換回避、CRITICAL #3 対応）
  local wrapper_file
  wrapper_file="$(mktemp /tmp/.spec-review-wrapper-XXXXXX.sh)"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'set -euo pipefail\n'
    printf 'PROMPT_CONTENT="$(cat %q)"\n' "$prompt_file"
    printf '%q --model sonnet "$PROMPT_CONTENT" > %q 2>&1\n' "$CLD_PATH" "$result_file"
    printf 'rm -f %q %q\n' "$prompt_file" "$wrapper_file"
  } > "$wrapper_file"
  chmod +x "$wrapper_file"

  echo "[spec-review-orchestrator] Issue #${issue_num}: spawn (window=${wrapper_file##*/}, name=${window_name})" >&2
  tmux new-window -d -n "$window_name" "bash $(printf '%q' "$wrapper_file")"

  # remain-on-exit: ポーリング後の確認に使用
  tmux set-option -t "$window_name" remain-on-exit on 2>/dev/null || true
}

# =============================================================================
# ポーリング（バッチ完了待ち）
# =============================================================================

wait_for_batch() {
  local -a batch_files=("$@")
  local poll_count=0

  while true; do
    local all_done=true

    for issue_file in "${batch_files[@]}"; do
      local issue_num
      issue_num="$(issue_num_from_file "$issue_file")"
      local result_file="${OUTPUT_DIR}/issue-${issue_num}-result.txt"

      if [[ ! -f "$result_file" ]]; then
        # ウィンドウがまだ存在するか確認
        local window_name
        window_name="$(window_name_for_file "$issue_file")"
        if ! tmux list-windows -F '#{window_name}' 2>/dev/null | grep -qF "$window_name"; then
          # ウィンドウが消えているが結果ファイルもない → タイムアウト扱い
          echo "[spec-review-orchestrator] Issue #${issue_num}: ウィンドウ消失・結果なし — タイムアウト扱い" >&2
          echo "TIMEOUT: Issue #${issue_num} — ウィンドウ消失" > "$result_file"
        else
          all_done=false
        fi
      fi
    done

    if [[ "$all_done" == "true" ]]; then
      break
    fi

    poll_count=$((poll_count + 1))
    if [[ "$poll_count" -ge "$MAX_POLL" ]]; then
      echo "[spec-review-orchestrator] バッチタイムアウト（${MAX_POLL}回×${POLL_INTERVAL}秒）" >&2
      # 未完了分は強制タイムアウトファイル生成
      for issue_file in "${batch_files[@]}"; do
        local issue_num
        issue_num="$(issue_num_from_file "$issue_file")"
        local result_file="${OUTPUT_DIR}/issue-${issue_num}-result.txt"
        if [[ ! -f "$result_file" ]]; then
          echo "TIMEOUT: Issue #${issue_num} — ポーリング上限到達" > "$result_file"
          local window_name
          window_name="$(window_name_for_file "$issue_file")"
          tmux kill-window -t "$window_name" 2>/dev/null || true
        fi
      done
      break
    fi

    sleep "$POLL_INTERVAL"
  done
}

# =============================================================================
# バッチ実行ループ
# =============================================================================

echo "[spec-review-orchestrator] 開始: ${TOTAL} Issues を MAX_PARALLEL=${MAX_PARALLEL} でバッチ処理"

COMPLETED=0
BATCH_START=0

while [[ "$BATCH_START" -lt "$TOTAL" ]]; do
  # バッチを切り出す
  local_batch=()
  for (( i=BATCH_START; i<TOTAL && i<BATCH_START+MAX_PARALLEL; i++ )); do
    local_batch+=("${ISSUE_FILES[$i]}")
  done

  echo "[spec-review-orchestrator] バッチ開始: インデックス ${BATCH_START}~$((BATCH_START+${#local_batch[@]}-1)) (${#local_batch[@]} Issues)"

  # バッチ内の全セッションを spawn
  for issue_file in "${local_batch[@]}"; do
    spawn_session "$issue_file"
  done

  # バッチ完了を待機
  wait_for_batch "${local_batch[@]}"

  COMPLETED=$((COMPLETED + ${#local_batch[@]}))
  BATCH_START=$((BATCH_START + MAX_PARALLEL))

  # バッチ間クリーンアップ
  for issue_file in "${local_batch[@]}"; do
    local window_name
    window_name="$(window_name_for_file "$issue_file")"
    tmux kill-window -t "$window_name" 2>/dev/null || true
  done

  echo "[spec-review-orchestrator] バッチ完了: ${COMPLETED}/${TOTAL} Issues 処理済み"
done

# =============================================================================
# 結果サマリー
# =============================================================================

echo ""
echo "✓ spec-review-orchestrator 完了: ${TOTAL} Issues"
echo "  出力ディレクトリ: ${OUTPUT_DIR}"

SUCCESS=0
FAILED=0
for issue_file in "${ISSUE_FILES[@]}"; do
  issue_num="$(issue_num_from_file "$issue_file")"
  result_file="${OUTPUT_DIR}/issue-${issue_num}-result.txt"
  if [[ -f "$result_file" ]]; then
    if grep -q "^TIMEOUT:" "$result_file" 2>/dev/null; then
      FAILED=$((FAILED + 1))
      echo "  ⚠️  Issue #${issue_num}: タイムアウト"
    else
      SUCCESS=$((SUCCESS + 1))
      echo "  ✓  Issue #${issue_num}: 完了"
    fi
  else
    FAILED=$((FAILED + 1))
    echo "  ✗  Issue #${issue_num}: 結果ファイルなし"
  fi
done

echo ""
echo "  成功: ${SUCCESS}/${TOTAL}, 失敗: ${FAILED}/${TOTAL}"

if [[ "$FAILED" -gt 0 ]]; then
  exit 1
fi
exit 0
