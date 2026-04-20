#!/usr/bin/env bash
# specialist-audit.sh - Worker JSONL から specialist completeness を独立検証
#
# 期待集合は pr-review-manifest.sh 経由で動的生成。
# LLM 自己申告（SPAWNED_FILE）に依存しない独立検証パス。
#
# Usage:
#   specialist-audit.sh --issue <N> [options]
#   specialist-audit.sh --jsonl <path> [options]
#
# Options:
#   --issue <N>             Issue 番号（JSONL パスを自動解決）
#   --jsonl <path>          JSONL パスを直接指定（--issue と排他）
#   --mode <phase>          pr-review-manifest.sh に渡すモード (default: merge-gate)
#   --manifest-file <path>  既存 MANIFEST_FILE を再利用（pr-review-manifest.sh 二重呼び出しを回避）
#   --quick                 FAIL を WARN に降格（quick ラベル用）
#   --warn-only             常に exit 0（bootstrapping 期間用）
#   --json                  JSON 形式で出力（default）
#   --summary               サマリのみ出力
#
# 環境変数:
#   SPECIALIST_AUDIT_MODE=warn|strict  (default: warn)
#   SKIP_SPECIALIST_AUDIT=1            完全スキップ
#
# Exit codes:
#   0 = PASS / WARN
#   1 = FAIL (missing 非空 かつ strict モード かつ --quick なし かつ --warn-only なし)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- デフォルト値 ---
ISSUE_NUM=""
JSONL_PATH=""
MODE="merge-gate"
MANIFEST_FILE_ARG=""
QUICK=false
WARN_ONLY=false
OUTPUT_FORMAT="json"
AUDIT_MODE="${SPECIALIST_AUDIT_MODE:-warn}"

# --- 引数パース ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --issue)
      ISSUE_NUM="$2"; shift 2 ;;
    --jsonl)
      JSONL_PATH="$2"; shift 2 ;;
    --mode)
      MODE="$2"; shift 2 ;;
    --manifest-file)
      MANIFEST_FILE_ARG="$2"; shift 2 ;;
    --quick)
      QUICK=true; shift ;;
    --warn-only)
      WARN_ONLY=true; shift ;;
    --json)
      OUTPUT_FORMAT="json"; shift ;;
    --summary)
      OUTPUT_FORMAT="summary"; shift ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1 ;;
  esac
done

# --- SKIP_SPECIALIST_AUDIT チェック ---
if [[ "${SKIP_SPECIALIST_AUDIT:-}" == "1" ]]; then
  echo "WARNING: SKIP_SPECIALIST_AUDIT=1 のため specialist-audit をスキップします" >&2
  mkdir -p ".audit/skip"
  printf '{"status":"SKIP","reason":"SKIP_SPECIALIST_AUDIT=1"}\n' \
    >> ".audit/skip/specialist-audit-skip-$(date +%s 2>/dev/null || echo 0)-$$.json"
  printf '{"status":"SKIP","reason":"SKIP_SPECIALIST_AUDIT=1"}\n'
  exit 0
fi

# --- --issue と --jsonl の排他チェック ---
if [[ -n "$ISSUE_NUM" && -n "$JSONL_PATH" ]]; then
  echo "ERROR: --issue と --jsonl は排他オプションです" >&2
  exit 1
fi
if [[ -z "$ISSUE_NUM" && -z "$JSONL_PATH" ]]; then
  echo "ERROR: --issue または --jsonl が必要です" >&2
  exit 1
fi

