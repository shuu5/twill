# regression-test-strategy — placeholder

**status**: placeholder (本 session 未実装、次 session で着手予定)

> 本 file は `twill-plugin-rebuild` spec の placeholder。次 session で既存 bats 90+ + 新 architecture 用追加 test の戦略を実装する。

## 目的

既存 bats regression test (90+ ファイル) を新 architecture で継承する戦略と、新規 invariant T-X (5 件) + 9 P0 bug を block する追加 test 計画を仕様化する。

## 想定 outline (次 session で実装)

1. **既存 bats test の継承戦略 (90+ ファイル)**
   - 不変条件 A-S の bats test → 保全 (`invariant-A` 〜 `invariant-S` 全て継承、ただし `invariant-M` は部分 Superseded で test 内容調整)
   - ADR 個別 test (`ac-scaffold-tests-973.bats` 等) → 該当 ADR が Superseded されたら test は archive (`.archive/` directory に移動、削除はしない)
   - chain step test → step.sh framework に書き換え (test rule の logic は流用)

2. **新規 bats test 追加 (新 invariant T-X)**
   - `file-mailbox-atomic-write.bats` (新 invariant T、並列 write race condition)
   - `step-verification-post-verify.bats` (新 invariant U、自己申告 step block)
   - `per-worker-state-isolation.bats` (新 invariant V、checkpoint cross-pollution 防止)
   - `phase-gate-hook.bats` (新 invariant W、Refined でない Issue に phase-impl 呼び出して deny)
   - `daemon-deploy-verify-set.bats` (新 invariant X、新規 daemon PR は起動 hook ファイル追加 assert)

3. **9 P0 bug の regression test**
   - 各 bug の修正 PR が含む test を新 architecture で継承
   - Bug #1703 (cross-pollution): `phase-review-cross-pollution-regression.bats` (新規、複数 Worker simulation)
   - Bug #973 (RED merge silent rot): step verification で構造的 block されることを assert
   - Bug #1687 (mcp disconnect): MCP 極小化後の動作 (1 tool のみで chain が回る) を verify

4. **integration test (新 spec の e2e)**
   - Phase 1 PoC の 8 verify points を bats 化 (Issue #1660 sanitize の e2e simulation)
   - 3 階層 spawn の e2e (admin → pilot → worker の chain が tmux で動く)
   - file mailbox の pyramid 集約 (worker → pilot → admin が動く)

5. **test 失敗時の運用**
   - 既存 RED test scaffold pattern は新 spec では禁止 (不変条件 U に違反)
   - 新規 test は GREEN で merge、RED test は同 PR 内で実装と pair で merge

6. **CI integration**
   - GitHub Actions で全 bats test を main push 時に実行
   - 新規 invariant T-X test は phase 1-3 内で必須 PASS

## 参照

- `invariant-fate-table.md` (新 invariant T-X の検証方法 field)
- `failure-analysis.md` (9 P0 bug の test 起点)
- `rebuild-plan.md` Phase 4 (bats 検証)
- 既存 `plugins/twl/tests/bats/` 90+ ファイル
