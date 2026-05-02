# ADR-029: twl MCP server を中心とする 4 epic 統合戦略

## Status

Accepted (Amended 2026-05-02: Decision 5 added — Tier 2 caller migration)

## Amendments

| Date | Section | Summary |
|---|---|---|
| 2026-05-02 | Decision 5 (new) | Tier 2 caller migration の Strategy / Phase / AC を追記。`#1101` epic close と `tools_comm.py` での MCP mailbox hub 実装完了を踏まえ、残作業 (production caller の `tmux send-keys` 直叩きを `mcp__twl__twl_send_msg` 経由に migrate) の方針を確定。`#1033` close、`#1050` 自然消滅、`#1034` epic close 条件を機械検証可能な形で明記。補助ドキュメント `architecture/migrations/tier-2-caller/{migration-strategy.md, rollback-plan.md}` を併設。 |

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

### Decision 5: Tier 2 caller migration による mailbox MCP hub 統合（2026-05-02 amendment）

#### 経緯

Decision 1-4 起票時点（2026-04-29）では新統合 epic 子 Issue 5（通信系）は計画段階だったが、2026-05-02 時点で以下が完遂済となった:

- **`#1101` epic CLOSED**（17 tools merged: `validation` 5、`state` 2、`autopilot` 各種、`comm` 3）
- **`#945` Phase 2 = ✅**: `tools.py` L903-1036 に validate_deps / validate_merge / validate_commit / check_specialist の 4 handler 実装、および `tools_comm.py` に `send_msg` / `recv_msg` / `notify_supervisor` の 3 tool 実装（ADR-028 §AC5-2 atomic write 規約準拠）
- **MCP mailbox hub 実装済**: `tools_comm.py` L66-78 (`_append_atomic` flock) + L147-179 (`_send_msg_impl` ULID + jsonl append) + L182-207 (`_recv_msg_impl` since-filter polling)

そのため #1037 Tier 2 残作業は **caller 側を `mcp__twl__twl_send_msg` 経由に migrate するのみ** となり、本 ADR の Decision 1（案 A 採択）の運用フェーズに移行する段階となった。

#### 残作業の caller inventory（実測 2026-05-02）

`grep -rn "tmux send-keys"` を `plugins/twl/scripts/`, `plugins/session/scripts/`, `plugins/twl/skills/`, `plugins/session/skills/` に対して実行（tests / docs 除外）:

| カテゴリ | 件数 | 主要ファイル |
|---|---|---|
| production scripts (`*.sh`, executable) | 5 ファイル / 約15行 | `session-comm.sh`（SSoT）, `autopilot-orchestrator.sh`, `lib/observer-auto-inject.sh`, `lib/inject-next-workflow.sh`, `su-observer/scripts/budget-detect.sh` |
| skills refs (Markdown 内コードサンプル) | 3 ファイル / 3行 | `monitor-channel-catalog.md`, `proxy-dialog-playbook.md`, `pitfalls-catalog.md`（参考情報、本 migration の対象外） |
| `session-comm.sh` を経由する production caller | 7 ファイル | `cld-spawn`, `cld-observe`, `spec-review-orchestrator.sh`, `pilot-fallback-monitor.sh`, `issue-lifecycle-orchestrator.sh`, `budget-detect.sh`, `autopilot-orchestrator.sh` |

> **Note (本 amendment の訂正値)**: `.explore/wave20-mcp-msg-cluster/summary.md` は「29 caller」と記述しているが、実測（production scripts のみ）は production code 5 ファイル ~15 行。`session-comm.sh` 経由を caller として展開すると 7 production caller。本 ADR では誤情報訂正のため実測値を採用し、詳細列挙は補助ドキュメント `architecture/migrations/tier-2-caller/migration-strategy.md` に外出しする。

#### 決定

1. **Tier 2 = caller migration スコープ確定**。`tools_comm.py` が既に MCP mailbox hub を提供するため、新規 backend 実装は不要。残作業は `tmux send-keys` 直叩き箇所と `session-comm.sh::cmd_inject` 内部を `mcp__twl__twl_send_msg` 経由に置換する。
2. **Strategy 層 = `#1032` Tier B 統合**。`session-comm.sh` に `session_msg send/recv/ack/list` API を追加し、内部 dispatch を `TWILL_MSG_BACKEND={tmux,mcp,mcp_with_fallback}` env 切替で行う。`#1032` Tier B（msg 抽象化）と本 amendment は同 Wave で吸収する。
3. **Shadow mode → blocking 切替 pattern**（`#1225 deps-yaml-guard` で validated 2026-04 月）を踏襲し、regression 検出後の rollback を保証する。
4. **`#1033` close**: file-based mailbox 単体実装は `tools_comm.py` で実現済（MCP server 内部実装として封じ込め）。本 amendment merge と同時に GitHub 上で close、close rationale は「`tools_comm.py` で実現済 → 本 ADR Decision 1 案 A 採択の系」。
5. **`#1050` (cmd_inject_file flock) 自然消滅**: caller が `tmux load-buffer` 経由しなくなるため flock 競合が構造消滅。Phase 4 (cleanup) で close 候補。
6. **`#1034` epic close 条件**: Tier B (`#1032`) merge + 本 Tier 2 caller migration Phase 3 完遂時に close。
7. **`#1197` (subshell mock 設計修正)** は本 caller migration により mock 設計の前提が変わるため、Phase 4 で再評価対象とする。

