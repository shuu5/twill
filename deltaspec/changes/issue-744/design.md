## Context

`autopilot-orchestrator.sh` の `inject_next_workflow()` 関数（L928 近辺）には pr-merge を検出した際に inject をスキップして return 0 する分岐がある。この分岐は「`status=merge-ready` が既に成立 → run_merge_gate が起動済み → inject 不要」という前提だが、`status=merge-ready` を書くのは `chain-runner.sh` の `step_all_pass_check` PASS 分岐のみである。Worker chain が `warning-fix` を terminal step として停止している場合、`all-pass-check` に到達しないため `status=running` のままとなり deadlock が発生する。

さらに、skip 経路は `RESOLVE_FAIL_COUNT` を先にリセットしてから return 0 するため（L922-924）、通常 `AUTOPILOT_STAGNATE_SEC` で発動する stagnate 検知を回避し deadlock が隠蔽される。

## Goals / Non-Goals

**Goals:**
- `pr-merge` skip 分岐を削除し、`/twl:workflow-pr-merge` を通常の inject 経路に統合する（Option A）
- inject timeout が繰り返された場合の force-exit safety net を追加する（AC-2）
- BATS テストで 3 ケース（inject 成功・重複防止・timeout force-exit）を自動検証する
- architecture doc に再発防止メモと ADR-018 相互参照を追記する

**Non-Goals:**
- Option B（status ガード付き skip 継続）は採用しない（race condition リスクと追加複雑性のため）
- `resolve_next_workflow.py` の変更は行わない（mapping は正常）
- `chain-runner.sh` の `workflow_done` migration（ADR-018 未完了部分）は本 Issue スコープ外

## Decisions

### D1: Option A — skip 分岐削除

`autopilot-orchestrator.sh` の pr-merge skip ブロック（L930-935）を削除する。

削除後の動作:
- allow-list regex `^/twl:workflow-[a-z][a-z0-9-]*$` は `/twl:workflow-pr-merge` にマッチする
- 通常の input-waiting 検出 → `tmux send-keys` inject の流れになる
- inject 成功後 `LAST_INJECTED_STEP[$entry]` が更新され、次 poll で重複 inject はされない
- Worker 側の `chain-runner.sh` も `workflow_injected` state による二重ガードが機能する（L997-999）

### D2: INJECT_TIMEOUT_COUNT — pr-merge 限定 timeout カウンタ

既存の `RESOLVE_FAIL_COUNT`（resolve 失敗時インクリメント）とは独立に `INJECT_TIMEOUT_COUNT` を連想配列として導入する。pr-merge を next_skill として検出した際、inject timeout（prompt_found=0）が発生するたびにカウントアップし、`DEV_AUTOPILOT_INJECT_TIMEOUT_MAX`（デフォルト 5）を超えた場合に:
1. `status=failed` + `failure.reason=inject_exhausted_pr_merge` を state に書く
2. `cleanup_worker` を呼び出す
3. poll loop の次回 poll で `status=failed` によって `run_merge_gate` 対象から除外される

inject 成功時にカウンタをリセットし、pr-merge 以外の workflow には適用しない。

### D3: ログ改善（AC-4）

inject 成功時と inject timeout 時に `status` / `current_step` / `pr` / `branch` を trace log に追記し、`status != merge-ready` の場合は WARNING で「Worker chain が all-pass-check 未到達の可能性」を出力する。

## Risks / Trade-offs

- **重複 inject リスク**: Option A 採用後、`LAST_INJECTED_STEP` 更新により同一 `current_step=warning-fix` に対して 2 回目以降の poll で再 inject はされない。ただし inject 失敗（prompt_found=0）時は `LAST_INJECTED_STEP` が更新されないため、次 poll で再試行される。これは既存の挙動と一致する（意図的）。
- **workflow-pr-merge inject 後の Worker 挙動**: `/twl:workflow-pr-merge` inject により Worker が workflow を実行し `all-pass-check` に到達 → `status=merge-ready` 書き込み → 次 poll で `run_merge_gate` 起動となる。inject 後の SKILL.md フロー（chain-runner の step 記録）でも重複実行は防止される。
- **ac-verify terminal との混在**: Worker が `ac-verify` を terminal step にして停止している場合、`resolve_next_workflow.py` は `workflow-pr-fix` を返す（pr-merge ではない）。本 fix の影響範囲外。
