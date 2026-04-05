#!/usr/bin/env bash
# tech-stack-detect.sh
# 変更ファイルのパス・拡張子から tech-stack を判定し、
# 該当する conditional specialist を stdout に出力する。
#
# Usage: git diff --name-only origin/main | bash scripts/tech-stack-detect.sh
# Output: specialist 名を改行区切りで出力（該当なしの場合は空）

set -euo pipefail

# プロジェクトルートを検出（git worktree のルート）
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

# stdin からファイルパスリストを読み込み
FILES=()
while IFS= read -r line; do
  [[ -n "$line" ]] && FILES+=("$line")
done

# 重複排除用の連想配列
declare -A SPECIALISTS

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
    SPECIALISTS["worker-nextjs-reviewer"]=1
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
    SPECIALISTS["worker-fastapi-reviewer"]=1
  fi
fi

# Supabase migration: supabase/migrations/ 配下の変更
for f in "${FILES[@]}"; do
  case "$f" in
    supabase/migrations/*) SPECIALISTS["worker-supabase-migration-checker"]=1; break ;;
  esac
done

# R: .R/.Rmd/.qmd ファイル
for f in "${FILES[@]}"; do
  case "$f" in
    *.R|*.Rmd|*.qmd) SPECIALISTS["worker-r-reviewer"]=1; break ;;
  esac
done

# E2E テスト: e2e/ 配下の .spec.ts/.test.ts
for f in "${FILES[@]}"; do
  case "$f" in
    e2e/*.spec.ts|e2e/*.test.ts|tests/e2e/*.spec.ts|tests/e2e/*.test.ts)
      SPECIALISTS["worker-e2e-reviewer"]=1; break ;;
  esac
done

# --- 結果出力 ---
for specialist in "${!SPECIALISTS[@]}"; do
  echo "$specialist"
done
