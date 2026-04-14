## 1. 前提確認

- [x] 1.1 Issue #491 (Worker runtime) が merge 済みであることを確認（`scripts/issue-lifecycle-orchestrator.sh` の存在確認 — dispatch/wait は orchestrator に統合済み）
- [x] 1.2 `workflow-issue-lifecycle` SKILL.md の存在確認

## 2. CO_ISSUE_V2 feature flag 導入

- [x] 2.1 `plugins/twl/skills/co-issue/SKILL.md` に `## Environment` セクションを追加（CO_ISSUE_V2 宣言、default=0、rollback 手順）
- [x] 2.2 Phase 2, Phase 3, Phase 4 それぞれの冒頭に `if [[ "${CO_ISSUE_V2:-0}" == "1" ]]` 分岐骨格を追記

## 3. Phase 2 改修 — DAG 構築 + bundle 書き出し

- [x] 3.1 `#<local-ref>` regex 抽出ロジックを追加（コードブロック除外）
- [x] 3.2 Kahn's algorithm による topological sort + level 分割ロジックを追加
- [x] 3.3 循環検出時のエラー停止ロジックを追加
- [x] 3.4 per-issue ディレクトリ（`.controller-issue/<sid>/per-issue/<index>/IN/`）作成と bundle 書き出し（draft.md, arch-context.md, deps.json）
- [x] 3.5 policies.json 生成（quick / scope-direct / 通常 の 3 パターン）
- [x] 3.6 AskUserQuestion `[dispatch | adjust | cancel]` を追加

## 4. Phase 3 改修 — Level-based dispatch

- [x] 4.1 level ループ（for level in [L0..Lk]）と `issue-lifecycle-orchestrator.sh --per-issue-dir <level-dir>` 呼び出しを追加（dispatch/waitは orchestrator に統合済み）
- [x] 4.2 orchestrator が同期完了待ちを内包（Bash-bg 不要）
- [x] 4.3 level_report: 各 OUT/report.json を Read して取得
- [x] 4.4 prev level の OUT/report.json から parent URL 読み出し → current level policies.parent_refs_resolved 注入
- [x] 4.5 failure → circuit_broken 判定ロジックを追加（DAG edge 参照）

## 5. Phase 4 改修 — Aggregate & Present

- [x] 5.1 全 `per-issue/*/OUT/report.json` Read + done/warned/failed/circuit_broken 分類
- [x] 5.2 summary table 提示ロジックを追加
- [x] 5.3 failure 時の AskUserQuestion `[retry subset | manual fix | accept partial]` を追加
- [x] 5.4 retry 選択時に `issue-lifecycle-orchestrator.sh --resume` 呼び出しを追加（SKILL.md に記載）

## 6. Phase 5 追加 — Soak auto-logging

- [x] 6.1 `gh issue view 493` で closed 確認ロジックを追加
- [x] 6.2 CO_ISSUE_V2=1 かつ 1 件以上成功時に `gh issue comment 493` で run log 投稿（フォーマット通り）
- [x] 6.3 投稿失敗は非ブロッキング（warning のみ）

## 7. deps.yaml 更新

- [x] 7.1 `deps.yaml` の co-issue controller `calls` に `workflow-issue-lifecycle` を追加
- [x] 7.2 `twl check` PASS を確認

## 8. テスト

- [x] 8.1 `tests/scenarios/co-issue-v2-smoke.test.sh` を新規作成（CO_ISSUE_V2=1 smoke: 2-issue 分解 → dispatch → collect → present）— spec-scaffold-tests エージェントが生成済み
- [x] 8.2 `tests/scenarios/co-issue-skill.test.sh` を flag==0 で実行して確認（26 passed, 3 pre-existing failed — 回帰なし）
- [x] 8.3 `tests/bats/structure/co-issue-phase3-specialist.bats` を flag==0 で実行（33 passed, 2 pre-existing failed — 回帰なし）

## 9. 最終確認

- [ ] 9.1 手動 E2E: `CO_ISSUE_V2=1` で 2-3 issue の要望を通し、全 issue が起票される（soak 期間での手動確認）
- [ ] 9.2 手動 rollback: `CO_ISSUE_V2=0` で即時旧動作に戻ることを確認（soak 期間での手動確認）
- [x] 9.3 scope 外ファイル（spec-review-gate.test.sh, issue-mgmt.md, deltaspec/changes/issue-447/）が未変更であることを確認
