# twill plugin radical rebuild 仕様書

> **目的**: 既存 twill plugin (file 1177、bash 5175 lines、ADR 43 件、不変条件 19 件) を、構造的欠陥を不能化する形で根本的に再設計する。
>
> **status**: draft-v2 (2026-05-12)、複数 session で fix-up 中。
>
> **audience**: 人間 (user / 設計者) + 将来 tool-architect (template 生成)。

---

## 構成 (18 file)

clean 分割: html (読む/比較する文書) + md (検索/git diff 重視の文書) のハイブリッド構成。

### A. 全体把握 (最初に読む)

| file | 形式 | 内容 |
|---|---|---|
| `README.md` | md | 本ドキュメント (index + 読む順序) |
| `overview.html` | html | architecture overview (図 1)、Key Points、新原則 7 条 |
| `failure-analysis.md` | md | 既存 plugin の失敗 9 件 P0 bug 深掘り + 横断要因 F-1/F-2/F-3 |

### B. 既存資産の継承戦略 (audit 結果)

| file | 形式 | 内容 |
|---|---|---|
| `adr-fate-table.md` | md | ADR 43 件 1 件ずつ fate audit (保全 / Superseded / 削除 / 統合) |
| `invariant-fate-table.md` | md | 不変条件 19 件 (A-S) 継承戦略 + ref-invariants.md drift 訂正課題 |
| `pitfalls-inheritance.md` | md | 既存 pitfalls-catalog 継承戦略 + 構造的不能化 mapping (**placeholder、次 session**) |

### C. 新 architecture 詳細 (実装参照用)

| file | 形式 | 内容 |
|---|---|---|
| `boundary-matrix.html` | html | admin / pilot / worker / tool / phase の責務 boundary 行列 (**placeholder、次 session**) |
| `crash-failure-mode.html` | html | worker/pilot/admin crash 検知 + recovery + SLA (最優先、本 session 実装) |
| `step-verification.html` | html | step verification framework (図 5)、framing 訂正 (post-verify 不在が問題) |
| `spawn-protocol.html` | html | 3 階層 spawn + file mailbox 仕様 + 通信 sequence (**placeholder、次 session**) |
| `gate-hook.html` | html | PreToolUse gate (図 3) + hook 実装案 (**placeholder、次 session**) |
| `admin-cycle.html` | html | administrator polling cycle (図 2b) + 不変条件 I-1〜I-7 (**placeholder、次 session**) |

### D. 削除・移行計画

| file | 形式 | 内容 |
|---|---|---|
| `deletion-inventory.md` | md | 削除対象 60+ 件 + 新規 helper 5 本 (**placeholder、次 session**) |
| `rebuild-plan.md` | md | 4 phase + Phase 1 PoC (#1660 sanitize 詳細) + 8 verify points (**placeholder、次 session**) |
| `regression-test-strategy.md` | md | 既存 bats 90+ 継承 + 新 architecture 追加 test 計画 (**placeholder、次 session**) |
| `dual-stack-routing.md` | md | 旧 chain と新 phase の共存ルール + 移行完了判定 (**placeholder、次 session**) |

### E. 補助

| file | 形式 | 内容 |
|---|---|---|
| `glossary.md` | md | 用語集 (administrator / pilot / worker / phase / step / mail 等) (**placeholder、次 session**) |
| `changelog.md` | md | 本 spec の変更履歴 |

---

## 読む順序

### 初めて読む人 (全体把握優先)

1. `overview.html` — 全体図 + Key Points + 新原則
2. `failure-analysis.md` — なぜ rebuild が必要か (失敗の証拠)
3. `crash-failure-mode.html` — 設計の root reliability

### 既存 plugin を知る人 (継承戦略確認)

1. `adr-fate-table.md` — 既存 ADR の fate
2. `invariant-fate-table.md` — 既存 invariant の継承
3. `deletion-inventory.md` (placeholder) — 何を消すか

### 実装する人 (実装参照)

1. `boundary-matrix.html` (placeholder) — 責務分担
2. `step-verification.html` — step framework + post-verify 規約
3. `spawn-protocol.html` (placeholder) — spawn / mailbox
4. `gate-hook.html` (placeholder) — gate 仕組み
5. `admin-cycle.html` (placeholder) — admin polling
6. `rebuild-plan.md` (placeholder) — Phase 1-4 plan + Phase 1 PoC 手順

---

## 進捗 status (2026-05-12 時点)

| status | file 数 | 列挙 |
|---|---|---|
| ✅ 本 session 実装済 | 7 | README / overview / failure-analysis / adr-fate-table / invariant-fate-table / crash-failure-mode / step-verification |
| 🟡 placeholder のみ | 11 | boundary-matrix / spawn-protocol / gate-hook / admin-cycle / deletion-inventory / rebuild-plan / regression-test-strategy / dual-stack-routing / pitfalls-inheritance / glossary / changelog |

次 session で残 11 file を実装する。

---

## 関連 (本 spec の外)

- `/tmp/twill-rebuild-design.html` — draft-v1 (本 spec の原案、rollback 用、archive 候補)
- `architecture/decisions/ADR-001` 〜 `ADR-042` — 既存 ADR (`adr-fate-table.md` で audit)
- `plugins/twl/refs/ref-invariants.md` — 既存 invariant SSoT (`invariant-fate-table.md` で audit、ref-invariants.md 自体の drift 課題あり)
- doobidoo Memory MCP: 本 session の lesson 3 件保存済 (`hash 6ef844e9 / 74b7cdf7 / 7727b59f`)
- ADR-043 (起票予定) — 本 spec 全体への正典 ADR、Superseded by 連鎖の起点

---

## 本 spec の SSoT 位置

- 本 spec directory = twill plugin radical rebuild の **設計仕様 SSoT**
- 旧 `architecture/decisions/` の ADR 43 件は `adr-fate-table.md` で fate を決定し、Superseded 化を計画的に進める
- 旧 `plugins/twl/refs/ref-invariants.md` の invariant 19 件は `invariant-fate-table.md` で継承戦略を決定 + drift 訂正
- 実装着手後の正典 ADR は `architecture/decisions/ADR-043-twill-radical-rebuild.md` (md 本体 + 本 spec を supplement として link)
