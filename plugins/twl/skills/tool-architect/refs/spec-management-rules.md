# spec-management-rules.md

tool-architect が `architecture/spec/` を管理する規律 ref doc。R-1〜R-9 + checklist + HTML template + CI gate 一覧。

[tool-architect SKILL.md](../SKILL.md) からの参照 doc。

## R-1: index 追加 MUST

新 file 追加時に `architecture/spec/README.html` の index table に entry を追加すること。

### rationale
- README は spec の entry point。新 file は必ず README から到達可能であること
- 浮いたページ (orphan) を作らない (R-3 と連携)
- 読み手 (人間 + 将来 tool-architect 自身) が新 file の存在を発見できる

### 違反例
- 新 file `spec/foo.html` を作成、README に何も追記せず PR → R-1 違反
- 補助 file (例: changelog.html、本来 section F) を「新 architecture」section (C) の table に置く → 不適切 placement

### 適用方法 (2 段 flow: dir 選択 → spec/ 内 sub-category)

**step 1: dir 選択**
- `spec/` — 新 twill architecture 仕様 (HTML のみ、common.css 例外)
- `migration/` — 旧→新 移行計画 (HTML)
- `research/` — 調査・実験 (HTML)
- `archive/` — 旧資産 (新規追加なし、move のみ)
- `decisions/` — 新 architecture ADR (MD のみ)

**step 2: spec/ 内 sub-category** (spec/ を選んだ場合のみ)
- `orientation` — 最初に読む (overview / failure-analysis 等)
- `core` — 新 architecture 詳細 (boundary / crash / spawn / gate-hook / monitor / hooks-mcp 等)
- `policy` — 既存接続 (twl-mcp / ssot 等)
- `auxiliary` — navigation / 用語 / 履歴 (glossary / changelog / architecture-graph 等)

**step 3: README.html の該当 section table に entry 追加**
- spec/ : 4 sub-category h3 table のうち適切なもの
- 他 dir: 単一 table (flat)
- entry format: `<tr><td><a href="foo.html"><code>foo.html</code></a></td><td><span class="badge ...">status</span></td><td>説明</td></tr>`

**step 4: badge 選択**: done / outline / archive / proposed / superseded のいずれか

