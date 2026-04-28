#!/usr/bin/env bash
# tech-stack-detect.sh
# 変更ファイルのパス・拡張子から tech-stack を判定し、
# 該当する conditional specialist を stdout に出力する。
#
# Usage: git diff --name-only origin/main | bash scripts/tech-stack-detect.sh
# Output: "worker-code-reviewer language=<name>" 形式を改行区切りで出力（該当なしの場合は空）
#         後方互換性のため specialist 名のみの行も並列出力する
#
# language hint 形式（Issue #1081）:
#   worker-code-reviewer language=fastapi
#   worker-code-reviewer language=hono
#   worker-code-reviewer language=nextjs
#   worker-code-reviewer language=r
# caller は prompt 先頭に "language=<name>:" を付与して Task を起動すること

set -euo pipefail

# プロジェクトルートを検出（git worktree のルート）
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

# stdin からファイルパスリストを読み込み
FILES=()
while IFS= read -r line; do
  [[ -n "$line" ]] && FILES+=("$line")
done

# 重複排除用の連想配列（language hint → 1）
declare -A LANGUAGE_HINTS

# --- 判定ルール ---

# Next.js: .tsx/.jsx ファイル + next.config.* 存在
has_tsx=false
for f in "${FILES[@]}"; do
  case "$f" in
    *.tsx|*.jsx) has_tsx=true; break ;;
  esac
done
if $has_tsx; then
  if ls "$PROJECT_ROOT"/next.config.* >/dev/null 2>&1; then
    LANGUAGE_HINTS["nextjs"]=1
  fi
fi

# FastAPI: .py ファイル + FastAPI import
has_py=false
for f in "${FILES[@]}"; do
  case "$f" in
    *.py) has_py=true; break ;;
  esac
done
if $has_py; then
  if grep -rql "from fastapi\|import fastapi" "$PROJECT_ROOT"/*.py "$PROJECT_ROOT"/**/*.py 2>/dev/null; then
    LANGUAGE_HINTS["fastapi"]=1
  fi
fi

# Supabase migration: supabase/migrations/ 配下の変更（language hint 対象外）
declare -A EXTRA_SPECIALISTS
for f in "${FILES[@]}"; do
  case "$f" in
    supabase/migrations/*) EXTRA_SPECIALISTS["worker-supabase-migration-checker"]=1; break ;;
  esac
done

# R: .R/.Rmd/.qmd ファイル
for f in "${FILES[@]}"; do
  case "$f" in
    *.R|*.Rmd|*.qmd) LANGUAGE_HINTS["r"]=1; break ;;
  esac
done

# E2E テスト: e2e/ 配下の .spec.ts/.test.ts（language hint 対象外）
for f in "${FILES[@]}"; do
  case "$f" in
    e2e/*.spec.ts|e2e/*.test.ts|tests/e2e/*.spec.ts|tests/e2e/*.test.ts)
      EXTRA_SPECIALISTS["worker-e2e-reviewer"]=1; break ;;
  esac
done

# --- 結果出力 ---

# language hint 行: "worker-code-reviewer language=<name>"
for lang in "${!LANGUAGE_HINTS[@]}"; do
  echo "worker-code-reviewer language=${lang}"
done

# language hint 対象外 specialist（supabase, e2e 等）
for specialist in "${!EXTRA_SPECIALISTS[@]}"; do
  echo "$specialist"
done
