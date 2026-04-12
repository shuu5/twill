#!/usr/bin/env bash
# issue-lifecycle-orchestrator.sh — co-issue v2 Worker 側バッチ orchestrator
#
# per-issue dir 配下の各 subdir に対して /twl:workflow-issue-lifecycle を
# tmux cld セッションで並列起動する。
#
# spec-review-orchestrator.sh のコードパターンを流用:
#   - tmux new-window + cld セッション並列起動
#   - MAX_PARALLEL バッチ制御
#   - ポーリング完了検知（OUT/report.json の存在確認）
#   - flock による window 名衝突回避
#   - || continue による失敗局所化
#   - Resume 対応（done スキップ / failed リセット）
#
# Usage:
#   bash issue-lifecycle-orchestrator.sh --per-issue-dir <abs-path>
#
# Environment:
#   MAX_PARALLEL   バッチあたり最大並列セッション数（デフォルト: 3）
#   POLL_INTERVAL  ポーリング間隔（秒、デフォルト: 10）
#   MAX_POLL       最大ポーリング回数（デフォルト: 360）

set -euo pipefail

SCRIPTS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# lockfile クリーンアップ（spawn_session 内で作成した /tmp/.coi-window-*.lock）
trap 'rm -f /tmp/.coi-window-*.lock 2>/dev/null || true' EXIT

MAX_PARALLEL="${MAX_PARALLEL:-3}"
if ! [[ "$MAX_PARALLEL" =~ ^[1-9][0-9]*$ ]]; then
  MAX_PARALLEL=3
fi
POLL_INTERVAL="${POLL_INTERVAL:-10}"
if ! [[ "$POLL_INTERVAL" =~ ^[1-9][0-9]*$ ]]; then
  POLL_INTERVAL=10
fi
MAX_POLL="${MAX_POLL:-360}"
if ! [[ "$MAX_POLL" =~ ^[1-9][0-9]*$ ]]; then
  MAX_POLL=360
fi

# --- 使い方 ---
usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

  --per-issue-dir DIR  per-issue ディレクトリの絶対パス（必須）
                       .controller-issue/<sid>/per-issue/ に相当
  -h, --help           このヘルプを表示

Environment:
  MAX_PARALLEL   バッチあたり最大並列セッション数（デフォルト: 3）
  POLL_INTERVAL  ポーリング間隔（秒、デフォルト: 10）
  MAX_POLL       最大ポーリング回数（デフォルト: 360）
EOF
}

# --- 引数パーサー ---
PER_ISSUE_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --per-issue-dir) PER_ISSUE_DIR="$2"; shift 2 ;;
    -h|--help)       usage; exit 0 ;;
    *) echo "Error: 不明なオプション: $1" >&2; exit 1 ;;
  esac
done

# --- バリデーション ---
if [[ -z "$PER_ISSUE_DIR" ]]; then
  echo "Error: --per-issue-dir は必須です" >&2
  usage
  exit 1
fi

