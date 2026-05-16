# Product Steering: twill plugin

twill plugin の product vision + core goals + users + success metrics。

`steering/` は project-wide 規約 (Spec Kit `steering/` 方式)。SKILL.md / CLAUDE.md とは独立した規約 SSoT として、contributor (人間 + AI) が project の方向性を理解する entry point。

## Product Vision

**TWiLL (Type-Woven, invariant-Led Layering) モノリポ**は、TWL CLI engine + plugins (twl / session 等) を統合した plugin-based development workflow を提供する。

中心思想:
- **LLM は判断のために使う、機械的にできることは機械に任せる** (CLAUDE.md global 原則)
- **chain-driven**: deps.yaml SSoT による component 構成 + workflow chain
- **autopilot-first**: 単一 Issue も co-autopilot 経由、Pilot セッションが tmux window + cld 起動 + Phase 管理を統括

## Core Goals

| Goal | Mechanism |
|---|---|
| AI agent と human contributor の協調 | CLAUDE.md (原則) + skill (オンデマンド) + hook (機械強制) + ADR (永続記録) |
| 仕様の永続性と living document 化 | `architecture/spec/` 現在形 declarative + `changes/` 変更提案 + `archive/` 完了済み |
| 多層防御による品質保証 | L1 skill + L2 bats + L3 hook+MCP + L4 pre-commit + L5 CI |
| cross-AI bias 低減 | Phase F 4 並列 specialist (opus 固定)、独立 context window |
| 再現性 (reproducibility) | OpenSpec lifecycle、proven commit chunking pattern (前 session 22 commit) |

## Users

### Primary

| User type | needs |
|---|---|
| **AI agent (tool-architect)** | 機械可読な規約 (R-1〜R-20)、明確な dir 境界、defense-in-depth な hook chain |
| **human contributor** | Spec Kit steering/ で project 方向性把握、Diátaxis 4 象限で文書探索効率 |

### Secondary

| User type | needs |
|---|---|
| **reviewer** | Phase F 4 軸 specialist findings + PR description で変更意図把握 |
| **future maintainer** | git history + ADR で「何をなぜ変えたか」、archive/ で rollback 参照 |

## Success Metrics

### Quantitative

- **PR throughput**: Wave 単位で 22 commit / 1 session を proven (前 session 実績)
- **merge gate pass rate**: bats 全 PASS + broken 0 / orphan 0 / L5 CI 全 pass = 100%
- **spec content quality**: Vale lint warning 件数 (本 task 後の baseline measurement)
- **content semantic drift**: Phase F 4 軸 specialist findings CRITICAL 件数 (本 task 後 → 0 目標)

### Qualitative

- 新規 contributor が 30 分以内に spec/ 構造を理解できる (steering/structure.md readability)
- spec edit の judgment cost が下がる (LLM が現在形 vs 過去形を機械判定可能)
- rollback 時の参照が容易 (archive/ で完了 change package が日付 prefix で時系列保持)

## Strategic Direction (本 task 後の defer)

### 短期 (1-3 wave)

- EXP-029 smoke 検証 (5 agent 実機 invoke、deduced → experiment-verified 昇格)
- 旧 worker-* 14 agent rename → specialist-*

### 中期 (3-10 wave)

- R-1/R-2/R-5 CI 機械化 (現状 PR review 依存を script 化)
- R-9 architecture-graph auto-gen (README.html → SVG 自動生成)

### 長期 (cross-cutting refactor)

- TypeSpec schema 移行 (HTML → schema-driven、業界 BP 完全準拠)
- AWS Kiro EARS 記法採用 (acceptance criteria 構造化)

## 参照

- `architecture/steering/tech.md` — 技術選択・言語・tool constraint
- `architecture/steering/structure.md` — dir 構造 + R-N 適用範囲 + contributor guide
- `plugins/twl/skills/tool-architect/SKILL.md` — spec edit 主 entry
- `architecture/decisions/ADR-0013-spec-clean-architecture.md` — 本 steering を確立した ADR
- `architecture/changes/001-spec-purify/` — 本 steering を反映する change package
