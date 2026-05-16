# Design: 001-spec-purify

技術選択根拠 + 業界 framework 適用 + 多層防御設計

## Decision Matrix (Phase 3 確定事項)

| 軸 | 値 | 意味 | 根拠 |
|---|---|---|---|
| Q1 | C | OpenSpec 3 階層 (changes/ + archive/) + Vale lint 併用 | 構造的物理分離、最も洗練された 2026 業界標準 (OpenSpec v1.0 2026-01) |
| Q2 | C | デモコード削除 + 論理表現置換 | 架空 code 19 件物理排除、EXP link で SSoT 一元化 |
| Q3 | C | 多層防御 L1-L5 | defense-in-depth、単層 bypass 防止 |
| Q4 | C | large scope、全 18 file 刷新 | 100% drift 解消、user の long-term 品質要求 |
| D1 | X1 | 1 change package = 1 feature 単位 | OpenSpec native、cross-file refactor atomic |
| D2 | Y1 | ADR / changes/ / spec 三出し責務分離 | ADR=決定根拠 / changes/=変更提案 / spec=現状 |
| D3 | Z1 | migration/ → archive/migration/ 吸収 | R-4 link 全更新で安全に統合 |
| D4 | W2 | HTML table + JSON Schema + ABNF + mermaid 図 | mermaid は GitHub native render、bats mmdc CLI syntax check 可能 |

## Phase 4 採用案 F (clean architecture) 確定根拠

ユーザー判断:
- **budget は安全性に含めない**観点
- 案 G → 案 F エスカレーションは **中レベル整合性 risk** (steering/ SSoT 重複 + hook/MCP logic 重複) のため不採用
- 一括設計で整合性 risk 0

### Alternatives Considered

#### 案 E minimal (rejected)
- 利点: additive only、完遂率 ◎
- 欠点: 4 軸目を structure 軸 Step 7 に統合、責務肥大化 (整合性 △)

#### 案 G pragmatic (rejected)
- 利点: twill convention 踏襲、proven budget
- 欠点: steering/ + MCP tool 不採用で長期メンテ性 ○ 止まり、後追い integration に中 risk

#### 案 F clean (採用) ◎
- 利点: 業界標準 (OpenSpec + Spec Kit + ReSpec + Diátaxis) 完全実装、整合性 risk 0、長期メンテ性 ◎
- 欠点: 1 session 超えリスク (su-compact 1-2 回挿む)

## 業界 framework 適用

### OpenSpec (changes/ + archive/ lifecycle)
- `architecture/changes/<NNN>-<slug>/` change package
- proposal / design / tasks / spec-delta の 4 文書
- 完了後 `archive/changes/YYYY-MM-DD-NNN-<slug>/` 移動

### GitHub Spec Kit (steering/ + decisions/)
- `architecture/steering/{product,tech,structure}.md` で project-wide 規約
- `architecture/decisions/ADR-NNNN-*.md` で重要な architectural decision

### ReSpec (semantic markup)
- `<section class="normative">` / `<section class="informative">`
- `<aside class="example">` for illustrative code
- `<aside class="ednote">` for editor notes
- `<pre data-status="verified|deduced|inferred|experiment-verified">`

### Diátaxis (Reference 層)
- spec/ = Reference (現状の事実のみ、命令禁止、過去形禁止)
- changes/ = How-to (変更方法)
- steering/ = Explanation (背景・規約)
- archive/ = deprecated reference

### Vale (prose linter)
- `existence` rule type で日付 / TODO / 過去形 narration 検出
- HTML 直接 parse
- pre-commit + CI で機械 enforce

## R-N rule 設計詳細

### R-14: spec/ content 現在形 declarative MUST

