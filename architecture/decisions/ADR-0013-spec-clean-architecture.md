# ADR-0013: spec clean architecture (案 F adoption)

## Status

**Accepted** (2026-05-16)

## Context

`architecture/spec/` の 18 file (HTML) が次の構造的問題を抱えていた (Agent A audit、2026-05-16 Phase 2):

1. **過去メモ密集**: worst 5 file で 33〜74 件の時系列マーカー (`(YYYY-MM-DD)` 日付 / "Phase N で" / "以前は〜" / "未作成 stub" 等)。現在形 declarative と過去 narration が混在し、現状仕様の判別が困難
2. **デモコード drift**: 57 件中 19 件が実コード照合不能の架空 (phase-gate.sh / twl_phase_gate_check MCP tool / administrator/SKILL.md 等の実在しない file 参照)
3. **experiment-verified 孤立**: EXP-014 等は spec/ から link 不在、verified claim と verify_source の整合性 audit が困難
4. **tool-architect 多層 enforce 不在**: 現状 R-1〜R-13 は manual + bats のみで、機械検出は broken link 0 / orphan 0 / caller marker hook のみ。content semantic 検出は皆無

これにより:
- AI agent (tool-architect) が新規編集時、既存の過去メモ混在を model にして drift を増幅する負の feedback loop
- Phase F 3 軸 (vocabulary / structure / ssot) では content semantic の問題を audit できない
- 5 軸 SSoT (SKILL / spec / rules / ref-schema / registry) は維持しているが、spec/ 自身の content quality は drift 状態

user の品質要求 (2026-05-16): 「メンテナンス性 + 論理構造再現性 + 安全性 + 整合性」を最大化、budget は安全性に含めない。

## Decision

`change 001-spec-purify` (architecture/changes/001-spec-purify/) で **案 F (clean architecture)** を採用、以下を確立する:

1. **OpenSpec 3 階層 lifecycle 採用** — `architecture/changes/<NNN>-<slug>/` (進行中) / `archive/changes/YYYY-MM-DD-<NNN>-<slug>/` (完了) / `archive/migration/` (D3 / Z1、旧 migration/ 統合)

2. **GitHub Spec Kit `steering/` dir 新設** — `architecture/steering/{product,tech,structure}.md` で project-wide 規約を SKILL.md / CLAUDE.md から独立化

3. **R-14〜R-20 rule 新設** — `plugins/twl/skills/tool-architect/refs/spec-management-rules.md` に追加 (R-14 現在形 declarative / R-15 code block 制限 / R-16 archive 移動 / R-17 changes/ lifecycle / R-18 ReSpec semantic markup / R-19 多層 hook chain / R-20 MCP tool 統合)

4. **Phase F 4 軸目 specialist 新規** — `plugins/twl/agents/specialist-spec-review-temporal.md` (opus 固定 R-13、content semantic audit、R-14〜R-18 検証)

5. **新 MCP tool `twl_spec_content_check` 実装** — `cli/twl/src/twl/mcp_server/tools_spec.py` (Python、html.parser + regex、check_types: past_narration / demo_code / declarative / changes_lifecycle / respec_markup)

6. **多層防御 L1-L5 確立**:
   - L1 skill: SKILL.md + spec-management-rules.md R-14〜R-20
   - L2 bats: 新規 4 file (tool-architect-temporal / specialist-spec-review-temporal / twl-spec-content-check / changes-dir-structure) + 既存 2 file update
   - L3 PreToolUse hook + MCP tool: 既存 hook 拡張 + 新 MCP tool
   - L4 pre-commit: Vale (.vale.ini + styles/TwillSpec/) + textlint (.textlintrc)
   - L5 CI: 既存 spec-link-check.yml 拡張 + 新 2 workflow (spec-content-check.yml + spec-respec-build.yml)

7. **spec/ 18 file 全 refactor** — 時系列メモ削除 + デモコード論理表現置換 (mermaid sequence / state machine / HTML table / JSON Schema / ABNF) + ReSpec semantic markup 適用 (新規 section のみ、grandfather)

8. **`architecture/migration/` → `architecture/archive/migration/` 吸収** — D3 / Z1 確定、R-4 link 全更新 (23 箇所)

## Rationale

### 案 F 採用根拠

案 G → 案 F エスカレーション risk 分析 (Phase 4) で **steering/ + MCP tool の後追い追加** が中レベル整合性 risk を持つことを特定:

