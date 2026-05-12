# pitfalls-inheritance — placeholder

**status**: placeholder (本 session 未実装、次 session で着手予定)

> 本 file は `twill-plugin-rebuild` spec の placeholder。次 session で既存 pitfalls-catalog の継承戦略を実装する。

## 目的

既存 `plugins/twl/skills/su-observer/refs/pitfalls-catalog.md` の lesson 群を新 spec でどう継承するかを仕様化する。「構造的不能化で不要になる lesson」「新 spec でも有効な lesson」「新 spec で強化される lesson」の 3 分類で audit する。

## 想定 outline (次 session で実装)

1. **既存 pitfalls-catalog の section 一覧**
   - §1 lesson 構造化 chain (Invariant N)
   - §2 stuck pattern recovery
   - §3 budget format 解釈 (Invariant Q)
   - §4 RED-only label bypass (ADR-038)
   - §5 cross-Wave cleanup (#1673)
   - §6 phase-review.json cross-pollution (#1703 関連)
   - §7 mcp disconnect (#1687)
   - §8 self-申告 step (L1873-1884)
   - §9 deploy/verify 分離 (#1687)
   - §10-19 (個別 lesson、各 P0 bug)

2. **継承分類 (audit table)**

   | pitfall | 新 spec での扱い |
   |---|---|
   | 構造化 chain (Inv N) | 保全 (新 spec でも MUST) |
   | stuck pattern | 保全 |
   | budget format (Inv Q) | 保全 |
   | RED-only bypass | 部分継承 (step verification で構造的不能化、Layer 4 のみ保全) |
   | cross-Wave cleanup | 構造的不能化 (Inv V で per-Worker scope 強制) |
   | phase-review cross-pollution | 構造的不能化 (Inv T/V で共通 path 禁止) |
   | mcp disconnect | 構造的不能化 (Inv X で deploy/verify セット) |
   | 自己申告 step | 構造的不能化 (Inv U で post-verify 必須) |
   | deploy/verify 分離 | 構造的不能化 (Inv X) |

3. **新 spec で追加すべき pitfall**
   - file mailbox 並列 write race (Inv T 検証)
   - PreToolUse hook config の deploy 漏れ (Inv X 強化)
   - 3 階層 spawn の cwd 渡し漏れ (Inv B 強化)
   - tmux new-window で path 解決失敗 (新 pitfall、未経験)

4. **継承先**
   - 構造的不能化 lesson → `architecture/spec/twill-plugin-rebuild/failure-analysis.md` に集約 (本 spec の MUST / SHOULD)
   - 保全 lesson → 既存 `pitfalls-catalog.md` を rebrand (new `administrator/refs/pitfalls-catalog.md`)
   - 新規 lesson → administrator/refs/pitfalls-catalog.md に追加

5. **運用ルール (Invariant N)**
   - 新 architecture でも 4-step chain (doobidoo → Issue → Wave → 永続文書) を MUST
   - 永続文書化先は `administrator/refs/pitfalls-catalog.md` (rebrand 後)

## 参照

- `failure-analysis.md` (9 P0 bug 深掘り、本 spec の lesson 起点)
- `invariant-fate-table.md` 不変条件 N (lesson structuralization) + T-X (新規)
- 既存 `plugins/twl/skills/su-observer/refs/pitfalls-catalog.md`
- ADR-036 (lesson structuralization MUST)
