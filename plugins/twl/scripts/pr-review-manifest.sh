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
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

# --- 引数パース ---
MODE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      if [[ $# -lt 2 ]]; then
        echo "Error: --mode requires a value" >&2
        exit 1
      fi
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
  phase-review|merge-gate|post-fix-verify|arch-review) ;;
  *)
    echo "Invalid mode: $MODE (must be phase-review, merge-gate, post-fix-verify, or arch-review)" >&2
    exit 1
    ;;
esac

# --- codex 利用可能チェック（auth.json ベース）---
# codex login status は auth.json/keyring を確認する（env var は見ない）。
# 各環境で事前に `codex login --with-api-key` を実行しておくこと。
codex_available() {
  command -v codex &>/dev/null && codex login status 2>&1 | grep -qi "logged in"
}

# --- stdin からファイルリストを読み込み ---
FILES=()
while IFS= read -r line; do
  [[ -n "$line" ]] && FILES+=("$line")
done

# --- 重複排除用の連想配列 ---
declare -A SPECIALISTS

# --- arch-review モード: architecture docs 専用 specialist ---
if [[ "$MODE" == "arch-review" ]]; then
  # 常時必須: architecture docs 変更あり（常に）→ worker-arch-doc-reviewer
  SPECIALISTS["worker-arch-doc-reviewer"]=1
  # 常時必須: architecture/ 配下変更あり（常に）→ worker-architecture
  SPECIALISTS["worker-architecture"]=1

  # 条件付き: deps.yaml 変更あり → worker-structure + worker-principles
  for f in "${FILES[@]}"; do
    case "$f" in
      *deps.yaml)
        SPECIALISTS["worker-structure"]=1
        SPECIALISTS["worker-principles"]=1
        break
        ;;
    esac
  done

  for specialist in "${!SPECIALISTS[@]}"; do
    echo "$specialist"
  done | sort -u
  exit 0
fi

# --- post-fix-verify モード: code-reviewer + security-reviewer + codex のみ ---
if [[ "$MODE" == "post-fix-verify" ]]; then
  SPECIALISTS["worker-code-reviewer"]=1
  SPECIALISTS["worker-security-reviewer"]=1

  # codex 環境チェック（auth.json ベース）
  if codex_available; then
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

# codex 環境チェック（auth.json ベース）
if codex_available; then
  SPECIALISTS["worker-codex-reviewer"]=1
fi

# merge-gate モードのみ: architecture/ 存在チェック → worker-architecture
if [[ "$MODE" == "merge-gate" ]]; then
  if [[ -d "$PLUGIN_ROOT/architecture" ]]; then
    SPECIALISTS["worker-architecture"]=1
  fi
fi

# merge-gate モード: 最低限必須 specialist（quick ラベル含む全ケースで保証）
# quick ラベルでも specialist review は省略不可（Issue #657）
if [[ "$MODE" == "merge-gate" ]]; then
  SPECIALISTS["worker-code-reviewer"]=1
  SPECIALISTS["worker-security-reviewer"]=1
fi

# phase-review / merge-gate モード: architecture/ 配下の .md 変更 → worker-arch-doc-reviewer
if [[ "$MODE" == "phase-review" || "$MODE" == "merge-gate" ]]; then
  for f in "${FILES[@]}"; do
    case "$f" in
      */architecture/*.md|*/architecture/*/*.md|*/architecture/*/*/*.md)
        SPECIALISTS["worker-arch-doc-reviewer"]=1
        break
        ;;
    esac
  done
fi

# merge-gate モードのみ: chain 関連ファイル (deps.yaml / SKILL.md / chain-runner.sh) 変更
# → worker-workflow-integrity を追加 (Layer 3: chain-integrity-drift 検出)
# architecture/*.md 単独変更は worker-architecture が担当するため、ここでは起動しない
if [[ "$MODE" == "merge-gate" ]]; then
  chain_related=false
  for f in "${FILES[@]}"; do
    case "$f" in
      *deps.yaml|*SKILL.md|*chain-runner.sh|*autopilot/chain.py)
        chain_related=true
        break
        ;;
    esac
  done
  if $chain_related; then
    SPECIALISTS["worker-workflow-integrity"]=1
  fi
fi

# --- 常時追加: AC alignment specialist (Issue 番号が解決可能な場合のみ) ---
# phase-review / merge-gate モードで Issue 番号が解決可能な場合に worker-issue-pr-alignment を必須化。
# 変更ファイルパターンに依存しない（コード変更ゼロでも Issue 内容と乖離している可能性があるため）。
# Issue 番号が解決できない場合（chain 外で merge-gate 実行など）はスキップ + warning ログ。
if [[ "$MODE" == "phase-review" || "$MODE" == "merge-gate" ]]; then
  ISSUE_NUM=""
  resolver="$SCRIPT_DIR/resolve-issue-num.sh"
  if [[ -f "$resolver" ]]; then
    # shellcheck disable=SC1090
    source "$resolver" 2>/dev/null || true
    if declare -f resolve_issue_num >/dev/null 2>&1; then
      ISSUE_NUM=$(resolve_issue_num 2>/dev/null || echo "")
    fi
  fi
  if [[ -n "$ISSUE_NUM" ]]; then
    SPECIALISTS["worker-issue-pr-alignment"]=1
  else
    echo "WARNING: pr-review-manifest: Issue 番号が解決不能のため worker-issue-pr-alignment をスキップします" >&2
  fi
fi

# --- 結果出力（重複なし、ソート済み）---
for specialist in "${!SPECIALISTS[@]}"; do
  echo "$specialist"
done | sort -u
