---
name: twl:workflow-pr-cycle
description: |
  [DEPRECATED] 3 workflow に分割済み。
  workflow-pr-verify → workflow-pr-fix → workflow-pr-merge を使用すること。
type: workflow
effort: medium
spawnable_by: []
deprecated: true
---

# workflow-pr-cycle [DEPRECATED]

このワークフローは以下の 3 つに分割されました（Issue #10）:

1. **workflow-pr-verify**: Step 1-3（ts-preflight, phase-review, scope-judge, pr-test）
2. **workflow-pr-fix**: Step 4-5（fix-phase, post-fix-verify, warning-fix）
3. **workflow-pr-merge**: Step 6-8.5（e2e-screening, pr-cycle-report, pr-cycle-analysis, all-pass-check, merge-gate, auto-merge）

代わりに `/twl:workflow-pr-verify` を実行してください。
