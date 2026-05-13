# 不変条件 A-X 参照ドキュメント

twill autopilot システムの不変条件 A-X（24 件）の正典定義。各条件の定義・根拠・検証方法・影響範囲を一本化する。

更新日: 2026-05-13 (第 5 弾 dig 反映、A-N 14 件 → A-S 19 件 → A-X 24 件に拡張、新規 T-X 5 件追加、ADR-043 由来)

## 本ドキュメントの SSoT 位置付け

本ドキュメントは不変条件 A-X の **Authority SSoT（Single Source of Truth）** であり、各 invariant の定義・意味は本ドキュメント自身で自己完結する。

- **「根拠」欄の役割**: 設計判断の出典 ADR または導入された背景を示す。ADR が invariant の詳細仕様を個別定義しない場合でも、invariant の実装整合性は **検証方法欄の bats test** と **影響範囲欄の実装ファイル** で維持される。
- **ADR-023 継承について**: 不変条件 D/E/F/G/I/J/K は Phase Z (#901) の chain 再設計に伴い [ADR-023](../architecture/decisions/ADR-023-tdd-direct-flow.md) に継承された。ADR-023 は chain 構造変更の ADR であり individual invariant の詳細仕様は持たないが、invariant の意味定義は本ドキュメント自身が SSoT として保持し、検証は bats test (`../tests/bats/invariants/autopilot-invariants.bats`) が担保する。
- **不変条件 B の 2 根拠保持**: 不変条件 B のみ ADR-008 + ADR-023 の 2 根拠を明示しているのは、ADR-008 が Worktree ライフサイクル単独の独立 ADR として成立しているため。他の invariant (D/E/F/G/I/J/K) は対応する独立 ADR が存在しないため、ADR-023 を継承先として単一参照する。
- **第 5 弾 dig (2026-05-13) 由来の用語 rename**: 旧 Pilot/Worker entity を新 phaser/specialist+atomic/workflow entity に rename。各 invariant の「定義」欄は新用語で記述するが、「検証方法」「影響範囲」path は既存 file (worker-* / pilot.sh / chain-runner.sh 等) を保全 (Phase 4 cleanup で実 file rename 完了時に path も連動更新予定)。
- **新規 invariant T-X 追加**: ADR-043 由来の 5 件 (T mailbox atomic / U Atomic skill verification / V per-specialist scope / W gate hook / X deploy-verify セット) を本 doc 末尾に追加。Inv U は第 5 弾 dig で「Step verification framework」→「Atomic skill verification」に rename + bats file 名を `atomic-verification-post-verify.bats` に変更予定。

---

## 不変条件 A: 状態の一意性

- **定義**: `issue-{N}.json` の `status` は常に定義された遷移パスのみ許可されなければならない（SHALL）。不正な状態遷移は拒否される。
- **根拠**: ADR なし — 慣習的制約
- **検証方法**: [`invariant-A: parallel writes to same issue produce valid JSON`](../tests/bats/invariants/autopilot-invariants.bats)
- **影響範囲**:
  - `cli/twl/src/twl/autopilot/state.py`
  - `cli/twl/src/twl/autopilot/orchestrator.py`

---

## 不変条件 B: Worktree ライフサイクル phaser 専任

- **定義**: Worktree の作成・削除は phaser (旧 Pilot、L1 role) が行わなければならない（SHALL）。下位 role (atomic / specialist) は使用のみ。
- **根拠**: [ADR-008: Worktree Lifecycle Pilot Ownership](../architecture/decisions/ADR-008-worktree-lifecycle-pilot-ownership.md) / [ADR-023](../architecture/decisions/ADR-023-tdd-direct-flow.md)
- **検証方法**: [`invariant-B: worktree-delete rejects worker role`](../tests/bats/invariants/autopilot-invariants.bats), [`invariant-B: Worker chain (chain-steps.sh) does not include worktree-create`](../tests/bats/invariants/autopilot-invariants.bats)
- **影響範囲**:
  - `plugins/twl/scripts/worktree-delete.sh`
  - `plugins/twl/scripts/chain-runner.sh`
  - `plugins/twl/scripts/autopilot-orchestrator.sh`

---

## 不変条件 C: specialist/atomic マージ禁止

- **定義**: 下位 role (specialist (旧 Worker subagent) / atomic (workflow chain の最小単位)) は `merge-ready` を宣言するのみでなければならない（SHALL）。マージは phaser-pr (旧 Pilot for PR phase) が実行する。下位 role が直接 `gh pr merge` を実行してはならない。
- **根拠**: ADR なし — 慣習的制約
- **検証方法**: [`invariant-C: merge-gate-execute rejects invalid ISSUE`](../tests/bats/invariants/autopilot-invariants.bats)
- **影響範囲**:
  - `plugins/twl/scripts/auto-merge.sh`
  - `plugins/twl/scripts/merge-gate-checkpoint-merge.sh`
  - `cli/twl/src/twl/autopilot/mergegate.py`

---

## 不変条件 D: 依存先 fail 時の skip 伝播

- **定義**: Phase N で fail した Issue に依存する Issue は自動 skip されなければならない（SHALL）。
- **根拠**: [ADR-023](../architecture/decisions/ADR-023-tdd-direct-flow.md)
- **検証方法**: [`invariant-D: single dependency fail causes skip`](../tests/bats/invariants/autopilot-invariants.bats), [`invariant-D: multiple deps with one failed causes skip`](../tests/bats/invariants/autopilot-invariants.bats)
- **影響範囲**:
  - `plugins/twl/scripts/autopilot-plan.sh`
  - `cli/twl/src/twl/autopilot/orchestrator.py`

---

## 不変条件 E: merge-gate リトライ制限

- **定義**: merge-gate のリトライは最大 1 回でなければならない（SHALL）。2 回目リジェクト = 確定失敗。
- **根拠**: [ADR-023](../architecture/decisions/ADR-023-tdd-direct-flow.md)
- **検証方法**: [`invariant-E: first retry allowed`](../tests/bats/invariants/autopilot-invariants.bats), [`invariant-E: second retry rejected`](../tests/bats/invariants/autopilot-invariants.bats)
- **影響範囲**:
  - `plugins/twl/scripts/merge-gate-checkpoint-merge.sh`
  - `cli/twl/src/twl/autopilot/orchestrator.py`

---

## 不変条件 F: squash merge API 失敗時 rebase 禁止

- **定義**: `gh pr merge --squash` API 呼び出し失敗後は rebase を禁止しなければならない（SHALL）。停止のみ。merge 前のコンフリクト事前検知とは別概念。
- **根拠**: [ADR-023](../architecture/decisions/ADR-023-tdd-direct-flow.md)
- **検証方法**: [`invariant-F: merge-gate-execute uses --squash flag`](../tests/bats/invariants/autopilot-invariants.bats)
- **影響範囲**:
  - `plugins/twl/scripts/merge-gate-checkpoint-merge.sh`
  - `cli/twl/src/twl/autopilot/mergegate.py`

---

## 不変条件 G: クラッシュ検知保証

- **定義**: Worker の crash/timeout は必ず検知されなければならない（SHALL）。
- **根拠**: [ADR-023](../architecture/decisions/ADR-023-tdd-direct-flow.md)
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
- **根拠**: [ADR-023](../architecture/decisions/ADR-023-tdd-direct-flow.md)
- **検証方法**: [`invariant-I: direct circular dependency (A->B->A) rejected`](../tests/bats/invariants/autopilot-invariants.bats), [`invariant-I: indirect circular dependency (A->B->C->A) rejected`](../tests/bats/invariants/autopilot-invariants.bats)
- **影響範囲**:
  - `plugins/twl/scripts/autopilot-plan.sh`

---

## 不変条件 J: merge 前 base drift 検知

- **定義**: merge-gate 実行前に origin/main に対する silent deletion を検知し、検出時は merge を停止しなければならない（SHALL）。
- **根拠**: [ADR-023](../architecture/decisions/ADR-023-tdd-direct-flow.md)
- **検証方法**: [`invariant-J: silent file deletion (no commit) is detected as base drift`](../tests/bats/invariants/autopilot-invariants.bats), [`invariant-J: intentional deletion (has commit) is not flagged`](../tests/bats/invariants/autopilot-invariants.bats)
- **影響範囲**:
  - `plugins/twl/scripts/merge-gate-checkpoint-merge.sh`

---

## 不変条件 K: phaser 実装禁止

- **定義**: phaser (旧 Pilot、L1 role) は Issue の実装（コード変更・PR 作成）を直接行ってはならない（SHALL）。実装は常に下位 role (workflow → atomic、必要時 specialist via Agent()) 経由。Emergency Bypass 時も `mergegate merge --force` 経由のみ許可。
- **根拠**: [ADR-023](../architecture/decisions/ADR-023-tdd-direct-flow.md)
- **検証方法**: [`invariant-K: ref-invariants.md defines invariant K (Pilot 実装禁止)`](../tests/bats/invariants/autopilot-invariants.bats), [`invariant-K: pilot cannot write implementation-only field`](../tests/bats/invariants/autopilot-invariants.bats)
- **影響範囲**:
  - `plugins/twl/skills/co-autopilot/SKILL.md`
  - `cli/twl/src/twl/autopilot/mergegate.py`
  - `cli/twl/src/twl/autopilot/orchestrator.py`

---

## 不変条件 L: autopilot マージ実行責務

- **定義**: autopilot 時のマージ実行は Orchestrator の `mergegate.py` 経由のみでなければならない（SHALL）。下位 role (workflow/atomic) の auto-merge ステップは `merge-ready` 宣言のみを行い、マージは実行しない。第 5 弾 dig 後は `administrator` polling cycle が旧 Orchestrator を代替。
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

<a id="invariant-n-lesson-structuralization"></a>

## 不変条件 N: Lesson Structuralization

- **定義**: 任意の lesson（observer-pitfall / observer-lesson / observer-wave 等）を doobidoo に保存した後、以下のチェーンを完遂しない限り「完遂」と扱わない（SHALL）:
  1. doobidoo 保存
  2. Issue 起票（`gh issue create` for follow-up implementation）
  3. Wave 実装（skill/refs/scripts 反映 PR）
  4. 永続文書化（pitfalls-catalog / SKILL.md / ADR）
- **適用範囲**: observer/Pilot が lesson を認識・記録する全ての文脈。
- **根拠**: [ADR-036: Lesson Structuralization MUST](../architecture/decisions/ADR-036-lesson-structuralization.md)
- **検証方法**: [`invariant-N: ref-invariants.md defines invariant N (Lesson Structuralization)`](../tests/bats/issue-1517-lesson-structuralization.bats), [`invariant-N: su-observer SKILL.md Step 1 contains lesson MUST chain`](../tests/bats/issue-1517-lesson-structuralization.bats), [`invariant-N: pitfalls-catalog §19 documents lesson structuralization pitfalls`](../tests/bats/issue-1517-lesson-structuralization.bats)
- **影響範囲**:
  - `plugins/twl/skills/su-observer/SKILL.md`
  - `plugins/twl/skills/su-observer/refs/pitfalls-catalog.md`
  - `plugins/twl/architecture/decisions/ADR-036-lesson-structuralization.md`

---

## 不変条件 O: session.json の claude_session_id は UUID v4 または空文字列のみ（#1552）

**目的**: `cld --observer` が非 UUID 値を `claude --resume` に渡して resume 失敗する P0 バグを防ぐ。

**制約**:
- `session.json` の `claude_session_id` および `predecessor.claude_session_id` には UUID v4 形式（`^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`）または空文字列のみを格納する
- LLM による `claude_session_id` の direct-edit は MUST NOT
- `claude_session_id` の更新は `session-init.sh` / `su-postcompact.sh` のみが行う
- phase 情報（例: `post-compact-YYYY-MM-DDTHH:MM-wNN`）は `phase_handoff` フィールドに格納すること

**違反検知**:
- `session-init.sh` / `su-postcompact.sh` は書き込み前に UUID v4 regex assert を行い、違反時は WARN を出力してその field の書き込みを skip する
- `cld --observer` は読み取り直後に UUID v4 check を行い、違反時は actionable error を出力して `exit 1` する

**影響範囲**:
  - `plugins/twl/skills/su-observer/scripts/session-init.sh`
  - `plugins/twl/scripts/su-postcompact.sh`
  - `plugins/session/scripts/cld`
  - `plugins/twl/skills/su-observer/refs/session-schema.md`

---

## 不変条件 P: Issue 起票 flow 大原則 (SHALL)

**目的**: 新規 Issue の起票 (`gh issue create`) は co-explore による explore-summary 作成を precondition として満たさなければならない (SHALL)。bypass は `SKIP_ISSUE_GATE=1 SKIP_ISSUE_REASON='<reason>'` の明示的併用のみ許可される。

**制約**:
- 新規 Issue の起票は以下いずれかの precondition を満たすこと (SHALL):
  1. **co-explore bootstrap path**: `TWL_CALLER_AUTHZ=co-explore-bootstrap` env marker + `/tmp/.co-explore-bootstrap-*.json` state file
  2. **co-issue Phase 4 create path**: `TWL_CALLER_AUTHZ=co-issue-phase4-create` env marker + `.controller-issue/<sid>/explore-summary.md` 存在
  3. **co-issue session in-flight path**: `/tmp/.co-issue-phase3-gate-*.json` 存在
  4. **明示的 bypass**: `SKIP_ISSUE_GATE=1 SKIP_ISSUE_REASON='<reason>'` の明示的併用 (intervention 記録 MUST)
- 上記以外の経路 (observer 直接 / Pilot 直接 / PR review 起点 / 手動) は deny される
- `SKIP_ISSUE_GATE=1` のみ (`SKIP_ISSUE_REASON` 欠落) は deny する

**適用範囲**: observer / Pilot / co-explore / co-issue / 手動 すべての `gh issue create` 経路 (GraphQL `gh api graphql` mutation は本 invariant の射程外、後継 Issue で追跡)

**根拠**: [ADR-037: Issue 作成 flow 大原則の正典化と enforcement 階層](../architecture/decisions/ADR-037-issue-creation-flow-canonicalization.md)

**検証方法**: bats `pre-bash-issue-create-gate.bats` (S1-S12)、pytest `test_validate_issue_create.py`

**影響範囲**:
  - `plugins/twl/scripts/hooks/pre-bash-issue-create-gate.sh`
  - `cli/twl/src/twl/mcp_server/tools.py` (`twl_validate_issue_create_handler`)
  - `plugins/twl/skills/co-explore/SKILL.md`
  - `plugins/twl/skills/co-issue/SKILL.md`
  - `plugins/twl/agents/su-observer/SKILL.md`
  - `plugins/twl/skills/co-autopilot/SKILL.md`

---

## 不変条件 Q: budget status line `(YYm)` format 解釈 (MUST) {#invariant-q}

<a id="invariant-q"></a>

**目的**: `5h:XX%(YYm)` の `(YYm)` は「次回 5h cycle reset までの wall-clock remaining（分）」であり、消費可能 token 残量ではない。reset 時点で budget は `5h:0%` に完全回復する。この解釈を MUST とする。

**制約**:
- `(YYm)` を「制限時間」「token 残量 YY分」「あと YY 分しか使えない」と読んではならない
- `(YYm)` は cycle reset までの wall-clock であり、reset 後は 5h budget が 100% 完全回復する
- `ScheduleWakeup` の `delaySeconds` は `(YYm) × 60 + 300`（cycle reset + 5 分余裕）を基準とすること

**正解例**:
- `5h:57%(26m)` → 26 分後に cycle reset、budget 100% 完全回復
- `5h:88%(8m)` → 8 分後に cycle reset、budget 100% 完全回復（8 分＋5 分余裕 = 780 秒で `ScheduleWakeup`）

**根拠**: doobidoo hash `f561e780` / `fa633006` の繰返し誤読観測（複数 session で 5+ 回誤読発生）

**検証方法**: bats `ref-invariants-budget.bats`、`pitfalls-budget-format.bats`、`skill-step0-budget-aware.bats`

**影響範囲**:
  - `plugins/twl/skills/su-observer/refs/pitfalls-catalog.md §4.6`
  - `plugins/twl/skills/su-observer/SKILL.md` Step 0 サブステップ 2.6
  - `plugins/twl/skills/su-observer/scripts/budget-detect.sh`
  - `plugins/twl/skills/su-observer/refs/monitor-channel-catalog.md §BUDGET-LOW`

---

## 不変条件 R: content-REJECT override 禁止 (#1613)

**目的**: merge-gate が content レベルで REJECT を返した PR (例: RED-only / AC 未達 / specialist CRITICAL) を Pilot が手動 `gh pr merge` で bypass することを禁止する。PR #1608 (Wave 90) で `merge-gate.json` が FAIL を書いたにも関わらず Pilot が手動 merge し test 11 件 RED を main に滞留させた regression の再発防止。

**制約**:
- merge-gate `status=FAIL` (REJECTED) 状態の PR で `gh pr merge` を実行してはならない (MUST NOT)
- override が必要な場合は `TWL_MERGE_GATE_OVERRIDE='<理由>'` env と専用 audit log への記録を併用すること
- stall recovery (不変条件 L パターン 8) と content-REJECT override は別カテゴリ。前者は Supervisor 観察介入として許可されるが、後者は本 invariant により禁止される
- `red-only` label 付与による specialist SKIP 経路は廃止 — label が付いていても worker-red-only-detector は WARNING を発行し、follow-up Issue (GREEN 実装 PR) の存在を verify する責務を負う

**違反検知**:
- `plugins/twl/scripts/merge-gate-check-merge-override-block.sh` が `gh pr merge` 直前に `merge-gate.json` を読み、FAIL 状態かつ override 未設定の場合は exit 1 で block する
- override 経路は `<autopilot-dir>/merge-override-audit.log` に user / 時刻 / 理由を記録

**根拠**: Issue #1613 explore-summary (PR #1608 timeline 解析) — content-REJECT を stall recovery 経路で処理した運用ルール曖昧 + label 二重設計の言い訳経路 + comment 表示の真偽値矛盾の 3 真因に対する defense-in-depth Layer 4 (human gate)

**検証方法**: bats `ac-scaffold-tests-1613.bats` (ac1a/ac1b/ac1c) — `merge-gate-check-merge-override-block.sh` が FAIL 状態で exit 1 を返し、`TWL_MERGE_GATE_OVERRIDE` 設定時のみ通過し audit log に記録すること

**影響範囲**:
  - `plugins/twl/scripts/merge-gate-check-merge-override-block.sh`
  - `plugins/twl/scripts/red-only-followup-create.sh`
  - `plugins/twl/scripts/worker-red-only-detector.sh` (red-only label の WARNING 降格)
  - `plugins/twl/agents/worker-red-only-detector.md`
  - `plugins/twl/scripts/chain-runner.sh` (`step_pr_comment_final` LIGHT-ERROR consistency check)

---

## 不変条件 S: RED-only label-based bypass の構造的閉塞 (#1626)

**目的**: `red-only` ラベルの付与だけで `worker-red-only-detector` の WARNING 降格 + merge-gate 通過を実現する escape hatch を機械強制で閉塞する。Wave 90/91/92 連続 4 件の RED-only merge 事故 (PR #1608/#1616/#1617/#1623) において、不変条件 R 実装後も「label 付与 → WARNING 降格 → label 付き = 正規 RED PR とみなして merge」の構造的バイパス経路が残存していたため、follow-up Issue 存在の AND 条件 + PreToolUse hook + Layer 1 fail-closed の三層 defense-in-depth で閉塞する。

**制約**:
- `red-only` ラベル付き PR で変更ファイルが test のみの場合、`worker-red-only-detector.sh` は follow-up Issue (`<!-- follow-up-for: PR #N -->` marker 付き body を持つ Issue) の存在を **AND 条件**として検証する (MUST)
  - follow-up 存在 → severity = **WARNING** (TDD RED phase 正規 path、merge 可)
  - follow-up 不在 → severity = **CRITICAL 昇格** (escape hatch 閉鎖、confidence 90、merge block)
  - gh 失敗 / PR_NUMBER 不明 → graceful skip (WARNING 維持、既存テスト互換)
- `merge-gate-check-red-only.sh` は変更ファイルリスト取得失敗時に `gh pr view --json files` で fallback を試み、双方失敗時は **fail-closed REJECT** を返す (MUST)。silent PASS (exit 0) は禁止
- `red-only-followup-create.sh` が生成する follow-up Issue の body には `<!-- follow-up-for: PR #N -->` marker を必ず含む (MUST)。ローカルフィルタ検索で識別可能な唯一の根拠
- merge-gate REJECT 時かつ red-only ラベル付き PR は follow-up Issue を自動起票する (SHOULD)。idempotent: marker 存在確認で重複起票を防ぐ
- `pre-bash-merge-gate-block.sh` PreToolUse hook が `gh pr merge` / `auto-merge.sh` 実行時に merge-gate.json status を verify する (MUST)。auto-merge.sh 経由も含む一律 block (Pilot/main session の bypass を防ぐ)

**違反検知**:
- `plugins/twl/scripts/worker-red-only-detector.sh`: follow-up 不在時に CRITICAL を出力 (severity 昇格)
- `plugins/twl/scripts/merge-gate-check-red-only.sh`: REJECT path で `red-only-followup-create.sh` を idempotent invoke + Layer 1 fail-closed (`gh pr view` fallback)
- `plugins/twl/scripts/hooks/pre-bash-merge-gate-block.sh`: `gh pr merge` / `auto-merge.sh` 実行時に merge-gate FAIL を検出して `permissionDecision=deny` を返す (PreToolUse hook 経由)
- bats: `int-1626-followup-verify-and-condition.bats` (5 test) / `int-1626-followup-auto-create-on-reject.bats` (4 test) / `int-1626-pre-bash-hook-blocks-gh-pr-merge.bats` (8 test) / `int-1626-layer1-fail-closed-on-fetch-failure.bats` (5 test) / `int-1626-warning-fix-cannot-add-red-only-label.bats` (3 test)

**根拠**: Issue #1626 explore-summary (`.explore/1626/summary.md`、363 行) — 不変条件 R で実装された 5 layer defense-in-depth の構造的不完全部分 (AC1/AC3 production flow 統合不在 + AC2 escape hatch + Layer 1 fail-open) を、TDD RED phase の正規利用を維持しつつ機械強制で閉塞する。lesson 28 (ADR-038): 「Worker self-discipline + SKILL prompt 警告では構造的 fix 不可、機械強制 (chain-runner + auto-merge + hook) の多層防御が必須」(Wave 90/91/92 で実証)

**検証方法**: bats `int-1626-*.bats` (5 ファイル、25 test、本 Issue で追加)、`ac-scaffold-tests-1613.bats` 14/14 GREEN regression 維持

**影響範囲**:
  - `plugins/twl/scripts/worker-red-only-detector.sh` (AC1 follow-up AND 条件)
  - `plugins/twl/scripts/merge-gate-check-red-only.sh` (AC2 followup auto-invoke + AC4 fail-closed)
  - `plugins/twl/scripts/red-only-followup-create.sh` (AC1.4 marker 追加)
  - `plugins/twl/scripts/hooks/pre-bash-merge-gate-block.sh` (AC3 新設 hook)
  - `plugins/twl/agents/worker-red-only-detector.md` (AC1.5 出力スキーマ更新)
  - `.claude/settings.json` (AC3.8 hook 登録)
  - `plugins/twl/architecture/decisions/ADR-038-lesson-28-red-only-label-bypass-closure.md` (lesson 永続文書化)

**対象外**: GitHub Web UI / `gh api graphql` 直接呼び出しの block (本 Issue scope 外、別 Issue で branch protection rule で対応)

---

## 不変条件 T: file mailbox atomic write 必須

- **目的**: 9 P0 bug の #1703 (phase-review.json cross-pollution) を構造的に不能化する。
- **制約**:
  - 全 mailbox write は **`flock` を取得した atomic write** を MUST とする
  - mailbox path は `.mailbox/<session-name>/inbox.jsonl` の per-session 形式
  - 共通 path への write は禁止 (横断要因 F-1 の構造的解消)
  - mailbox write には必ず `{"from": "<sender>", "ts": "<iso8601>", ...}` を含める (sender tracking)
- **違反検知**: bats `file-mailbox-atomic-write.bats` で並列 write race condition を検証 (新規 EXP-006)。flock 不使用 / 共通 path write は CRITICAL severity で audit fail
- **根拠**: [ADR-043](../architecture/decisions/ADR-043-twill-radical-rebuild.md) Decision §3 (file mailbox 4 階層 entity)、9 P0 bug 分析の Bug #1703 lesson、横断要因 F-1
- **検証方法**: bats `file-mailbox-atomic-write.bats` (新規)、`twl audit --registry` で registry.yaml `mailbox` entity の forbidden (events / .supervisor/events/) を検出
- **影響範囲**:
  - `plugins/twl/scripts/mailbox.sh` (新規 helper、Phase 1 PoC で作成)
  - 全 phaser / specialist / atomic SKILL.md (mail write 経路)

---

## 不変条件 U: Atomic skill verification

- **目的**: 9 P0 bug の #973 (RED merge silent rot)、L1873-1884 自己申告 step を構造的に不能化する。第 5 弾 dig で「Step verification framework」→「Atomic skill verification」に rename + atomic SKILL.md inline 実装に変更。
- **制約**:
  - 全 atomic skill 呼び出しは **4-phase lifecycle (pre-check → exec → post-verify → report)** を atomic SKILL.md 本文に **inline 実装** することを MUST
  - post-verify で機械検証 (test 数増加 / RED→GREEN / src diff / Agent return value 等) を **必ず実施**
  - self-report-only (record_current_step + ok のみ) は禁止
  - post-verify FAIL → atomic abort + phaser escalate (mail に failure 明記)
  - 旧 `step.sh framework` 外部 bash 呼び出しは廃止 (案 3 step.sh 単一 SSoT は第 5 弾 dig で廃案、案 4 registry.yaml + atomic SKILL.md inline に進化)
- **違反検知**: bats `atomic-verification-post-verify.bats` (新規、旧 step-verification-post-verify.bats から rename) で 4-phase 動作 + post-verify FAIL 時の escalate mail emit を検証 (EXP-011 + EXP-012 repurpose)
- **根拠**: [ADR-043](../architecture/decisions/ADR-043-twill-radical-rebuild.md) Decision §4 (Atomic skill verification)、9 P0 bug 分析の Bug #973 lesson、L1873-1884 自己申告 step 問題
- **検証方法**: bats `atomic-verification-post-verify.bats` (新規)、test なしで green-impl 呼び出すと atomic abort することを verify。EXP-011 (4-phase lifecycle) + EXP-012 (post-verify FAIL escalate) で実機検証
- **影響範囲**:
  - 全 atomic SKILL.md (`plugins/twl/skills/atomic-*/SKILL.md`、Phase 1 PoC で作成、4-phase lifecycle inline 実装 MUST)
  - 全 workflow SKILL.md (`plugins/twl/skills/workflow-*/SKILL.md`、atomic を `Skill()` で順次呼ぶ)
  - 旧 `plugins/twl/scripts/step.sh` (Phase 3 cutover で全廃)

---

## 不変条件 V: per-specialist checkpoint path (共通 path 禁止)

- **目的**: 9 P0 bug の #1703 (checkpoint cross-pollution) + #1673 (cleanup cross-Wave 破壊) を構造的に不能化する。
- **制約**:
  - 全 state / cleanup / checkpoint write は **per-specialist (issue_number / session_name) を含むパス** にデフォルト書き込み
  - 共通パスへの write は明示的 `--shared` フラグ + audit log 必須
  - cleanup スクリプトは `--scope <wave-id>` を必須引数とし、他 Wave のリソースに触れない
  - per-phaser worktree scope (phaser-impl-<issue> 等) で隔離
- **違反検知**: bats `per-specialist-state-isolation.bats` (新規) で複数 specialist simulation の cross-pollution を検証
- **根拠**: [ADR-043](../architecture/decisions/ADR-043-twill-radical-rebuild.md) Decision §3 (file mailbox per-session)、9 P0 bug 分析の Bug #1703, #1673 lesson、横断要因 F-1
- **検証方法**: bats `per-specialist-state-isolation.bats` (新規)、複数 specialist simulation で他 specialist の state を読み書きしないことを verify
- **影響範囲**:
  - `cli/twl/src/twl/autopilot/checkpoint.py` の `_checkpoint_dir()` (per-issue 必須化、`--shared` 明示なしは fail)
  - `plugins/twl/scripts/autopilot-cleanup.sh` (`--scope` 必須化、または完全廃止)

---

## 不変条件 W: PreToolUse hook で status gate 機械化

- **目的**: 9 P0 bug の #1660 / #1662 / #1663 / #1684 (env var 経由 caller authz) を構造的に不能化する。
- **制約**:
  - phaser-* invocation は **PreToolUse hook 経由で前提 status を verify** することを MUST
  - bash env var (`TWL_CALLER_AUTHZ` 等) による caller authz は廃止
  - gate hook handler (旧 `phase-gate.sh`、第 5 弾 dig で「gate hook handler」概念に統一) thin helper (~30 lines) で実装、status 不一致は exit 2 + administrator notify
  - tier 1 (`command` hook) + tier 2 (`mcp_tool` hook = `twl_phase_gate_check`) の階層防御、bypassPermissions でも貫通 (verified)
- **違反検知**: bats `gate-hook.bats` (新規、旧 phase-gate-hook.bats から rename 推奨) で Refined でない Issue に phaser-impl を invoke して deny されることを verify (EXP-001〜003 + EXP-007〜008)
- **根拠**: [ADR-043](../architecture/decisions/ADR-043-twill-radical-rebuild.md) Decision §6 (PreToolUse hook + MCP shadow tier 階層防御)、9 P0 bug 分析の Bug #1660/1662/1663/1684 lesson、横断要因 F-2
- **検証方法**: bats `gate-hook.bats` (新規)、Refined でない Issue に phaser-impl を呼び出すと deny されることを verify
- **影響範囲**:
  - `plugins/twl/scripts/hooks/gate-hook-handler.sh` (新規 helper、旧 phase-gate.sh から rename)
  - `plugins/twl/hooks/hooks.json` (PreToolUse hook 設定、registry.yaml hooks section から auto-gen)
  - 既存 `TWL_CALLER_AUTHZ` 機構の廃止 (chain-runner.sh / observer-parallel-check.sh 等)

---

## 不変条件 X: deploy / verify セット必須 (daemon / watchdog)

- **目的**: 9 P0 bug の #1687 (mcp-watchdog deploy 経路不在、5 ヶ月 5 回再発) を構造的に不能化する。
- **制約**:
  - 新規 daemon / watchdog 実装は **「起動 hook」+「起動確認テスト」セット** で merge することを MUST
  - 起動 hook (session-start hook 等) と起動確認 test (bats で `ps` / `pgrep` 確認) を **同 PR 内に含む**
  - N 回 (N≥2) 再発するバグは **修正ではなく root cause 分析** を required (epic / spike issue 化)
  - Plugin Monitor (`plugins/twl/monitors/monitors.json`) で deploy + verify を一体化、自前 watchdog 廃止
- **違反検知**: bats `daemon-deploy-verify-set.bats` (新規) で新規 watchdog 系 PR の起動 hook ファイル追加を assert
- **根拠**: [ADR-043](../architecture/decisions/ADR-043-twill-radical-rebuild.md) Decision §2 (Plugin Monitor 採用)、9 P0 bug 分析の Bug #1687 lesson、横断要因 F-3
- **検証方法**: bats `daemon-deploy-verify-set.bats` (新規)、新規 watchdog 系 PR は起動 hook ファイルの追加を assert
- **影響範囲**:
  - `plugins/twl/hooks/hooks.json` 配下の hook 登録規約
  - `plugins/twl/monitors/monitors.json` (Plugin Monitor 設定、registry.yaml monitors section から auto-gen)
  - `plugins/twl/tests/bats/` 配下の daemon verification test
  - 新 spec の `architecture/spec/twill-plugin-rebuild/rebuild-plan.html` (本 invariant を `Phase 1 PoC` の verify points VP-X として含める)

---

## SU-* との境界

SU-1〜SU-9 は Supervisor（su-observer）固有の application-level 制約であり、本ドキュメントの不変条件 A-X (24 件) とは独立した体系である。SU-* の正典は [`architecture/domain/contexts/supervision.md`](../architecture/domain/contexts/supervision.md)（SSoT）。運用 mirror は [`skills/su-observer/refs/su-observer-constraints.md`](../skills/su-observer/refs/su-observer-constraints.md) を参照。Security gate (Layer A-D) 定義は [`skills/su-observer/refs/su-observer-security-gate.md`](../skills/su-observer/refs/su-observer-security-gate.md) を参照。
