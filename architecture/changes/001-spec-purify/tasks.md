# Tasks: 001-spec-purify

15-18 commit の実装 checklist。

## Phase 5: Implementation

### Foundation (rule + skill 確立)

- [x] **C1**: changes/001-spec-purify/ change package 作成 (proposal + design + tasks + spec-delta/MODIFIED.md + spec-delta/ADDED.md + changes/README.md) — **本 commit**
- [ ] **C2**: R-14〜R-17 spec-management-rules.md 追記
- [ ] **C3**: R-18〜R-20 spec-management-rules.md 追記 + SKILL.md 更新 (Phase F 4 軸目 mention + R-14〜R-20 サマリ table)
- [ ] **C4**: ADR-0013-spec-clean-architecture 新規 (decisions/)
- [ ] **C5**: steering/ (product/tech/structure.md) 新設
- [ ] **C6**: ReSpec markup HTML template 追加 (spec-management-rules.md)

### Specialist + Tool 実装

- [ ] **C7**: 新 specialist `specialist-spec-review-temporal.md` 作成 + registry.yaml update (specialist entry + glossary.specialist.examples) + ref-specialist-output-schema.md (spec-temporal category enum 追加) + ref-specialist-spec-review-constraints.md (4 軸目言及)
- [ ] **C8**: Vale config (.vale.ini + styles/TwillSpec/{PastTense, DeclarativeOnly, CodeBlock}.yml) + textlint config (.textlintrc)
- [ ] **C9**: 新 MCP tool `twl_spec_content_check` 実装 (cli/twl/src/twl/mcp_server/tools_spec.py + tools.py 登録) + hook 拡張 (pre-tool-use-spec-write-boundary.sh に時系列パターン soft warn 追加)
- [ ] **C10**: bats 新規 4 file (tool-architect-temporal.bats + specialist-spec-review-temporal.bats + twl-spec-content-check.bats + changes-dir-structure.bats) + 既存 2 file update (tool-architect-rules.bats + tool-architect-deployment.bats)

### spec/ 18 file refactor

- [ ] **C11**: spec/ refactor group A (orientation 3 file: README + overview + failure-analysis)
- [ ] **C12**: spec/ refactor group B (core 8 file: boundary-matrix + spawn-protocol + crash-failure-mode + gate-hook + monitor-policy + hooks-mcp-policy + admin-cycle + atomic-verification)
- [ ] **C13**: spec/ refactor group C (policy/auxiliary 7 file: tool-architecture + twl-mcp-integration + ssot-design + glossary + registry-schema + architecture-graph + changelog 一部)

### Archive + CI

- [ ] **C14**: archive/migration/ 移動 + R-4 inbound link 全更新 (D3 / Z1 適用)
- [ ] **C15**: L5 CI 新規 (.github/workflows/spec-content-check.yml + spec-respec-build.yml) + spec-link-check.yml paths 拡張

## Phase 6: Quality Review

- [ ] **F1〜Fn**: 3 並列 code-reviewer findings 対応 (CRITICAL 1 件以上で本 wave 留め置き、N は finding 件数依存)

## Phase 7: Summary

- [ ] **G1**: changelog.html entry 追加 (本 wave 完遂 marker、Phase G)
- [ ] **G2**: archive/changes/2026-05-16-001-spec-purify/ に移動 (R-17 lifecycle)
- [ ] **G3**: working-memory.md 退避 + doobidoo memory store (lesson 永続化)

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