if [[ "$PER_ISSUE_DIR" != /* ]]; then
  echo "Error: --per-issue-dir は絶対パスで指定してください: $PER_ISSUE_DIR" >&2
  exit 1
fi

if [[ "$PER_ISSUE_DIR" =~ /\.\./ || "$PER_ISSUE_DIR" =~ /\.\.$ ]]; then
  echo "Error: --per-issue-dir にパストラバーサルは使用できません: $PER_ISSUE_DIR" >&2
  exit 1
fi

if [[ ! -d "$PER_ISSUE_DIR" ]]; then
  echo "Error: --per-issue-dir が存在しません: $PER_ISSUE_DIR" >&2
  exit 1
fi

# --- cld 存在確認 ---
CLD_PATH=$(command -v cld 2>/dev/null || true)
if [[ -z "$CLD_PATH" ]]; then
  echo "Error: cld が見つかりません" >&2
  exit 1
fi

# --- per-issue subdir 収集（IN/draft.md が存在するディレクトリ） ---
mapfile -t SUBDIRS < <(
  find "$PER_ISSUE_DIR" -mindepth 1 -maxdepth 1 -type d | sort | while read -r d; do
    if [[ -f "$d/IN/draft.md" ]]; then
      echo "$d"
    fi
  done
)
TOTAL="${#SUBDIRS[@]}"

if [[ "$TOTAL" -eq 0 ]]; then
  echo "Error: --per-issue-dir に IN/draft.md を含むサブディレクトリが見つかりません: $PER_ISSUE_DIR" >&2
  exit 1
fi

echo "[issue-lifecycle-orchestrator] サブディレクトリ数: ${TOTAL}, MAX_PARALLEL: ${MAX_PARALLEL}"

# ADR-017 IM-7: N=1 不変量は各 Worker（workflow-issue-lifecycle）が個別に
# spec-review-session-init.sh 1 を呼び出すことで保証する。
# orchestrator はセッション初期化を行わない（state file 競合防止）。

# =============================================================================
# sid 抽出ユーティリティ
# =============================================================================

# per-issue-dir のパスから sid8（先頭8文字）を抽出
extract_sid8() {
  local dir="$1"
  # .controller-issue/<sid>/per-issue パターンから抽出を試みる
  local sid
  sid="$(basename "$(dirname "$dir")" 2>/dev/null || echo "")"
  if [[ -z "$sid" || "$sid" == "." ]]; then
    # フォールバック: パス全体のハッシュ
    sid="$(printf '%s' "$dir" | md5sum | cut -c1-8)"
  fi
  # tmux 特殊文字（:, %, ., !）を除去してウィンドウ名を安全にする
  local clean_sid="${sid:0:8}"
  clean_sid="${clean_sid//[^a-zA-Z0-9_-]/x}"
  printf '%s' "$clean_sid"
}

# サブディレクトリからインデックスを取得
index_of_subdir() {
  local target="$1"
  local i=0
  for d in "${SUBDIRS[@]}"; do
    if [[ "$d" == "$target" ]]; then
      echo "$i"
      return
    fi
    i=$((i + 1))
  done
  echo "0"
}

SID8="$(extract_sid8 "$PER_ISSUE_DIR")"

# =============================================================================
# window 名生成
# =============================================================================

window_name_for_subdir() {
  local subdir="$1"
  local idx
  idx="$(index_of_subdir "$subdir")"
  echo "coi-${SID8}-${idx}"
}

# =============================================================================
# セッション spawn
# =============================================================================

spawn_session() {
  local subdir="$1"
  local window_name
  window_name="$(window_name_for_subdir "$subdir")"
  local report_file="${subdir}/OUT/report.json"
  local state_file="${subdir}/STATE"

  # Resume: OUT/report.json が存在する（done 済み）→ スキップ
  if [[ -f "$report_file" ]]; then
    echo "[issue-lifecycle-orchestrator] ${subdir##*/}: report.json 既存 — スキップ" >&2
    return 0
  fi

  # Resume: STATE が "failed" → リセット
  if [[ -f "$state_file" ]] && grep -qF "failed" "$state_file" 2>/dev/null; then
    echo "[issue-lifecycle-orchestrator] ${subdir##*/}: STATE=failed — リセットして再実行" >&2
    printf 'running\n' > "$state_file"
  fi

  # flock で window 名衝突回避
  local lockfile="/tmp/.coi-window-${window_name}.lock"
  exec {lockfd}>"$lockfile"
  if ! flock -n "$lockfd"; then
    echo "[issue-lifecycle-orchestrator] ${subdir##*/}: window ロック取得失敗 — スキップ" >&2
    exec {lockfd}>&-
    return 0
  fi

  # 既存ウィンドウがあれば kill
  tmux kill-window -t "$window_name" 2>/dev/null || true

  mkdir -p "${subdir}/OUT"

  # プロンプトをテンポラリファイルに書き出す
  local prompt_file
  prompt_file="$(mktemp /tmp/.coi-prompt-XXXXXX.txt)"
  printf '%s\n' "/twl:workflow-issue-lifecycle $(printf '%q' "$subdir")" > "$prompt_file"

  local SESSION_SCRIPTS
  SESSION_SCRIPTS="${SCRIPTS_ROOT}/../../session/scripts"

  echo "[issue-lifecycle-orchestrator] ${subdir##*/}: spawn (window=${window_name})" >&2

  # flock 解放（cld-spawn 前）
  exec {lockfd}>&-

  # cld-spawn: 対話モードで起動（one-shot モード stdout 問題を回避 — #541）
  "${SESSION_SCRIPTS}/cld-spawn" --cd "$(pwd)" --window-name "${window_name}" || {
    rm -f "$prompt_file" 2>/dev/null || true
    echo "[issue-lifecycle-orchestrator] ${subdir##*/}: cld-spawn 失敗" >&2
    return 1
  }

  tmux set-option -t "$window_name" remain-on-exit on 2>/dev/null || true

  # inject-file: プロンプトをセッションに安全に送達（wait-ready 後）
  "${SESSION_SCRIPTS}/session-comm.sh" inject-file "${window_name}" "${prompt_file}" --wait 60 || {
    rm -f "$prompt_file" 2>/dev/null || true
    tmux kill-window -t "${window_name}" 2>/dev/null || true
    echo "[issue-lifecycle-orchestrator] ${subdir##*/}: inject-file 失敗" >&2
    return 1
  }

  rm -f "$prompt_file" 2>/dev/null || true
}

