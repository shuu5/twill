# ADR-029: twl MCP server を中心とする 4 epic 統合戦略

## Status

Proposed

## Context

### 背景

2026-04-23 の Claude Code v2.1.118 で hooks の `type: "mcp_tool"` handler が追加されたことを契機に、TWiLL の MCP 関連 4 epic（#945, #1034, #1036, #1037）の責務が重複しはじめた。本 ADR は 4 epic 横断の重複を整理し、子 Issue 起票順序と epic 更新方針を確定する。

### 4 epic の現状（実測 2026-04-29）

| Epic | Title | State | 進捗 | 残作業 |
|---|---|---|---|---|
| **#945** | twl CLI を MCP server 化する検討（Phase 0/1/2） | OPEN | Phase 0/1 ✅ 完遂（Wave A-Q、6 PR merged） | **Phase 2 (AC9)** = 残 15 モジュール (mergegate, orchestrator, worktree, github, project, plan 等) MCP 化、未着手 |
| **#1037** | hooks → MCP 移行戦略（4 Tier） | OPEN | 未着手 | **Tier 0** = twl MCP server tools 拡充（他 Tier の前提）; Tier 1-3 = hook MCP 化 / supervisor / CRG/doobidoo 自動化 |
| **#1034** | session-comm: tmux send-keys → 内製 mailbox（Tier A/B/C） | OPEN | Tier A (#1031) ✅ closed, Tier B (#1032) Open | **Tier C (#1033) は #1037 Tier 2 と統合再設計フェーズ**。Issue body の "Update 2026-04-28" で案 A/B/C 提示済 |
| **#1036** | code-review-graph (CRG) MCP 実活用化（4 Tier） | OPEN | 未着手 | **Tier 0** = #754 stdio deadlock hang 根本解決（前提・ブロッカー）; Tier 1-3 = agent query / worker 統合 / 利用率モニタ |

### 実装現状（cli/twl/src/twl/mcp_server/tools.py 棚卸し、2026-04-29）

`tools.py` は 255 行、5 tool 登録済み:

