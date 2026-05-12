# rebuild-plan — placeholder

**status**: placeholder (本 session 未実装、次 session で着手予定)

> 本 file は `twill-plugin-rebuild` spec の placeholder。次 session で Strangler Fig 4 phase rebuild plan の詳細を実装する。draft-v1 §11 を発展、Phase 1 PoC (#1660 sanitize) の具体手順を deep-dive。

## 目的

新 architecture への移行 plan を Strangler Fig 4 phase + 各 phase の verify points + rollback path で仕様化する。Phase 1 PoC は Issue #1660 (SKIP_*_REASON sanitize) を新 architecture で再実装することで proof-of-concept とする。

## 想定 outline (次 session で実装)

1. **Phase 1: PoC (Day 1-3)** — 最小実装で 3 階層 + step verification + file mailbox + gate hook が動くことを実証
   - ADR-043 起票 (md 本体 + 本 spec directory を supplement として link)
   - 新 helper 5 本作成 (mailbox.sh / step.sh / phase-gate.sh / spawn-tmux.sh / admin-cycle.sh、合計 ~200 lines)
   - SKILL.md 3 個 draft (phase-impl / worker-test-ready / administrator)
   - PreToolUse hook 設定 (.claude/hooks/phase-gate.json)
   - PoC 完遂: Issue #1660 sanitize を新 architecture で再実装 (6 step フロー、admin polling 検知 → phase-impl spawn → worker spawn → test-scaffold + green-impl + check → mail 集約 → status Implementing → phase-pr → branch protection auto-merge)

2. **Phase 1 verify points (8 項目)**
   - 3 階層 spawn が動く (tmux list-windows で確認)
   - file mailbox が動く (.mailbox/.../inbox.jsonl)
   - step verification が動く (test 数増加 + RED/GREEN 確認)
   - gate hook が動く (Refined でない Issue に phase-impl 呼び出して deny)
   - admin polling が動く (CronCreate 25 min)
   - context 効率化 (admin token 使用量 < 旧 su-observer)
   - fail-fast at step level (意図的 fail で step abort)
   - PR 完遂 (Issue #1660 auto-merge、Status=Merged)

3. **Phase 2: dual-stack (Day 4-7)** — 残り phase + 旧 freeze
   - 残り 3 phase の SKILL.md (phase-explore / phase-refine / phase-pr)
   - 残り worker 6 個の SKILL.md
   - tool-* 4 個 (rebrand from co-architect/project/utility/self-improve)
   - Project Board option 追加 (Explored / PR Reviewed の新規追加、Todo/InProgress/Done を Idea/Implementing/Merged に rename、option_id 維持)
   - Actions yaml 整理 (archive-merged.yml 新規、auto-merge.yml 改、auto-refined.yml/project-status-done.yml 削除)
   - 旧 chain-runner.sh は freeze (新規修正禁止、in-flight Issue のみ実行)

4. **Phase 3: cutover (Day 8-11)** — 旧 bash 全削除
   - in-flight Issue 全完遂 or 新経路に migration
   - 旧 bash 削除 (~5000 lines、deletion-inventory.md 参照)
   - workflow-* SKILL.md 13 個 削除
   - twl MCP server 極小化 (1 tool のみ)
   - chain SSoT 三重化撤廃 (chain.py / chain-steps.sh / chain 削除)
   - checkpoint dir 削除

5. **Phase 4: cleanup (Day 12-14)** — docs + 検証
   - README / CLAUDE.md / refs/ を新 architecture に整合
   - ADR Superseded マーク (adr-fate-table.md の Superseded chain 順序に従う、Phase 4 最後に ADR-043 を Accepted 化)
   - bats regression test 全 PASS 確認
   - 新規 bats test 追加 (file mailbox concurrent / phase-gate deny / step verification fail-fast / daemon deploy verify)
   - Project Board UI 設定 (Kanban 6-stage + Table view、Web UI 手動 or copyProjectV2)
   - Memory MCP に lesson 集約 (本 spec の deep-dive を doobidoo 保存)
   - ADR-037 番号重複正規化

6. **rollback path**
   - Phase 1 PoC 失敗 → 旧 chain-runner.sh で #1660 を再実装、本 spec 修正
   - Phase 2 dual-stack 中の問題 → 該当 phase を旧 chain にフォールバック
   - Phase 3 cutover 後の問題 → git revert (commit 単位で rollback、本 spec の rebuild commit を分離するため atomic rollback 可能)
   - Phase 4 後の問題 → Phase 4 cleanup commit を revert で旧 ADR Status を復元

## 参照

- `overview.html` §9 (rebuild plan overview)
- `crash-failure-mode.html` §8 (Phase 1 PoC での crash verify points)
- `step-verification.html` (Phase 1 PoC の核心 framework)
- `deletion-inventory.md` (Phase 3 削除対象詳細)
- `regression-test-strategy.md` (Phase 4 検証戦略)
- 既存 draft `/tmp/twill-rebuild-design.html` §11 (原案、図 5 timeline)
