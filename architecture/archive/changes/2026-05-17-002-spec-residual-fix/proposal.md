# Proposal: 002-spec-residual-fix

001-spec-purify 完遂後の spec/ 残存違反 fix + R-21〜R-25 rule gap fill

## What

001-spec-purify (2026-05-16 archive 済) の continuation として、以下を実施する:

1. **R-14/R-15 残存 78 件 → 0 化** — 全 18 spec file の MCP tool `twl_spec_content_check` で ok=true 達成
2. **EXP-044 起票** — `twl_spec_content_check` 実機 invoke smoke (experiment-index.html に追加)
3. **status badge 昇格** — registry-schema.html §1.5.1 で registry.yaml row を inferred → deduced (R-24 evidence: 656 行実在)
4. **R-21〜R-25 新規 rule 追加** — rule gap fill (spec-management-rules.md + SKILL.md + tool-architecture.html §3.6.1)
5. **EXP-039 誤参照 fix** — tool-architecture.html §2.7 L156 を EXP-044 link に修正

### 追加 rule (R-21〜R-25)

- **R-21**: shell command 手順書系 `<pre>` の `<aside class="example">` wrap MUST (grandfather 例外あり)
- **R-22**: 日付 annotation `(YYYY-MM-DD)` は changelog/meta/ednote/ADR Status 以外で禁止 MUST
- **R-23**: incomplete marker (forbidden 単語 list は spec-management-rules.md 参照) は spec/ 配下禁止 MUST (R-14 から独立)
- **R-24**: verify status 昇格は evidence (bats PASS / verify_source URL / EXP log_hash + verify_checks) を含む commit と同時 MUST
- **R-25**: spec から `experiment-index.html#EXP-NNN` link 時、参照先 EXP 内容と意味的一致 MUST

## Why

001 完遂時点で MCP tool が catch しない意味的違反 (Japanese morphology、`<dd>` 内 transient marker、過去 narration の機械検出 false negative) が 78 件残存していた。本 wave で:

- 機械検証 (twl_spec_content_check) を全 18 file で PASS させる
- R-1〜R-20 では拾えない rule gap (date annotation / incomplete marker / status evidence / EXP semantic) を R-21〜R-25 として明文化
- EXP-044 を新規起票し本 wave 自体を experiment-verified candidate とする

## Acceptance Criteria

- [x] 全 18 spec file の MCP tool ok=true 達成
- [x] R-21〜R-25 を spec-management-rules.md + SKILL.md + tool-architecture.html §3.6.1 に追加
- [x] EXP-044 起票 + tool-architecture.html L156 link 修正
- [x] registry-schema.html §1.5.1 registry.yaml row inferred → deduced (evidence: 656 行実在)
- [x] Phase F 4 並列 review (vocabulary / structure / ssot / temporal、opus 固定) で fix loop 1 回収束
- [x] broken link 0 / orphan 0 維持
- [x] changelog.html に Phase G entry

## ADR Reference

- (新規 ADR なし、001 で確立した spec-clean-architecture を継続適用)

## Out of scope (defer to 別 Wave)

- mermaid render 復活 (script include 欠如) → 003 wave
- common.css 視覚 class 定義 (.normative/.informative/.example/.ednote) → 003 wave
- aside wrap upgrade (admin-cycle L158 / monitor-policy L50,L111 / spawn-protocol L166 / twl-mcp-integration L47) → 003 wave
- R-21 grandfather 例外明示 / R-17 recursive meta-PR 例外明示 → tools_spec.py 改修と合わせて別 wave
- bats tests (R-21〜R-25 grep / EXP-044 smoke) → 別 wave (plugins/twl/tests/ 配下)
- EXP smoke 実施 (EXP-027/028/029/032/034/039/044) → research/ 配下、別 wave

## 遡及作成 note

本 proposal.md は wave 完遂後の遡及作成 (2026-05-17、change 003 wave 冒頭で R-17 lifecycle 違反検出に対する補正)。当初 wave は `changes/<NNN>-<slug>/` package 未作成のまま `architecture/spec/changelog.html` に entry を記録し終了したため、R-17 Step 1 (proposal 作成) + Step 3 (archive 移動) が欠落していた。本 package は changelog 2026-05-17 entry + 9 commit の git log + Phase F findings 統合資料から逆構築した。
