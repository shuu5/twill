---
name: twl:workflow-arch-review
description: |
  Architecture docs 専用 PR レビュー workflow（arch-phase-review → arch-fix-phase → merge-gate → auto-merge）。
  コード専用ステップ（ts-preflight, pr-test, e2e 等）を省いた軽量 chain。

  Use when user: says アーキテクチャレビュー/arch-review,
  or when called from co-architect.
type: workflow
effort: medium
spawnable_by:
- user
- controller
tools: [Bash, Read, Skill]
maxTurns: 30
---

# Architecture Docs レビュー Workflow（chain-driven）

architecture docs 変更の PR に特化した軽量レビュー workflow。
ts-preflight・pr-test・e2e など、コード専用ステップを含まない。

## chain ライフサイクル

| Step | コンポーネント | 型 |
|------|--------------|------|
| 1 | arch-phase-review | composite |
| 2 | arch-fix-phase | atomic |
| 3 | merge-gate | composite |
| 4 | auto-merge | atomic |

## ドメインルール

### arch-phase-review と co-autopilot PR cycle の差異

| step | co-autopilot PR cycle | workflow-arch-review |
|------|----------------------|---------------------|
| prompt-compliance | あり | なし |
| ts-preflight | あり | なし |
| phase-review | コード specialist | architecture specialist |
| scope-judge | あり | なし |
| pr-test | あり | なし |
| ac-verify | あり | なし |
| e2e-screening | あり | なし |
| fix-phase | あり | あり（max 1 round、arch-fix-phase） |
| merge-gate | あり | あり（既存再利用） |
| auto-merge | あり | あり（既存再利用） |

## chain 実行指示（MUST — 全ステップを順に実行せよ。途中で停止するな）

**重要**: 以下の全ステップを上から順に実行すること。各ステップ完了後、**即座に**次のステップに進むこと。

### 前提: 前 workflow コンテキスト復元

```bash
CR="${CLAUDE_PLUGIN_ROOT}/scripts/chain-runner.sh"
ISSUE_NUM=$(bash "$CR" resolve-issue-num 2>/dev/null || echo "")
AUTOPILOT_DIR="${AUTOPILOT_DIR:-.autopilot}"
CONTEXT_FILE="${AUTOPILOT_DIR}/issues/issue-${ISSUE_NUM}-context.md"
[[ -n "$ISSUE_NUM" && -f "$CONTEXT_FILE" ]] && echo "=== 前 workflow コンテキスト ===" && cat "$CONTEXT_FILE"
```

### Step 1: arch-phase-review（並列 specialist レビュー）【LLM 判断】

`commands/arch-phase-review.md` を Read → 実行。

specialist 選択は `pr-review-manifest.sh --mode arch-review` が決定する:
- 常時: worker-arch-doc-reviewer + worker-architecture
- deps.yaml 変更あり: + worker-structure + worker-principles

### Step 2: arch-fix-phase（修正ループ）【LLM 判断】

`commands/arch-fix-phase.md` を Read → 実行。

CRITICAL/WARNING findings がある場合のみ修正を実施（最大 1 ラウンド）。
CRITICAL 残存 → REJECT（merge-gate が BLOCK する）。

### Step 3: merge-gate（マージ判定）【LLM 判断】

`commands/merge-gate.md` を Read → 実行。
arch-phase-review と arch-fix-phase の checkpoint を統合して最終判定。

### Step 4: auto-merge（squash merge → cleanup）【LLM 判断】

merge-gate が PASS の場合のみ。`commands/auto-merge.md` を Read → 実行。

## 完了後の遷移

- IS_AUTOPILOT=true → context.md 書き出し → 停止
- IS_AUTOPILOT=false → 「workflow-arch-review 完了」と案内

## compaction 復帰プロトコル

`refs/ref-compaction-recovery.md` を Read し従うこと。ステップリスト: `arch-phase-review arch-fix-phase merge-gate auto-merge`
