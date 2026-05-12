# changelog — twill plugin rebuild spec

本 spec の変更履歴を記録する。

## 2026-05-12 — draft-v2 (本 session 着手)

### 新規作成 (Phase 5 implementation)

- `README.md` — index + 読む順序 + 各 file の役割
- `overview.html` — 全体図 (図 1)、Key Points、新原則 7 条、status ↔ phase mapping
- `failure-analysis.md` — 9 件 P0 bug 深掘り + 横断要因 F-1/F-2/F-3 + MUST 15 件 + SHOULD 6 件
- `adr-fate-table.md` — ADR 43 件 fate audit + Superseded chain 順序 + ADR-037 番号重複正規化課題
- `invariant-fate-table.md` — 不変条件 A-S 19 件継承戦略 + 新規 T-X 5 件追加 + `ref-invariants.md` drift 訂正課題
- `crash-failure-mode.html` — 3 階層 (worker/pilot/admin) crash 検知 + recovery + SLA + 周辺 failure mode
- `step-verification.html` — step framework (図 1)、framing 訂正 (自己申告 anti-pattern → 責務分離 + post-verify 不在)、step.sh pseudo-bash、step rule 8 件 + worker SKILL.md 例 + 旧比較

### Placeholder 化 (次 session 実装予定)

- `boundary-matrix.html` (admin / pilot / worker / tool / phase 責務 boundary 行列)
- `spawn-protocol.html` (3 階層 spawn + file mailbox 通信 protocol)
- `gate-hook.html` (PreToolUse gate 機構実装)
- `admin-cycle.html` (administrator polling cycle 詳細)
- `deletion-inventory.md` (削除対象 60+ 件 + 新規 helper 5 本)
- `rebuild-plan.md` (Phase 1-4 plan + Phase 1 PoC 詳細)
- `regression-test-strategy.md` (既存 bats 継承 + 新規 invariant test)
- `dual-stack-routing.md` (旧 chain と新 phase の併存ルール)
- `pitfalls-inheritance.md` (既存 pitfalls-catalog 継承戦略)
- `glossary.md` (用語集)
- `changelog.md` (本 file)

### 主要変更点 (draft-v1 → draft-v2)

| 領域 | draft-v1 | draft-v2 |
|---|---|---|
| 構造 | 単一 html | 18 file 分割 (html 7 + md 11) |
| 失敗 analysis | §1 で 3 件のみ簡素言及 | `failure-analysis.md` 9 件全件 deep dive + 横断要因 |
| ADR 言及 | 11 件 | 43 件 fate audit |
| 不変条件 | 未言及 | 既存 19 件 + 新規 5 件 = 24 件 |
| crash failure mode | 言及なし | 新 file (3 階層 × 3 種別) |
| step verification framing | "自己申告 anti-pattern" | "責務分離 + post-verify 不在が問題" (agent B 指摘反映) |
| 不足領域 | 5 項目程度 | 17 項目 identified、本 session で 7 項目 cover |

### feature-dev workflow Phase 進捗 (本 session)

| Phase | status |
|---|---|
| Phase 1 Discovery | ✅ completed |
| Phase 2 Codebase Exploration (3 agent) | ✅ completed |
| Phase 3 Clarifying Questions (4 件) | ✅ completed |
| Phase 4 Architecture Design (18 file 構成案) | ✅ completed |
| Phase 5 Implementation (主要 7 file + placeholder 11 file) | ✅ completed |
| Phase 6 Quality Review | 進行中 |
| Phase 7 Summary | pending |

---

## 2026-05-12 — draft-v1 (前 session)

- `/tmp/twill-rebuild-design.html` として単一 html で作成
- A 軸 (pilot 責務 boundary) / B 軸 (step verification framework) / C 軸 (admin polling cycle) の深掘り
- §9 削除 inventory + §11 timeline 完了
- doobidoo Memory MCP 永続化 (hash 6ef844e9 / 74b7cdf7 / 7727b59f)

---

## 今後の予定 (draft-v3 以降)

- 次 session で残 11 file (placeholder) を実装
- ADR-043 起票 (md 本体 + 本 spec を supplement として link)
- Phase 1 PoC 着手 (Issue #1660 sanitize、user 明示承認後)
- ADR-037 番号重複正規化 (Phase 4 cleanup)
- `ref-invariants.md` drift 訂正 (A-N → A-X)
