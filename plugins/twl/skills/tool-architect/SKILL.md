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

## 7-phase multi-agent PR cycle (2026-05-16 確定)

詳細仕様: [tool-architecture.html §3.3](../../../../architecture/spec/tool-architecture.html#s3-3) (7 phase table + feature-dev:feature-dev との対比)。

| Phase | 名称 | agent | 並列数 | 必須/optional |
|---|---|---|---|---|
| A | Discovery | (なし) | — | MUST (todo list 作成、edit request 理解) |
| B | Spec Exploration | `specialist-spec-explorer` | **2-3 並列** | MUST |
| C | Clarifying Questions | (なし、`AskUserQuestion`) | — | **MUST NOT SKIP** (R-12) |
| D | Spec Design | `specialist-spec-architect` | **2-3 並列** | optional (structural change 必要時のみ) |
| E | Implementation | (現行 caller marker workflow) | — | MUST |
| F | Quality Review | `specialist-spec-review-{vocabulary,structure,ssot}` | **3 並列固定 (opus 固定、R-13)** | **MUST NOT SKIP** (R-12) |
| G | Summary | (なし) | — | MUST (changelog entry 追加) |

並列 agent 合計: 最大 8 並列 (B 3 + D 3 + F 3)、最小 5 並列 (B 2 + F 3、D skip 時)。

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

### Phase F: Quality Review (3 並列固定、opus 固定、MUST NOT SKIP、R-12 + R-13)

3 軸 = 3 file 別 spec-review agent を**同時並列 spawn**。各 agent は独立 context window + opus model。

```
Agent(specialist-spec-review-vocabulary):
  prompt: "git diff origin/main で確認、用語整合性 audit (forbidden synonym)"

Agent(specialist-spec-review-structure):
  prompt: "git diff origin/main で確認、構造整合性 audit (cross-ref + R-1/R-2)"

Agent(specialist-spec-review-ssot):
  prompt: "git diff origin/main で確認、SSoT 整合性 audit (ADR + 不変条件 + EXP + registry-schema)"
```

全 3 agent の findings (JSON、`ref-specialist-output-schema.md` 準拠) を統合。**confidence ≥80 の CRITICAL/WARNING のみ報告**。findings 0 件 (全 PASS) でも実行証跡を Phase G で記録 (R-12)。

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

## 管理ルール (R-1〜R-13)

詳細: [`refs/spec-management-rules.md`](refs/spec-management-rules.md) — R-1〜R-13 + checklist + HTML template + CI gate 一覧

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
Phase F: Quality Review (Agent × 3 並列固定 spec-review-{vocabulary,structure,ssot}、opus 固定)
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
- `plugins/twl/refs/ref-specialist-output-schema.md` — specialist 共通出力 schema (category=spec-vocabulary/spec-structure/spec-ssot)
- `scripts/spec-anchor-link-check.py` — link integrity 機械検証 tool
- `.github/workflows/spec-link-check.yml` — CI gate (R-8 強制)
- `plugins/twl/scripts/hooks/pre-tool-use-spec-write-boundary.sh` — caller marker enforce (R-7 強制)
- [`refs/spec-management-rules.md`](refs/spec-management-rules.md) — 本 SKILL の規律 ref doc (R-1〜R-13 詳細)
