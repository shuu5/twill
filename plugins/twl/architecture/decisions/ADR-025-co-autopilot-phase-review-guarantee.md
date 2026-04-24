# ADR-025: co-autopilot phase-review guarantee

**Status**: Proposed
**Date**: 2026-04-24
**Issue**: #940
**Epic**: Phase AA Wave 1
**Related**: ADR-001 (Autopilot-first), ADR-017 (co-issue v2), #919, #946, #948, #924

---

## Context

ADR-001 (Autopilot-first) により全 Implementation は co-autopilot 経由で実行される。
Phase Z (Wave A-G1) で 14 PR が specialist review を経由せずマージされた事故 (#919) を受け、
phase-review の実行保証を多層防御で明文化する必要がある。

ADR-001 の具体化として、co-autopilot が phase-review を必ず通過させるための
構造的保証を本 ADR で定義する。#919 事故の根本原因は Observer が auto-merge.sh を直接呼び出し
chain をバイパスしたことにあり、多層防御でこの経路を封鎖する。

## Decision

chain 正規 flow における phase-review の必須保証を以下 5 レイヤーで担保する:

1. **CHAIN_STEPS 固定** (chain.py / chain-steps.sh SSoT)
   - step 10=phase-review, dispatch_mode=llm
   - workflow-pr-verify に組込済 → 正規 flow では必ず呼出

2. **auto-merge.sh 4 Layer guard** (Worker 側)
   - Layer 1: IS_AUTOPILOT=true → `status: merge-ready` 宣言のみ (merge しない)
   - Layer 2: CWD guard (worktrees/ reject)
   - Layer 3: tmux window guard (ap-#N reject)
   - Layer 4: issue-{N}.json fallback guard (#924)

3. **merge-gate-check-phase-review.sh** (Pilot 側, defense-in-depth, #439)
   - phase-review checkpoint 不在 → REJECT

4. **orchestrator inject 4 pattern 分類** (#946, PR#949)
   - silent skip 経路を failed で表面化

5. **Observer Pilot fallback 禁止運用ルール** (SKILL.md MUST NOT)
   - Observer が auto-merge.sh を直接呼んで chain をバイパスする運用を禁止
   - 詰まったら根本原因特定 → fix → chain 再実行

## Consequences

- テスト時も chain 正規 flow を強制する（phase-review をスキップした shortcut は認めない）
- Emergency bypass は ADR-001 の例外条項（retrospective 記録義務）に従う
- 5 レイヤーのいずれかが機能不全の場合は残レイヤーが safety net として機能する
- 本 ADR の適用範囲は co-autopilot 経由の全 Issue 実装フローとする

## References

- #940 (本 ADR 起票 Issue)
- #919 (Phase Z integrity 検証, 14 PR skip 事故)
- #946 (orchestrator inject 分類化, closed via PR#949)
- #948 (pilot-completion-signals, closed via PR#952)
- #924 (auto-merge Layer 4 fallback guard)
- ADR-001 (Autopilot-first)
