#!/usr/bin/env bash
# co-issue-manual-fix-b.sh — co-issue manual fix [B] path Status-only executor
# ADR-024 Phase B: Status=Refined SSoT（label 付与廃止）
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

# Status=Refined を設定（Phase B 移行後: Status only SSoT）
# || _status_exit=$? で set -euo pipefail 下でも失敗終了コードを捕捉できる
_status_exit=0
bash "${SCRIPTS_ROOT}/chain-runner.sh" board-status-update "$ISSUE_NUMBER" Refined || _status_exit=$?
# observability: status update 失敗時のみ WARN
if [[ "$_status_exit" -ne 0 ]]; then
  printf '[%s] WARN status_update_failed issue=#%s exit_code=%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$ISSUE_NUMBER" "$_status_exit" \
    >> /tmp/refined-status-update.log 2>/dev/null || true
fi
