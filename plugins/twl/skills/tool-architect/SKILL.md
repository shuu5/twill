---
name: twl:tool-architect
description: |
  tool-architect: architecture/spec/ HTML 編集の唯一 author。
  twill plugin の新仕様 (architecture spec HTML) を管理する spec edit tool。
  spec edit boundary hook で caller を機械的に enforce。
  spec 編集前に `export TWL_TOOL_CONTEXT=tool-architect` MUST。

  Use when user: needs to edit architecture/spec/ HTML files (content update, refactor, new file addition).
type: tool
effort: medium
allowed-tools: [Bash, Read, Edit, Write, Skill, Agent]
spawnable_by:
  - user
  - administrator
---

# tool-architect

architecture/spec/ HTML 編集の唯一 author。twill plugin の新仕様 (architecture spec) を管理する。

## architecture/ ディレクトリ構造 (SSoT)

```
architecture/
├── spec/              ← 新 twill 仕様 SSoT (純粋 architecture spec、HTML のみ + common.css)
├── migration/         ← 旧→新 移行計画
├── research/          ← 調査レポート / 実験記録
├── archive/           ← 旧資産 (deprecated 仕様、rollback 保持、過去 ADR 等)
└── decisions/         ← 新 architecture ADR (旧 ADR は archive/decisions/ に保持)
```

**tool-architect の編集対象は `architecture/spec/` 配下 (sub-dir 全 nest 含む) のみ**。他 dir (migration / research / archive / decisions) は本 SKILL の責務外。

## caller marker (前提 MUST)

- 編集前: `export TWL_TOOL_CONTEXT=tool-architect`
- 編集後: `unset TWL_TOOL_CONTEXT` (MUST、leak 防止)
  - 同 shell で後続 spawn される他 caller (phaser-* / admin / 等) が `tool-architect` 扱いで spec を誤編集する事故を防ぐ
  - sub-process は env を継承するため、unset しないと sub-shell 経由でも leak する
- hook (`plugins/twl/scripts/hooks/pre-tool-use-spec-write-boundary.sh`) で機械的 enforce、未 set / 他 caller で `architecture/spec/` 配下 (sub-dir 全 nest 含む) を Edit/Write/NotebookEdit しようとすると JSON `permissionDecision: deny` を返す

## 管理ルール (R-1〜R-9)

詳細: [`refs/spec-management-rules.md`](refs/spec-management-rules.md) — R-1〜R-9 + checklist + HTML template + CI gate 一覧

### サマリ

| # | ルール | 強制方法 (現状) |
|---|---|---|
| R-1 | 新 file 追加時に `architecture/spec/README.html` index table に entry 追加 MUST | PR review |
| R-2 | 新 file 追加時に `architecture/spec/architecture-graph.html` の node + edge 追加 MUST | PR review |
| R-3 | 新 file は ≥1 inbound link 必須 (orphan 禁止、README は entry point 例外) | `spec-anchor-link-check.py --check-orphan` (CI) |
| R-4 | file 削除/rename 時に inbound/outbound link 全更新 MUST | `spec-anchor-link-check.py` (CI、broken 0) |
| R-5 | badge=outline で merge 禁止 (content 化完了後 merge) | PR review |
| R-6 | HTML 以外は `research/` or `archive/` 限定、`spec/` 配下に置かない (common.css 例外) | PR review |
| R-7 | spec 編集前 `TWL_TOOL_CONTEXT=tool-architect` env set MUST | `pre-tool-use-spec-write-boundary.sh` hook |
| R-8 | PR 内で broken link 0 + orphan 0 必須 | `.github/workflows/spec-link-check.yml` CI gate |
| R-9 | architecture-graph.html は手動 maintenance | tool-architect 規律 (PR review) |

## 標準ワークフロー

```bash
# 1. caller marker set
export TWL_TOOL_CONTEXT=tool-architect

# 2. spec 編集 (Edit/Write)
#    - 新 file 追加: refs/spec-management-rules.md の HTML template から起こす
#    - 編集後 R-1〜R-9 checklist を walkthrough (refs/spec-management-rules.md)

# 3. 機械検証
python3 scripts/spec-anchor-link-check.py --check-orphan --output text
# → "broken: 0" + "orphan: 0" 両方確認、exit 0 必須

# 4. caller marker unset (MUST、leak 防止)
unset TWL_TOOL_CONTEXT

# 5. commit + push (host で実施、message prefix は project convention に従う)
git add architecture/spec/ && git commit -m "spec(<file>): <change summary>" && git push
```

## file 操作の checklist (refs/spec-management-rules.md 参照)

| 操作 | 主要 step |
|---|---|
| 新規追加 | HTML template → R-1 (README) + R-2 (graph) + R-3 (inbound) 適用 → 機械検証 |
| 編集 | R-7 caller marker → 内容変更 → (badge 変更時 R-5 / link 変更時 R-4) → 機械検証 |
| 削除 | 全 inbound link 更新 (R-4) → README + graph から entry 削除 (R-1 + R-2) → 機械検証 |
| rename | 全 inbound href 更新 (R-4) → README + graph entry 更新 → 機械検証 |
| move (dir 間) | rename と同じ + R-6 (HTML / 非 HTML の境界) 適用 |

## 関連 spec / file

- `architecture/spec/tool-architecture.html` — tool-* 3 件 architecture spec (役割 / verify 機構 / PR cycle、本 SKILL の高レベル仕様 SSoT、§3.6 で Clean redesign 整合性宣言)
- `architecture/spec/architecture-graph.html` — link 図 hub (R-2 強制 target)
- `architecture/spec/README.html` — index hub (R-1 強制 target、entry point)
- `architecture/spec/registry-schema.html` — registry.yaml schema 定義
- `architecture/decisions/ADR-0012-administrator-rebrand.md` — administrator rebrand (Proposed)
- `scripts/spec-anchor-link-check.py` — link integrity 機械検証 tool
- `.github/workflows/spec-link-check.yml` — CI gate (R-8 強制)
- `plugins/twl/scripts/hooks/pre-tool-use-spec-write-boundary.sh` — caller marker enforce (R-7 強制)
- [`refs/spec-management-rules.md`](refs/spec-management-rules.md) — 本 SKILL の規律 ref doc (詳細)
