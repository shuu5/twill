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
  worktree-create
  board-status-update
  crg-auto-build
  arch-ref
  opsx-propose
  ac-extract
  change-id-resolve
  test-scaffold
  check
  opsx-apply
  ts-preflight
  pr-test
  all-pass-check
  pr-cycle-report
)

# quick Issue でスキップするステップの一覧（SSOT）
QUICK_SKIP_STEPS=(
  crg-auto-build
  arch-ref
  opsx-propose
  ac-extract
  change-id-resolve
  test-scaffold
  check
  opsx-apply
)