#### 実行 Phase（Wave 21 想定、L effort）

| Phase | スコープ | env var 設定 | 切替 / 完了点 |
|---|---|---|---|
| **Phase 1**: Strategy 層実装 | `session-comm.sh` に `session_msg` API 追加。`session-comm-backend-tmux.sh` に既存 `cmd_inject` ロジック移動、`session-comm-backend-mcp.sh` 新規作成（`twl mcp call mcp__twl__twl_send_msg ...` または `python -m twl.mcp_client` wrapper） | `TWILL_MSG_BACKEND=tmux`（default 維持） | `session-comm-backend-{tmux,mcp}.sh` 整備、Strategy 層 unit test (`bats`) PASS |
| **Phase 2**: shadow migration | production caller 5 ファイル ~15 行を `session_msg send` API に書換、両 backend 並走（mcp は dry-run）、shadow log で MCP/tmux 整合性比較 | `TWILL_MSG_BACKEND=mcp_with_fallback`（log only） | shadow log で 1 週間以上 mismatch 0 件確認、`mcp-shadow-compare.sh` PASS |
| **Phase 3**: blocking 切替 | default を mcp に切替、`tmux send-keys` fallback は kill-window 等の緊急介入のみ | `TWILL_MSG_BACKEND=mcp`（default） | bats integration test（Pilot↔Worker 双方向、AT 非依存性 = `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=0` 確認）PASS |
| **Phase 4**: cleanup | `tmux send-keys` 直叩き lint を `twl audit` に追加、`session-comm.sh::cmd_inject_file` 削除、`#1050`/`#1197` 再評価・close 判定 | — | `tmux send-keys` lint PASS（whitelist 例外のみ）、`#1033`/`#1050`/`#1034` close 完了 |

#### Acceptance Criteria

- AC5-1: production caller 全件が `session_msg` API 経由に migrate 済（`grep -rn "tmux send-keys" plugins/{twl,session}/{scripts,skills}/ --exclude-dir=tests` で whitelist 記載のみ）
- AC5-2: bidirectional 通信が並列 100 msg で損失ゼロ（stress test、mailbox jsonl の atomic append 検証）
- AC5-3: bats integration test PASS、`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=0` でも動作（AT 非依存性）
- AC5-4: backend 切替（`TWILL_MSG_BACKEND=tmux` / `mcp` 両方）で同テスト PASS
- AC5-5: shadow mode で mismatch 0 件を 1 週間以上維持（`#1225` で validated 基準）
- AC5-6: `#1033` close、`#1034` epic close、`#1050` close（Phase 4 完了時）
- AC5-7: 補助ドキュメント `architecture/migrations/tier-2-caller/migration-strategy.md` および `rollback-plan.md` の存在 + 本 ADR との整合性
- AC5-8: `mcp__twl__twl_send_msg` の `try/except ImportError` gate と FastMCP 接続失敗時の fallback パス（`session-comm-backend-tmux.sh`）が Phase 3 後も保持される（rollback 経路の保証）

#### Bounded Context 整合

- caller migration は **Autopilot Context** および **Session Comm Context**（`plugins/session/`）内部の I/O 経路変更のみ
- **TWiLL Integration Context**（`plugins/twl/architecture/domain/contexts/twill-integration.md`）が "Open Host Service" として `mcp__twl__twl_send_msg` を提供する構造は維持（Decision 3 で AC10 充足の道筋確定済、本 amendment で実装系統が caller 側にも適用される）
- ADR-022 (chain-ssot-boundary) との整合: `session_msg` API 追加が `chain.py CHAIN_STEPS` / `chain-steps.sh` / `deps.yaml.chains` の 3 SSoT に影響する場合は、子 Issue 起票時に `twl check --deps-integrity` PASS を AC に含める

#### 実装単位

Wave 21 で **1 Pilot 1 Worker × 1 PR（Phase 1+2 一括）+ 1 PR（Phase 3）+ 1 PR（Phase 4）** の 3 PR 構成。Phase 1+2 は同時 implement 可（shadow log のみで blocking なし）、Phase 3 は default 切替で別 PR、Phase 4 は cleanup で別 PR。total ~L effort（~6-8h Worker 時間）。

#### 不採用案 (Decision 5 内サブ案)

