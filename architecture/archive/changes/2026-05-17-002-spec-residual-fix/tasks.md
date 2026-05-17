# Tasks: 002-spec-residual-fix (遡及作成、change 003 wave 冒頭で再構築)

## 累積 9 commit (HEAD=11dd89b8)

| Step | commit | scope |
|---|---|---|
| C1 | `778dcbdb` | commit A: tool-architecture.html R-14/R-15 (29 件) + EXP-044 起票 + L156 EXP-039 誤参照 fix |
| C2 | `5638c574` | commit B: registry-schema.html R-14/R-15 (15 件) + 重複削除 (-290 行 net shrink) + mermaid 化 |
| C3 | `107bce40` | commit C: 8 file batch R-15/R-14 fix (24 件、`<pre data-status>` 化) |
| C4 | `8cd7fd7c` | commit D: 4 file R-14 fix (10 件、date / 未完了 / 過去 narration) |
| C5 | `6eb6e070` | commit E: tool-architecture §9 ednote 化 + ADR-043 entry fix + .pending CSS cleanup |
| C6 | `d049f585` | commit F: status badge 昇格 (registry-schema §1.5.1 inferred → deduced) |
| C7 | `63549f19` | commit G: R-21〜R-25 rule 追加 (spec-management-rules.md + SKILL.md) |
| C8 | `7d451ffb` | commit H: Phase F fix loop 1 (R-21〜R-25 reflection + R-22/R-14 残存 fix) |
| C9 | `11dd89b8` | commit I: Phase G Summary (changelog entry) |

## Phase F 実行証跡 (4 並列 review、opus 固定 R-13)

| 軸 | agent | findings | status |
|---|---|---|---|
| 1 | specialist-spec-review-vocabulary | 0 | PASS |
| 2 | specialist-spec-review-structure | 6 CRITICAL | FAIL → fix loop 1 で resolve |
| 3 | specialist-spec-review-ssot | 1 WARNING | WARN → fix loop 1 で resolve |
| 4 | specialist-spec-review-temporal | 11 WARNING + 2 (resolve) + 5 INFO defer | WARN → 11/13 resolve、5 INFO は別 wave |

## 機械検証結果

- broken link: 0 (PASS)
- orphan link: 0 (PASS)
- MCP tool `twl_spec_content_check` 全 18 file ok=true 達成
- bats coverage 99 件 PASS

## defer items (本 wave で未着手、別 wave 化)

1. R-21 grandfather 例外明示 (spec-management-rules.md 文言追加)
2. R-17 recursive meta-PR 例外明示
3. tools_spec.py PAST_NARRATION_PATTERNS に date annotation pattern 再追加
4. tools_spec.py UNCOMPLETED_PATTERNS context-aware exempt
5. R-21〜R-25 bats tests
6. EXP-044 smoke implementation
7. pseudocode aside wrap upgrade (admin-cycle L158 / monitor-policy L50,L111 / spawn-protocol L166 / twl-mcp-integration L47) ← change 003 wave で実施
8. EXP smoke 実施 (EXP-027/028/029/032/034/039/044)
9. spec-anchor-link-check.py EXP semantic correctness audit (R-25 enforce 拡張)
10. visual rendering 復活 (mermaid script include / common.css 視覚 class 拡張) ← change 003 wave で実施
11. defer items 11 件 を GitHub Issue 化

## 遡及 note

本 tasks.md は change 003 wave 冒頭での R-17 lifecycle 補正として遡及作成。当初 wave は `changes/<NNN>-<slug>/` package 未作成のまま spec/ 直編集で進行し、changelog 2026-05-17 entry のみで完了とした。本 package は git log + changelog + Phase F findings から逆構築。
