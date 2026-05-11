#!/usr/bin/env bash
# chain-steps.sh — chain ステップ順序の共有定義（chain.py から生成）
# このファイルは `twl chain export --shell` で再生成される。直接編集しないこと。
#
# このファイルを source して CHAIN_STEPS 配列を取得する:
#   source "$(dirname "${BASH_SOURCE[0]}")/chain-steps.sh"
#
# workflow-setup → workflow-test-ready → workflow-pr-cycle の全ステップ順。

CHAIN_STEPS=(
  init
  project-board-status-update
  crg-auto-build
  arch-ref
  ac-extract
  test-scaffold
  green-impl
  check
  prompt-compliance
  ts-preflight
  phase-review
  scope-judge
  pr-test
  ac-verify
  post-fix-verify
  all-pass-check
  merge-gate-check
  pr-cycle-report
)

# direct モード（scope/direct ラベル）でスキップするステップの一覧（SSOT）
DIRECT_SKIP_STEPS=(
)

# dispatch_mode SSOT: 各ステップの実行モード
# runner = chain-runner.sh が bash で直接実行
# llm   = LLM Skill が実行し、chain-runner は llm-delegate/llm-complete で記録
declare -A CHAIN_STEP_DISPATCH=(
  [init]=runner
  [project-board-status-update]=trigger
  [crg-auto-build]=llm
  [arch-ref]=runner
  [ac-extract]=runner
  [test-scaffold]=llm
  [green-impl]=llm
  [check]=runner
  [prompt-compliance]=runner
  [ts-preflight]=runner
  [phase-review]=llm
  [scope-judge]=llm
  [pr-test]=runner
  [ac-verify]=llm
  [post-fix-verify]=runner
  [all-pass-check]=runner
  [merge-gate-check]=runner
  [pr-cycle-report]=runner
)

# ワークフロー境界メタデータ（SSOT は chain.py の STEP_TO_WORKFLOW）
declare -A CHAIN_STEP_WORKFLOW=(
  [init]=setup
  [project-board-status-update]=setup
  [crg-auto-build]=setup
  [arch-ref]=setup
  [ac-extract]=setup
  [test-scaffold]=test-ready
  [green-impl]=test-ready
  [check]=test-ready
  [prompt-compliance]=pr-verify
  [ts-preflight]=pr-verify
  [phase-review]=pr-verify
  [scope-judge]=pr-verify
  [pr-test]=pr-verify
  [ac-verify]=pr-verify
  [post-fix-verify]=pr-fix
  [all-pass-check]=pr-merge
  [merge-gate-check]=pr-merge
  [pr-cycle-report]=pr-merge
)

# ワークフロー完了後の次 skill（SSOT は chain.py の WORKFLOW_NEXT_SKILL）
declare -A CHAIN_WORKFLOW_NEXT_SKILL=(
  [setup]="workflow-test-ready"
  [test-ready]="workflow-pr-verify"
  [pr-verify]="workflow-pr-fix"
  [pr-fix]="workflow-pr-merge"
  [pr-merge]=""
)

# LLM ステップのコマンドパス（空 = Skill で実行）
declare -A CHAIN_STEP_COMMAND=(
  [crg-auto-build]="commands/crg-auto-build.md"
  [test-scaffold]=""
  [green-impl]="commands/green-impl.md"
  [phase-review]="commands/phase-review.md"
  [scope-judge]="commands/scope-judge.md"
  [ac-verify]="commands/ac-verify.md"
)
