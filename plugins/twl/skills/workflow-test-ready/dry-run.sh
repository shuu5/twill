#!/usr/bin/env bash
# dry-run.sh - workflow-test-ready chain step 順序を trace に記録する dry-run スクリプト
# Issue #144 (Phase 4-A): bats workflow-scenarios テストから呼び出される。
#
# 副作用は TWL_CHAIN_TRACE のみ。前提は workflow-setup/dry-run.sh と同じ。
# sandbox には deltaspec/changes/<id>/ を 1 件以上配置しておくこと
# （change-id-resolve が成功するため）。
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

# Quick guard: 非 quick 想定（quick の場合 SKILL.md は workflow-test-ready 自体を
# スキップするため、本 dry-run は非 quick path のみカバー）
# Step 1: change-id-resolve（mechanical, deltaspec/changes/ が必要）
bash "$CR" change-id-resolve >/dev/null 2>&1 || true

# Step 2: test-scaffold（chain-runner marker）
bash "$CR" test-scaffold >/dev/null 2>&1 || true

# Step 3: check（mechanical — 失敗してもトレースは emit）
bash "$CR" check >/dev/null 2>&1 || true

# Step 4: change-apply（chain-runner marker）→ post-change-apply（marker）
bash "$CR" change-apply >/dev/null 2>&1 || true
bash "$CR" post-change-apply >/dev/null 2>&1 || true

echo "[dry-run] workflow-test-ready completed"
