# ADR-044: chain SSoT 統一 — step.sh 単一 SSoT (1 step = 1 file) [Withdrawn]

**Status**: Withdrawn (2026-05-14、第 5 弾 dig Round X で案 4 registry.yaml 統合 SSoT を採用、本 ADR の案 3 step.sh framework は不採用化)

**Withdrawal Rationale**: 本 ADR は **案 3 (step.sh single SSoT)** を Decision として記述している。第 5 弾 dig (2026-05-13) で **案 4 (registry.yaml 統合 SSoT)** に方針変更され、案 3 は採用されないまま Proposed → Withdrawn に遷移した。chain SSoT 統一の最終 Decision は ADR-043 §5 + registry.yaml §3 chains を参照。本 ADR の body は **設計史 (案 3 検討プロセス)** として保存。

**Superseding decision**: [ADR-043: twill plugin radical rebuild](ADR-043-twill-radical-rebuild.md) §5 (chain SSoT 統一は registry.yaml §3 chains で実装、step.sh framework は不要)

**Related (historical)**: ADR-043 (twill plugin radical rebuild、本 ADR の上位)、ADR-020 / ADR-022 (Superseded by ADR-043)

**References**: `architecture/spec/twill-plugin-rebuild/ssot-design.html` (案 4 registry.yaml 統合 SSoT、本 ADR の案 3 は廃案)

---

## Context

twill plugin の chain 定義は ADR-022 で **3 SSoT** に正式化されていた:

1. `cli/twl/src/twl/autopilot/chain.py` `CHAIN_STEPS` (Python source SSoT、905 行 verified)
2. `plugins/twl/scripts/chain-steps.sh` (chain.py から `twl chain export --shell` で生成、98 行 computed)
3. `plugins/twl/deps.yaml.chains` (workflow metadata、5 workflow × steps)

2026-05-12 本 session で以下が verified:

- chain-runner.sh (1714 行) の case 文に CHAIN_STEPS 外 step が大量 (worktree-create / cwd-guard / board-status-update / next-step / llm-delegate / auto-merge 等)
- chain_integrity audit は 2 つの実装に分散 (validation/audit.py L198-282 と chain/integrity.py)、verify 範囲が不完全

## Decision

**chain SSoT を「step.sh 単一 SSoT」(案 3) に統一する**。詳細設計:

### 1. 1 step = 1 `*.sh` file

```
plugins/twl/scripts/steps/
├── lib/
│   ├── step.sh                  # framework (step::run helper、~80 行)
│   ├── mailbox.sh
│   └── status-board.sh
├── test-scaffold.sh             # 1 step = 1 file
├── green-impl.sh
├── check.sh
├── pr-test.sh
├── ac-verify.sh
├── phase-review.sh
├── pr-cycle-report.sh
├── merge-gate-check.sh
├── worktree-create.sh
└── ...
```

### 2. step.sh framework (~80 行)

各 step file は `step::run --name --workflow --depends --pre-check --exec --post-verify` を呼び出す。framework が:

1. pre-check (前提状態 snapshot)
2. exec (LLM 作業)
3. post-verify (機械検証 = test 数増加 / RED→GREEN / src diff 等、Inv U)
4. report (pilot mailbox に event emit)

詳細 pseudo-bash: `architecture/spec/twill-plugin-rebuild/ssot-design.html` §3.3。

### 3. `_verify_<name>()` 規約

各 step.sh 内に同名 verify 関数を必須:

```bash
_verify_test_scaffold() {
  # post-verify rule
  # - test count 増加 ≥ 1
  # - RED (test 全 fail)
  # - src/ 変更 = 0
}
```

### 4. deps.yaml.chains は metadata のみ

```yaml
chains:
  test-ready:
    description: "RED test 作成 + post-verify"
    steps:
      - test-scaffold
      - green-impl
      - check
    next_workflow: "pr-verify"
```

phase-impl SKILL.md が yq で読み、step::run を順次呼び出す。

### 5. chain-runner.sh + chain.py + chain-steps.sh 全廃

- `cli/twl/src/twl/autopilot/chain.py` (905 行) → 削除
- `plugins/twl/scripts/chain-steps.sh` (98 行) → 削除
- `plugins/twl/scripts/chain-runner.sh` (1714 行) → 削除 (case 文 dispatch 廃止)
- `twl check --deps-integrity` CLI → `twl check --steps-integrity` に rename

### 6. 新 audit section 9 (steps_integrity)

- deps.yaml.chains.<workflow>.steps に存在する全 step × `steps/<name>.sh` 存在
- step.sh 内の STEP_WORKFLOW = deps.yaml で属する workflow
- step.sh 内の `_verify_<name>` 関数定義 (Inv U post-verify 必須)
- step.sh が `step::run` framework を呼び出す (self-report-only 防止)

