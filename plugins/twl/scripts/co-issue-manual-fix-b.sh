#!/usr/bin/env bash
# co-issue-manual-fix-b.sh — co-issue manual fix [B] path dual-write executor
# ADR-024 dual-write 順序: label 先 → Status 後
# Emergency Bypass 準拠 (glossary.md L26): orchestrator failure 後の fallback
set -euo pipefail

ISSUE_NUMBER="${1:-${ISSUE_NUMBER:-}}"
ISSUE_REPO="${2:-${ISSUE_REPO:-}}"

if [[ -z "$ISSUE_NUMBER" || -z "$ISSUE_REPO" ]]; then
  echo "Usage: $0 <issue_number> <repo>" >&2
  exit 1
fi

# 入力検証: ISSUE_NUMBER は正の整数のみ許可（chain-runner.sh と同一規約）
if [[ ! "$ISSUE_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "ERROR: ISSUE_NUMBER must be a positive integer: ${ISSUE_NUMBER}" >&2
  exit 1
fi

# 入力検証: ISSUE_REPO は owner/repo 形式のみ許可
if [[ ! "$ISSUE_REPO" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]]; then
  echo "ERROR: ISSUE_REPO must be in owner/repo format: ${ISSUE_REPO}" >&2
  exit 1
fi

# SCRIPTS_ROOT: 環境変数で上書き可能だが絶対パスに正規化し .. を拒否
_DEFAULT_SCRIPTS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="${SCRIPTS_ROOT:-${_DEFAULT_SCRIPTS_ROOT}}"
SCRIPTS_ROOT="$(cd "${SCRIPTS_ROOT}" && pwd 2>/dev/null)" || {
  echo "ERROR: SCRIPTS_ROOT is not a valid directory: ${SCRIPTS_ROOT}" >&2
  exit 1
}

# (a) label 先に付与（ADR-024: label 先 → Status 後）
gh issue edit "$ISSUE_NUMBER" --repo "$ISSUE_REPO" --add-label refined

# (b) Status を後に更新（ADR-024: label 完了後に実行）
# fail-soft: label 付与済みの場合、Status 更新失敗は警告のみ（workflow-issue-refine Step 6' と等価）
bash "${SCRIPTS_ROOT}/chain-runner.sh" board-status-update "$ISSUE_NUMBER" Refined \
  || echo "WARN: board-status-update Refined failed (label already applied)" >&2
