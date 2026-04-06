#!/usr/bin/env bash
# pr-review-manifest.sh - PR review 系 specialist 選択の動的マニフェスト出力
#
# phase-review / merge-gate / post-fix-verify の specialist 選択ロジックを統合し、
# 必須 specialist リストを機械的に出力する。
#
# Usage: git diff --name-only origin/main | bash scripts/pr-review-manifest.sh --mode <mode>
# Mode: phase-review | merge-gate | post-fix-verify
# Stdout: specialist 名（1行1名、重複なし）
# Exit: 0（常に成功）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

# --- 引数パース ---
MODE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$MODE" ]]; then
  echo "Usage: pr-review-manifest.sh --mode <phase-review|merge-gate|post-fix-verify>" >&2
  exit 1
fi

case "$MODE" in
  phase-review|merge-gate|post-fix-verify) ;;
  *)
    echo "Invalid mode: $MODE (must be phase-review, merge-gate, or post-fix-verify)" >&2
    exit 1
    ;;
esac

# --- stdin からファイルリストを読み込み ---
FILES=()
while IFS= read -r line; do
  [[ -n "$line" ]] && FILES+=("$line")
done

# --- 重複排除用の連想配列 ---
declare -A SPECIALISTS

# --- post-fix-verify モード: code-reviewer + security-reviewer + codex のみ ---
if [[ "$MODE" == "post-fix-verify" ]]; then
  SPECIALISTS["worker-code-reviewer"]=1
  SPECIALISTS["worker-security-reviewer"]=1

  # codex 環境チェック
  if command -v codex &>/dev/null && [[ -n "${CODEX_API_KEY:-}" ]]; then
    SPECIALISTS["worker-codex-reviewer"]=1
  fi

  for specialist in "${!SPECIALISTS[@]}"; do
    echo "$specialist"
  done | sort -u
  exit 0
fi

# --- phase-review / merge-gate モード ---

# 基本ルール: deps.yaml 変更あり → worker-structure + worker-principles
for f in "${FILES[@]}"; do
  case "$f" in
    *deps.yaml)
      SPECIALISTS["worker-structure"]=1
      SPECIALISTS["worker-principles"]=1
      break
      ;;
  esac
done

# 基本ルール: コード変更あり → worker-code-reviewer + worker-security-reviewer
has_code=false
for f in "${FILES[@]}"; do
  case "$f" in
    *.sh|*.bash|*.py|*.ts|*.tsx|*.js|*.jsx|*.rb|*.go|*.rs|*.java|*.kt|*.swift|*.c|*.cpp|*.h|*.cs|*.php|*.sql|*.R|*.Rmd|*.qmd)
      has_code=true
      break
      ;;
  esac
done

if $has_code; then
  SPECIALISTS["worker-code-reviewer"]=1
  SPECIALISTS["worker-security-reviewer"]=1
fi

# tech-stack-detect.sh の内部呼び出し
if [[ ${#FILES[@]} -gt 0 ]]; then
  tech_script="$SCRIPT_DIR/tech-stack-detect.sh"
  if [[ -x "$tech_script" ]]; then
    while IFS= read -r specialist; do
      [[ -n "$specialist" ]] && SPECIALISTS["$specialist"]=1
    done < <(printf '%s\n' "${FILES[@]}" | bash "$tech_script")
  fi
fi

# codex 環境チェック
if command -v codex &>/dev/null && [[ -n "${CODEX_API_KEY:-}" ]]; then
  SPECIALISTS["worker-codex-reviewer"]=1
fi

# merge-gate モードのみ: architecture/ 存在チェック → worker-architecture
if [[ "$MODE" == "merge-gate" ]]; then
  if [[ -d "$PROJECT_ROOT/architecture" ]]; then
    SPECIALISTS["worker-architecture"]=1
  fi
fi

# --- 結果出力（重複なし、ソート済み）---
for specialist in "${!SPECIALISTS[@]}"; do
  echo "$specialist"
done | sort -u