詳細実装: `cli/twl/src/twl/validation/steps_integrity.py` (新規、~80 行)、ssot-design.html §5。

## Consequences

### 利点

- 1 step = 1 file = 単一 SSoT (定義 + 実装 + 検証が同 file)
- chain-runner.sh case 文 bloat 全廃
- LLM が `steps/` directory listing で chain 全体を理解可能
- step 単体テスト容易 (bats per-step)
- step.sh framework が Inv U (post-verify 機械検証必須) を構造的に enforce

### コスト

- chain-runner.sh 1714 + chain.py 905 + chain-steps.sh 98 = ~2,717 行廃止
- step.sh framework + 18 step file ≈ 80 + 18×20 ≈ 440 行 (新規)
- ネット **~2,277 行削減**
- migration: Phase 2 dual-stack で旧 chain と新 step.sh 併存、Phase 3 cutover で旧廃止

### 移行段階

| Phase | chain-runner.sh | step.sh | chain.py | chain-steps.sh |
|---|---|---|---|---|
| 現状 | active 1714 行 | 不在 | active 905 | generated 98 |
| Phase 1 PoC | active | 新規 5 step (test-scaffold/green-impl/check/pr-test/merge-gate-check) | active | generated |
| Phase 2 dual | frozen | 残 step 追加 (18 step 全件) | frozen | frozen |
| Phase 3 cutover | 削除 | active (SSoT) | 削除 | 削除 |
| Phase 4 cleanup | (削除済) | active | (削除済) | (削除済) |

## Verification

- EXP-011: step::run 4 phase lifecycle 動作
- EXP-012: post-verify FAIL で step abort + escalate
- EXP-013: per-Worker mailbox scope (Inv V)
- EXP-014: bash 4.3+ local -n nameref 動作 (CI image verify)

詳細: `architecture/spec/twill-plugin-rebuild/experiment-index.html`

Phase 1 PoC 着手前に EXP-011〜014 PASS 必須。

## Supplement

本 ADR の **supplement** は `architecture/spec/twill-plugin-rebuild/ssot-design.html`:

- §1 三重化問題の verified 物証
- §2 案 1/2/3 trade-off (案 3 採用根拠)
- §3 案 3 (step.sh) 詳細設計
- §4 chain-runner.sh 廃止 migration
- §5 chain_integrity audit の置換 (steps_integrity)
- §6 Phase 1 PoC で検証する不変条件
- §7 tmux / gh CLI wrapper 粒度 (research-findings KP-7/KP-8)

## Status timeline

- 2026-05-13: Proposed (本 draft)
- **2026-05-14: Withdrawn** (第 5 弾 dig で案 4 registry.yaml 統合 SSoT に方針変更、ADR-043 §5 で superseding decision を記録)

## Related

- ADR-043: twill plugin radical rebuild (本 ADR の Decision を superseding)
- ADR-020 / ADR-022: Superseded by ADR-043 (chain SSoT 三重化境界の旧定義)
- ssot-design.html §6 verify points (案 4 採用後の verify points は registry.yaml §3 chains 経由)

---

## Withdrawal Note

本 ADR が Withdrawn になった経緯:

第 5 弾 dig (2026-05-13、`architecture/spec/twill-plugin-rebuild/dig-report-ssot-2026-05-13.md` Round 1-10) で SSoT 設計の再検討が行われ、案 3 (step.sh 単一 SSoT) より **案 4 (registry.yaml 統合 SSoT、5 section: glossary / components / chains / hooks-monitors / integrity_rules)** が以下の理由で優位と判断:

1. **単一 file での chain + vocabulary + components + audit rule の統合管理** (案 3 では step.sh + registry.yaml の二重管理)
2. **machine-verification の容易性** (registry.yaml の YAML parse + `twl audit` での integrity check 一元化)
3. **Phase 2 dual-stack への自然な拡張** (案 3 step.sh framework は new layer 追加、案 4 は既存 deps.yaml の進化系)
4. **vocabulary audit との統合** (case 4 では glossary + integrity_rules を同一 file 内で参照、`twl audit --section 11/12` で 1 file scan)

これに伴い、案 3 step.sh framework は不採用化、本 ADR は Withdrawn として Decision body を保存 (設計史)。

最終 Decision は **ADR-043 §5 (chain SSoT 統一 = registry.yaml §3 chains で実装、step.sh framework 不要)** に記録済。Phase 1 PoC seed の chain (test-ready chain) は既に registry.yaml §3 で実装済。
