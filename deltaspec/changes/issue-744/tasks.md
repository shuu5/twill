## 1. autopilot-orchestrator.sh — pr-merge skip 分岐削除（AC-1）

- [x] 1.1 `autopilot-orchestrator.sh` の pr-merge skip ブロック（L930-935）を削除する
- [x] 1.2 allow-list regex が `/twl:workflow-pr-merge` にマッチすることを手動確認する

## 2. autopilot-orchestrator.sh — INJECT_TIMEOUT_COUNT 追加（AC-2）

- [x] 2.1 `INJECT_TIMEOUT_COUNT` 連想配列をスクリプト冒頭の配列宣言セクションに追加する
- [x] 2.2 `inject_next_workflow()` 内で next_skill が pr-merge / /twl:workflow-pr-merge の場合、inject timeout 発生時に `INJECT_TIMEOUT_COUNT[$entry]` をインクリメントする
- [x] 2.3 `INJECT_TIMEOUT_COUNT[$entry]` が `DEV_AUTOPILOT_INJECT_TIMEOUT_MAX`（デフォルト 5）を超えた場合に `status=failed` + `failure.reason=inject_exhausted_pr_merge` を state に書き込み、`cleanup_worker` を呼び出す処理を追加する
- [x] 2.4 inject 成功時に `INJECT_TIMEOUT_COUNT[$entry]=0` でリセットする

## 3. autopilot-orchestrator.sh — ログ改善（AC-4）

- [x] 3.1 inject 成功時の trace log に `status` / `current_step` / `pr` / `branch` を追記する
- [x] 3.2 inject 対象の `status != merge-ready` の場合に WARNING ログを出力する

## 4. BATS テスト新規追加（AC-3）

- [x] 4.1 `plugins/twl/tests/unit/inject-next-workflow/pr-merge-skip-guard.bats` を新規作成する
- [x] 4.2 ケース (a): warning-fix 完了後に `/twl:workflow-pr-merge` が inject されることを検証する
- [x] 4.3 ケース (b): `LAST_INJECTED_STEP` による重複 inject 防止を検証する
- [x] 4.4 ケース (c): `DEV_AUTOPILOT_INJECT_TIMEOUT_MAX` 上限超過で `status=failed` + `cleanup_worker` 呼び出しを検証する
- [x] 4.5 `bats plugins/twl/tests/unit/inject-next-workflow/pr-merge-skip-guard.bats` で 3 ケース PASS を確認する（22/22）

## 5. アーキテクチャドキュメント更新（AC-5）

- [x] 5.1 `autopilot.md` の「状態遷移」セクション（L182 近辺）に pr-merge skip の再発防止メモを追記する
- [x] 5.2 `autopilot.md` の merge-ready 書き込み責任者を「Worker（chain-runner.sh `step_all_pass_check`）」に訂正する
- [x] 5.3 ADR-018 との相互参照（`workflow_done` migration の chain-runner 側完了状態）を追記する
