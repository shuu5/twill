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

SCRIPTS_ROOT="${SCRIPTS_ROOT:-$(dirname "$0")}"

# (a) label 先に付与（ADR-024: label 先 → Status 後）
gh issue edit "$ISSUE_NUMBER" --repo "$ISSUE_REPO" --add-label refined

# (b) Status を後に更新（ADR-024: label 完了後に実行）
bash "${SCRIPTS_ROOT}/chain-runner.sh" board-status-update "$ISSUE_NUMBER" Refined
