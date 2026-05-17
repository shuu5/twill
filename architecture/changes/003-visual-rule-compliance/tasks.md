# Tasks: 003-visual-rule-compliance

## 計画 commit chain

| Step | commit | scope | 機械検証 |
|---|---|---|---|
| C1 | commit A | 002 package archive 遡及作成 (proposal.md + tasks.md) | N/A (archive/ 配下) |
| C2 | commit B | 003 change package 起票 (proposal.md + tasks.md = 本 file) | N/A (changes/ 配下) |
| C3 | commit C | mermaid CDN script include + `<code>` 除去 (3 file × 9 block) | MCP tool ok / broken-link 0 |
| C4 | commit D | common.css 4 class 追加 (.normative / .informative / aside.example / aside.ednote) | N/A (CSS 単独) |
| C5 | commit E | data-status 二重定義 fix (glossary L107 + tool-architecture L626) + heading 階層 skip fix (tool-architecture h5→h4 / h4→h3) | MCP tool ok |
| C6 | commit F | R-22 violation fix (tool-architecture L535/L1093 日付削除) | MCP tool ok |
| C7 | commit G | R-23 violation fix (monitor-policy L148 + registry-schema L302) | MCP tool ok |
| C8 | commit H | R-24 violation fix (registry-schema L150/L156 空 verified span) | MCP tool ok |
| C9 | commit I | aside wrap upgrade × 5 箇所 (admin-cycle L158 / monitor-policy L50,L111 / spawn-protocol L166 / twl-mcp-integration L47) | MCP tool ok |
| Phase F | — | 4 並列 spec-review (vocabulary / structure / ssot / temporal、opus 固定) | findings ≥80 confidence のみ |
| fix loop | commit J+ | findings に応じた fix | MCP tool ok |
| Phase G | commit Z | changelog.html entry 追加 | broken/orphan 0 |

## 機械検証 chain (commit C 以降)

```bash
# A. broken/orphan
python3 scripts/spec-anchor-link-check.py --check-orphan --output text
# 期待: broken: 0 / orphan: 0

# B. MCP tool 全 18 file
for f in architecture/spec/*.html; do
  echo "{\"file_path\": \"$(pwd)/$f\"}" | uv run --directory cli/twl python -c \
    'import json, sys; from twl.mcp_server.tools_spec import twl_spec_content_check_handler; args=json.load(sys.stdin); print(json.dumps(twl_spec_content_check_handler(**args)))'
done | jq -s '[.[] | .ok] | all'
# 期待: true (全 file ok)
```

## Phase F 4 軸 expected behavior

| 軸 | 確認観点 |
|---|---|
| vocabulary | mermaid CDN URL / common.css class 名が forbidden synonym と矛盾しないか |
| structure | data-status 二重定義 fix の id anchor + heading 階層整合性 |
| ssot | R-22/R-23/R-24 fix 後の EXP/ADR/Inv 参照整合性 |
| temporal | aside wrap upgrade で `<aside class="example">` の R-15/R-18 compliance |

## 完遂後 archive 移動 (R-17 Step 3)

```bash
git mv architecture/changes/003-visual-rule-compliance architecture/archive/changes/2026-05-17-003-visual-rule-compliance
```
