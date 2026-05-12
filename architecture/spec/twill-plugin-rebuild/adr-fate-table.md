# ADR 43 件 fate audit — 新 spec での継承戦略

> **目的**: 既存 `architecture/decisions/` 配下 43 件 ADR を 1 件ずつ audit し、新 spec での fate (保全 / Superseded by ADR-043 / 部分 Superseded / 削除 / 統合) を決定する。
>
> **status**: draft-v2、user 承認後に ADR-043 起票時の Superseded chain の正典として運用する。

---

## 集計

| fate | 件数 |
|---|---|
| 保全 (新 spec でも有効、変更なし) | 22 |
| 部分 Superseded (新 spec で一部置換、残りは有効) | 9 |
| Superseded by ADR-043 (新 spec で完全置換) | 6 |
| Superseded by 他 ADR (既存 chain、ADR-043 と無関係) | 2 |
| 正規化要 (番号重複等の課題) | 1 (ADR-037 重複) |
| Proposed のまま (実装待ち、新 spec で吸収) | 3 |

合計 43 (実際は ADR-037 が 2 件あるので 42 ファイル + 1 重複 = 43 件)。

---

## 全件 fate table

| ADR | 主題 | Status | fate | 根拠 |
|---|---|---|---|---|
| ADR-001 | Autopilot-first 原則 | Accepted | **保全** | phase-* spawn 設計の根幹原則、新 spec でも有効 |
| ADR-002 | Controller 統合 | Accepted | **保全** | phase-* / tool-* 分類の根幹、controller 概念は維持 |
| ADR-003 | 統一 state file (`issue-{N}.json`) | Accepted | **部分 Superseded** | 新 spec で file mailbox (`.mailbox/<session>/inbox.jsonl`) に発展、`issue-{N}.json` の role は status SSoT が GitHub Project Board に移譲される分縮小 |
| ADR-004 | Output 標準化 | Accepted | **保全** | worker 出力フォーマット規約、step verification の `--detail` field 設計に継承 |
| ADR-005 | self-improve review | Accepted | **保全** | tool-self-improve に rebrand |
| ADR-006 | Project Board 必須化 (Board = Issue status SSoT) | Accepted | **保全 (強化)** | 新 spec の核心、6-stage 拡張で発展 (Idea/Explored/Refined/Implementing/PR Reviewed/Merged) |
| ADR-007 | クロスリポジトリプロジェクト管理 | Accepted | **保全** | tool-project に rebrand |
| ADR-008 | Worktree lifecycle Pilot 専任 | Accepted | **保全** | 不変条件 B の根拠、新 spec でも全層 tmux spawn の前提として有効 |
| ADR-009 | postprocess type | Accepted | **保全** | skill type 分類、新 spec でも維持 |
| ADR-010 | Pilot active review trade-off | Accepted | **保全 (強化)** | pilot 責務 boundary 設計に継承、worker mail 集約原則 |
| ADR-011 | co-self-improve 位置づけ | Accepted | **保全** | tool-self-improve に rebrand |
| ADR-012 | drift detection severity levels | Accepted | **保全** | step verification の severity 規約に継承 |
| ADR-013 | Observer first-class (co-observer) | Accepted | **Superseded by ADR-014** (既存 chain) | 既に supersede 済、新 spec とは独立 |
| ADR-014 | Supervisor redesign (su-observer) | Accepted | **保全 (rebrand)** | administrator (新 spec) の前身。SKILL.md は rebrand、設計原則は保全 |
| ADR-015 | deltaspec auto-init | Accepted | **保全** | session 初期化フロー、新 spec の admin-cycle.sh で継承 |
| ADR-016 | test target real issues | Accepted | **保全** | regression test 戦略に継承 |
| ADR-017 | co-issue v2 Pilot/Worker プロセス隔離 | Accepted | **保全 (3 階層への発展前提)** | 新 spec の 3 階層構造の前身、pilot/worker isolation は新 spec でも有効 |
| ADR-018 | state schema SSOT | Accepted | **保全** | 不変条件 M の根拠、新 spec でも有効 |
| ADR-019 | spec-implementation category | Accepted | **保全** | skill category 分類、新 spec でも維持 |
| ADR-020 | chain SSOT refinement (D-2/D-5 partial superseded) | Proposed | **Superseded by ADR-022 (partial、既存) + ADR-043 (完全)** | 新 spec で chain SSoT 三重化を解消、本 ADR は完全に Superseded |
| ADR-021 | Pilot-driven workflow loop | Accepted | **部分 Superseded** | pilot loop は維持、ただし orchestrator state 機械は新 spec の admin polling cycle に再設計 |
| ADR-022 | chain SSoT 境界明確化 (deps.yaml.chains 独立 SSoT) | Accepted | **Superseded by ADR-043** | 新 spec で chain SSoT 三重化を廃止、deps.yaml.chains は chain.py に統合 |
| ADR-023 | TDD direct flow (chain 再設計) | Accepted | **部分 Superseded** | chain step 構造の概念は保全、ただし「自己申告 step」(L1873-1884) の前提を step verification framework で再設計 |
| ADR-024 | refined を label から Status field へ移行 | Accepted | **部分 Superseded (拡張)** | label→Status field 移行は保全、ただし 5-stage→6-stage に拡張 (Verified 削除確定、PR Reviewed 追加、Idea/Implementing/Merged rename) |
| ADR-025 | co-autopilot phase review guarantee | Accepted | **部分 Superseded** | Known Gap 4 (#1399 phase-review.json shared path) は新 spec の per-Worker mailbox で構造的解消、本 ADR の他の guarantee は保全 |
| ADR-026 | spawn syntax discipline | Accepted | **保全 (強化)** | 新 spec の tmux new-window 規約に継承 |
| ADR-027 | pwd fallback forbidden | Accepted | **保全 (強化)** | 不変条件 K/L の補強、新 spec でも有効 |
| ADR-028 | atomic RMW strategy | Accepted | **保全 (拡張)** | state file への atomic write は新 spec の file mailbox の flock 設計に発展 |
| ADR-029 | twl MCP server 中心 4 epic 統合戦略 | Accepted | **部分 Superseded** | MCP 7 hook → 1 hook 極小化 (新 spec)。`twl_validate_deps` のみ保全、他 6 hook は Claude Code 標準 hook + bash 経由に置換 |
| ADR-030 | human gate marker | Accepted | **保全** | administrator 介入 layer の根拠、`intervention-catalog.md` 経由で継承 |
| ADR-031 | observer self-supervision | Accepted | **保全** | administrator の self-supervision (heartbeat 自己監視) として継承 |
| ADR-032 | completeness severity staging | Accepted | **保全** | pilot review framework の severity 設計に継承 |
| ADR-033 | cross-repo protocol pinning | Accepted | **保全** | cross-repo 運用ルール、新 spec でも有効 |
| ADR-034 | Autonomous chain reliability (wave-progress-watchdog) | Accepted | **Superseded by ADR-043** | wave-progress-watchdog 廃止、admin polling cycle (新 spec §3b) で代替 |
| ADR-035 | Subagent MCP server inheritance | Accepted | **保全 (強化)** | 新 spec の worker 内部 subagent (1 階層) 設計の前提として強化、subagent から子 subagent spawn 不可の公式制約 (verified 2026-05-12) を明示 |
| ADR-036 | Lesson structuralization MUST | Accepted | **保全** | 不変条件 N の根拠、新 spec でも有効 (4-step chain: doobidoo→Issue→Wave→永続文書) |
| ADR-037 (issue-creation-flow-canonicalization) | Issue 作成 flow 大原則 | Proposed | **保全 + 正規化** | 不変条件 P の根拠、新 spec でも有効。**ただし ADR-037 番号重複問題あり、正規化必要 (例: ADR-037a に rename)** |
| ADR-037 (stuck-pattern-ssot) | Stuck pattern SSoT 化 | Accepted | **保全 + 正規化** | stuck-patterns.yaml SSoT 設計、新 spec でも有効。**番号重複正規化必要 (例: ADR-037b に rename or 別 ADR 番号付与)** |
| ADR-038 | Lesson 28 RED-only label bypass closure | Accepted | **部分 Superseded** | 5 layer defense は保全、ただし step verification framework (新 spec §6) で RED-only merge を構造的に block する layer が追加され、本 ADR の Layer 4 (human gate) との重複が整理される |
| ADR-039 | PR 作成段階 event horizon (pre-pr-gate hook) | Proposed | **Superseded by ADR-043** | 新 spec の step verification framework (§6) + gate hook (§5) に統合 |
| ADR-040 | feature-dev spawn gate | Accepted | **保全 (強化)** | tool-architect 等の user 明示依頼許可ルール、新 spec の tool-* 設計に継承 |
| ADR-041 | feature-dev spawn integration | Accepted | **部分 Superseded** | spawn-controller.sh 統合は新 spec で tmux new-window 直接呼び出しに簡素化 (spawn-controller.sh 自体は削除)、ただし「user 明示依頼許可」原則は保全 |
| ADR-042 | tmux server crash recovery + wave resume | Accepted | **部分 Superseded** | tmux server crash recovery は新 spec の crash-failure-mode.html に統合・拡張 (wave resume → admin polling cycle で代替) |

---

## ADR-043 正典 (本 spec の起点)

```
ADR-043: twill plugin radical rebuild — 3 階層 administrator/pilot/worker + file mailbox + step verification framework
Status: Proposed (本 session 起票予定)
Supersedes (完全置換): ADR-020, ADR-022, ADR-034, ADR-039
Supersedes (部分置換): ADR-003, ADR-021, ADR-023, ADR-024, ADR-025, ADR-029, ADR-038, ADR-041, ADR-042
Strengthens (補強): ADR-006, ADR-008, ADR-010, ADR-014, ADR-017, ADR-026, ADR-027, ADR-028, ADR-035, ADR-040
Inherits (保全継承): その他 22 件
References: spec directory architecture/spec/twill-plugin-rebuild/
```

---

## Superseded chain の起票順序 (実装計画)

ADR-043 を起票して既存 ADR を Superseded マークする際の **順序** (依存解決):

### Phase 1 (PoC 着手と同時)
1. **ADR-043 起票** (Proposed status) + 本 spec directory への link

### Phase 2 (dual-stack 開始時)
2. ADR-020 → Superseded by ADR-043 (chain SSoT 三重化解消)
3. ADR-022 → Superseded by ADR-043 (chain SSoT boundary を ADR-043 に統合)
4. ADR-039 → Superseded by ADR-043 (pre-pr-gate を step verification framework に統合)

### Phase 3 (cutover 完了時)
5. ADR-034 → Superseded by ADR-043 (wave-progress-watchdog 廃止)
6. ADR-023 → 部分 Superseded by ADR-043 (TDD direct flow を step verification framework に継承)
7. ADR-024 → 部分 Superseded by ADR-043 (6-stage に拡張)
8. ADR-025 → 部分 Superseded by ADR-043 (phase-review.json shared path 解消)
9. ADR-029 → 部分 Superseded by ADR-043 (MCP 極小化)
10. ADR-038 → 部分 Superseded by ADR-043 (Layer 4 と新 spec layer の整理)
11. ADR-041 → 部分 Superseded by ADR-043 (spawn-controller.sh 簡素化)
12. ADR-042 → 部分 Superseded by ADR-043 (crash recovery 統合)
13. ADR-003 → 部分 Superseded by ADR-043 (state file 構造変更)
14. ADR-021 → 部分 Superseded by ADR-043 (orchestrator 再設計)

### Phase 4 (cleanup)
15. **ADR-037 重複の正規化** (ADR-037a / ADR-037b に rename or 新 ADR 番号付与)
16. ADR-043 を **Accepted** に昇格 (Phase 4 完了時)

---

## 注意事項

1. **ADR-013 / ADR-020 は既存 chain で既に Superseded**: 新 spec とは独立、本 audit では「既存 chain」と注記。
2. **ADR-037 番号重複**: `ADR-037-issue-creation-flow-canonicalization.md` と `ADR-037-stuck-pattern-ssot.md` の 2 件が同 number。新 spec で正規化必要 (Phase 4 cleanup 時)。
3. **「部分 Superseded」の意味**: ADR 全体ではなく、その ADR 内の特定 section / decision が新 spec で置換される。残りは保全 (Superseded by ADR-043 とは別の status)。
4. **「保全 (強化)」の意味**: 新 spec でも ADR の原則は有効、加えて新 spec の仕組みでより強く enforce される。

---

## audit 方法

- 全 ADR ファイルを Phase 2 で code-explorer agent C が grep + 読み込み
- 各 ADR の Title / Status / Decision section / Consequences section を確認
- 新 spec (draft-v1 + 本 session で深掘り) との整合性を 1 件ずつ評価
- confidence: deduced (各 ADR を Read していない、本 audit は agent 出力からの集約)

次 session で各 ADR を直接 Read して fate を verified に格上げする予定。
