#!/usr/bin/env bash
# merge-gate-check-pr.sh - PR 存在確認（merge-gate Step: PR 存在確認）
#
# PR が存在しない場合は REJECT checkpoint を書き込んで exit 1 を返す。
# Issue #649 対応: merge-gate は PR が存在しない状態で実行してはならない。

set -euo pipefail

PR_NUM=$(gh pr view --json number -q '.number' 2>/dev/null || echo "")
if [[ -z "$PR_NUM" || "$PR_NUM" == "none" ]]; then
  echo "REJECT: PR が存在しません。PR を作成してから merge-gate を実行してください" >&2
  python3 -m twl.autopilot.checkpoint write \
    --step merge-gate \
    --status REJECT \
    --findings '[{"severity":"CRITICAL","category":"chain-integrity-drift","message":"PR が存在しない状態で merge-gate が実行されました。PR を作成してから再実行してください","confidence":100}]'
  exit 1
fi
