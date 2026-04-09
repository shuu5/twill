#!/usr/bin/env bash
# chain-steps.sh - chain ステップ順序の共有定義（SSOT）
#
# このファイルを source して CHAIN_STEPS 配列を取得する:
#   source "$(dirname "${BASH_SOURCE[0]}")/chain-steps.sh"
#
# workflow-setup → workflow-test-ready → workflow-pr-cycle の全ステップ順。
# chain-runner.sh と compaction-resume.sh の両方がこのファイルを参照する。

CHAIN_STEPS=(
  init
  board-status-update
  crg-auto-build
  arch-ref
  change-propose
  ac-extract
  change-id-resolve
  test-scaffold
  check
  change-apply
  post-change-apply
  prompt-compliance
  ts-preflight
  pr-test
  ac-verify
  all-pass-check
  pr-cycle-report
)

# quick Issue でスキップするステップの一覧（SSOT）
QUICK_SKIP_STEPS=(
  crg-auto-build
  arch-ref
  change-propose
  ac-extract
  change-id-resolve
  test-scaffold
  check
  change-apply
  prompt-compliance
)

# dispatch_mode SSOT: 各ステップの実行モード
# runner = chain-runner.sh が bash で直接実行
# llm   = LLM Skill が実行し、chain-runner は llm-delegate/llm-complete で記録
declare -A CHAIN_STEP_DISPATCH=(
  [init]=runner
  [board-status-update]=runner
  [crg-auto-build]=llm
  [arch-ref]=runner
  [change-propose]=llm
  [ac-extract]=runner
  [change-id-resolve]=runner
  [test-scaffold]=llm
  [check]=runner
  [change-apply]=llm
  [post-change-apply]=llm
  [prompt-compliance]=runner
  [ts-preflight]=runner
  [pr-test]=runner
  [ac-verify]=llm
  [all-pass-check]=runner
  [pr-cycle-report]=runner
)

# ワークフロー境界メタデータ（SSOT は chain.py の STEP_TO_WORKFLOW — このファイルはミラー）
declare -A CHAIN_STEP_WORKFLOW=(
  [init]=setup
  [board-status-update]=setup
  [crg-auto-build]=setup
  [arch-ref]=setup
  [change-propose]=setup
  [ac-extract]=setup
  [change-id-resolve]=test-ready
  [test-scaffold]=test-ready
  [check]=test-ready
  [change-apply]=test-ready
  [post-change-apply]=test-ready
  [prompt-compliance]=pr-verify
  [ts-preflight]=pr-verify
  [pr-test]=pr-verify
  [ac-verify]=pr-verify
  [all-pass-check]=pr-merge
  [pr-cycle-report]=pr-merge
)

# ワークフロー完了後の次 skill（SSOT は chain.py の WORKFLOW_NEXT_SKILL — このファイルはミラー）
declare -A CHAIN_WORKFLOW_NEXT_SKILL=(
  [setup]=workflow-test-ready
  [test-ready]=workflow-pr-verify
  [pr-verify]=workflow-pr-fix
  [pr-fix]=workflow-pr-merge
  [pr-merge]=""
)

# LLM ステップのコマンドパス（空 = Skill で実行）
declare -A CHAIN_STEP_COMMAND=(
  [crg-auto-build]=commands/crg-auto-build.md
  [change-propose]=commands/change-propose.md
  [test-scaffold]=""
  [change-apply]=""
  [post-change-apply]=""
  [ac-verify]=commands/ac-verify.md
)
