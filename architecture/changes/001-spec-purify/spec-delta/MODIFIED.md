# Modified Specs

spec/ 18 file の変更概要 (C11〜C13 + C14)

## Group A: orientation (3 file、C11)

### README.html
- 過去メモ削除 (33 件): dir-first refactoring 経緯、過去 draft 版 (twill-spec-purify Phase) 説明、SSoT 位置の歴史記述
- machine-readable index (`<dl class="mri">`) 維持
- ReSpec markup 追加: 新規 section に `<section class="normative">` / `<aside class="ednote">`
- `architecture/migration/` → `archive/migration/` 参照更新 (R-4、7 件)
- changes/ + archive/ + steering/ entry を index table に追加 (R-1)

### overview.html
- 過去日付 (15 件) 削除
- 旧用語比較記述 (7 件) 削除 ("以前は phase だった" 等)
- ReSpec markup 追加 (新規 section のみ)

### failure-analysis.html
- "F-4 (2026-05-15 追記)" 等の日付 (4 件) 削除
- "Phase I dig で追加" 等の Phase reference (1 件) 削除
- ReSpec markup 追加

## Group B: core (8 file、C12)

### boundary-matrix.html
- "(2026-05-12) 変更" 等の日付 (13 件) 削除
- "(旧 phase)" 等の括弧書き過去比較 (2 件) 削除
- ReSpec markup 追加

### spawn-protocol.html
- pseudocode 移行: spawn-tmux.sh / mailbox.sh の bash pseudocode (~150 行) → mermaid sequence diagram 置換
- experiment-index.html#exp-010 link 追加 (孤立 deduced claim 解消)
- 過去日付 (8 件) + 過去比較 (10 件) 削除
- ReSpec markup 追加

### crash-failure-mode.html
- 架空 admin-health-check.sh コード削除 (R-15 違反)
- experiment-verified link 追加
- 未来 promise (5 件) 削除
- ReSpec markup 追加

### gate-hook.html
- 架空 phase-gate.sh / twl_phase_gate_check コード削除 (~120 行、Agent A 検出の最大 risk file)
- 規範表現: HTML table + JSON Schema で hook config schema 表現
- 過去日付 (3 件) 削除
- ReSpec markup 追加

### monitor-policy.html
- 架空 administrator/SKILL.md コード削除 (Step 0 health-check の架空 pseudocode)
- mermaid state machine で monitor lifecycle 表現
- 過去 round 記述 ("Round 1 (Phase I 2026-05-15) で確定") 削除
- ReSpec markup 追加

### hooks-mcp-policy.html
- Stage A/B/C "migration" 記述削除 (現状仕様のみ宣言)
- 未来 promise (12 件) → 現状形に書き換え or 削除
- ReSpec markup 追加

### admin-cycle.html
- 架空 admin mailbox mail 例削除 (現 mail schema と不一致)
- 架空 CronCreate SKILL.md コード削除
- mermaid sequence で admin cycle 表現
- ReSpec markup 追加

### atomic-verification.html
- "draft-v3 (2026-05-13)" header 削除
- "旧 step-verification.html から rename" 履歴削除
- 規範 SKILL.md schema を table 化
- ReSpec markup 追加

## Group C: policy/auxiliary (7 file、C13)

### tool-architecture.html
- 27 件の日付マーカー削除 (worst 3)
- "draft-v5 (2026-05-16)" header 削除
- Phase A-G 仕様は現状形 declarative で維持 (本 spec の核心、保持必須)
- "2026-05-13 dig" / "2026-05-16 確定" section marker 削除
- ReSpec markup 追加

### twl-mcp-integration.html
- 12 件の日付削除、11 件の過去比較削除
- TWL_AUDIT propagation コード (架空) → schema table に置換
- ReSpec markup 追加

### ssot-design.html
- 18 件の日付削除
- 廃案 3 案の "歴史的記録" section → `archive/decisions/0001-ssot-design-rejected-alternatives.md` に切り出し
- atomic SKILL.md 4-phase 例 (旧 `$ARGUMENTS[session]` 記法含む) → schema table + mermaid 置換
- ReSpec markup 追加

### glossary.html
- 37 件の日付削除 (worst 2)
- §11 forbidden synonym table から "(2026-05-13) rename" 等の追加日付削除
- "旧 〜" / "廃止" の過去比較記述削除 (16 件 → 0 件、glossary 内 forbidden table は legitimate exception)
- ReSpec markup 追加

### registry-schema.html
- 74 件 (worst 1) の過去メモ削除
- Phase 1 PoC 未来 promise (20 件) → 現状形に書き換え (例: "Phase 1 PoC で実体作成" → "components seed に列挙")
- "(2026-05-13) 新規" / "draft-v1" マーカー削除
- ReSpec markup 追加

### architecture-graph.html
- `archive/migration/` への edge 更新 (R-4)
- `changes/` cluster node 追加 (R-2)
- 過去 dig 結果記述 (2 件) 削除
- ReSpec markup 追加

### changelog.html
- C16 で本 wave entry 追加 (Phase G、本 file 自身は changelog なので過去日付は legitimate)
- 既存 entry は維持 (R-14 例外)

## R-4 link 全更新 (C14)

migration/ → archive/migration/ への path 変更で、以下 file の inbound link を update:

- `architecture/spec/spawn-protocol.html` (× 2)
- `architecture/spec/admin-cycle.html` (× 1)
- `architecture/spec/monitor-policy.html` (× 1)
- `architecture/spec/registry-schema.html` (× 2)
- `architecture/spec/gate-hook.html` (× 1)
- `architecture/spec/README.html` (× 7)
- `architecture/spec/architecture-graph.html` (× 7、cluster node href)
- `plugins/twl/agents/specialist-spec-review-ssot.md` (Bash コマンド例内、× 2)

合計 23 箇所更新。`spec-anchor-link-check.py` broken 0 で完了確認。
