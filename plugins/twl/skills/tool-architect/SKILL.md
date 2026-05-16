---
name: twl:tool-architect
description: |
  tool-architect: architecture/spec/ HTML 編集の唯一 author。
  twill plugin の新仕様 (architecture spec HTML) を管理する spec edit tool。
  7-phase multi-agent PR cycle (A Discovery → B Exploration → C Clarifying →
  D Design → E Implementation → F Quality Review → G Summary) で spec を維持。
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

architecture/spec/ HTML 編集の唯一 author。twill plugin の新仕様 (architecture spec) を管理する。**7-phase multi-agent PR cycle** で深部 drift 検出 + 質の高い spec edit を実現。

## architecture/ ディレクトリ構造 (SSoT)

```
architecture/
├── spec/              ← 現状の正式仕様 SSoT (Diátaxis Reference、HTML のみ + common.css、現在形 declarative R-14)
├── changes/           ← 進行中の変更提案 (OpenSpec lifecycle、proposal/design/tasks/spec-delta、R-17)
├── archive/           ← 完了 change package + 旧資産統合先 (rollback 保持、過去 ADR 等)
│   ├── changes/       ← 完了 change package (YYYY-MM-DD-NNN-<slug>、R-17 lifecycle)
│   └── migration/     ← 旧 architecture/migration/ 統合先 (D3 / Z1、change 001-spec-purify C14 で実装)
├── decisions/         ← architecture ADR (Explanation、Status: Proposed/Accepted/Superseded/Withdrawn)
├── steering/          ← project-wide 規約 (Spec Kit 方式、product/tech/structure.md、change 001-spec-purify C5 で新設)
└── research/          ← 調査レポート / 実験記録 (EXP page、experiment-index.html)
```

**tool-architect の編集対象は `architecture/spec/` 配下 (sub-dir 全 nest 含む) のみ**。`changes/` / `archive/` / `decisions/` / `steering/` / `research/` は本 SKILL の責務外 (ただし `changes/<NNN>-<slug>/` 配下 MD file は本 SKILL 経由で作成・管理する)。

## caller marker (前提 MUST)

- 編集前: `export TWL_TOOL_CONTEXT=tool-architect`
- 編集後: `unset TWL_TOOL_CONTEXT` (MUST、leak 防止)
  - 同 shell で後続 spawn される他 caller (phaser-* / admin / 等) が `tool-architect` 扱いで spec を誤編集する事故を防ぐ
  - sub-process は env を継承するため、unset しないと sub-shell 経由でも leak する
- hook (`plugins/twl/scripts/hooks/pre-tool-use-spec-write-boundary.sh`) で機械的 enforce、未 set / 他 caller で `architecture/spec/` 配下 (sub-dir 全 nest 含む) を Edit/Write/NotebookEdit しようとすると JSON `permissionDecision: deny` を返す

## 7-phase multi-agent PR cycle (2026-05-16 確定)