# =============================================================================
# ポーリング（バッチ完了待ち）
# =============================================================================

wait_for_batch() {
  local -a batch_subdirs=("$@")
  local poll_count=0

  while true; do
    local all_done=true

    for subdir in "${batch_subdirs[@]}"; do
      local report_file="${subdir}/OUT/report.json"

      if [[ ! -f "$report_file" ]]; then
        local window_name
        window_name="$(window_name_for_subdir "$subdir")"
        if ! tmux list-windows -F '#{window_name}' 2>/dev/null | grep -qxF "$window_name"; then
          echo "[issue-lifecycle-orchestrator] ${subdir##*/}: ウィンドウ消失・report.json なし — タイムアウト扱い" >&2
          mkdir -p "${subdir}/OUT"
          printf '{"status":"timeout","error":"window_lost"}\n' > "$report_file"
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
      echo "[issue-lifecycle-orchestrator] バッチタイムアウト（${MAX_POLL}回×${POLL_INTERVAL}秒）" >&2
      for subdir in "${batch_subdirs[@]}"; do
        local report_file="${subdir}/OUT/report.json"
        if [[ ! -f "$report_file" ]]; then
          mkdir -p "${subdir}/OUT"
          printf '{"status":"timeout","error":"poll_limit_reached"}\n' > "$report_file"
          local window_name
          window_name="$(window_name_for_subdir "$subdir")"
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

echo "[issue-lifecycle-orchestrator] 開始: ${TOTAL} subdirs を MAX_PARALLEL=${MAX_PARALLEL} でバッチ処理"

COMPLETED=0
BATCH_START=0
OVERALL_FAILED=0

while [[ "$BATCH_START" -lt "$TOTAL" ]]; do
  local_batch=()
  for (( i=BATCH_START; i<TOTAL && i<BATCH_START+MAX_PARALLEL; i++ )); do
    local_batch+=("${SUBDIRS[$i]}")
  done

  echo "[issue-lifecycle-orchestrator] バッチ開始: インデックス ${BATCH_START}~$((BATCH_START+${#local_batch[@]}-1)) (${#local_batch[@]} subdirs)"

  for subdir in "${local_batch[@]}"; do
    spawn_session "$subdir" || continue
  done

  wait_for_batch "${local_batch[@]}"

  COMPLETED=$((COMPLETED + ${#local_batch[@]}))
  BATCH_START=$((BATCH_START + MAX_PARALLEL))

  for subdir in "${local_batch[@]}"; do
    window_name="$(window_name_for_subdir "$subdir")"
    tmux kill-window -t "$window_name" 2>/dev/null || true
  done

  echo "[issue-lifecycle-orchestrator] バッチ完了: ${COMPLETED}/${TOTAL} subdirs 処理済み"
done

# =============================================================================
# 結果サマリー
# =============================================================================

echo ""
echo "✓ issue-lifecycle-orchestrator 完了: ${TOTAL} subdirs"
echo "  per-issue-dir: ${PER_ISSUE_DIR}"

SUCCESS=0
FAILED=0

for subdir in "${SUBDIRS[@]}"; do
  report_file="${subdir}/OUT/report.json"
  subdir_name="${subdir##*/}"
  if [[ -f "$report_file" ]]; then
    status="$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('status','unknown'))" "$report_file" 2>/dev/null || echo "parse_error")"
    if [[ "$status" == "done" ]]; then
      SUCCESS=$((SUCCESS + 1))
      echo "  ✓  ${subdir_name}: done"
    else
      FAILED=$((FAILED + 1))
      OVERALL_FAILED=$((OVERALL_FAILED + 1))
      echo "  ⚠️  ${subdir_name}: ${status}"
    fi
  else
    FAILED=$((FAILED + 1))
    OVERALL_FAILED=$((OVERALL_FAILED + 1))
    echo "  ✗  ${subdir_name}: report.json なし"
  fi
done

echo ""
echo "  成功: ${SUCCESS}/${TOTAL}, 失敗: ${FAILED}/${TOTAL}"

if [[ "$OVERALL_FAILED" -gt 0 ]]; then
  exit 1
fi
exit 0
