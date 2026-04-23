#!/usr/bin/env bash
# dry-run.sh - workflow-setup chain step 順序を trace に記録する dry-run スクリプト
# Issue #144 (Phase 4-A): bats workflow-scenarios テストから呼び出される。
#
# 副作用は TWL_CHAIN_TRACE のみ。実 gh / git push / worktree 操作は行わない。
#
# 前提:
#   - CLAUDE_PLUGIN_ROOT: plugin ルート（未設定なら本スクリプト位置から解決）
#   - TWL_CHAIN_TRACE:    trace 出力先（必須）
#   - CWD:                テスト sandbox（branch != main、AUTOPILOT_DIR 未設定）
#
# Usage:
#   TWL_CHAIN_TRACE=/tmp/trace.jsonl bash dry-run.sh           # normal path
#   TWL_CHAIN_TRACE=/tmp/trace.jsonl bash dry-run.sh --quick   # quick path
#
# 各 chain step は SKILL.md の chain 実行指示（必須順）に対応する。順序が
# 変わった場合は対応する bats シナリオが落ちるよう設計（回帰テスト凍結）。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
# shellcheck source=../../scripts/dry-run-lib.sh
source "$PLUGIN_ROOT/scripts/dry-run-lib.sh"

CR="$PLUGIN_ROOT/scripts/chain-runner.sh"

QUICK=false
[[ "${1:-}" == "--quick" ]] && QUICK=true

# Step 1: init（mechanical）
bash "$CR" init "" >/dev/null 2>&1 || true

# Step 2: worktree-create（autopilot 経由では Pilot が事前作成済みのためスキップ）
# dry-run では trace marker のみ emit（python 呼び出しを避ける）
dry_run_emit_step worktree-create

# Step 2.3: board-status-update（mechanical, 引数なし→早期 return）
bash "$CR" board-status-update "" >/dev/null 2>&1 || true

# Step 2.4: crg-auto-build（LLM ステップ — chain-runner case 未登録）
dry_run_emit_step crg-auto-build

# Step 2.5: arch-ref（mechanical, 引数なし→skip）
bash "$CR" arch-ref "" >/dev/null 2>&1 || true

# Step 3: ac-extract（mechanical, issue 番号なし→skip）
bash "$CR" ac-extract >/dev/null 2>&1 || true

# 完了後の遷移
if $QUICK; then
  # Quick path: workflow-test-ready をスキップし、直接実装→ ac-verify を実行。
  # ac-verify 完了後に停止し、orchestrator が workflow-pr-fix を inject する。
  # merge-gate は workflow-pr-merge の責務（ADR-018 準拠、#671 修正）。
  bash "$CR" ac-verify >/dev/null 2>&1 || true
fi

echo "[dry-run] workflow-setup completed (quick=$QUICK)"
