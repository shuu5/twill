#!/usr/bin/env bash
# dry-run.sh - workflow-pr-merge chain step 順序を trace に記録する dry-run スクリプト
# Issue #144 (Phase 4-A): bats workflow-scenarios テストから呼び出される。
#
# 副作用は TWL_CHAIN_TRACE のみ。auto-merge / e2e-screening / pr-cycle-analysis /
# merge-gate は破壊的・LLM のため mock emit。pr-cycle-report / all-pass-check は
# chain-runner mechanical 経由（safe）。
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

# Step 6: e2e-screening（LLM）
dry_run_emit_step e2e-screening

# Step 7: pr-cycle-report（mechanical, no PR + no stdin → skip）
bash "$CR" pr-cycle-report "" >/dev/null 2>&1 </dev/null || true

# Step 7.3: pr-cycle-analysis（LLM）
dry_run_emit_step pr-cycle-analysis

# Step 7.5: all-pass-check（mechanical, no AUTOPILOT_DIR → ok skip）
bash "$CR" all-pass-check PASS >/dev/null 2>&1 || true

# Step 8: merge-gate（LLM）
dry_run_emit_step merge-gate

# Step 8.5: auto-merge（破壊的 — mock emit のみ。実 squash merge は行わない）
dry_run_emit_step auto-merge

echo "[dry-run] workflow-pr-merge completed"
