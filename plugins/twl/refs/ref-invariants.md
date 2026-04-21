# 不変条件 A-M 参照ドキュメント

twill autopilot システムの不変条件 A-M（13 件）の正典定義。各条件の定義・根拠・検証方法・影響範囲を一本化する。

更新日: 2026-04-21

---

## 不変条件 A: 状態の一意性

- **定義**: `issue-{N}.json` の `status` は常に定義された遷移パスのみ許可されなければならない（SHALL）。不正な状態遷移は拒否される。
- **根拠**: ADR なし — 慣習的制約
- **検証方法**: [`invariant-A: parallel writes to same issue produce valid JSON`](../tests/bats/invariants/autopilot-invariants.bats)
- **影響範囲**:
  - `cli/twl/src/twl/autopilot/state.py`
  - `cli/twl/src/twl/autopilot/orchestrator.py`

---

## 不変条件 B: Worktree ライフサイクル Pilot 専任

- **定義**: Worktree の作成・削除は Pilot が行わなければならない（SHALL）。Worker は使用のみ。
- **根拠**: [ADR-008: Worktree Lifecycle Pilot Ownership](../architecture/decisions/ADR-008-worktree-lifecycle-pilot-ownership.md) / [DeltaSpec: Worktree ライフサイクル安全性](../deltaspec/specs/autopilot-lifecycle.md#scenario-worktreeライフサイクル安全性)
- **検証方法**: [`invariant-B: worktree-delete rejects worker role`](../tests/bats/invariants/autopilot-invariants.bats), [`invariant-B: Worker chain does not include worktree-create`](../tests/bats/invariants/autopilot-invariants.bats)
- **影響範囲**:
  - `plugins/twl/scripts/worktree-delete.sh`
  - `plugins/twl/scripts/chain-runner.sh`
  - `plugins/twl/scripts/autopilot-orchestrator.sh`

---

## 不変条件 C: Worker マージ禁止

- **定義**: Worker は `merge-ready` を宣言するのみでなければならない（SHALL）。マージは Pilot が実行する。Worker が直接 `gh pr merge` を実行してはならない。
- **根拠**: ADR なし — 慣習的制約
- **検証方法**: [`invariant-C: merge-gate-execute rejects invalid ISSUE`](../tests/bats/invariants/autopilot-invariants.bats)
- **影響範囲**:
  - `plugins/twl/scripts/auto-merge.sh`
  - `plugins/twl/scripts/merge-gate-checkpoint-merge.sh`
  - `cli/twl/src/twl/autopilot/mergegate.py`

---

## 不変条件 D: 依存先 fail 時の skip 伝播

- **定義**: Phase N で fail した Issue に依存する Issue は自動 skip されなければならない（SHALL）。
- **根拠**: [DeltaSpec: Phase 内 Issue 失敗時の skip 伝播](../deltaspec/specs/autopilot-lifecycle.md#scenario-phase内-issue失敗時のskip伝播)
- **検証方法**: [`invariant-D: single dependency fail causes skip`](../tests/bats/invariants/autopilot-invariants.bats), [`invariant-D: multiple deps with one failed causes skip`](../tests/bats/invariants/autopilot-invariants.bats)
- **影響範囲**:
  - `plugins/twl/scripts/autopilot-plan.sh`
  - `cli/twl/src/twl/autopilot/orchestrator.py`

---

## 不変条件 E: merge-gate リトライ制限

- **定義**: merge-gate のリトライは最大 1 回でなければならない（SHALL）。2 回目リジェクト = 確定失敗。
- **根拠**: [DeltaSpec: retry 制限](../deltaspec/specs/autopilot-lifecycle.md#scenario-retry制限) / [DeltaSpec: merge-gate REJECT 2 回目確定失敗](../deltaspec/specs/merge-gate.md#scenario-merge-gate-reject2回目確定失敗-リトライ最大1回制限)
- **検証方法**: [`invariant-E: first retry allowed`](../tests/bats/invariants/autopilot-invariants.bats), [`invariant-E: second retry rejected`](../tests/bats/invariants/autopilot-invariants.bats)
- **影響範囲**:
  - `plugins/twl/scripts/merge-gate-checkpoint-merge.sh`
  - `cli/twl/src/twl/autopilot/orchestrator.py`

---

## 不変条件 F: squash merge API 失敗時 rebase 禁止

- **定義**: `gh pr merge --squash` API 呼び出し失敗後は rebase を禁止しなければならない（SHALL）。停止のみ。merge 前のコンフリクト事前検知とは別概念。
- **根拠**: [DeltaSpec: merge 失敗時の対応](../deltaspec/specs/merge-gate.md#scenario-merge失敗時の対応)
- **検証方法**: [`invariant-F: merge-gate-execute uses --squash flag`](../tests/bats/invariants/autopilot-invariants.bats)
- **影響範囲**:
  - `plugins/twl/scripts/merge-gate-checkpoint-merge.sh`
  - `cli/twl/src/twl/autopilot/mergegate.py`

---

## 不変条件 G: クラッシュ検知保証

- **定義**: Worker の crash/timeout は必ず検知されなければならない（SHALL）。
- **根拠**: [DeltaSpec: Worker crash 検知](../deltaspec/specs/autopilot-lifecycle.md#scenario-worker-crash検知)
- **検証方法**: [`invariant-G: crash-detect transitions to failed when pane absent`](../tests/bats/invariants/autopilot-invariants.bats)
- **影響範囲**:
  - `plugins/twl/scripts/crash-detect.sh`
  - `cli/twl/src/twl/autopilot/orchestrator.py`

---

## 不変条件 H: deps.yaml コンフリクト時自動 rebase

- **定義**: deps.yaml 変更 Issue は並列実行を許可しなければならない（SHALL）。merge-gate がコンフリクト検出時に自動 rebase を試行し、失敗時は conflict 状態に遷移する。リトライ上限は 1 回（不変条件 E と整合）。不変条件 F（squash merge API 失敗後 rebase 禁止）とは別概念。
- **根拠**: ADR なし — 慣習的制約
- **検証方法**: [`invariant-H: deps.yaml components have valid types`](../tests/bats/invariants/autopilot-invariants.bats)
- **影響範囲**:
  - `plugins/twl/scripts/merge-gate-checkpoint-merge.sh`
  - `plugins/twl/deps.yaml`

---

## 不変条件 I: 循環依存拒否

- **定義**: plan.yaml 生成時に循環依存を検出した場合、拒否しなければならない（SHALL）。
- **根拠**: [DeltaSpec: 循環依存拒否](../deltaspec/specs/autopilot-lifecycle.md#scenario-循環依存拒否)
- **検証方法**: [`invariant-I: direct circular dependency rejected`](../tests/bats/invariants/autopilot-invariants.bats), [`invariant-I: indirect circular dependency rejected`](../tests/bats/invariants/autopilot-invariants.bats)
- **影響範囲**:
  - `plugins/twl/scripts/autopilot-plan.sh`

---

## 不変条件 J: merge 前 base drift 検知

- **定義**: merge-gate 実行前に origin/main に対する silent deletion を検知し、検出時は merge を停止しなければならない（SHALL）。
- **根拠**: [DeltaSpec: merge 前 base drift 検知](../deltaspec/specs/merge-gate.md#scenario-merge前-base-drift検知)
- **検証方法**: [`invariant-J: silent file deletion is detected as base drift`](../tests/bats/invariants/autopilot-invariants.bats), [`invariant-J: intentional deletion is not flagged`](../tests/bats/invariants/autopilot-invariants.bats)
- **影響範囲**:
  - `plugins/twl/scripts/merge-gate-checkpoint-merge.sh`

---

## 不変条件 K: Pilot 実装禁止

- **定義**: Pilot は Issue の実装（コード変更・PR 作成）を直接行ってはならない（SHALL）。実装は常に Worker 経由。Emergency Bypass 時も `mergegate merge --force` 経由のみ許可。
- **根拠**: [DeltaSpec: 不変条件 K — Pilot 実装禁止](../deltaspec/specs/autopilot-lifecycle.md#scenario-不変条件-k-pilot実装禁止228)
- **検証方法**: [`invariant-K: autopilot.md defines invariant K`](../tests/bats/invariants/autopilot-invariants.bats), [`invariant-K: pilot cannot write implementation-only field`](../tests/bats/invariants/autopilot-invariants.bats)
- **影響範囲**:
  - `plugins/twl/skills/co-autopilot/SKILL.md`
  - `cli/twl/src/twl/autopilot/mergegate.py`
  - `cli/twl/src/twl/autopilot/orchestrator.py`

---

## 不変条件 L: autopilot マージ実行責務

- **定義**: autopilot 時のマージ実行は Orchestrator の `mergegate.py` 経由のみでなければならない（SHALL）。Worker chain の auto-merge ステップは `merge-ready` 宣言のみを行い、マージは実行しない。
- **根拠**: ADR なし — 慣習的制約
- **検証方法**: #789 で bats テスト生成予定
- **影響範囲**:
  - `cli/twl/src/twl/autopilot/mergegate.py`
  - `plugins/twl/scripts/auto-merge.sh`

---

## 不変条件 M: chain 遷移は orchestrator/手動 inject のみ

- **定義**: chain 遷移（`current_step` の terminal 検知後の次 workflow 起動）は orchestrator の `inject_next_workflow` または手動 skill inject（`/twl:workflow-<name>`）のみ許可しなければならない（SHALL）。Pilot の直接 nudge による chain bypass は禁止。
- **根拠**: [ADR-018: autopilot state schema SSOT](../architecture/decisions/ADR-018-state-schema-ssot.md) / issue-438
- **検証方法**: #789 で bats テスト生成予定
- **影響範囲**:
  - `cli/twl/src/twl/autopilot/orchestrator.py`
  - `plugins/twl/scripts/chain-runner.sh`
  - `plugins/twl/skills/co-autopilot/SKILL.md`

---

## SU-* との境界

SU-1〜SU-7 は Supervisor（su-observer）固有の application-level 制約であり、本ドキュメントの不変条件 A-M とは独立した体系である。SU-* の定義は [`skills/su-observer/SKILL.md`](../skills/su-observer/SKILL.md) を参照。
