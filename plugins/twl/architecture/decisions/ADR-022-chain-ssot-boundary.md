# ADR-022: chain SSoT 境界明確化 — deps.yaml.chains は workflow skill 概念順の独立 SSoT

**Status**: Accepted
**Date**: 2026-04-22
**Issue**: #878
**Partially Supersedes**: ADR-020 (D-2 CHAIN_META、D-5 差分ゼロ検証)
**Related**: ADR-0007 (chain SSOT 2 レイヤー責務分離)、ADR-020 (chain SSoT refinement)、ADR-021 (pilot-driven workflow loop)

---

## Context

Phase C #867 (step 名 rename) 実施後、`twl check --deps-integrity` で以下 3 drift が未解消であることが発覚した (#878):

1. **setup.steps**: chain.py が `arch-ref` を setup 所属 (STEP_TO_WORKFLOW) に記述しているが、deps.yaml は test-ready.steps に置いている
2. **pr-merge.steps 順序**: chain.py CHAIN_STEPS L48-49 は `all-pass-check → pr-cycle-report` 順、deps.yaml と workflow-pr-merge SKILL は `pr-cycle-report → all-pass-check` 順 (workflow skill 側が実装として使用している順序)
3. **deps.yaml に chain.py 非保有 step**: deps.yaml.chains に `worktree-create`、`e2e-screening`、`merge-gate`、`auto-merge`、`fix-phase`、`post-fix-verify`、`warning-fix`、`pr-cycle-analysis`、`arch-phase-review`、`arch-fix-phase` の 10 step が存在するが、これらは `workflow-pr-fix` / `workflow-pr-merge` / `workflow-arch-review` SKILL が内部 orchestrate しており、`chain-runner.sh` は dispatch しない (dispatch_mode = llm/trigger)

ADR-020 は Proposed 状態で、以下の方針を提案していた:
- **D-2**: `CHAIN_META: dict[str, dict[str, str]]` を chain.py に追加し、llm/trigger step を含む全 step の `{chain, dispatch_mode}` を chain.py 側で保有
- **D-5**: `twl chain validate` で `CHAIN_STEPS ∪ CHAIN_META` set == deps.yaml.chains 全 step set (差分ゼロ) を検証

しかし ADR-020 D-2 を実装すると、以下のリスクが発生する:

- chain.py CHAIN_STEPS に `worktree-create`、`merge-gate`、`auto-merge` 等を追加した場合、`chain-runner.sh` の `next-step` API が「次に実行すべき step」として返す可能性があり、runner がそれらの未実装 step を dispatch しようとして runtime 破綻
- llm/trigger step の dispatch_mode を chain.py 側で正確管理するには、workflow skill 各々の内部実行順を chain.py にエンコードする必要があり、workflow skill の refactor が波及する

## Decision

**chain.py CHAIN_STEPS の SSoT 範囲を「chain-runner.sh dispatch 対象の runner step のみ」に限定し、deps.yaml.chains は workflow skill 内 orchestrate 順含む拡張 metadata として独立 SSoT とする。**

### D-1: SSoT 境界の明文化

| レイヤー | SSoT 対象 | 保有者 |
|---------|----------|--------|
| chain-runner.sh が dispatch する step の **存在と名前** | chain.py `CHAIN_STEPS` | chain.py (SSoT) |
| chain-runner.sh が dispatch する step の **bash mirror** | chain-steps.sh `CHAIN_STEPS` | chain.py からの export (computed artifact) |
| workflow skill 内 orchestrate の **step 所属 chain・実行順序** | deps.yaml.chains / workflow-*/SKILL.md | deps.yaml + SKILL.md (独立 SSoT) |

### D-2: deps-integrity 検証の緩和

`twl check --deps-integrity` は以下のみ検証する:

- chain.py `CHAIN_STEPS` == chain-steps.sh `CHAIN_STEPS` (完全一致、既存維持)
- chain.py `QUICK_SKIP_STEPS` == chain-steps.sh `QUICK_SKIP_STEPS` (完全一致、既存維持)
- chain.py `DIRECT_SKIP_STEPS` == chain-steps.sh `DIRECT_SKIP_STEPS` (完全一致、既存維持)
- **chain.py `CHAIN_STEPS ∩ STEP_TO_WORKFLOW.keys()`** ⊆ **deps.yaml.chains 全 chain flatten の step 集合** (包含のみ、所属 chain・順序は検証しない)

### D-3: ADR-020 D-2/D-5 の部分 Superseded

ADR-020 以下の提案は本 ADR により **Superseded**:

- **D-2 CHAIN_META 導入**: llm/trigger step の chain 所属・dispatch_mode を chain.py 側で保有する方針 → **棄却**。workflow skill 側の SSoT として維持
- **D-5 差分ゼロ検証**: `CHAIN_STEPS ∪ CHAIN_META` set == deps.yaml.chains 全 step set → **棄却**。chain.py CHAIN_STEPS ⊆ deps.yaml flatten に緩和

ADR-020 D-1 (名称正規化)、D-3 (export API)、D-4 (feature flag) は本 ADR の Scope 外で維持。

### D-4: workflow skill 内 orchestrate step の取扱い