| 既存 tool | 由来 | 用途 |
|---|---|---|
| `twl_validate` | Phase 0 α (#962) | プラグイン構造検証 |
| `twl_audit` | Phase 0 α (#962) | TWiLL コンプライアンス監査 |
| `twl_check` | Phase 0 α (#962) | ファイル存在 + chain 整合性検査 |
| `twl_state_read` | Phase 1 (PR not yet referenced) | autopilot state read |
| `twl_state_write` | Phase 1 | autopilot state write |

実機検証 ✅: `mcp__twl__twl_validate / twl_audit / twl_check / twl_state_read / twl_state_write` が全て connected（本 session 起動時に deferred tool として観測）。

### 重複構造の確定

memory hash `1c66e4995b77f3866d1ef7f19cb587d0a28461beddf1fa978eee8cfa037811ef` で「#1037 Tier 0 が他全 Tier のブロッカー」と既に確定済み。実測で重複は以下の構造:

```
                      tools.py 拡充
                    （= MCP tool 追加）
                          │
        ┌─────────────────┼─────────────────┐
        ▼                 ▼                 ▼
  #945 Phase 2     #1037 Tier 0      #1034 Tier C 案 A
  (15 module 化)   (5 検証系 +       (mailbox = #1037 Tier 2
                    3 通信系 +         通信系と完全重複)
                    2 状態系)
```

- **#945 Phase 2 と #1037 Tier 0 は同じ tools.py への追加** で完全重複（同じファイル、同じパターン、同じ責務）
- **#1037 Tier 0 通信系と #1034 Tier C は同じ MCP 通信機構** で完全重複（mailbox の MCP hub 化）
- **#1036 Tier 0 (CRG hang) は独立問題**だが、MCP RPC stdio deadlock の教訓は新統合 epic に逆輸入される

### user 方針（2026-04-29 セッション）

> 「複数 epic と #945 が絡む問題が結構ある。整理して優先順位を決めて自律実行」

→ epic 統合の確定 + 子 Issue 起票順序 + 自律実行可能な状態を作ることが本 ADR の責務。

## Decision

### Decision 1: 部分統合戦略を採用（案 B）

**新統合 epic「twl MCP server tools 拡充」を起票し、#945 Phase 2 と #1037 Tier 0 を吸収する。** #1034 Tier C は案 A（#1037 Tier 2 = 通信系統合）採用で確定、#1036 は独立維持。

#### 不採用案

| 案 | 内容 | 不採用 rationale |
|---|---|---|
| **案 A: 完全統合** | 新統合 epic に 4 epic 全部を吸収（#945/#1034/#1036/#1037 close） | #945 Epic は Phase 0/1 完遂の歴史記録として価値あり、close は不要。#1036 は CRG hang 問題が独立スコープで scope 拡張になる |
| **案 C: 統合せず調整のみ** | 4 epic 維持 + 子 Issue 起票順序合意 | tools.py 拡充の責務が #945 Phase 2 と #1037 Tier 0 に分散したまま、子 Issue が両 epic を行き来し追跡が複雑化。重複作業の構造的解消にならない |

#### 案 B 採用理由

1. **重複の核心は tools.py 拡充**: #945 Phase 2 と #1037 Tier 0 は同じファイルへの同じパターンの追加。ここを統合すれば最大の重複（10+ 子 Issue 想定）が解消する
2. **#1034 Tier C は実質判断済**: Issue body の "Update 2026-04-28" で案 A（#1037 Tier 2 吸収）が提示済。新 epic 立て直し不要
3. **#1036 独立維持**: CRG hang は #754 stdio deadlock の真因解明が前提で、scope が異なる。MCP RPC stdio 教訓のみ新統合 epic に逆輸入
4. **#945 Epic 維持**: Phase 0/1 完遂の歴史記録として価値、Phase 2 のみ新 epic 経由で実装

### Decision 2: 新統合 epic の子 Issue 構造（5 件、起票順）

新統合 epic「epic(mcp): twl MCP server tools 拡充 — #945 Phase 2 + #1037 Tier 0 統合」配下に以下 5 件の子 Issue を起票する。詳細 AC 案は `/tmp/phase-alpha-recommended-issues.md` を参照。

| 順 | 子 Issue 名 | カテゴリ | 由来 epic | 依存 |
|---|---|---|---|---|
| 1 | tools.py 棚卸し + 拡充計画策定 | meta | #1037 Tier 0 + #945 AC9 | なし（最初の子 Issue） |
| 2 | 検証系 tool 群追加（5 tool） | validation | #1037 Tier 0 | 子 1 完了後 |
| 3 | 状態系 tool 群追加（2-3 tool） | state | #1037 Tier 0 + #945 Phase 2 | 子 1 完了後（子 2 と並走可） |
| 4 | autopilot 系 tool 群追加（mergegate / orchestrator / worktree） | autopilot | #945 Phase 2（AC9 第 1 Wave） | 子 1 完了後（子 2/3 と並走可） |
| 5 | 通信系 tool 群追加（mailbox MCP hub + 通知系 notify_supervisor / send_msg / recv_msg 3 tool） | comm | #1037 Tier 0 通知系 + #1037 Tier 2 + #1034 Tier C 案 A | 子 1, 2 完了後 |

各子 Issue の AC は以下を共通フォーマットとする:

- 対象 module / tool 名の確定
- handler 関数（pure Python、in-process testable）の追加
- MCP tool 登録（`@mcp.tool()` decorator + `try/except ImportError` gate）
- pytest による handler unit test 追加
- 既存 bash wrapper / bats test の互換性維持確認
- `tools.py` の行数増加 + drift 確認（`twl --validate` PASS 維持）
- **Bounded Context 整合 contract（必要時）**: tool が他 Bounded Context (Autopilot / PR Cycle 等) の internal モジュールを import する場合、context-map.md の "Open Host Service" 方向（TWiLL Integration → 該当 Context）と整合する依存方向を維持する contract（handler signature + import 規約）を子 Issue body に明記する
- **ADR-028 整合確認**: 子 Issue 3, 4, 5 で `session.json` への write 経路が増える場合、ADR-028 の write authority matrix（§Implementation）への追記が必要かを判定し、必要時は同 ADR 改訂 PR を子 Issue とセットで起票する
- **glossary 整合**: ADR-029 で多用される MUST 用語（"epic", "MCP server", "MCP tool", "tools.py"）が glossary.md に未定義のため、子 1 (棚卸し + 拡充計画) で用語追加要否を判定する（glossary 照合ポリシーは完全一致のみ）

### Decision 3: 既存 4 epic の更新方針

#### #945（twl CLI MCP server 化）

- **保持**: Phase 0/1 完遂記録として残す
- **更新**: AC9（Phase 2 開始基準）を「新統合 epic の子 Issue 4（autopilot 系第 1 Wave）が merge された時点で AC9 充足」に再定義
- **AC9 充足判定の手順**（機械検証不可、手動更新が必要）:
  1. 新統合 epic 子 Issue 4 PR が main に merge される
  2. Pilot または Observer が `gh issue view 945` で AC9 チェックボックスを確認
  3. `gh issue edit 945` または body 直接編集で AC9 を `[x]` に更新
  4. memory に AC9 充足を記録（doobidoo `memory_store`）
  5. 子 Issue 4 の Issue body に「merge 時に #945 AC9 を手動更新する」MUST タスクを明記する
- **AC10 充足の手順**（Architecture Spec 更新）:
  - 子 Issue 1 (棚卸し + 拡充計画) で `plugins/twl/architecture/domain/contexts/twill-integration.md` の **Component Mapping + Key Workflows + Responsibility** に MCP server を Open Host Service 提供方法として追加
  - 同時に `plugins/twl/architecture/domain/context-map.md` の TWiLL Integration ↔ 各 Context の依存表現を見直す
- **close 条件**: 新統合 epic の autopilot 系 (mergegate/orchestrator/worktree) 子 Issue 群が全 merge された段階 + AC9/AC10 手動更新完了
- **Issue 本文への追記**: 「Phase 2 は新統合 epic [新番号] に委譲。当 Epic は Phase 0/1 完遂記録として保持」

#### #1034（session-comm mailbox）

- **保持**: Tier A/B 進行中
- **更新**: Tier C は案 A（#1037 Tier 2 吸収）で確定、新統合 epic の子 Issue 5（通信系）に委譲
- **close 条件**: Tier B (#1032) merge + 新統合 epic 子 Issue 5 merge
- **#1033 (Tier C 単独 Issue)**: close on rationale "新統合 epic 子 Issue 5 に吸収"

#### #1036（CRG MCP 実活用化）

- **独立維持**: CRG hang 問題は scope が異なるため統合しない
- **更新なし** (本 ADR とは独立に進行)
- **教訓共有**: MCP RPC stdio deadlock 対策（#754 真因仮説 H3）を新統合 epic 子 Issue 1 (棚卸し + 拡充計画) に「設計上の留意点」として記載

#### #1037（hooks → MCP 移行戦略）

- **保持**: epic 全体は維持（Tier 0/1/2/3 構造維持）
- **更新**: Tier 0 を新統合 epic に委譲。Tier 0 のチェックボックスは新統合 epic 子 Issue 1, 2, 3 に置き換え
- **close 条件**: Tier 0 委譲完了 + Tier 1-3 個別 close
- **Issue 本文への追記**: 「Tier 0 は新統合 epic [新番号] に委譲。Tier 1-3 は新統合 epic 子 Issue 群の merge 後に着手」

### Decision 4: 子 Issue の実行順序と担当 controller

新統合 epic の子 Issue 起票後、Wave 単位の実行順序と担当 controller を以下に確定する。

```
Wave 1: 子 1 (棚卸し + 拡充計画)         — co-explore + co-issue（設計タスク）
Wave 2: 子 2 (検証系) + 子 3 (状態系) + 子 4 (autopilot 系第 1 Wave)  — co-autopilot で 3 並走（実装タスク）
Wave 3: 子 5 (通信系)                     — co-autopilot 1 Pilot 1 Issue（実装タスク）
```

**Controller 振り分け**:
- 子 1 は「拡充計画」策定の性質上、co-autopilot ではなく **co-explore + co-issue** で扱う（実装ではなく設計タスク、`.explore/<epic-number>-mcp-inventory/summary.md` 生成 → 子 2-5 起票）
- 子 2-5 は通常の **co-autopilot 実装フロー**（1 Pilot 多 Issue で Wave 2 並走、Wave 3 単独）

Wave 並走数は ADR-014 の OBS-4 拡張（5 並列まで）を満たす。

## Consequences

### Positive

- **重複作業の構造的解消**: tools.py への追加が単一 epic 配下に集約され、子 Issue 間で同じパターン（handler + MCP tool + test）を踏襲できる
- **#1034 Tier C の判断済化**: Issue body Update 2026-04-28 の保留状態が closed 化され、開発が再開できる
- **追跡複雑性の削減**: 現状 4 epic 横断で子 Issue 起票が必要 → 1 統合 epic + 既存 epic への参照で完結
- **Architecture Spec 準拠**: TWiLL Integration Context（context-map.md）の "Open Host Service" 提供方法に MCP server を追加する道筋が確定（#945 AC10 充足）

### Negative

- **新 epic 起票コスト**: co-issue で 1 件 + 子 Issue 5 件 = 計 6 件の起票作業
- **#945 Epic body の更新リスク**: 既存 AC9 の再定義は historic record の整合性チェックが必要
- **#1037 Tier 1-3 進行への影響**: Tier 0 を委譲することで Tier 1-3 の進行 trigger が新統合 epic 完了に依存（直列化リスク）
- **#1036 教訓共有の手動化**: 新統合 epic 子 Issue 1 の rationale section に MCP RPC stdio 教訓を手書きする必要

### Mitigations

- **新 epic 起票は co-issue 委譲**: 標準ワークフローを使い手動 churn を最小化
- **#945 AC9 再定義の検証**: co-issue refine 時に worker-arch-doc-reviewer を spawn し既存 AC との整合性を確認
- **#1037 Tier 1-3 並走化**: Tier 1 (軽量検証 hook MCP 化) は Tier 0 完了を待たず、新統合 epic 子 Issue 2 (検証系) merge 後に着手可能と明記
- **#1036 教訓の正式参照**: 子 Issue 1 内で `docs/crg-auto-build-hang-analysis.md` および ADR-029 (本 ADR) の Decision 2 を参照
- **Architecture Spec 同期**: Decision 3 #945 に明記の通り、子 Issue 1 で `twill-integration.md` の Component Mapping + Key Workflows + Responsibility に MCP server を Open Host Service 提供方法として追加する。本 ADR とセットで同 spec の改訂 PR を起票する想定（co-architect 経由が望ましい）
- **Bounded Context 違反予防**: Decision 2 共通 AC に追加した「Bounded Context 整合 contract」により、子 Issue 4 で Autopilot Context 内部モジュール (state.py / orchestrator.py) を tools.py に統合する際の依存方向逆転リスクを子 Issue 起票時に検出可能にする
- **tools.py モジュール分割評価**: 子 1 (棚卸し + 拡充計画) で全 15+ tool 追加後の予想行数 (780-1000 行) を試算し、必要時はモジュール分割方針 (`tools_validation.py` / `tools_state.py` / `tools_autopilot.py` / `tools_comm.py` 等) を提案する

## Alternatives Considered

### 案 A: 完全統合（#945/#1034/#1036/#1037 全 close）

新統合 epic 1 件に 4 epic を全部吸収する案。

**不採用理由**:
1. **#945 の Phase 0/1 完遂記録の喪失**: Issue close = body の active 性消失で、Phase 1 の AC8（AI 失敗率測定プロトコル）等の進行中 work item が見えにくくなる
2. **#1036 の CRG hang scope 拡張**: tools.py 拡充と CRG パッケージ側の hang 解析は scope が直交。同一 epic 配下にすると refine 時に観点が混ざる
3. **#1037 Tier 1-3 の trigger 複雑化**: Tier 1-3 は元々 epic 単独で進行可能だが、close すると trigger が新 epic に依存

### 案 C: 統合せず調整のみ

4 epic 維持 + 子 Issue 起票順序合意で重複を回避する案。

**不採用理由**:
1. **tools.py の責務分散維持**: #945 Phase 2 と #1037 Tier 0 が同じファイルに追加するのに別 epic 配下のままで、子 Issue 間の整合性確認が手動化
2. **追跡の複雑性**: observer / Pilot が「これはどっちの epic 配下？」を毎回判定する必要
3. **将来の重複再発リスク**: 構造的解消ではなく合意ベースで進めるため、新たな MCP 関連 epic が起票されると同じ問題が再発

## Related ADRs

- **ADR-014** (Observer → Supervisor): su-observer の Wave 管理責務が本 ADR の epic 統合判断に関わる（Wave 計画立案）
- **ADR-018** (state-schema-ssot): tools.py への state_read/write 追加が SSOT 原則と整合する道筋
- **ADR-022** (chain-ssot-boundary): chain 関連 tool 追加時に CHAIN_STEPS / chain-steps.sh / deps.yaml.chains の 3 SSoT 整合性を維持
- **ADR-026** (spawn-syntax-discipline): MCP tool 追加が spawn 経路に影響する場合の WARN 機構
- **ADR-028** (atomic-rmw-strategy): session.json write authority matrix への新 tool 追加時の flock 整合性（B-1 委譲方針との整合）

## References

- **Issue 本文**:
  - [#945](https://github.com/shuu5/twill/issues/945) — twl CLI を MCP server 化する検討
  - [#1034](https://github.com/shuu5/twill/issues/1034) — session-comm mailbox epic
  - [#1036](https://github.com/shuu5/twill/issues/1036) — CRG MCP 実活用化 epic
  - [#1037](https://github.com/shuu5/twill/issues/1037) — hooks → MCP 移行戦略 epic
- **Explore Summaries**:
  - `.explore/945/summary.md` — Phase 0 探索（co-explore 完了）
  - `.explore/945-phase1/summary.md` — Phase 1 探索（state MCP 化設計）
  - `.explore/1023/summary.md` — twl simplification 4 施策評価
- **Memory Hash**:
  - `1c66e4995b77f3866d1ef7f19cb587d0a28461beddf1fa978eee8cfa037811ef` — 4 epic 横断戦略既確定事項
  - `8dbcc66f...` — co-architect spawn と co-autopilot 並走時の SSOT 分離（`.controller-issue/<ts>/`）
  - `3f88b7b4...` — MCP 設定 deploy 課題
- **Code**:
  - `cli/twl/src/twl/mcp_server/tools.py` (255 行、5 tool 登録済)
  - `cli/twl/src/twl/mcp_server/server.py` (FastMCP entry point)
  - `cli/twl/src/twl/autopilot/state.py` (586 行、StateManager pure)
- **Source ADR for hang analysis**:
  - `docs/crg-auto-build-hang-analysis.md` — #754 詳細分析（MCP RPC stdio deadlock 真因仮説 H3）
