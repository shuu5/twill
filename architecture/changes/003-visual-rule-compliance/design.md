# Design: 003-visual-rule-compliance

## Architecture 決定

新規 architecture 決定なし。本 wave は 001-spec-purify で確立した spec-clean-architecture (ADR-0013) を継続適用する maintenance wave。

## 採用 pattern

| 課題 | 採用 pattern | 根拠 |
|---|---|---|
| mermaid 未レンダリング | CDN ESM script + `mermaid.initialize({startOnLoad: true})` を `</body>` 直前に直接 include | v10+ mermaid 推奨 pattern、build step 不要、各 file 自己完結 |
| `<pre class="mermaid"><code>` 干渉 | regex `(<pre class="mermaid"[^>]*>)<code>(.*?)</code>(</pre>)` で `<code>` wrap 除去 | mermaid.js は `<pre class="mermaid">` 直下 text を期待、`<code>` 子要素は parse 失敗要因 |
| R-18 markup 視覚未反映 | common.css に 4 class (.normative / .informative / aside.example / aside.ednote) + pre.mermaid container 視覚化 (~97 行) を追加 | W3C ReSpec convention 準拠 (border + label + background)、WCAG AA contrast 達成 |
| R-22/R-23/R-24 個別違反 | 個別 Edit で 5 箇所修正 (L535 日付削除 / monitor-policy L148・registry-schema L302・admin-cycle L287 incomplete marker rename / registry-schema L150/L156 空 verified → deduced + path 訂正) | 機械検証 (MCP tool) では catch 不能な意味的違反、Phase F specialist 補完で検出 |
| 前 wave priority 4 aside wrap | 5 箇所全部 grandfather 不適用、upgrade 確定 (admin-cycle L158 / monitor-policy L50,L111 / spawn-protocol L166 / twl-mcp-integration L47) | 全箇所 pseudocode/shell であり aside.example の canonical 対象、grandfather 例外条件 (canonical pattern 定義) に該当せず |
| 002 package R-17 lifecycle 違反 | 遡及作成 (changelog + 9 commit log + Phase F findings から逆構築) | R-17 Step 1 (proposal) + Step 3 (archive 移動) 補正、SSoT 完全性を優先 |

## Trade-offs

- **CDN script include 18 file 増殖**: ✗ mermaid を含む 3 file のみへ追加 (judgment: 無関係 file への script 強制は不要)
- **build step 不要**: ✓ CI / pipeline 追加せずに済む、PR 単位で完結
- **CSS の per-file override**: ✗ common.css 一元化 (全 file 自動反映、styling drift 排除)
- **R-21 grandfather 例外**: ✗ 前 wave defer の 5 箇所全部 upgrade を選択 (canonical pattern として明確化)
- **002 package 遡及**: ✓ R-17 完全準拠、archive 内 lifecycle 文書として保存

## 影響範囲

- **HTML**: 9 file (admin-cycle / common.css / glossary / monitor-policy / registry-schema / spawn-protocol / ssot-design / tool-architecture / twl-mcp-integration + README + changelog)
- **新規 file**: 5 file (002 archive 2 + 003 active 3)
- **CSS**: 1 file (common.css に 97 行追加)
- **機械検証**: 全 file ok=true 維持 (broken/orphan 0、MCP tool ok=true)

## Out of scope (defer to 別 wave)

proposal.md に列挙済 (R-21 grandfather 明示 / tools_spec.py 改修 / R-21〜R-25 bats tests / EXP smoke 実施 / spec-anchor-link-check R-25 拡張 / GitHub Issue 化)。
