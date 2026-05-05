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
   - step 10=phase-review, dispatch_mode=llm（chain-runner.sh が llm-delegate/llm-complete で管理）
   - ADR-022 D-1 による chain-runner.sh dispatch 対象 step として CHAIN_STEPS に含む
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

## Alternatives

1. **Pilot-side 単一 gate のみ**: merge-gate-check-phase-review.sh (Layer 3) のみで防御。Pilot が merge 前に phase-review checkpoint を検証するシンプルな構成。しかし Worker 側の auto-merge.sh 直呼び出し経路を封鎖できず、#919 事故と同じバイパスが再発可能。

2. **CI/CD 統合（GitHub Actions）**: phase-review の実行を GitHub Actions で強制し、PASS しなければ PR をブロック。chain 外の外部システム依存になり、co-autopilot ワークフローのローカル実行やオフライン環境での動作に影響する。また chain-runner.sh との統合点が複数生まれ複雑度が上がる。

上記 2 案は単一障害点または外部依存の問題があるため、Worker・Pilot・orchestrator の多層で独立した防御（5 レイヤー）を採用する。

## Consequences

- テスト時も chain 正規 flow を強制する（phase-review をスキップした shortcut は認めない）
- Emergency bypass は ADR-001 の例外条項（retrospective 記録義務）に従う
- 5 レイヤーのいずれかが機能不全の場合は残レイヤーが safety net として機能する
- 本 ADR の適用範囲は co-autopilot 経由の全 Issue 実装フローとする

## Known Gaps

**Known Gap 1 (解消済み)**: phase-review mode での `worker-architecture` 欠落（mode mismatch）は #971 修正 A で解消済み (`pr-review-manifest.sh:150-174` を修正し、phase-review mode でも conditional trigger で worker-architecture を追加するように変更。merge-gate の既存挙動は維持)。

**Known Gap 2 (追跡中)**: composite step LLM bypass — `commands/phase-review.md` が composite step のため、LLM が Read のみで Task spawn せず次 step に進めば検出されない（#963 actual=[]）。本 ADR では未カバー。修正 C (chain-runner.sh + chain.py での `subagent_type=*` 出現必須化、ADR-025 Layer 1 拡張) を別 Issue として追跡予定。この弱点は Layer 1 (CHAIN_STEPS 固定) が dispatch 保証のみで実行内容を検証しないことに起因する。**修正 C 完了時は本 ADR の Layer 1 記述を改訂すること（または補足 ADR を作成し本 ADR の Status を Superseded に更新すること）。**

**Known Gap 3 (追跡中)**: `SPECIALIST_AUDIT_MODE=warn` の長期化 — `specialist-audit.sh` のデフォルトが `warn` のため、audit FAIL を exit 0 で素通りしている。これは **phase-review step の実行保証（Layer 3: merge-gate-check-phase-review.sh）とは別レイヤー** の問題（audit result の severity 制御）であり、Consequences 「phase-review をスキップした shortcut は認めない」は phase-review step の実行を指し、audit result の評価方法は対象外。修正 A/G (#971) が main に入った後、false-positive 0 件を 2 週間確認してから warn → fail 昇格（修正 E）を別 Issue で実施予定。

**Known Gap 4 (解消済み, #1399)**: checkpoint isolation 欠如 — `phase-review.json` が autopilot session 全体で 1 ファイル共有のため、並列 Worker 実行時に last-writer-wins で stale な finding を merge-gate が読む race condition（Wave 40 evidence: 3 PR が false-block）。解消策: per-issue checkpoint ファイル（`checkpoints/phase-review-{ISSUE_NUMBER}.json`）を導入し、`_check_phase_review_guard` が `issue_number` 引数または `ISSUE_NUMBER` 環境変数から checkpoint ファイルを動的解決する（checkpoint isolation）。Layer 3（merge-gate-check-phase-review.sh / `_check_phase_review_guard`）の拡張として実装。既存の `phase-review.json` へのフォールバックにより後方互換性を維持。

## References

- #940 (本 ADR 起票 Issue)
- #919 (Phase Z integrity 検証, 14 PR skip 事故)
- #946 (orchestrator inject 分類化, closed via PR#949)
- #948 (pilot-completion-signals, closed via PR#952)
- #924 (auto-merge Layer 4 fallback guard)
- #439 (merge-gate-check-phase-review.sh 導入)
- ADR-001 (Autopilot-first)
- ADR-022 (chain SSoT 境界明確化)
