#!/usr/bin/env bash
# dry-run.sh - workflow-pr-fix chain step 順序を trace に記録する dry-run スクリプト
# Issue #144 (Phase 4-A): bats workflow-scenarios テストから呼び出される。
#
# 副作用は TWL_CHAIN_TRACE のみ。fix-phase / post-fix-verify / warning-fix は
# 全て LLM ステップのため chain-runner case 未登録 → mock emit。
#
# Usage:
#   TWL_CHAIN_TRACE=/tmp/trace.jsonl bash dry-run.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
# shellcheck source=../../scripts/dry-run-lib.sh
source "$PLUGIN_ROOT/scripts/dry-run-lib.sh"

# Step 4: fix-phase（LLM）
dry_run_emit_step fix-phase

# Step 4.5: post-fix-verify（LLM）
dry_run_emit_step post-fix-verify

# Step 5: warning-fix（LLM）
dry_run_emit_step warning-fix

echo "[dry-run] workflow-pr-fix completed"
