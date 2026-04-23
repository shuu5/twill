# 不変条件 A-M 参照ドキュメント

twill autopilot システムの不変条件 A-M（13 件）の正典定義。各条件の定義・根拠・検証方法・影響範囲を一本化する。

更新日: 2026-04-23

## 本ドキュメントの SSoT 位置付け

本ドキュメントは不変条件 A-M の **SSoT（Single Source of Truth）** であり、各 invariant の定義・意味は本ドキュメント自身で自己完結する。

- **「根拠」欄の役割**: 設計判断の出典 ADR または導入された背景を示す。ADR が invariant の詳細仕様を個別定義しない場合でも、invariant の実装整合性は **検証方法欄の bats test** と **影響範囲欄の実装ファイル** で維持される。
- **ADR-023 継承について**: 不変条件 D/E/F/G/I/J/K は旧 DeltaSpec spec scenario が根拠文書として機能していたが、Phase Z (#901) で DeltaSpec 廃止に伴い [ADR-023](../architecture/decisions/ADR-023-tdd-direct-flow.md) に継承された。ADR-023 は chain 構造変更の ADR であり individual invariant の詳細仕様は持たないが、invariant の意味定義は本ドキュメント自身が SSoT として保持し、検証は bats test (`../tests/bats/invariants/autopilot-invariants.bats`) が担保する。
- **不変条件 B の 2 根拠保持**: 不変条件 B のみ ADR-008 + ADR-023 の 2 根拠を明示しているのは、ADR-008 が Worktree ライフサイクル単独の独立 ADR として成立しているため。他の invariant (D/E/F/G/I/J/K) は対応する独立 ADR が存在しないため、ADR-023 を継承先として単一参照する。

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
- **根拠**: [ADR-008: Worktree Lifecycle Pilot Ownership](../architecture/decisions/ADR-008-worktree-lifecycle-pilot-ownership.md) / [ADR-023: deltaspec-free chain と TDD 直行 flow](../architecture/decisions/ADR-023-tdd-direct-flow.md) (DeltaSpec 除去後も本不変条件は ADR-008 に継承)
- **検証方法**: [`invariant-B: worktree-delete rejects worker role`](../tests/bats/invariants/autopilot-invariants.bats), [`invariant-B: Worker chain (chain-steps.sh) does not include worktree-create`](../tests/bats/invariants/autopilot-invariants.bats)
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
- **根拠**: [ADR-023: deltaspec-free chain と TDD 直行 flow](../architecture/decisions/ADR-023-tdd-direct-flow.md) (不変条件 D は DeltaSpec spec scenario から ADR-023 に継承)
- **検証方法**: [`invariant-D: single dependency fail causes skip`](../tests/bats/invariants/autopilot-invariants.bats), [`invariant-D: multiple deps with one failed causes skip`](../tests/bats/invariants/autopilot-invariants.bats)
- **影響範囲**:
  - `plugins/twl/scripts/autopilot-plan.sh`
  - `cli/twl/src/twl/autopilot/orchestrator.py`

---

## 不変条件 E: merge-gate リトライ制限

- **定義**: merge-gate のリトライは最大 1 回でなければならない（SHALL）。2 回目リジェクト = 確定失敗。
- **根拠**: [ADR-023: deltaspec-free chain と TDD 直行 flow](../architecture/decisions/ADR-023-tdd-direct-flow.md) (不変条件 E の retry 制限と merge-gate REJECT 2 回目確定失敗は DeltaSpec spec scenario から ADR-023 に継承)
- **検証方法**: [`invariant-E: first retry allowed`](../tests/bats/invariants/autopilot-invariants.bats), [`invariant-E: second retry rejected`](../tests/bats/invariants/autopilot-invariants.bats)
- **影響範囲**:
  - `plugins/twl/scripts/merge-gate-checkpoint-merge.sh`
  - `cli/twl/src/twl/autopilot/orchestrator.py`

---

## 不変条件 F: squash merge API 失敗時 rebase 禁止

- **定義**: `gh pr merge --squash` API 呼び出し失敗後は rebase を禁止しなければならない（SHALL）。停止のみ。merge 前のコンフリクト事前検知とは別概念。
- **根拠**: [ADR-023: deltaspec-free chain と TDD 直行 flow](../architecture/decisions/ADR-023-tdd-direct-flow.md) (不変条件 F は DeltaSpec spec scenario から ADR-023 に継承)
- **検証方法**: [`invariant-F: merge-gate-execute uses --squash flag`](../tests/bats/invariants/autopilot-invariants.bats)
- **影響範囲**:
  - `plugins/twl/scripts/merge-gate-checkpoint-merge.sh`
  - `cli/twl/src/twl/autopilot/mergegate.py`

---

## 不変条件 G: クラッシュ検知保証

- **定義**: Worker の crash/timeout は必ず検知されなければならない（SHALL）。
- **根拠**: [ADR-023: deltaspec-free chain と TDD 直行 flow](../architecture/decisions/ADR-023-tdd-direct-flow.md) (不変条件 G の Worker crash 検知は DeltaSpec spec scenario から ADR-023 に継承)
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
- **根拠**: [ADR-023: deltaspec-free chain と TDD 直行 flow](../architecture/decisions/ADR-023-tdd-direct-flow.md) (不変条件 I の循環依存拒否は DeltaSpec spec scenario から ADR-023 に継承)
- **検証方法**: [`invariant-I: direct circular dependency (A->B->A) rejected`](../tests/bats/invariants/autopilot-invariants.bats), [`invariant-I: indirect circular dependency (A->B->C->A) rejected`](../tests/bats/invariants/autopilot-invariants.bats)
- **影響範囲**:
  - `plugins/twl/scripts/autopilot-plan.sh`

---

## 不変条件 J: merge 前 base drift 検知

- **定義**: merge-gate 実行前に origin/main に対する silent deletion を検知し、検出時は merge を停止しなければならない（SHALL）。
- **根拠**: [ADR-023: deltaspec-free chain と TDD 直行 flow](../architecture/decisions/ADR-023-tdd-direct-flow.md) (不変条件 J の merge 前 base drift 検知は DeltaSpec spec scenario から ADR-023 に継承)
- **検証方法**: [`invariant-J: silent file deletion (no commit) is detected as base drift`](../tests/bats/invariants/autopilot-invariants.bats), [`invariant-J: intentional deletion (has commit) is not flagged`](../tests/bats/invariants/autopilot-invariants.bats)
- **影響範囲**:
  - `plugins/twl/scripts/merge-gate-checkpoint-merge.sh`

---

## 不変条件 K: Pilot 実装禁止

- **定義**: Pilot は Issue の実装（コード変更・PR 作成）を直接行ってはならない（SHALL）。実装は常に Worker 経由。Emergency Bypass 時も `mergegate merge --force` 経由のみ許可。
- **根拠**: [ADR-023: deltaspec-free chain と TDD 直行 flow](../architecture/decisions/ADR-023-tdd-direct-flow.md) (不変条件 K の Pilot 実装禁止は DeltaSpec spec scenario から ADR-023 に継承)
- **検証方法**: [`invariant-K: ref-invariants.md defines invariant K (Pilot 実装禁止)`](../tests/bats/invariants/autopilot-invariants.bats), [`invariant-K: pilot cannot write implementation-only field`](../tests/bats/invariants/autopilot-invariants.bats)
- **影響範囲**:
  - `plugins/twl/skills/co-autopilot/SKILL.md`
  - `cli/twl/src/twl/autopilot/mergegate.py`
  - `cli/twl/src/twl/autopilot/orchestrator.py`

---

## 不変条件 L: autopilot マージ実行責務

- **定義**: autopilot 時のマージ実行は Orchestrator の `mergegate.py` 経由のみでなければならない（SHALL）。Worker chain の auto-merge ステップは `merge-ready` 宣言のみを行い、マージは実行しない。
- **適用範囲**: Worker chain および Orchestrator の autopilot 実行パス。**Supervisor (su-observer) による観察介入 (intervention-catalog.md Layer 0/1) は対象外**。stall 回復のための手動 squash merge 等は Supervisor の監視責務に基づく例外として許可される (#848)。
- **根拠**: ADR なし — 慣習的制約
- **検証方法**: [`invariant-L: ref-invariants.md defines invariant L (autopilot マージ実行責務)`](../tests/bats/invariants/autopilot-invariants.bats), [`invariant-L: auto-merge.sh sets merge-ready without merging in autopilot mode`](../tests/bats/invariants/autopilot-invariants.bats)
- **影響範囲**:
  - `cli/twl/src/twl/autopilot/mergegate.py`
  - `plugins/twl/scripts/auto-merge.sh`
  - `plugins/twl/refs/intervention-catalog.md` (Supervisor 観察介入の例外定義)

---

## 不変条件 M: chain 遷移は orchestrator/手動 inject のみ

- **定義**: chain 遷移（`current_step` の terminal 検知後の次 workflow 起動）は orchestrator の `inject_next_workflow` または手動 skill inject（`/twl:workflow-<name>`）のみ許可しなければならない（SHALL）。Pilot の直接 nudge による chain bypass は禁止。
- **根拠**: [ADR-018: autopilot state schema SSOT](../architecture/decisions/ADR-018-state-schema-ssot.md) / issue-438
- **検証方法**: [`invariant-M: ref-invariants.md defines invariant M (chain 遷移制限)`](../tests/bats/invariants/autopilot-invariants.bats), [`invariant-M: co-autopilot SKILL.md prohibits direct Pilot nudge (不変条件 M)`](../tests/bats/invariants/autopilot-invariants.bats), [`invariant-M: inject-next-workflow.sh validates workflow skill name against allow-list`](../tests/bats/invariants/autopilot-invariants.bats)
- **影響範囲**:
  - `cli/twl/src/twl/autopilot/orchestrator.py`
  - `plugins/twl/scripts/chain-runner.sh`
  - `plugins/twl/skills/co-autopilot/SKILL.md`

---

## SU-* との境界

SU-1〜SU-7 は Supervisor（su-observer）固有の application-level 制約であり、本ドキュメントの不変条件 A-M とは独立した体系である。SU-* の定義は [`skills/su-observer/SKILL.md`](../skills/su-observer/SKILL.md) を参照。
