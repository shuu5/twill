#!/usr/bin/env bash
# session-state-wrapper.sh - session plugin の session-state.sh を呼び出す wrapper
# plugins/twl から plugins/session への cross-plugin 依存を1箇所に集約
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SESSION_SCRIPTS="${SCRIPT_DIR}/../../session/scripts"

if [[ ! -d "$SESSION_SCRIPTS" ]]; then
  echo "Error: session plugin not found at $SESSION_SCRIPTS" >&2
  exit 1
fi

exec "$SESSION_SCRIPTS/session-state.sh" "$@"
