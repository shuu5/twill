# Proposal: 003-visual-rule-compliance

architecture/spec/ visual rendering 復活 + 残存 rule 違反 fix + 前 wave defer 統合

## What

002-spec-residual-fix 完遂後の spec/ について、以下の visual rendering 問題と rule compliance 違反を一括 fix する。

### 1. mermaid render 復活 (CRITICAL)

- 全 3 file (registry-schema / ssot-design / tool-architecture) の 9 mermaid block が完全未レンダリング
- 原因: (a) 全 file に `<script>` mermaid CDN 読み込み欠如、(b) 9 block 全てに `<pre class="mermaid"><code>` の `<code>` 干渉 wrap

### 2. common.css 視覚 class 拡張 (WARNING)

- `.normative` / `.informative` / `aside.example` / `aside.ednote` の CSS 定義欠如
- R-18 で適用された semantic markup が visual 上反映されない (素の block 表示)

### 3. data-status 二重定義 fix (WARNING)

- glossary.html L107 + tool-architecture.html L626 で `proposed|implemented|deprecated` と定義 (実態 `inferred|deduced|verified|experiment-verified`)

### 4. heading 階層 skip fix (WARNING)

- tool-architecture.html h3→h5 (L195)、h2→h4 (L1021-1056)
- WCAG 2.1 SC 1.3.1 違反相当、TOC 生成崩れ

### 5. R-22/R-23/R-24 個別違反 fix (WARNING)

- R-22: tool-architecture.html L535/L1093 「change 001-spec-purify で実装完遂、2026-05-16」日付付き change 参照
- R-23: monitor-policy.html L148 ednote 外「未実装 helper」、registry-schema.html L302 `(stub)`
- R-24: registry-schema.html L150/L156 空 `<span class="vs verified">` evidence なし

### 6. priority 4 aside wrap upgrade (前 wave defer 統合)

- admin-cycle.html L158 (17 行 pseudocode)
- monitor-policy.html L50 / L111 (shell / Monitor pattern)
- spawn-protocol.html L166 (flock 3 行)
- twl-mcp-integration.html L47 (Python import chain 12 行)
- 全 5 箇所 `<aside class="example">` wrap (grandfather 適用 0、upgrade 確定)

### 7. R-17 lifecycle 補正

- 002-spec-residual-fix package を archive/changes/2026-05-17-002-spec-residual-fix/ に遡及作成 (本 wave 冒頭で実施)
- 003 package 起票 (本 file)

## Why

002 完遂 (HEAD=11dd89b8) で機械検証は全 18 file PASS だが、visual rendering (mermaid / CSS) と一部 rule (R-22/R-23/R-24) は機械検証で catch されない。ユーザー指摘「CSS が適用されていないページ / 見づらい部分 / 基本ルールに従っていない部分」を解消する必要がある。

aside wrap upgrade は前 wave priority 4 defer の spec/ 範囲分の引き継ぎ。

R-17 補正は 002 package 不在 (R-17 violation) を是正するため。

## Acceptance Criteria

- [ ] 全 3 mermaid file (registry-schema / ssot-design / tool-architecture) に CDN mermaid script 追加
- [ ] 9 mermaid block の `<code>` 除去
- [ ] common.css に 4 class (normative / informative / example / ednote) 追加
- [ ] data-status 二重定義 fix (glossary.html L107 + tool-architecture.html L626)
- [ ] tool-architecture.html heading 階層 skip fix
- [ ] R-22 violation fix (tool-architecture L535/L1093)
- [ ] R-23 violation fix (monitor-policy L148 + registry-schema L302)
- [ ] R-24 violation fix (registry-schema L150/L156)
- [ ] aside wrap upgrade × 5 箇所 (admin-cycle / monitor-policy / spawn-protocol / twl-mcp-integration)
- [ ] 002 package archive 遡及作成 (proposal.md + tasks.md)
- [ ] 003 package 起票 (proposal.md + tasks.md = 本 file + tasks.md)
- [ ] 機械検証 (broken/orphan/MCP tool) 全 PASS 維持
- [ ] Phase F 4 並列 review 通過 (fix loop SLA=LARGE: user 個別判断)
- [ ] changelog.html に Phase G entry
- [ ] 完遂後 `archive/changes/2026-05-17-003-visual-rule-compliance/` に移動 (R-17 lifecycle)

## ADR Reference

- (新規 ADR なし、001 で確立した spec-clean-architecture を継続適用)

## Out of scope (defer to 別 Wave)

- R-21 grandfather 例外明示 (spec-management-rules.md 文言、plugins/twl/skills 配下、tool-architect SKILL 範囲外)
- R-17 recursive meta-PR 例外明示 (同上)
- tools_spec.py 改修 (PAST_NARRATION_PATTERNS / UNCOMPLETED_PATTERNS、cli/twl/ 配下、別 wave)
- R-21〜R-25 bats tests + EXP-044 smoke (plugins/twl/tests/ 配下、別 wave)
- EXP smoke 実施 (EXP-027/028/029/032/034/039/044、research/ 配下、別 wave)
- spec-anchor-link-check.py R-25 EXP semantic audit 拡張 (scripts/ 配下、別 wave)
- defer items 多数を GitHub Issue 化 (twill-ecosystem #10、別 process)

## 参照 framework

- [mermaid CDN](https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.esm.min.mjs) — v10+ ES module、`<script type="module">` で import + `mermaid.initialize({startOnLoad: true})`
- [W3C ReSpec](https://respec.org/docs/) — `.normative` / `.informative` / `aside.example` / `aside.ednote` の reference 視覚 spec
- [WCAG 2.1 SC 1.3.1](https://www.w3.org/WAI/WCAG21/Understanding/info-and-relationships.html) — heading 階層 skip 禁止
