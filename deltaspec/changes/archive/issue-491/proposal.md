## Why

co-issue v2 の Pilot 側 (Issue #492) が Worker runtime を呼び出すために、1 issue の lifecycle 全体（structure → spec-review → aggregate → fix loop → arch-drift → create）を自律実行する Worker 側 runtime が必要。現在は spec-review-orchestrator.sh (PR #467) が spec-review のみを外部化しているが、lifecycle 全体を担う機構が未実装。

## What Changes

- `plugins/twl/skills/workflow-issue-lifecycle/SKILL.md` 新規作成（user-invocable workflow）
- `plugins/twl/scripts/issue-lifecycle-orchestrator.sh` 新規作成（spec-review-orchestrator.sh パターン流用のバッチ orchestrator）
- `plugins/twl/commands/issue-create.md` 拡張（`--repo <owner/repo>` オプション追加）
- `plugins/twl/tests/bats/scripts/issue-lifecycle-orchestrator.bats` 新規追加
- `plugins/twl/tests/scenarios/workflow-issue-lifecycle-smoke.test.sh` 新規追加
- `plugins/twl/deps.yaml` 更新（新エントリ 2 件 + `spawnable_by` 拡張 5 件）

## Capabilities

### New Capabilities

- **workflow-issue-lifecycle**: 1 issue につき structure → spec-review → aggregate → arch-drift → fix loop → create を自律実行。CRITICAL findings → body 修正 → 再レビューループ、WARNING only → 修正 + 終了、clean → 即終了、max_rounds 到達 → circuit_broken
- **issue-lifecycle-orchestrator**: Pilot が呼ぶバッチ orchestrator。tmux + polling + MAX_PARALLEL バッチ制御 + flock + resume 対応

### Modified Capabilities

- **issue-create**: `--repo <owner/repo>` オプション追加。未指定時は現在リポへ作成（後方互換維持）。Worker が cross-repo 子 issue を起票する際に使用
- **issue-structure / issue-spec-review / issue-review-aggregate / issue-arch-drift / issue-create**: `spawnable_by` を `[controller]` → `[controller, workflow]` に拡張（workflow-issue-lifecycle から呼べるよう型制約更新）

## Impact

- **新規ファイル**: SKILL.md (workflow), orchestrator script (bash), bats tests, smoke scenario
- **変更ファイル**: issue-create.md (option 追加), deps.yaml (5 件 spawnable_by 拡張 + 2 件新エントリ)
- **非改変**: spec-review-orchestrator.sh (PR #467 成果物), workflow-issue-refine/SKILL.md (Issue #493 に委譲), co-issue/SKILL.md (Issue #492 に委譲)
- **依存**: PR #467 (spec-review-orchestrator.sh, merge 済み 2026-04-11), ADR-017 Issue #490 設計原則
