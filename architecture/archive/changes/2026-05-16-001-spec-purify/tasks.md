# Tasks: 001-spec-purify

15-18 commit の実装 checklist。

## Phase 5: Implementation

### Foundation (rule + skill 確立)

- [x] **C1**: changes/001-spec-purify/ change package 作成 (proposal + design + tasks + spec-delta/MODIFIED.md + spec-delta/ADDED.md + changes/README.md) — 1fafc33e
- [x] **C2**: R-14〜R-17 spec-management-rules.md 追記 — 9220d132
- [x] **C3**: R-18〜R-20 spec-management-rules.md 追記 + SKILL.md 更新 (Phase F 4 軸目 mention + R-14〜R-20 サマリ table) — 79996184
- [x] **C4**: ADR-0013-spec-clean-architecture 新規 (decisions/) — 75175cda
- [x] **C5**: steering/ (product/tech/structure.md) 新設 — e46259bd
- [x] **C6**: ReSpec markup HTML template 追加 (spec-management-rules.md) — ee559df5

### Specialist + Tool 実装

- [x] **C7**: 新 specialist `specialist-spec-review-temporal.md` 作成 + registry.yaml update (specialist entry + glossary.specialist.examples) + ref-specialist-output-schema.md (spec-temporal category enum 追加) + ref-specialist-spec-review-constraints.md (4 軸目言及) — 7f9f9e61
- [x] **C8**: Vale config (.vale.ini + styles/TwillSpec/{PastTense, DeclarativeOnly, CodeBlock}.yml) + textlint config (.textlintrc) — 758a8967
- [x] **C9**: 新 MCP tool `twl_spec_content_check` 実装 (cli/twl/src/twl/mcp_server/tools_spec.py + tools.py 登録) + hook 拡張 (pre-tool-use-spec-write-boundary.sh に時系列パターン soft warn 追加) — ce760e13 + fbc6440b
- [x] **C10**: bats 新規 4 file (tool-architect-temporal.bats + specialist-spec-review-temporal.bats + twl-spec-content-check.bats + changes-dir-structure.bats) + 既存 2 file update (tool-architect-rules.bats + tool-architect-deployment.bats) — a2acc4e5

### spec/ 18 file refactor

- [x] **C11**: spec/ refactor group A (orientation 3 file: README + overview + failure-analysis) — 38ca96cc (overview + failure-analysis) + f4f67825 (README + 新 dir entry)
- [x] **C12**: spec/ refactor group B (core 8 file: boundary-matrix + spawn-protocol + crash-failure-mode + gate-hook + monitor-policy + hooks-mcp-policy + admin-cycle + atomic-verification) — 2649a90e〜1fd6c3a7 (8 commit)
- [x] **C13**: spec/ refactor group C (policy/auxiliary 7 file: tool-architecture + twl-mcp-integration + ssot-design + glossary + registry-schema + architecture-graph + changelog 一部) — 106ae64c〜768ae16e (7 commit)

### Archive + CI

- [x] **C14**: archive/migration/ 移動 + R-4 inbound link 全更新 (D3 / Z1 適用) — 9bf251b0
- [x] **C15**: L5 CI 新規 (.github/workflows/spec-content-check.yml + spec-respec-build.yml) + spec-link-check.yml paths 拡張 — 4ea27b26

## Phase 6: Quality Review

- [x] **F1-F6**: 3 並列 code-reviewer findings 対応 (CRITICAL 3 件 + WARNING 5 件 + INFO 3 件、CRITICAL 全件 fix で 5c576f45 commit)
- [x] **F7**: tool-architecture.html を本 wave 実装と整合化 (cross-file consistency 漏れ後追い fix、~253 行追加、§2.7 / §3.2.2 / §3.6.1 / §3.7.3.4 / §3.9 / §3.10 / §11.1 新設)
- [x] **F8**: bats `changes-dir-structure.bats` を R-17 archive 移動に追従 (9 件 → 10 件、5 件 fail → 全 PASS)
- [x] **F9-F15**: Phase 6 4 並列 review (vocabulary/structure/ssot/temporal、本 wave で新規) findings CRITICAL 15 + WARNING 11 一括 fix (前 wave からの cross-file 漏れ 8 件 + R-14 declarative 改善 5 件 + EXP-029 SSoT update + ADR-0013 References + tool-architecture.html 内部矛盾 5 件 + experiment-verified → deduced 降格 4 件 + registry.yaml comment + SKILL.md archive path)

## Phase 7: Summary

- [x] **G1**: changelog.html entry 追加 (本 wave 完遂 marker、Phase G、151e9e04)
- [x] **G2**: archive/changes/2026-05-16-001-spec-purify/ に移動 (R-17 lifecycle 完遂、151e9e04)
- [x] **G3**: working-memory.md 退避 + doobidoo memory store (lesson 永続化)

## 検証 (各 commit 後 MUST)

- [ ] broken link 0 (`python3 scripts/spec-anchor-link-check.py`)
- [ ] orphan 0 (`--check-orphan`)
- [ ] bats 全 PASS (新規 + 既存、99 + 新 4 file)
- [ ] Vale clean (C8 以降)
- [ ] L5 CI 全 pass (C15 以降、warning mode 開始)

## Budget 管理 (su-compact 計画)

| Checkpoint | 想定 progress | Action |
|---|---|---|
| C8 完了 | ~50% | su-compact 1 回目検討 (working memory 退避 + doobidoo store) |
| C13 完了 | ~80% | su-compact 2 回目検討 |
| C16 完了 | 100% | working-memory.md 退避 + Phase G |

working-memory.md に各 phase 進捗を逐次記録 (su-compact 時に context 復旧の base)。

## Emergency Override

L3 hook / L4 pre-commit の bypass が必要な場合:
1. `architecture/changes/active/intervention-log.md` に記録 (日時 / bypass 理由 / commit SHA)
2. `--no-verify` 等を実行
3. R-19 で次 commit までに resolve

bypass は **architectural decision** であり、tool-architect の autonomy 範囲外。user 確認 MUST。