**ルール**: spec/*.html の散文は現在形 declarative ("〜する" / "〜である" / "MUST" / "MUST NOT") のみ。過去 narration ("〜した" / "〜だった" / "確認した") は禁止。

**例外**: 
- `changelog.html` 自身 (history 専用 file)
- `<div class="meta">` 内の draft date (structural metadata)
- `<aside class="ednote">` 内 (editor note は historical 記述 OK)

**検出**: L3 MCP tool (past_narration check) + L4 Vale `Twill.PastTense` rule + Phase F 4 軸目 (temporal) Step 2

### R-15: spec/ code block は schema/table/ABNF/mermaid のみ

**ルール**: `<pre>` / `<code>` block に許容するのは JSON Schema / ABNF / mermaid 図 / HTML table / 型定義 のみ。bash/python/js の実行可能コードは `<aside class="example">` で囲み informative 扱いとするか、`architecture/research/` の experiment ページに移動し spec/ からは link only とする。

**検出**: L3 MCP tool (demo_code check) + L2 bats `<pre>` grep + Phase F 4 軸目 Step 3

### R-16: 過去 narration は archive/ or changes/archive/ へ

**ルール**: spec/ に蓄積された過去 narration (デモコード、メモ、時系列記述) は spec/ から削除し、`archive/` または `changes/archive/` に移動。

**migration/ → archive/migration/**: D3 / Z1 で確定。R-4 (link 全更新) と連動。

**検出**: L2 bats (migration/ 相対 path 残存 grep)

### R-17: changes/ lifecycle (proposal → spec → archive)

**ルール**: 変更提案は `changes/<NNN>-<slug>/` change package として管理。lifecycle: proposal.md → spec/ 反映 → archive/ 移動 の 3 段階。

各 change package は `proposal.md` + `design.md` + `tasks.md` + `spec-delta/` を必須。

**検出**: L3 MCP tool (changes_lifecycle check) + L2 bats (changes/ dir 構造確認)

### R-18: ReSpec semantic markup 必須 (新規追加 section)

**ルール**: spec/ file に新規 section を追加する場合、ReSpec semantic markup を付与:
- `<section class="normative">` or `<section class="informative">`
- `<aside class="example">` for example code
- `<aside class="ednote">` for editor notes
- `<pre data-status="verified|deduced|inferred|experiment-verified">` for code blocks

**Grandfather**: 既存 section の遡及適用なし、新規追加 section のみ MUST。

**検出**: L2 bats (新規 section に markup grep) + L3 MCP tool (respec_markup check) + L5 CI (ReSpec build check)

### R-19: 多層 hook chain (L1-L5) 義務

**ルール**: tool-architect による spec/ 編集は L1 (skill) → L2 (bats) → L3 (hook+MCP) → L4 (pre-commit) → L5 (CI) の全層を通過 MUST。

**Emergency override**: L3/L4 を `--no-verify` 等で bypass する場合は `architecture/changes/active/intervention-log.md` に日時 + bypass 理由 + commit SHA を記録 MUST。

**検出**: Phase G Summary で各層 pass/fail を changelog.html entry に明記。

### R-20: twl_spec_content_check MCP tool 統合 MUST

**ルール**: tool-architect Phase E 機械検証 step に `twl_spec_content_check` 実行を追加。出力 JSON で CRITICAL/WARNING 検出時は Phase F 開始前に修正。

**検出**: L5 CI (spec-content-check.yml) で PR trigger 実行。

## 多層防御 L1-L5 mapping

| Layer | 実装 | 検出対象 | 強制 R |
|---|---|---|---|
| **L1 skill 教育** | SKILL.md + spec-management-rules.md R-14〜R-20 | LLM セルフチェック | R-14〜R-20 |
| **L2 bats 静的** | tool-architect-temporal.bats + specialist-spec-review-temporal.bats + twl-spec-content-check.bats + changes-dir-structure.bats (新規 4) + tool-architect-rules.bats + tool-architect-deployment.bats (既存 update 2) | 静的検証 | R-14〜R-20 |
| **L3 PreToolUse hook + MCP tool** | pre-tool-use-spec-write-boundary.sh (現状維持 + soft warn 拡張) + 新 MCP tool twl_spec_content_check | AI write 前 caller marker deny (既存) + content lint (新規、HTML parse + regex) | R-14, R-15, R-17, R-19, R-20 |
| **L4 pre-commit** | .vale.ini + styles/TwillSpec/{PastTense, DeclarativeOnly, CodeBlock}.yml + .textlintrc | git commit 前の文体 / code block / 過去形 narration 検出 | R-14, R-15 |
| **L5 CI** | spec-link-check.yml (既存、paths 拡張) + spec-content-check.yml (新規) + spec-respec-build.yml (新規) | merge 前の link/content/build 検証 | R-14〜R-20 |

## Trade-off

### 利点

- 業界標準完全準拠で長期メンテ性 ◎
- 5 軸 specialist (Phase F 4 並列、+ existing 3) で content semantic も clean 検出
- MCP tool 化で hook regex より深い HTML 構造解析、false-positive 大幅減
- steering/ で contributor guide が規約から独立、新メンバー参入コスト ↓
- changes/ lifecycle で「何を変えたか」の証跡永続化

### 欠点 (Risk)

- 実装規模大 (15-18 commit、新 MCP tool Python 実装、Vale config 複数)
- 1 session 超えリスク (su-compact 1-2 回挿む)
- C9 (MCP tool) の false-positive チューニング負荷

### Risk Mitigation

- 各 commit 後 broken 0 / orphan 0 / bats PASS 維持
- su-compact 時に working-memory.md 退避
- 各 phase 完了時 commit + push (incremental review)
- false-positive 高 risk な検出は WARNING (not CRITICAL) で発行、CI は warning mode 開始 → 安定後 error mode 切替
