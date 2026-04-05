#!/bin/bash
# codex-review.sh — Codex CLI による補完的コードレビュー
# phase-review の Bash 直接実行として specialists と並列で動作
#
# Usage: codex-review.sh <base_branch> <output_file>
# Exit 0 on graceful skip (codex not installed / API key not set)

set -euo pipefail

BASE_BRANCH="${1:-main}"
OUTPUT_FILE="${2:-/dev/stdout}"

# === Input Validation ===
# ブランチ名のサニタイズ: 許可パターン外はコマンド置換インジェクション防止のため拒否
if [[ ! "$BASE_BRANCH" =~ ^[a-zA-Z0-9/_.~^-]+$ ]]; then
  echo "ERROR: invalid BASE_BRANCH: $BASE_BRANCH" >&2
  exit 1
fi

# 出力先の親ディレクトリ確認
if [ "$OUTPUT_FILE" != "/dev/stdout" ]; then
  mkdir -p "$(dirname "$OUTPUT_FILE")"
fi

# === Graceful Degradation ===
# NOTE: phase-review.md でも同様のチェックを実施（不要な子プロセス起動回避のための二重防御）
if ! command -v codex &>/dev/null; then
  echo "WARN: codex CLI not installed, skipping Codex review" >&2
  exit 0
fi

if [ -z "${CODEX_API_KEY:-}" ]; then
  echo "WARN: CODEX_API_KEY not set, skipping Codex review" >&2
  exit 0
fi

# === Prompt Design ===
PROMPT="Run 'git diff ${BASE_BRANCH}...HEAD' to get the PR changes, then review the diff.

Focus areas:
1. Code Quality: naming consistency, single responsibility, DRY violations, bug patterns (null/undefined references, boundary conditions, resource leaks, race conditions), complexity
2. Security: injection (SQL, XSS, command), authentication/authorization issues, hardcoded credentials, data exposure, path traversal

For each issue, assign a confidence score (0-100). Only report issues with confidence >= 80.

Output format (MUST follow exactly):

codex-review 完了。Critical: X, High: Y, Warning: Z, Suggestion: W
主な問題: [brief list of top issues]

## Critical (N)
- **file:line** - description (confidence: XX)

## High (N)
- **file:line** - description (confidence: XX)

## Warning (N)
- **file:line** - description (confidence: XX)

## Suggestion (N)
- **file:line** - description (confidence: XX)

If no issues found, output exactly:
codex-review 完了。Critical: 0, High: 0, Warning: 0, Suggestion: 0
No significant issues found."

# === Execute ===
# read-only sandbox: レビュー用途ではファイル書き込み不要（Prompt Injection 対策）
# stderr をログファイルに保存（認証エラー、rate limit等の診断用）
STDERR_LOG="${OUTPUT_FILE%.md}.stderr.log"
if [ "$OUTPUT_FILE" = "/dev/stdout" ]; then
  STDERR_LOG="/dev/stderr"
fi

codex exec \
  --sandbox read-only \
  "$PROMPT" > "$OUTPUT_FILE" 2>"$STDERR_LOG"
