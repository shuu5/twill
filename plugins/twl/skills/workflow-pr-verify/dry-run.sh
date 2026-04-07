#!/usr/bin/env bash
# dry-run.sh - workflow-pr-verify chain step 順序を trace に記録する dry-run スクリプト
# Issue #144 (Phase 4-A): bats workflow-scenarios テストから呼び出される。
#
# 副作用は TWL_CHAIN_TRACE のみ。
# **回帰テスト**: ac-verify は Issue #134 で step 3.5 (pr-test の後) に確定。
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

# Step 1: ts-preflight（mechanical, no tsconfig → skip）
bash "$CR" ts-preflight >/dev/null 2>&1 || true

# Step 2: phase-review（LLM, 並列 specialist レビュー）
dry_run_emit_step phase-review

# Step 2.5: scope-judge（LLM）
dry_run_emit_step scope-judge

# Step 3: pr-test（mechanical, no tests → warn skip）
bash "$CR" pr-test >/dev/null 2>&1 || true

# Step 3.5: ac-verify（chain-runner marker — Issue #134 で pr-test の後に確定）
bash "$CR" ac-verify >/dev/null 2>&1 || true

echo "[dry-run] workflow-pr-verify completed"