詳細仕様: [tool-architecture.html §3.3](../../../../architecture/spec/tool-architecture.html#s3-3) (7 phase table + feature-dev:feature-dev との対比)。

| Phase | 名称 | agent | 並列数 | 必須/optional |
|---|---|---|---|---|
| A | Discovery | (なし) | — | MUST (todo list 作成、edit request 理解) |
| B | Spec Exploration | `specialist-spec-explorer` | **2-3 並列** | MUST |
| C | Clarifying Questions | (なし、`AskUserQuestion`) | — | **MUST NOT SKIP** (R-12) |
| D | Spec Design | `specialist-spec-architect` | **2-3 並列** | optional (structural change 必要時のみ) |
| E | Implementation | (現行 caller marker workflow) | — | MUST |
| F | Quality Review | `specialist-spec-review-{vocabulary,structure,ssot,temporal}` | **4 並列固定 (opus 固定、R-13)** | **MUST NOT SKIP** (R-12) |
| G | Summary | (なし) | — | MUST (changelog entry 追加) |

並列 agent 合計: 最大 10 並列 (B 3 + D 3 + F 4)、最小 6 並列 (B 2 + F 4、D skip 時)。

### Phase A: Discovery

edit request を理解し、todo list を作成する。request が不明確な場合のみ user clarify。

```
1. TaskCreate で Phase 1-7 を todo 化、Phase 1 を in_progress
2. edit request の text を要約 (1-3 文)
3. 対象 spec file の path を初期推定 (Phase B で深掘り)
```

### Phase B: Spec Exploration (2-3 並列 spec-explorer)

関連 spec file の探索 + cross-ref 抽出 + 関連 ADR/不変条件/EXP listing。各 agent に異なる focus 割当。

```
Agent(specialist-spec-explorer):
  prompt: "<edit request> focus=role: 役割整合性 (§2 10 role 体系との整合)"

Agent(specialist-spec-explorer):
  prompt: "<edit request> focus=history: 変更履歴 (ADR / EXP / changelog 反映状況)"

Agent(specialist-spec-explorer):
  prompt: "<edit request> focus=impact: 影響範囲 (cross-ref / boundary-matrix / linked files)"
```

各 agent は **5-10 key files listing** を `files_to_inspect` field で返す。Pilot は受領後に key files を Read で深部把握 (feature-dev pattern)。

### Phase C: Clarifying Questions (MUST NOT SKIP、R-12)

Phase B findings に基づき曖昧点 + 設計分岐 + scope boundary を user 確認。`AskUserQuestion` で 3-5 問 listing。

```
- 曖昧点 / 暗黙前提 を質問
- 設計分岐 (3 案候補) を A/B/C で提示
- "whatever you think is best" 回答時は推奨案明示 + approve 取得 MUST
- scope boundary の確認 (どこまで edit、どこから別 PR)
```

### Phase D: Spec Design (optional、structural change 必要時のみ)

3 案並列設計。non-structural edit (1-2 行修正、用語置換等) では skip。

```
Agent(specialist-spec-architect):
  prompt: "<edit request> + Phase B findings、blueprint=minimal: 最小変更案"

Agent(specialist-spec-architect):
  prompt: "<edit request> + Phase B findings、blueprint=clean: clean redesign 案"

Agent(specialist-spec-architect):
  prompt: "<edit request> + Phase B findings、blueprint=pragmatic: balance 案"
```

各 agent は section design + R-10 dir 配置 + cross-ref impact + migration cost を返す。Pilot は 3 案を比較表で user に提示し、案選択を `AskUserQuestion` で取得。

### Phase E: Implementation

caller marker → Edit/Write → 機械検証 → caller marker unset。

```bash
# 1. caller marker set
export TWL_TOOL_CONTEXT=tool-architect

# 2. spec 編集 (Edit/Write)
#    - 新 file 追加: refs/spec-management-rules.md の HTML template から起こす
#    - 編集後 R-1〜R-13 checklist を walkthrough (refs/spec-management-rules.md)

# 3. 機械検証
python3 scripts/spec-anchor-link-check.py --check-orphan --output text
# → "broken: 0" + "orphan: 0" 両方確認、exit 0 必須

# 4. caller marker unset (MUST、leak 防止)
unset TWL_TOOL_CONTEXT

# 5. commit (Phase F の前)
git add architecture/spec/ && git commit -m "spec(<file>): <change summary>"
```

### Phase F: Quality Review (4 並列固定、opus 固定、MUST NOT SKIP、R-12 + R-13)

4 軸 = 4 file 別 spec-review agent を**同時並列 spawn**。各 agent は独立 context window + opus model。

```
Agent(specialist-spec-review-vocabulary):
  prompt: "git diff origin/main で確認、用語整合性 audit (forbidden synonym)"

Agent(specialist-spec-review-structure):
  prompt: "git diff origin/main で確認、構造整合性 audit (cross-ref + R-1/R-2)"

Agent(specialist-spec-review-ssot):
  prompt: "git diff origin/main で確認、SSoT 整合性 audit (ADR + 不変条件 + EXP + registry-schema)"

Agent(specialist-spec-review-temporal):
  prompt: "git diff origin/main で確認、content semantic audit (R-14 時系列 + R-15 デモコード + R-16 archive + R-17 changes/ lifecycle + R-18 ReSpec markup)"
```

全 4 agent の findings (JSON、`ref-specialist-output-schema.md` 準拠) を統合。**confidence ≥80 の CRITICAL/WARNING のみ報告**。findings 0 件 (全 PASS) でも実行証跡を Phase G で記録 (R-12)。

#### Phase F 実行前 MUST (R-20)

Phase E (Implementation) で `twl_spec_content_check` MCP tool を実行し、CRITICAL/WARNING を Phase F 開始前に修正:

```
twl_spec_content_check(
  file_path="architecture/spec/<edited-file>.html",
  check_types=["past_narration", "demo_code", "respec_markup", "declarative"]
)
```

出力 JSON で `ok: false` の場合、Phase F に進む前に Phase E に戻り修正する (R-20 義務)。

#### scope-based fix loop SLA ([tool-architecture.html §3.8](../../../../architecture/spec/tool-architecture.html#s3-8))

| scope | 判定基準 | fix loop 上限 | escalation |
|---|---|---|---|
| small | 1 file / < 20 行 / structural change なし | 3 回 | user `AskUserQuestion` approve |
| medium | 2-5 file / 20-100 行 / structural change 小 | 5 回 | user approve + 残 findings listing |
| large | 6+ file / 100+ 行 / R-10 dir 構造変更 / 新 file 追加 | user 個別判断 | 進捗 ≥ 80% で merge or revert 提案 |

**recursive PR (tool-architect が自身の spec を更新する場合)**: Phase F は user / 他 tool に委譲 (self-review bias 回避)、fix loop は user 主導。

### Phase G: Summary

changelog.html entry 追加 + 累積 commit list + defer task listing + Phase F findings 実行証跡 (R-12)。

```
1. caller marker set (changelog は spec/ 配下のため必要)
2. architecture/spec/changelog.html に entry 追加 (本日 commit 列挙、Phase F findings 件数 + 軸別 status 記載)
3. caller marker unset
4. commit (Phase G commit)
5. TaskCreate を completed に
```

## 管理ルール (R-1〜R-20)

詳細: [`refs/spec-management-rules.md`](refs/spec-management-rules.md) — R-1〜R-20 + checklist + HTML template + CI gate 一覧

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
| R-10 | 新 file の dir + sub-category decision tree (Q1-Q7) | tool-architect 規律 (PR review) |
| **R-11** | agent file は `plugins/twl/agents/specialist-spec-*.md` 命名規約 MUST | bats test (registry-yaml-specialists / tool-architect-deployment) |
| **R-12** | Phase C (Clarifying) + Phase F (Quality Review) は MUST NOT SKIP | bats test (tool-architect-7phase) + PR review |
| **R-13** | Phase F specialist は `model: opus` 固定 (sonnet downgrade 禁止) | bats test (agent frontmatter model 検証) |
| **R-14** | spec/ content 現在形 declarative MUST (時系列メモ禁止) | L4 Vale `Twill.PastTense` + L3 hook + Phase F 4 軸目 (temporal) |
| **R-15** | spec/ code block は schema/table/ABNF/mermaid のみ | L3 MCP tool `twl_spec_content_check` + L4 Vale + Phase F 4 軸目 |
| **R-16** | 過去 narration は archive/ or changes/archive/ へ | L2 bats (migration/ 旧 path grep) + R-4 link 整合性 |
| **R-17** | changes/ lifecycle MUST (proposal → spec → archive) | L3 MCP tool (changes_lifecycle) + L2 bats (changes-dir-structure) |
| **R-18** | ReSpec semantic markup 必須 (新規 section、grandfather) | L2 bats + L3 MCP tool (respec_markup) + L5 ReSpec build check |
| **R-19** | 多層 hook chain L1-L5 義務 (emergency override は intervention-log 記録 MUST) | Phase G Summary 記録 (将来 CI 機械化) |
| **R-20** | `twl_spec_content_check` MCP tool 統合 MUST (Phase E 機械検証) | L5 CI workflow (spec-content-check.yml) + L2 bats |

## 標準ワークフロー (7-phase 概要)

```
Phase A: Discovery (todo list + edit request 要約)
   ↓
Phase B: Spec Exploration (Agent × 2-3 並列 spec-explorer、5-10 key files listing 受領)
   ↓
Phase C: Clarifying Questions (AskUserQuestion、MUST NOT SKIP)
   ↓
Phase D: Spec Design (Agent × 2-3 並列 spec-architect、optional、3 案比較 → user 選択)
   ↓
Phase E: Implementation (caller marker set → Edit/Write → 機械検証 → caller marker unset → commit)
   ↓
Phase F: Quality Review (Agent × 4 並列固定 spec-review-{vocabulary,structure,ssot,temporal}、opus 固定)
   ↓ scope-based fix loop (small=3 / medium=5 / large=user 判断)
   ↓
Phase G: Summary (changelog entry + 累積 commit list + defer task listing)
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

- `architecture/spec/tool-architecture.html` — tool-* 3 件 architecture spec (役割 / verify 機構 / 7-phase PR cycle / agent 仕様、本 SKILL の高レベル仕様 SSoT、§3.3 + §3.7 + §3.8 参照)
- `architecture/spec/architecture-graph.html` — link 図 hub (R-2 強制 target)
- `architecture/spec/README.html` — index hub (R-1 強制 target、entry point)
- `architecture/spec/registry-schema.html` — registry.yaml schema 定義
- `architecture/decisions/ADR-0012-administrator-rebrand.md` — administrator rebrand (Proposed)
- `plugins/twl/agents/specialist-spec-explorer.md` — Phase B agent (sonnet、2-3 並列、5-10 key files listing)
- `plugins/twl/agents/specialist-spec-architect.md` — Phase D agent (sonnet、2-3 並列、3 案 blueprint、optional)
- `plugins/twl/agents/specialist-spec-review-vocabulary.md` — Phase F 軸 1 (opus、用語整合性)
- `plugins/twl/agents/specialist-spec-review-structure.md` — Phase F 軸 2 (opus、構造整合性)
- `plugins/twl/agents/specialist-spec-review-ssot.md` — Phase F 軸 3 (opus、SSoT 整合性)
- `plugins/twl/agents/specialist-spec-review-temporal.md` — Phase F 軸 4 (opus、content semantic、R-14〜R-18 audit、change 001-spec-purify C7 で新規作成)
- `plugins/twl/refs/ref-specialist-output-schema.md` — specialist 共通出力 schema (category=spec-vocabulary/spec-structure/spec-ssot/spec-temporal)
- `cli/twl/src/twl/mcp_server/tools_spec.py` — `twl_spec_content_check` MCP tool handler (C9 で新規作成、R-20)
- `architecture/archive/changes/2026-05-16-001-spec-purify/` — 本 SKILL を確立した change package (proposal/design/tasks/spec-delta、R-17 lifecycle 完遂で archive 移動済)
- `architecture/decisions/ADR-0013-spec-clean-architecture.md` — 本 SKILL の設計根拠 ADR (C4 で新規作成)
- `architecture/steering/{product,tech,structure}.md` — project-wide 規約 (C5 で新規作成)
- `.vale.ini` + `styles/TwillSpec/` — L4 pre-commit lint config (C8)
- `.github/workflows/spec-content-check.yml` — L5 CI (R-20 強制、C15)
- `.github/workflows/spec-respec-build.yml` — L5 CI (R-18 強制、C15)
- `scripts/spec-anchor-link-check.py` — link integrity 機械検証 tool
- `.github/workflows/spec-link-check.yml` — CI gate (R-8 強制)
- `plugins/twl/scripts/hooks/pre-tool-use-spec-write-boundary.sh` — caller marker enforce (R-7 強制) + 時系列パターン warning (R-14、C9 で拡張)
- [`refs/spec-management-rules.md`](refs/spec-management-rules.md) — 本 SKILL の規律 ref doc (R-1〜R-20 詳細)