# --- JSONL パス解決（--issue の場合）---
resolve_jsonl() {
  local issue="$1"

  # 99文字切り捨て対応: グロブで前方一致検索（worktrees/fix と worktrees/feat の両方）
  local proj_dir=""
  for pattern in \
    "$HOME/.claude/projects/-home-shuu5-projects-local-projects-twill-worktrees-*-${issue}-*" \
    "$HOME/.claude/projects/-home-shuu5-projects-local-projects-twill-worktrees-*${issue}*"; do
    local found
    found=$(ls -td $pattern 2>/dev/null | head -1 || echo "")
    if [[ -n "$found" ]]; then
      proj_dir="$found"
      break
    fi
  done

  if [[ -z "$proj_dir" ]]; then
    echo "WARN: プロジェクトディレクトリが見つかりません (issue=${issue})" >&2
    return 1
  fi

  if [[ ! -d "$proj_dir" ]]; then
    echo "WARN: プロジェクトディレクトリが存在しません: $proj_dir" >&2
    return 1
  fi

  # Issue 番号を含む JSONL を選択（sequential 実行での競合対策）
  local selected=""
  while IFS= read -r jsonl; do
    if grep -l "Issue #${issue}\|issue-${issue}\|\"#${issue}\"" "$jsonl" >/dev/null 2>&1; then
      selected="$jsonl"
      break
    fi
  done < <(ls -t "$proj_dir"/*.jsonl 2>/dev/null)

  if [[ -z "$selected" ]]; then
    # フォールバック: 最新の JSONL を使用
    selected=$(ls -t "$proj_dir"/*.jsonl 2>/dev/null | head -1 || echo "")
  fi

  if [[ -z "$selected" ]]; then
    echo "WARN: JSONL ファイルが見つかりません: $proj_dir" >&2
    return 1
  fi

  echo "$selected"
}

# --- JSONL 解決 ---
if [[ -n "$ISSUE_NUM" ]]; then
  resolved_jsonl=""
  if ! resolved_jsonl=$(resolve_jsonl "$ISSUE_NUM" 2>&1); then
    warn_msg=$(echo "$resolved_jsonl" | grep -v '^WARN:' || echo "unknown error")
    out_json="{\"status\":\"WARN\",\"reason\":\"jsonl_resolution_failed\",\"issue\":${ISSUE_NUM},\"detail\":\"${warn_msg}\"}"
    echo "$out_json"
    exit 0
  fi
  JSONL_PATH="$resolved_jsonl"
fi

if [[ ! -f "$JSONL_PATH" ]]; then
  out_json="{\"status\":\"WARN\",\"reason\":\"jsonl_not_found\",\"jsonl\":\"${JSONL_PATH}\",\"issue\":${ISSUE_NUM:-null}}"
  echo "$out_json"
  exit 0
fi

# --- specialist 抽出（actual set）---
mapfile -t ACTUAL_SPECIALISTS < <(
  grep -oE '"subagent_type":"twl:twl:worker-[^"]+"' "$JSONL_PATH" 2>/dev/null \
    | sort -u \
    | sed 's|^"subagent_type":"twl:twl:||; s|"$||' \
    || true
)

# --- 期待集合生成（expected set）---
EXPECTED_SPECIALISTS=()
if [[ -n "$MANIFEST_FILE_ARG" && -f "$MANIFEST_FILE_ARG" ]]; then
  # --manifest-file 再利用（pr-review-manifest.sh 二重呼び出しを回避）
  mapfile -t EXPECTED_SPECIALISTS < <(
    grep -v '^#' "$MANIFEST_FILE_ARG" | grep -v '^[[:space:]]*$' | sed 's|^twl:twl:||' | sort -u || true
  )
else
  manifest_script="${CLAUDE_PLUGIN_ROOT:-${SCRIPT_DIR}/..}/scripts/pr-review-manifest.sh"
  if [[ ! -f "$manifest_script" ]]; then
    echo "WARN: pr-review-manifest.sh が見つかりません: $manifest_script" >&2
    out_json="{\"status\":\"WARN\",\"reason\":\"manifest_script_not_found\",\"issue\":${ISSUE_NUM:-null}}"
    echo "$out_json"
    exit 0
  fi

  # ISSUE_NUM を export して worker-issue-pr-alignment の動的判定を揃える
  if [[ -n "${ISSUE_NUM:-}" ]]; then
    export ISSUE_NUM
  fi

  mapfile -t EXPECTED_SPECIALISTS < <(
    git diff --name-only origin/main 2>/dev/null \
      | bash "$manifest_script" --mode "$MODE" 2>/dev/null \
      || true
  )
fi

# --- 突合: missing = expected - actual, extra = actual - expected ---
MISSING=()
for exp in "${EXPECTED_SPECIALISTS[@]+"${EXPECTED_SPECIALISTS[@]}"}"; do
  found=false
  for act in "${ACTUAL_SPECIALISTS[@]+"${ACTUAL_SPECIALISTS[@]}"}"; do
    [[ "$exp" == "$act" ]] && found=true && break
  done
  $found || MISSING+=("$exp")
done

EXTRA=()
for act in "${ACTUAL_SPECIALISTS[@]+"${ACTUAL_SPECIALISTS[@]}"}"; do
  found=false
  for exp in "${EXPECTED_SPECIALISTS[@]+"${EXPECTED_SPECIALISTS[@]}"}"; do
    [[ "$act" == "$exp" ]] && found=true && break
  done
  $found || EXTRA+=("$act")
done

# --- status 判定 ---
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "unknown")
if [[ ${#MISSING[@]} -eq 0 ]]; then
  STATUS="PASS"
  EXIT_CODE=0
else
  if [[ "$WARN_ONLY" == "true" || "$QUICK" == "true" || "$AUDIT_MODE" == "warn" ]]; then
    STATUS="WARN"
    EXIT_CODE=0
  else
    STATUS="FAIL"
    EXIT_CODE=1
  fi
fi

# --- JSON 生成（jq が利用可能な場合は使用、なければ手動構築）---
issue_field="${ISSUE_NUM:-null}"

if command -v jq &>/dev/null; then
  expected_json=$(printf '%s\n' "${EXPECTED_SPECIALISTS[@]+"${EXPECTED_SPECIALISTS[@]}"}" | jq -R . | jq -s . 2>/dev/null || echo '[]')
  actual_json=$(printf '%s\n' "${ACTUAL_SPECIALISTS[@]+"${ACTUAL_SPECIALISTS[@]}"}" | jq -R . | jq -s . 2>/dev/null || echo '[]')
  missing_json=$(printf '%s\n' "${MISSING[@]+"${MISSING[@]}"}" | jq -R . | jq -s . 2>/dev/null || echo '[]')
  extra_json=$(printf '%s\n' "${EXTRA[@]+"${EXTRA[@]}"}" | jq -R . | jq -s . 2>/dev/null || echo '[]')

  RESULT_JSON=$(jq -n \
    --arg status "$STATUS" \
    --argjson issue "$issue_field" \
    --arg jsonl "$JSONL_PATH" \
    --arg mode "$MODE" \
    --argjson expected "$expected_json" \
    --argjson actual "$actual_json" \
    --argjson missing "$missing_json" \
    --argjson extra "$extra_json" \
    --arg timestamp "$TIMESTAMP" \
    --arg audit_mode "$AUDIT_MODE" \
    '{status:$status,issue:$issue,jsonl:$jsonl,mode:$mode,expected:$expected,actual:$actual,missing:$missing,extra:$extra,timestamp:$timestamp,audit_mode:$audit_mode}' \
    2>/dev/null || echo "{\"status\":\"${STATUS}\",\"error\":\"jq_failed\"}")
else
  # jq 非利用時のフォールバック（簡易 JSON）
  RESULT_JSON="{\"status\":\"${STATUS}\",\"issue\":${issue_field},\"mode\":\"${MODE}\",\"timestamp\":\"${TIMESTAMP}\",\"audit_mode\":\"${AUDIT_MODE}\"}"
fi

# --- audit ログ保存 ---
TIMESTAMP_NS=$(date +%s%N 2>/dev/null || date +%s 2>/dev/null || echo "0")
RUN_ID="${AUDIT_RUN_ID:-$(date +%Y%m%d-%H%M%S 2>/dev/null || echo "unknown")}"
AUDIT_DIR=".audit/${RUN_ID}"
mkdir -p "$AUDIT_DIR"
AUDIT_FILE="${AUDIT_DIR}/specialist-audit-${ISSUE_NUM:-unknown}-${TIMESTAMP_NS}-$$.json"
echo "$RESULT_JSON" > "$AUDIT_FILE"

# --- 出力 ---
if [[ "$OUTPUT_FORMAT" == "summary" ]]; then
  echo "specialist-audit: ${STATUS} (issue=${ISSUE_NUM:-?}, missing=${#MISSING[@]}, actual=${#ACTUAL_SPECIALISTS[@]}/${#EXPECTED_SPECIALISTS[@]})"
else
  echo "$RESULT_JSON"
fi

# --- FAIL 時 stderr 出力 ---
if [[ "$STATUS" == "FAIL" ]]; then
  missing_str="${MISSING[*]+"${MISSING[*]}"}"
  echo "REJECT: specialist-audit FAIL — missing: ${missing_str}" >&2
fi

exit $EXIT_CODE