`worktree-create`、`e2e-screening`、`merge-gate`、`auto-merge`、`fix-phase`、`post-fix-verify`、`warning-fix`、`pr-cycle-analysis`、`arch-phase-review`、`arch-fix-phase` の 10 step は **workflow-*/SKILL.md が SSoT**。deps.yaml.chains は workflow skill の orchestrate 順序を反映した metadata として維持する。

## Consequences

### 利点

- **Runtime 破綻リスク回避**: chain-runner.sh が未実装 step を dispatch する可能性を排除
- **現運用と整合**: 既存の workflow skill (pr-fix / pr-merge / arch-review) の orchestrate 実態を改変せず、integrity check を緩和するだけで errors=0 達成
- **実装工数最小**: `chain/integrity.py` の比較ロジック変更 (26 行) のみで完結。chain.py / deps.yaml / SKILL.md の改変不要
- **SSoT の概念明確化**: runner dispatch と workflow orchestrate の責務境界が ADR で明文化

### 懸念 / 代償

- **chain.py と deps.yaml の順序が乖離する可能性**: `chain.py CHAIN_STEPS` の `all-pass-check → pr-cycle-report` 順と、deps.yaml + workflow-pr-merge SKILL の `pr-cycle-report → all-pass-check` 順が不整合のまま許容される。これは workflow-pr-merge SKILL が内部で step を順に bash invoke するため runtime 上は問題ないが、chain.py の `next-step` API が workflow 順を反映しない可能性がある (Phase D 追加 Issue で調査)
- **viz tool との整合**: deps.yaml ベースで生成される chain-flow 図は workflow 概念順を反映する (chain.py CHAIN_STEPS 順ではない)。既存の仕様通り

### ロールバック手順

本 ADR の方針を revert する場合 (ADR-020 D-2/D-5 方針へ戻す):

1. `cli/twl/src/twl/chain/integrity.py` の flatten check を chain_name 単位の完全一致比較に戻す
2. chain.py に `CHAIN_META` 導入 (ADR-020 D-2 実装)
3. deps.yaml.chains の step 所属・順序を chain.py SSoT に揃える
4. workflow skill の内部 orchestrate を chain.py CHAIN_STEPS 順に合わせる

## Non-goal

- **chain.py と workflow-pr-merge SKILL の step 順序整合化**: `all-pass-check` と `pr-cycle-report` の順序不整合は別 Issue (Phase D) で調査する。本 ADR のスコープ外
- **CHAIN_META の将来導入**: step メタデータ (dispatch_mode, 所属 chain) が必要になった場合は、chain.py の新規 dict として追加検討 (本 ADR で廃案にしたわけではなく、必要性が再確認された時点で再提案)
- **deps.yaml.chains の step 順序検証**: workflow skill 概念順の正しさは bats テスト (#870 chain-export-drift.bats) で verify する方針 (本 ADR のスコープ外)

## 変更履歴

### #1481 (2026-05-07): post-fix-verify の deterministic dispatch への変更

`post-fix-verify` の `dispatch_mode` を `llm` から `runner` に変更し、deterministic dispatch を実現:

- **変更前**: `post-fix-verify.dispatch_mode: llm` — workflow-pr-fix SKILL が LLM 判断で specialist spawn
- **変更後**: `post-fix-verify.dispatch_mode: runner` — chain-runner.sh が `pr-review-manifest.sh` を実行し、manifest 各行に対して `claude --print --agent twl:twl:worker-codex-reviewer` 等で deterministic spawn

**背景**: 2026-05-01 以降、worker-codex-reviewer の出力がゼロになる問題（#1481）が発生。LLM 自己申告ベースの dispatch では spawn が保証されないため、deterministic runner step への移行が必要。

**影響範囲**:
- `deps.yaml` の `post-fix-verify.dispatch_mode` を `runner` に変更
- `chain-runner.sh` に `step_post_fix_verify` 関数を追加（pr-review-manifest.sh 呼び出し + deterministic spawn）
- `merge-gate-check-spawn.sh` から `SPAWNED_FILE` 自己申告を廃止し、`findings.yaml` 存在ベース判定に変更
- `specialist-audit.sh` に HARD FAIL ロジックを追加（`codex_available=YES` かつ `findings.yaml` に `worker-codex-reviewer` reason なし → exit 1）

D-4 の範囲内の変更だが、`post-fix-verify` は runner step に移行するため D-1 テーブルの分類が更新される（workflow SKILL orchestrate → chain-runner.sh dispatch）。

### #1263 (2026-05-03): fix-phase 発動条件に ac-verify CRITICAL を追加

`workflow-pr-fix` の `fix-phase` 判定を変更:

- **変更前**: `phase-review.critical_count > 0` のみが fix-phase の発動条件
- **変更後**: `phase_review_critical + ac_verify_critical > 0`（どちらか 1 以上で発動）

変更対象:
- `plugins/twl/commands/fix-phase.md` — checkpoint 読み込みと発動条件を更新
- `plugins/twl/skills/workflow-pr-fix/SKILL.md` — fix ループ条件の記述を更新
- `plugins/twl/skills/co-autopilot/SKILL.md` — TDD GREEN phase 完遂ルール追加（禁止事項）
- `plugins/twl/refs/pr-merge-chain-steps.md` — fix-phase セクションに ac-verify CRITICAL 判定を明記

この変更は D-4（workflow skill 内 orchestrate step の取扱い）の範囲内であり、chain.py CHAIN_STEPS や chain-steps.sh には影響しない。
