#!/usr/bin/env bash
# dry-run.sh - workflow-test-ready chain step 順序を trace に記録する dry-run スクリプト
# Issue #907 (Phase Z Wave D): TDD 直行 flow。DeltaSpec 依存なし（ADR-023 D-1）。
#
# 副作用は TWL_CHAIN_TRACE のみ。前提は workflow-setup/dry-run.sh と同じ。
#
# Usage:
#   TWL_CHAIN_TRACE=/tmp/trace.jsonl bash dry-run.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
# shellcheck source=../../scripts/dry-run-lib.sh
source "$PLUGIN_ROOT/scripts/dry-run-lib.sh"

CR="$PLUGIN_ROOT/scripts/chain-runner.sh"

# Step 1: test-scaffold（AC-based、chain-runner marker）
bash "$CR" test-scaffold >/dev/null 2>&1 || true

# Step 2: check（mechanical — 失敗してもトレースは emit）
bash "$CR" check >/dev/null 2>&1 || true

echo "[dry-run] workflow-test-ready completed"