- **案 5X (full atomic blocking 切替)**: shadow mode を skip、Phase 1+2+3 を 1 PR で blocking 切替。**不採用理由**: production caller 5 ファイル同時切替は regression リスク高、`#1225` で validated 済の安全 pattern を放棄する根拠なし、rollback コストが大きい
- **案 5Y (Strategy 層なしで直接 caller を `mcp__twl__twl_send_msg` 呼出)**: `TWILL_MSG_BACKEND` 切替なしで caller を直接 MCP tool 呼出に書換。**不採用理由**: rollback 経路が caller 側 diff 全体の revert に依存（人為ミス源）、`#1032` Tier B Strategy 層との二重保守、緊急介入時の tmux 経路保持が困難
- **案 5Z (Phase 1-3 を 1 PR 一括 merge)**: 3 Phase を 1 PR にまとめ Wave 21 1 PR 完遂。**不採用理由**: shadow → blocking の閾値判断（mismatch 0 件 1 週間維持）が PR 内に閉じこめられず、Phase 2 観察期間と Phase 3 実施タイミングを分離できない

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

### Decision 5 関連の Consequences（2026-05-02 amendment）

#### Positive (Decision 5)

- **observer 自律性向上**: `tmux send-keys` race / inject 失敗 / queue 残留（"Press up to edit queued messages" false positive、memory `feedback_inject_queue_verification`）が MCP server 内 dispatch に置き換わることで構造的に解消。inject 失敗率 ~10% → ~0% の見込み（実装後 metrics で検証）
- **`#1050` (cmd_inject_file flock) 自然消滅**: caller が `tmux load-buffer` を経由しなくなれば flock 競合問題自体が消失、tech-debt 1 件減
- **`#1033` close 確定**: file-based mailbox 単体実装は不要 → tools_comm.py で実現済（Decision 1 案 A 採択の系として）
- **`#1034` epic close への道筋**: Tier B (`#1032`) merge + 本 Tier 2 caller migration Phase 3 完遂で close 可能
- **shadow mode pattern の再利用**: `#1225 deps-yaml-guard` で validated 済の 3-step migration（bash hook 並走 → mismatch 0 件確認 → blocking 切替）を踏襲、新規リスク導入なし
- **Wave 完遂時間短縮見込**: observer 1 cycle (capture + judge + inject) ~60s → ~10s（83% 短縮、推定）、autopilot fail recovery (kill + restart) ~5min → ~2min（60% 短縮、推定、実装後 metrics で検証）

#### Negative (Decision 5)

- **production caller migration の regression リスク**: 5 ファイル ~15 行同時切替で意図しない動作変更が発生し得る。shadow mode 並走で緩和するが、shadow log 解析の人為ミスで mismatch 見逃しリスクあり
- **shadow log 解析コスト**: Phase 2 で 1 週間以上 mismatch 0 件を維持する必要があり、observer / Pilot の手動確認負荷が一時的に増加
- **緊急 rollback 時の env var 操作必要**: blocking 切替後（Phase 3）の rollback は `TWILL_MSG_BACKEND=tmux` 設定 + 既存 caller の関数 path 引き継ぎが必要、即時 1 コマンド rollback ではない（補助 `rollback-plan.md` で手順明記）
- **`tools_comm.py` への依存集中**: 通信全体が `tools_comm.py` に依存することで MCP server 障害時の影響範囲が拡大（Phase 4 lint 追加で `tmux send-keys` 経路を緊急介入用に保持することで緩和）
- **`#1197` (subshell mock 設計修正)** の影響範囲評価が Phase 4 まで延期となり、test-fixture 整合性の最終確認が遅れる

#### Mitigations (Decision 5)

- **shadow mode 段階的 rollout**: `#1225` で validated 済の 3-step pattern を踏襲、Phase 2 で 1 週間以上 mismatch 0 件確認後 Phase 3 移行
- **`mcp-shadow-compare.sh` 整合性スクリプト**: Wave 21 Phase 2 で同スクリプトを caller migration 用に拡張（既存 hook MCP 化用 SSoT を再利用）、mismatch 自動検出で手動確認負荷を低減
- **緊急介入用 tmux 経路保持**: Phase 4 lint で `tmux send-keys` を 100% 禁止せず、whitelist (`session-comm-backend-tmux.sh` 内 + kill-window 緊急処理) を許容
- **rollback-plan.md 明文化**: Phase 別 rollback 手順 + 緊急時 1 コマンド復帰手順 + データロス対策（mailbox jsonl 保存）を補助ドキュメントで明文化、人為ミス防止
- **bats integration test の AT 非依存性確認**: `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=0` 設定での test PASS を AC5-3 として明記、AT 機能依存リスクを構造的に排除
- **`tools_comm.py` 障害時の fallback**: `mcp__twl__twl_send_msg` の `try/except ImportError` gate (AC5-8) と FastMCP 接続失敗時の `session-comm-backend-tmux.sh` fallback パスを Phase 3 後も保持し、MCP server 障害時の通信断絶を防ぐ

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
