# Added Items

新規追加 dir / file の listing

## New Directories

| Path | 役割 | Commit |
|---|---|---|
| `architecture/changes/` | 進行中の変更提案 (OpenSpec lifecycle、本 commit で作成) | C1 |
| `architecture/changes/001-spec-purify/` | 本 change package | C1 |
| `architecture/changes/001-spec-purify/spec-delta/` | spec/ 変更概要 (ADDED/MODIFIED) | C1 |
| `architecture/steering/` | project-wide 規約 (Spec Kit steering/ 方式) | C5 |
| `architecture/archive/changes/` | 完了 change package 移動先 (R-17 lifecycle) | C16 (G2) |
| `architecture/archive/migration/` | 旧 architecture/migration/ 統合先 (D3 / Z1) | C14 |
| `styles/TwillSpec/` | Vale custom rule dir (project root) | C8 |

## New Files

### Specs / Rules / Docs (Phase 5 Foundation)

| Path | 役割 | Commit |
|---|---|---|
| `architecture/changes/README.md` | changes/ 運用ガイド | C1 |
| `architecture/changes/001-spec-purify/proposal.md` | scope 宣言 | C1 |
| `architecture/changes/001-spec-purify/design.md` | 技術選択根拠 | C1 |
| `architecture/changes/001-spec-purify/tasks.md` | 実装 checklist | C1 |
| `architecture/changes/001-spec-purify/spec-delta/MODIFIED.md` | spec/ 変更概要 | C1 |
| `architecture/changes/001-spec-purify/spec-delta/ADDED.md` | 新規追加概要 (本 file) | C1 |
| `architecture/decisions/ADR-0013-spec-clean-architecture.md` | 案 F 設計根拠 ADR | C4 |
| `architecture/steering/product.md` | TWiLL plugin product vision + goals | C5 |
| `architecture/steering/tech.md` | 技術選択・言語・tool constraint | C5 |
| `architecture/steering/structure.md` | spec/ dir 構造・R-N 適用範囲・contributor guide | C5 |
| `architecture/archive/decisions/0001-ssot-design-rejected-alternatives.md` | ssot-design.html から切り出した 3 廃案 | C13 |
| `architecture/spec/changelog.html` entry (G1 で追加) | 本 wave 完遂 marker | G1 |

### Specialist Agent (C7)

| Path | 役割 |
|---|---|
| `plugins/twl/agents/specialist-spec-review-temporal.md` | Phase F 4 軸目 (時系列マーカー / デモコード / 論理表現)、opus 固定 R-13 |

### MCP Tool (C9)

| Path | 役割 |
|---|---|
| `cli/twl/src/twl/mcp_server/tools_spec.py` | `twl_spec_content_check` handler 実装 (Python、html.parser + regex) |

### Lint Config (C8)

| Path | 役割 |
|---|---|
| `.vale.ini` | Vale 設定 (StylesPath = styles/TwillSpec) |
| `styles/TwillSpec/PastTense.yml` | 過去形 narration 検出 (existence rule) |
| `styles/TwillSpec/DeclarativeOnly.yml` | 「以前は」「Phase N で」「未作成」「stub」検出 |
| `styles/TwillSpec/CodeBlock.yml` | `<pre>` タグ存在検出 (warning) |
| `.textlintrc` | textlint 設定 (changelog.html 等 MD 系) |

### Tests (C10)

| Path | 内容 (test 件数) |
|---|---|
| `plugins/twl/tests/bats/skills/tool-architect-temporal.bats` | R-14〜R-20 heading 存在 + content grep (~12 test) |
| `plugins/twl/tests/bats/agents/specialist-spec-review-temporal.bats` | model=opus + frontmatter + category=spec-temporal (~11 test) |
| `plugins/twl/tests/bats/scripts/twl-spec-content-check.bats` | MCP tool handler 単体 + 統合 (~10 test) |
| `plugins/twl/tests/bats/structure/changes-dir-structure.bats` | changes/ 3 文書 + spec-delta 揃い確認 (~8 test) |

### CI Workflows (C15)

| Path | 役割 |
|---|---|
| `.github/workflows/spec-content-check.yml` | L5 CI: twl_spec_content_check + Vale CLI 実行 |
| `.github/workflows/spec-respec-build.yml` | L5 CI: ReSpec CLI build success check |

## Modified Files

### Skill / Rules / Refs

| Path | 変更内容 | Commit |
|---|---|---|
| `plugins/twl/skills/tool-architect/refs/spec-management-rules.md` | R-14〜R-20 追加 (7 rule) + CI gate 一覧 update + HTML template に ReSpec markup 追加 | C2, C3, C6 |
| `plugins/twl/skills/tool-architect/SKILL.md` | Phase F 4 軸目 mention + R-14〜R-20 サマリ table + dir 構造図 update (changes/, steering/, archive/) | C3 |
| `plugins/twl/refs/ref-specialist-output-schema.md` | category enum に `spec-temporal` 追加 | C7 |
| `plugins/twl/refs/ref-specialist-spec-review-constraints.md` | 4 軸目 (temporal) 言及追加 | C7 |
| `plugins/twl/registry.yaml` | components に specialist-spec-review-temporal entry 追加 + glossary.specialist.examples に追加 | C7 |
| `plugins/twl/scripts/hooks/pre-tool-use-spec-write-boundary.sh` | 時系列パターン warning 検出 logic 追加 (deny ではなく additionalContext warning) | C9 |
| `cli/twl/src/twl/mcp_server/tools.py` | `twl_spec_content_check` tool 登録 | C9 |

### Tests (既存 update)

| Path | 変更内容 |
|---|---|
| `plugins/twl/tests/bats/skills/tool-architect-rules.bats` | R-14〜R-20 grep test 追加 (~7 test 追加) |
| `plugins/twl/tests/bats/integration/tool-architect-deployment.bats` | 4 軸目 specialist (temporal) test 追加、registry 6 specialist 確認に update |

### Spec/ HTML (C11/C12/C13)

合計 18 file: README + overview + failure-analysis + boundary-matrix + spawn-protocol + crash-failure-mode + gate-hook + monitor-policy + hooks-mcp-policy + admin-cycle + atomic-verification + tool-architecture + twl-mcp-integration + ssot-design + glossary + registry-schema + architecture-graph + changelog

詳細は `MODIFIED.md` 参照。

### CI (既存 update)

| Path | 変更内容 |
|---|---|
| `.github/workflows/spec-link-check.yml` | paths に `architecture/changes/**` + `architecture/archive/**` + `architecture/steering/**` 追加 |

### Migration → Archive (C14)

| 旧 path | 新 path |
|---|---|
| `architecture/migration/adr-fate-table.html` | `architecture/archive/migration/adr-fate-table.html` |
| `architecture/migration/deletion-inventory.html` | `architecture/archive/migration/deletion-inventory.html` |
| `architecture/migration/dual-stack-routing.html` | `architecture/archive/migration/dual-stack-routing.html` |
| `architecture/migration/invariant-fate-table.html` | `architecture/archive/migration/invariant-fate-table.html` |
| `architecture/migration/pitfalls-inheritance.html` | `architecture/archive/migration/pitfalls-inheritance.html` |
| `architecture/migration/rebuild-plan.html` | `architecture/archive/migration/rebuild-plan.html` |
| `architecture/migration/regression-test-strategy.html` | `architecture/archive/migration/regression-test-strategy.html` |

R-4 link 全更新 (23 箇所)。