- **steering/ 後追い**: 規約 SSoT が SKILL.md + CLAUDE.md + steering/ の 3 箇所重複、migration plan 必要
- **MCP tool 後追い**: hook の regex logic と MCP tool の HTML parse logic が重複、hook → MCP tool refactor 必要

一括設計 (案 F 直行) ならこれら整合性 risk は 0。user が「budget を安全性に含めない」観点から、整合性 risk 最小化 = 一括設計が正解。

### 業界 BP 準拠

- **OpenSpec** (verified URL: https://openspec.dev/、v1.0 2026-01) — Brownfield-first SDD、changes/ + archive/ lifecycle が最も洗練
- **GitHub Spec Kit** (verified URL: https://github.com/github/spec-kit、2025-09、96K+ stars) — `.specify/` + `steering/` 構成、CHANGELOG ルート別置き
- **ReSpec** (verified URL: https://respec.org/docs/) — `<section class="normative">` / `<aside class="example">` semantic markup
- **Diátaxis** (verified URL: https://diataxis.fr/) — Reference / How-to / Explanation / Tutorial 4 象限分離
- **Vale** (verified URL: https://vale.sh/docs) — existence rule type、日本語日付 pattern 検出可能 (regexp2 ライブラリ)
- **AWS Kiro** (re:Invent 2025) — requirements/design/tasks 3 文書分離 + EARS 記法

### 5 軸 SSoT 6 軸目への拡張

既存 5 軸 (SKILL / spec / rules / ref-schema / registry) に **changes/ change package** を 6 軸目として追加。各軸が独立 SSoT として cross-ref で双方向整合性 enforce。

## Consequences

### Positive

- **長期メンテ性 ◎**: 業界標準 (OpenSpec + Spec Kit + ReSpec + Diátaxis) 完全準拠、新メンバー参入コスト ↓
- **整合性 risk 0**: 一括設計、後追い refactor 不要
- **再現性 ◎**: change lifecycle 明示 + LLM 判断不要、proven pattern (前 session 22 commit) 踏襲
- **安全性 ◎**: 多層防御 L1-L5、defense-in-depth で単層 bypass を許容
- **content semantic audit 確立**: Phase F 4 軸目 + MCP tool で過去メモ・デモコード drift を機械検出
- **証跡永続化**: changes/ + ADR + changelog の 3 階層で「何をなぜ変えたか」が永続記録

### Negative / Trade-offs

- **実装規模大**: 15-18 commit、新 MCP tool Python 実装 + Vale config 複数 + 新 CI workflow 2 件
- **1 session 超えリスク**: su-compact を 1-2 回挿む可能性
- **C9 (MCP tool) の false-positive チューニング負荷**: HTML parse + regex の semantic 判定は初期 tuning が必要
- **bats test 件数増**: 既存 99 + 新規 ~40 = 約 140 test、CI 時間 +30%

### Risk Mitigation

- 各 commit 後 broken 0 / orphan 0 / bats PASS 維持
- false-positive 高 risk な検出は WARNING (not CRITICAL) で発行、CI は warning mode 開始 → 安定後 error mode 切替
- su-compact 時に working-memory.md 退避 + doobidoo memory store で knowledge 永続化
- 各 phase 完了時 commit + push (incremental review pattern)

### Implementation timing

- 本 ADR Accepted 後、change 001-spec-purify C5 以降を実装
- C5: steering/ 新設
- C6: ReSpec markup template 追加 (spec-management-rules.md)
- C7: specialist-spec-review-temporal.md 新規
- C8: Vale + textlint config
- C9: twl_spec_content_check MCP tool 実装
- C10: bats 新規 4 file + 既存 2 file update
- C11-C13: spec/ 18 file 全 refactor (group A/B/C)
- C14: archive/migration/ 移動 + R-4 link 全更新
- C15: L5 CI 新規 2 workflow
- C16 (G1): changelog.html entry + archive/changes/ 移動

## Alternatives Considered

### 案 E minimal (rejected、Phase 4)

- **内容**: 既存 file への additive only、新 specialist なし (4 軸を structure 軸 Step 7 に統合)、MCP tool なし、Vale 2-3 rule
- **rejection 理由**: 4 軸目を structure に詰め込むため specialist 責務肥大化、整合性 △。content semantic 検出の false-positive リスク高い

### 案 G pragmatic (rejected、Phase 4 + 再検討)

- **内容**: twill convention 踏襲、新 specialist 1 (content 統合)、MCP tool なし、Vale 5-7 rule、L5 既存 workflow 拡張
- **rejection 理由**: 案 G → 案 F エスカレーション (後から steering/ + MCP tool 追加) は中レベル整合性 risk を持つ。user が「budget を安全性に含めない」観点で、一括設計 (案 F 直行) が安全性最大化

### 案 H: do nothing (考慮なし、user 要求と矛盾)

現状放置 = drift 拡大、5 軸 SSoT も spec/ content quality が drift で実質機能不全。user 要求 (品質保証仕組み確立) と矛盾。

## References

### 関連 spec / rule

- `plugins/twl/skills/tool-architect/refs/spec-management-rules.md` — R-1〜R-20 詳細 (本 ADR で R-14〜R-20 を確定)
- `plugins/twl/skills/tool-architect/SKILL.md` — 7-phase multi-agent PR cycle (本 ADR で Phase F 4 軸目を確定)
- `architecture/changes/001-spec-purify/` — 本 ADR を反映する change package (proposal/design/tasks/spec-delta)
- `architecture/spec/tool-architecture.html` — tool-* 3 件 spec (§3.3 7-phase、§3.7 5 agent、§3.8 fix loop SLA)

### 関連 ADR

- ADR-0012-administrator-rebrand (Proposed、su-* → admin-* rebrand、本 ADR と独立)

### 業界 BP (verified URL fetched)

- [OpenSpec](https://openspec.dev/) — changes/ + archive/ 3 階層 lifecycle
- [GitHub Spec Kit](https://github.com/github/spec-kit) — steering/ + decisions/ 構成
- [ReSpec](https://respec.org/docs/) — semantic markup (normative / informative / example / ednote)
- [Diátaxis](https://diataxis.fr/) — 4 象限分離 (Reference / How-to / Explanation / Tutorial)
- [Vale](https://vale.sh/docs) — existence rule + regexp2 lookahead
- [W3C Manual of Style](https://w3c.github.io/manual-of-style/) — normative vs informative 慣行
- [RFC 2119](https://datatracker.ietf.org/doc/html/rfc2119) — MUST/SHOULD/MAY normative keyword
- [TypeSpec 1.0](https://typespec.io/) — `@example` decorator declarative example
- [Cyrille Martraire, Living Documentation (2019)](https://www.pearson.com/us/higher-education/program/Martraire-Living-Documentation-Continuous-Knowledge-Sharing-by-Design/PGM2683060.html) — present tense + git history が source of past changes
- [AWS Kiro](https://kiro.dev/docs/specs/) — requirements/design/tasks 3 文書 + EARS 記法
- [Endor Labs Agent Governance](https://www.endorlabs.com/learn/introducing-agent-governance-using-hooks-to-bring-visibility-to-ai-coding-agents) — Claude Code Hooks + MCP tool 統合
- [Zenflow committee approach](https://zencoder.ai/zenflow) — multi-model 相互検証

### 関連 Issue / PR / 過去 ADR

- 本 change package 完遂後、`architecture/spec/changelog.html` に entry 追加 (Phase G、C16)
- 後続 task: EXP-029 smoke 検証 (5 agent 実機 invoke、deduced → experiment-verified 昇格)、旧 worker-* 14 agent rename (前 session defer)

### 業界 BP 適用 mapping

| 業界 BP | 本 ADR での採用要素 |
|---|---|
| OpenSpec | `changes/` + `archive/changes/` lifecycle、proposal/design/tasks/spec-delta 4 文書 |
| GitHub Spec Kit | `steering/{product,tech,structure}.md` 新設、CHANGELOG 別置き |
| ReSpec | `<section class="normative">` / `<aside class="example">` / `<pre data-status>` markup |
| Diátaxis | spec/ = Reference、changes/ = How-to、steering/ = Explanation の責務分離 |
| Vale | `Twill.PastTense` / `Twill.DeclarativeOnly` / `Twill.CodeBlock` custom rule |
| AWS Kiro | proposal.md + design.md + tasks.md の 3 文書分離 (EARS 記法は本 task では採用見送り、別 ADR 候補) |
| Living Documentation | 過去 narration → git history + archive、spec/ は現在形 declarative のみ |