詳細な decision tree は [R-10](#r-10-新-file-の-dir--sub-category-decision-tree) 参照。

## R-2: architecture-graph 追加 MUST

新 file 追加時に `architecture/spec/architecture-graph.html` に node + edge を追加すること。

### rationale
- architecture-graph は spec の link 関係を可視化する hub
- 新 file が他 file との関係性を持つことを明示
- リファクタリング時に影響範囲を把握しやすくする
- **graph 内 `<a xlink:href>` は inbound link としてカウントされるため、R-2 適用は R-3 (orphan 禁止) の機械的保証の一翼を担う**

### 違反例
- 新 file を作成、README には追加したが graph に node なし → R-2 違反
- node label が file 名と不一致 → click navigation 後に混乱

### 適用方法

実 graph 構造 (`architecture/spec/architecture-graph.html`) は以下 pattern を使用する。実例は graph file 内 node section + edge section を参照のこと。

```html
<!-- 該当 category 列に node 追加 -->
<a xlink:href="foo.html">
  <title>foo.html — short desc</title>
  <g class="node">
    <circle class="cat-{a|b|c|d|e|f|g}" cx="{col-x}" cy="{次の row-y}" r="22" />
    <text x="{col-x}" y="{cy+3}">label (短縮形)</text>
  </g>
</a>

<!-- 関連 file への edge -->
<line class="edge" x1="..." y1="..." x2="..." y2="..." />
<!-- hub 強調が必要なら class="edge hub" -->
```

## R-3: orphan 禁止 (inbound link ≥1)

新 file は少なくとも 1 つの inbound link を持つこと。entry point (README.html) は除外。

### rationale
- 浮いたページは存在を発見できない、リファクタリング時に取り残される
- spec の連結性を機械的に保証

### 違反例
- 新 file 作成、どこからも link されていない → R-3 違反

### 機械検証

`python3 scripts/spec-anchor-link-check.py --check-orphan --output text`

orphan 検出時は exit 1。

### 機械検証の limitation
- 検証 scope: spec_dir 内 (`architecture/spec/`) の file 間 link のみ
- 外部 dir (`research/`, `archive/` 等) からの inbound link は spec_dir 内 file としては自動カウントされない
- `external_relative` (`../research/foo.html`) は spec_dir 外を指すため inbound カウント対象外
- `./foo.html` (same-dir relative) は cross_file_html として inbound カウント対象 (Phase 1B fix)
- spec_dir 外 file の orphan は本 check の scope 外

### entry point の扱い
- `README.html` は spec entry point として inbound 0 で OK (`--entry-points README.html` で default 除外)
- 他 entry を追加する場合 `--entry-points README.html,other.html` で comma-separated

## R-4: 削除/rename 時の link 全更新 MUST

file を削除または rename する際、その file への inbound link をすべて更新すること。

### rationale
- broken link 0 の維持 (CI gate R-8 と連携)
- リファクタリング時に取り残し防止

### 違反例
- `foo.html` を削除、他 file からの `<a href="foo.html">` が残存 → broken link 検出 (CI fail)

### 適用方法
1. `grep -r "foo.html" architecture/spec/` で inbound 全特定
2. 削除の場合: 各 inbound link を削除 (他 file から `<a>` タグ削除) または後継 file への redirect 化
3. rename の場合: 各 inbound href を新 path に更新
4. README + graph entry も同期更新 (R-1 + R-2)
5. 機械検証 (R-8) で broken 0 確認

## R-5: badge=outline merge 禁止

`<span class="badge todo">outline</span>` 状態の file を merge してはならない。content 化完了 (`<span class="badge done">done</span>`) 後に merge。

### rationale
- spec の品質保証
- outline 状態 (骨格のみ、決定事項を欠く) の file は読み手に誤解を与える

### 違反例
- `<span class="badge todo">outline</span>` のまま PR merge → R-5 違反

### badge 識別基準 (merge 可否の根拠)
- `<span class="badge done">done</span>`: content 完成、決定済、merge 可
- `<span class="badge todo">outline</span>`: 骨格のみ、決定事項を欠く (merge 不可、R-5)
- `<span class="badge archive">archive</span>`: 過去仕様、rollback 用に保持 (廃止予定 not yet) — merge 可 (内容は完成、現役でないだけ)
- `<span class="badge proposed">proposed</span>`: 将来仕様、内容は完成しているが採用未確定 — merge 可 (内容は決定済、status のみ pending)
- `<span class="badge superseded">superseded</span>`: 廃止済、後継あり、参照のみ可 — merge 可

「outline」は「内容未完成」、「proposed / archive / superseded」は「内容完成 + status 区別」。merge 可否は内容完成度で決まる。

## R-6: HTML 以外は research/archive 限定

`architecture/spec/` 配下には HTML のみ。MD / 画像 / その他 file は `architecture/research/` または `architecture/archive/` に置く。

### rationale
- spec/ 配下 = 新 twill の純粋 HTML 仕様
- 調査レポート (MD) は research/、過去資産は archive/

### 違反例
- `architecture/spec/dig-report-2026-05-15.md` 作成 → R-6 違反、`architecture/research/` に置くべき

### 例外
- `architecture/spec/common.css` (spec 用 stylesheet) は OK
- 画像 file は spec/ 配下に置かない、必要なら research/ 等の別 dir に
- 既存 dig-report MD (`dig-report-*.md`) は現 spec_dir 内に共存しているが、後続作業で `architecture/research/` に move 予定 (transient state)

## R-7: caller marker MUST

`architecture/spec/` 配下 (sub-dir 全 nest 含む) を Edit/Write/NotebookEdit する前に `export TWL_TOOL_CONTEXT=tool-architect`。編集後 `unset`。

### rationale
- spec edit author を機械的に limit (tool-architect 専任)
- 他 caller (phaser / admin / tool-project 等) からの誤編集を hook で deny
- env unset = user manual edit として allow (人間が直接編集する場合)
- **unset し忘れによる leak risk**:
  - 同 shell で後続 spawn される他 caller が `tool-architect` 扱いで spec を誤編集
  - sub-process は env を継承するため、unset しないと sub-shell 経由でも leak

### 機械検証
`plugins/twl/scripts/hooks/pre-tool-use-spec-write-boundary.sh` が PreToolUse で発火、env unset (user manual) or `TWL_TOOL_CONTEXT=tool-architect` のみ allow、その他 (phaser-* / admin / 等) なら JSON `permissionDecision: deny` を返す。**hook の path match は `*architecture/spec/*` で sub-dir 全 nest を包含**。

### 適用方法
```bash
export TWL_TOOL_CONTEXT=tool-architect
# (Edit/Write spec file 群)
unset TWL_TOOL_CONTEXT
```

## R-8: PR broken link 0 + orphan 0 MUST

PR merge gate として CI で broken link 0 + orphan 0 を強制。

### rationale
- spec の整合性 invariant を maintain
- ローカル開発で見逃しても CI で確実に block

### 機械検証
`.github/workflows/spec-link-check.yml` が PR trigger で `python3 scripts/spec-anchor-link-check.py --check-orphan --output json` を実行 (JSON parse で堅牢化)、broken または orphan > 0 で exit 1 → PR block。

CI trigger paths: `architecture/spec/**` / `scripts/spec-anchor-link-check.py` / `.github/workflows/spec-link-check.yml` 自身 (script 改修も CI 自検対象)。

## R-9: architecture-graph 手動 maintenance

architecture-graph.html の node + edge は手動 maintenance。

### rationale
- 手動 maintenance は drift risk あり (R-2 強制で軽減)
- 典型的な drift パターン:
  - 新 file 追加時に graph node 追加忘れ → graph で表示されない
  - file rename 後 graph label 更新忘れ → click navigation で 404
  - file 削除後 edge 削除忘れ → broken link 表示

## R-10: 新 file の dir + sub-category decision tree

新 file 追加時、以下 decision tree で dir + sub-category を機械的に決定する。R-1 の section 配置と R-2 の cluster 色に直結。

```
Q1: 新 twill 設計仕様か?
  YES → Q2 へ
  NO  → Q3 へ

Q2: spec/ 内の何の仕様か?
  「なぜ rebuild か / 全体像 / 失敗分析」 → spec/orientation
  「role 責務 / invariant / lifecycle / protocol / policy (Monitor/Hooks 等)」 → spec/core
  「既存資産接続 (旧 MCP / 旧 SSoT)」 → spec/policy
  「用語 / changelog / navigation (graph) / CSS」 → spec/auxiliary

Q3: 移行・既存資産関連か?
  YES → Q4 へ
  NO  → Q5 へ

Q4: audit (旧資産評価) か plan (実行計画) か?
  audit (ADR fate / invariant fate / pitfalls 等) → migration/fate-audit
  plan (deletion / rebuild / regression / dual-stack 等) → migration/plan

Q5: 調査・実験関連か?
  YES → research/ (dig-report / experiment / findings 等)
  NO  → Q6 へ

Q6: 過去バージョン保存 / rollback 用 か?
  YES → archive/ (新規追加なし、既存 file の維持のみ)
  NO  → Q7 へ

Q7: ADR (新 architecture decision record) か?
  YES → decisions/ (MD のみ、ADR template 規約)
  NO  → 上記いずれにも該当しない → tool-architect 責務外 (user 判断)
```

### 拡張性 scenario walkthrough

**Scenario 1: 新 ADR (例: ADR-0013-phaser-spawn-invariant.md)**
- Q1: NO → Q3: NO → Q5: NO → Q6: NO → Q7: YES → `decisions/` 配置
- 作業: ADR-template に従って MD 作成 → README の decisions/ section に entry 追加 → architecture-graph に node 追加 (cat-dec class)

**Scenario 2: 新 spec file (例: phaser-lifecycle.html — phaser lifecycle 詳細)**
- Q1: YES → Q2: 「role 責務 / lifecycle」 → `spec/core` 配置
- 作業: `export TWL_TOOL_CONTEXT=tool-architect` → HTML template から起こす → README の spec/core sub-section table に entry → architecture-graph spec/core cluster (cx=210) に node + edge 追加 (cat-spec-core class)

**Scenario 3: 新 research file (例: dig-report-XXX-2026-06-01.html)**
- Q1: NO → Q3: NO → Q5: YES → `research/` 配置
- 作業: HTML 作成 (research/ なので caller marker 不要) → README の research/ section table に entry 追加 → architecture-graph research/ cluster (cx=490) に node 追加 (cat-res class)

### research/ 追加時の R-1 適用 (補足)

`architecture/research/` に HTML を追加する場合も R-1 を適用する。R-7 caller marker は research/ 自体は対象外だが、README (spec/) に entry 追加するため caller marker MUST。

### 現状の制約
- 編集者は R-2 適用時に SVG 構造 (上記 R-2 適用方法参照) を手動更新
- 漏れは PR review or CI gate (broken link 0 / orphan 0) で検出

## file 操作 checklist

### 新規追加
- [ ] R-7: caller marker set (`export TWL_TOOL_CONTEXT=tool-architect`)
- [ ] R-6: 拡張子確認 (HTML のみ spec/ 配下、common.css 例外)
- [ ] HTML template から起こす (本 doc 末尾参照)
- [ ] R-1: README.html index table に entry 追加
- [ ] R-2: architecture-graph.html に node + edge 追加 (R-3 にも貢献)
- [ ] R-5: badge 適切 (done / proposed / etc.)
- [ ] 機械検証 (`spec-anchor-link-check --check-orphan`): broken 0 + orphan 0
- [ ] caller marker unset (`unset TWL_TOOL_CONTEXT`)
- [ ] commit + push

### 編集
- [ ] R-7: caller marker set
- [ ] 内容変更
- [ ] (badge 変更時) R-5 確認
- [ ] (link 変更時) R-4 確認
- [ ] 機械検証
- [ ] caller marker unset
- [ ] commit + push

### 削除
- [ ] R-7: caller marker set
- [ ] R-4: inbound link 全特定 (`grep -r "file.html" architecture/spec/`)
- [ ] R-4: inbound link 全更新 (link の削除 or 後継 file への redirect)
- [ ] R-1: README から entry 削除
- [ ] R-2: graph から node + edge 削除
- [ ] 機械検証
- [ ] caller marker unset
- [ ] commit + push

### rename
- [ ] R-7: caller marker set
- [ ] `git mv old.html new.html`
- [ ] R-4: inbound href 全更新
- [ ] R-1: README entry の path 更新
- [ ] R-2: graph node + edge 更新
- [ ] 機械検証
- [ ] caller marker unset
- [ ] commit + push

### move (dir 間、例: spec/ → research/)
- [ ] R-7: caller marker set (spec/ 外の dir なら不要、ただし spec/ 関連 link 更新があるなら必要)
- [ ] R-6: 移動先 dir の妥当性確認 (HTML/MD の区別)
- [ ] `git mv`
- [ ] R-4: inbound href 全更新 (相対 path `../research/file.html` 等)
- [ ] R-1: README で section を移動 entry
- [ ] R-2: graph で node の category 色を変更 (or 別 cluster へ移動)
- [ ] 機械検証
- [ ] caller marker unset
- [ ] commit + push

## HTML template

新 spec file の standard template (実 spec file 構造に合わせて簡潔化):

```html
<!DOCTYPE html>
<html lang="ja">
<head>
<meta charset="UTF-8">
<title>twill plugin spec — {file-name}</title>
<link rel="stylesheet" href="common.css">
<style>
  /* file-specific accent (optional) */
  header.doc-header { border-bottom: 3px solid var(--brand); }
</style>
</head>
<body>

<header class="doc-header">
  <h1>{file-title}</h1>
  <div class="meta">draft-vN ({YYYY-MM-DD}) &middot; {short-description}</div>
</header>

<div class="info">
  <strong>目的</strong>: {file purpose} <br>
  <strong>status</strong>: <span class="badge done">done</span> (または outline / proposed / archive / superseded) <br>
  <strong>関連</strong>: <a href="{related1}.html">{related1}</a> / <a href="{related2}.html">{related2}</a>
</div>

<h2 id="s1">セクション 1</h2>
<p>...</p>

<h2 id="s2">セクション 2</h2>
<p>...</p>

</body>
</html>
```

### badge convention
R-5 の「badge 識別基準」section 参照。

## R-11: agent file 配置・命名規約 (Phase 1 PoC、2026-05-16 追加)

tool-architect 7-phase multi-agent PR cycle (architecture/spec/tool-architecture.html §3.3) で使用する specialist agent は `plugins/twl/agents/specialist-spec-*.md` 命名規約に従い、`agents/` 配下に配置すること。

### rationale
- registry.yaml の `integrity_rules.prefix_role_match` が file prefix と role field の整合性を機械的に audit (CRITICAL)
- `specialist-spec-*` prefix で「spec edit 専用 specialist」と他 specialist を機械的に区別 (search 効率、命名 ambiguity 解消)
- agents/ directory への配置は公式 subagent 仕様に準拠 (変更不可)
- registry.yaml glossary.specialist.examples に `specialist-spec-*` 5 件全列挙

### 違反例
- `plugins/twl/agents/spec-review.md` (`specialist-` prefix なし) → prefix_role_match 違反
- `plugins/twl/skills/specialist-spec-review-vocabulary.md` (agents/ 外配置) → 公式仕様違反
- `plugins/twl/agents/spec-review-vocabulary.md` (`specialist-spec-` prefix 短縮) → 命名規約違反

### 対象 agent (Phase 1 PoC で作成)

| agent file | Phase | 役割 | model |
|---|---|---|---|
| `agents/specialist-spec-explorer.md` | B | spec cross-ref 探索、2-3 並列 | sonnet |
| `agents/specialist-spec-architect.md` | D | spec section design 3 案、2-3 並列 (optional) | sonnet |
| `agents/specialist-spec-review-vocabulary.md` | F 軸 1 | 用語整合性 (vocabulary forbidden synonym) | opus |
| `agents/specialist-spec-review-structure.md` | F 軸 2 | 構造整合性 (cross-ref + R-1/R-2) | opus |
| `agents/specialist-spec-review-ssot.md` | F 軸 3 | SSoT 整合性 (ADR + 不変条件 + EXP) | opus |

### 機械検証
- registry.yaml `integrity_rules.prefix_role_match` (`twl audit --registry`)
- `tests/bats/structure/registry-yaml-specialists.bats` (5 entry 存在確認)
- `tests/bats/integration/tool-architect-deployment.bats` (5 agent file 全存在確認 + name と file path 一致)

## R-12: 7-phase Phase C / Phase F は MUST NOT SKIP (2026-05-16 追加)

tool-architecture.html §3.3 7-phase multi-agent PR cycle の Phase C (Clarifying Questions) と Phase F (Quality Review) は edit scope に関わらず skip 禁止。

### rationale
- **Phase C skip リスク**: 設計分岐を user 確認せず実装 → 後から revert 必要、spec 意図不一致 drift 発生 (2026-05-15 Q3 実績で確認)
- **Phase F skip リスク**: deep drift (用語 forbidden / SSoT 不整合 / orphan / R-1/R-2 違反) を見落としたまま merge → CI gate (broken/orphan 0) は mechanical check のみで semantic drift を検出できない
- Phase D は structural change なし時のみ optional (architect 案選択不要なため)

### 違反例
- edit request が「1 行の誤字修正」でも Phase F 3 並列 specialist を skip → R-12 違反 (small scope でも用語 forbidden は発生しうる)
- Phase C で user が "whatever you think is best" と回答した場合に AskUserQuestion なしで進む → R-12 違反 (推奨案を明示 + approve 取得 MUST)

### MUST NOT SKIP の実装ルール
- **Phase C**: AskUserQuestion で曖昧点を listing、user 回答必須 (回答が "whatever you think is best" でも推奨案提示 + approve 取得 MUST)
- **Phase F**: 3 agent (specialist-spec-review-vocabulary / -structure / -ssot) を並列 spawn、findings 0 件 (全 PASS) でも実行証跡を Phase G Summary に記録

### 機械検証
- SKILL.md 本文記述 (LLM 規律、`tests/bats/skills/tool-architect-7phase.bats` で Phase C/F 記述存在 grep)
- PR review: Phase C/F の実行証跡 (findings or PASS 記録) が Summary に含まれるか目視確認
- 将来 CI: changelog.html entry に Phase F 実行日時 + findings 件数記録の機械検証

## R-13: Phase F specialist は model: opus 固定 (2026-05-16 追加)

specialist-spec-review-vocabulary / -structure / -ssot の 3 agent は `model: opus` を MUST、sonnet / haiku へ downgrade 禁止。

### rationale
- **実績根拠**: 2026-05-15 Q3 refactoring (8 file / 100+ 行) で 3 並列 opus reviewer が CRITICAL 14 件検出。sonnet では深部 drift (語彙境界の微妙な violation / ADR 未反映 / cross-file SSoT ずれ) を見落とすレベルの問題が含まれていた
- spec の semantic correctness は code の syntax correctness より model の文脈理解深度に依存、deep audit には opus 必須
- cross-AI bias 低減: specialist は caller と独立 context window、かつ opus により召喚 session の model と異なる場合 complementary perspective が生まれる
- specialist-exp-reviewer.md (verified) も既に `model: opus` 採用済、本規律は実態と整合

### 違反例
- `specialist-spec-review-vocabulary.md` の frontmatter に `model: sonnet` を記述 → R-13 違反 (cost 削減目的でも不可)
- Phase F を 1 agent の sonnet で実行して「Quality Review 完了」と宣言 → R-13 違反 (3 並列固定 + opus 固定の両方違反)

### 機械検証
- agent frontmatter: `model: opus` MUST (`tests/bats/agents/specialist-spec-review-{vocabulary,structure,ssot}.bats` で model=opus grep 検証)
- registry.yaml components entry に `model: opus` assertion (Phase 2 以降の `twl audit --registry` で enforce)
- `tests/bats/integration/tool-architect-deployment.bats` test 7: 3 review agent 全て model=opus 確認

### 参照
- `ref-specialist-output-schema.md` Model 割り当て表 (2026-05-16 update: opus = deep audit specialist 用途を明記)
- `architecture/spec/tool-architecture.html` §3.7.3 (opus 採用の Q3 実績根拠詳述)

## CI gate 一覧

### 実装済み CI gate (機械的強制)

| CI gate | tool | 強制 R |
|---|---|---|
| broken link 0 | `scripts/spec-anchor-link-check.py` (default mode) | R-8 (broken 部分), R-4 |
| orphan 0 | `scripts/spec-anchor-link-check.py --check-orphan` | R-3, R-8 (orphan 部分) |
| caller marker enforce | `pre-tool-use-spec-write-boundary.sh` (PreToolUse hook) | R-7 |
| agent file 配置検証 | `tests/bats/structure/registry-yaml-specialists.bats` + `tests/bats/integration/tool-architect-deployment.bats` (bats) | R-11 |
| 7-phase section 存在 | `tests/bats/skills/tool-architect-7phase.bats` (bats、Phase A-G grep) | R-12 |
| Phase F opus 固定 | `tests/bats/agents/specialist-spec-review-{vocabulary,structure,ssot}.bats` (bats、model=opus grep) | R-13 |

### PR review 依存 (機械化されていない、reviewer 目視)

| Gate | 強制 R | 検出方法 |
|---|---|---|
| README entry 追加確認 | R-1 | reviewer 目視 |
| graph node 追加確認 | R-2 | reviewer 目視 |
| badge=outline merge 禁止 | R-5 | reviewer 目視 |
| HTML/MD 配置 boundary | R-6 | reviewer 目視 |
| dir + sub-category 整合 (R-10) | R-10 | reviewer 目視 + decision tree 適用確認 |
| Phase C/F 実行証跡 | R-12 | reviewer 目視 (changelog entry の Phase F findings 記載確認、将来 CI 機械化) |

## CI automation roadmap (将来 task、別 phase)

現状機械化済: R-3 (orphan) / R-8 (broken link) / R-7 (caller marker hook)。残 R-1/R-2/R-5/R-6 は PR review 依存だが、以下の機械化 roadmap で段階的に強制可能。

### Phase 2 推奨 (未実装、別 phase で着手)

- **R-1 README entry 自動検証** (`scripts/spec-readme-check.py`):
  - 実装方針: README.html parse → spec/ 配下 .html file との突合 → entry 不在 file を listing
  - CI trigger: `architecture/spec/**` 変更時
  - exit 1 で PR block

- **R-2 graph node 存在確認** (`scripts/spec-graph-check.py`):
  - 実装方針: architecture-graph.html の `<a xlink:href>` 全抽出 → 全 architecture/* .html と突合 → node 不在 file listing
  - CI trigger: 同上
  - exit 1 で PR block

- **R-5 badge=outline merge 禁止** (`scripts/spec-badge-check.py`):
  - 実装方針: 変更された HTML file の `.badge.todo` 存在 grep → 検出時 PR block
  - exception: PR title に `[WIP]` 含む場合 skip

### Phase 3 長期 (auto-generation、別 phase)

- **R-9 architecture-graph auto-gen** (`scripts/spec-graph-gen.py`):
  - 実装方針: README.html の table を読み spec dir 構造を SVG として再生成
  - drift 完全排除、手動 maintenance overhead 解消
  - CI で diff 検出 → out-of-date 警告

## 関連

- [tool-architect SKILL.md](../SKILL.md) (本 doc の親 SKILL)
- `architecture/spec/tool-architecture.html` (tool-* 3 件 spec、本 doc の規律が適用される対象 spec page、§3.6 で Clean redesign 整合性宣言)
- `architecture/spec/README.html` (spec index、R-1 強制 target)
- `architecture/spec/architecture-graph.html` (link graph、R-2 強制 target)
- `architecture/decisions/ADR-0012-administrator-rebrand.md` (administrator rebrand、Proposed)
- `scripts/spec-anchor-link-check.py` (link integrity tool、R-3 / R-8 機械検証)
- `.github/workflows/spec-link-check.yml` (CI gate、R-8 強制)
- `plugins/twl/scripts/hooks/pre-tool-use-spec-write-boundary.sh` (caller marker hook、R-7 強制)
