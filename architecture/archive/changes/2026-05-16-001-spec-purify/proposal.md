# Proposal: 001-spec-purify

architecture/spec/ purification + tool-architect 多層 enforce 強化

## What

architecture/spec/ 18 file の content を以下の原則で刷新し、tool-architect (spec edit tool) の多層防御 (L1-L5) を確立する。

### 原則 (R-14〜R-20)

1. spec/ は **現在形 declarative** 宣言のみ (時系列メモ・過去 narration 禁止) — R-14
2. spec/ 内 code block は **schema / table / ABNF / mermaid** のみ (実行可能 howto code は research/ へ link) — R-15
3. 過去 narration は **archive/ or changes/archive/** へ — R-16
4. spec の変更は **changes/ lifecycle** で管理 (proposal → spec → archive) — R-17
5. spec/ は **ReSpec semantic markup** を新規 section に必須 (`<section class="normative">` 等) — R-18
6. 上記を **多層防御 L1-L5** で自動 enforce (skill / bats / hook+MCP / pre-commit / CI) — R-19
7. 新 MCP tool `twl_spec_content_check` 統合 — R-20

## Why

現状 spec/ は以下の問題を抱える (Agent A audit 結果):

- **過去メモ密集**: worst 5 file (registry-schema 74 件 / glossary 56 件 / tool-architecture 55 件 / changelog 35 件 / README 33 件)
- **デモコード混在**: 約 57 件、うち **19 件が実コード照合不能の架空** (phase-gate.sh / twl_phase_gate_check / administrator/SKILL.md 等の実在しない file への参照)
- **experiment-verified 孤立**: EXP-014 等は spec/ から link 不在
- **deduced claim だが verified EXP link なし**: 一部 spec で `<span class="vs verified">` 表示するが、対応 EXP 不在のケース

これにより:
- 現状仕様の判別困難 (現在形 vs 過去形 混在で readability 低下)
- spec ↔ 実装 drift 増大 (架空 demo code が実装乖離を隠蔽)
- Phase F 3 軸 specialist では content semantic を audit できず
- AI agent (tool-architect) が新規編集時、既存の過去メモ混在を model にしてしまう

## Acceptance Criteria

- [ ] R-14〜R-20 spec-management-rules.md に追加 (verified: bats grep)
- [ ] specialist-spec-review-temporal.md 新規 (Phase F 4 軸目、opus 固定 R-13)
- [ ] MCP tool `twl_spec_content_check` 実装 + tools.py 登録
- [ ] Vale config (.vale.ini + styles/TwillSpec/) + textlint config (.textlintrc)
- [ ] bats 全 PASS (新規 4 file + 既存 2 file update)
- [ ] spec/ 18 file 全 refactor (時系列メモ削除 + デモコード論理表現置換 + ReSpec markup 新規 section 適用)
- [ ] `architecture/migration/` → `architecture/archive/migration/` 吸収 (D3 / Z1) + R-4 link 全更新
- [ ] L5 CI 3 workflow 全 pass (spec-link-check + spec-content-check + spec-respec-build)
- [ ] broken link 0 / orphan 0 維持
- [ ] changelog.html に Phase G entry
- [ ] 完遂後 `archive/changes/2026-05-16-001-spec-purify/` に移動 (R-17 lifecycle)

## ADR Reference

- ADR-0013-spec-clean-architecture (本 change package 中で作成、C4)

## 参照 framework (業界 BP、verified URL fetched)

- [OpenSpec](https://openspec.dev/) — changes/ + archive/ lifecycle、Brownfield-first SDD (v1.0 2026-01)
- [GitHub Spec Kit](https://github.com/github/spec-kit) — steering/ 構成、CHANGELOG ルート別置き (2025-09 公開、96K+ stars)
- [ReSpec](https://respec.org/docs/) — `<section class="normative">` / `<aside class="example">` semantic markup
- [Diátaxis](https://diataxis.fr/) — Reference / How-to / Explanation 4 象限
- [Vale](https://vale.sh/docs) — existence rule type で日付 / TODO / 過去形 narration 検出
- [TypeSpec 1.0](https://typespec.io/) — @example decorator (将来 schema 移行 candidate)

## Out of scope (defer to 別 Wave)

- **TypeSpec schema 移行**: 本 task は HTML maintenance、TypeSpec 移行は別 Wave
- **experiment-index.html 全 EXP verify**: 本 task は spec/ 浄化のみ、EXP-029 smoke は別 Wave
- **旧 worker-* 14 agent rename → specialist-***: 前 session defer task、本 task と独立
- **archive/changes/ 旧データ移行**: archive/changes/ は新規 dir、旧 changes/ なし
