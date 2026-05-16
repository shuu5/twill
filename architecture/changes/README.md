# architecture/changes/

進行中の変更提案を管理する作業領域 (OpenSpec changes/ 相当)。

## Lifecycle (R-17)

1. **作成**: `changes/<NNN>-<slug>/` 配下に `proposal.md` + `design.md` + `tasks.md` 配置
2. **実装中**: `tasks.md` の checklist を更新しながら commit
3. **merge 完了**: `architecture/archive/changes/YYYY-MM-DD-NNN-<slug>/` に `git mv`

## 命名規則

- NNN: 3 桁連番 (001, 002, ...)
- slug: kebab-case 20 文字以内

## change package の構成

- `proposal.md`: scope 宣言 (what / why / acceptance criteria)
- `design.md`: 技術選択根拠 + trade-off + 業界 framework 参照
- `tasks.md`: 実装タスク分解 (commit checklist)
- `spec-delta/`: ADDED / MODIFIED / REMOVED セクション別差分 (任意)

## SSoT 関係 (D2 三出し責務分離)

| dir | 役割 | 寿命 | 編集権限 |
|---|---|---|---|
| `architecture/spec/` | 現状の正式仕様 (Diátaxis Reference) | 永続 (現在形 declarative) | tool-architect 専任 (R-7) |
| `architecture/changes/` | 変更提案 (How-to) | 中期 (proposal → archive) | tool-architect / human contributor |
| `architecture/decisions/` | ADR (Explanation、決定の根拠) | 永続 (immutable、Status: Superseded で更新) | architect role |
| `architecture/archive/changes/` | 完了済み change package | 永続 (rollback 参照用) | move only |
| `architecture/steering/` | project-wide 規約 (Spec Kit 方式) | 永続 (contributor guide) | architect role |

## 関連 rule

R-16 / R-17 / R-18: [`plugins/twl/skills/tool-architect/refs/spec-management-rules.md`](../../plugins/twl/skills/tool-architect/refs/spec-management-rules.md) 参照
