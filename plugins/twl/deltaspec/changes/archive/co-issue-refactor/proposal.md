## Why

co-issue SKILL.md が肥大化し、Phase 4（Issue 一括作成）のロジックが controller に密結合していた。
thin orchestrator 化により、各 Phase のロジックを専用 workflow に委譲し保守性・トークン効率を改善する。

## What Changes

- #204: co-issue Phase 4 を workflow-issue-create に分離
- #205: co-issue SKILL.md を thin orchestrator にリファクタリング（1,179 tok → 792 tok）

## Capabilities

### New Capabilities

- workflow-issue-create: Phase 4 の Issue 作成ロジックを独立 workflow として分離

### Modified Capabilities

- co-issue: thin orchestrator 化（Phase 呼び出しのみ、ロジックは workflow に委譲）
- deps.yaml: co-issue の calls から reference 5件を削除、workflow-issue-create を追加

## Impact

- plugins/twl/skills/co-issue/SKILL.md
- plugins/twl/skills/workflow-issue-create/SKILL.md（新規）
- plugins/twl/deps.yaml
