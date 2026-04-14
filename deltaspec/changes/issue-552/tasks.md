## 1. 新規 atomic 作成

- [ ] 1.1 `plugins/twl/commands/autopilot-pilot-wakeup-loop.md` を新規作成（Step 4 の orchestrator 起動・PHASE_COMPLETE 検知ループ・stagnation 検知・Silence heartbeat・状況精査モードを記述）

## 2. co-autopilot SKILL.md 書き換え

- [ ] 2.1 Step 4 のインライン実装（nohup/disown・ScheduleWakeup ループ・stagnation 検知・Silence heartbeat・状況精査モード、L88-L186）を削除し `autopilot-pilot-wakeup-loop` atomic への委譲形式に書き換える
- [ ] 2.2 Step 4.5 を narrative から atomic 委譲形式（`commands/<name>.md を Read → 実行` のみ）に書き換える
- [ ] 2.3 state file 解決ルールセクション（L228-245）を削除し autopilot.md へのリンクに置き換える
- [ ] 2.4 不変条件セクション（L247-252）を autopilot.md へのリンクのみに短縮する
- [ ] 2.5 chain 停止時の復旧手順セクション（L253-285）を削除し autopilot.md へのリンクに置き換える
- [ ] 2.6 本文行数（frontmatter 除く）が 200 行未満であることを確認

## 3. autopilot.md への documentation 移動

- [ ] 3.1 `architecture/domain/contexts/autopilot.md` に「Recovery Procedures」セクションを新規追加（orchestrator 再起動手順・手動 workflow inject 手順を移動）
- [ ] 3.2 autopilot.md「State Management」セクションに state file 解決ルール（AUTOPILOT_DIR SSOT・デフォルト値・override 方法・Pilot→Worker 継承経路・SSOT から導出されるパス）を統合
- [ ] 3.3 autopilot.md「Constraints」セクションに不変条件の詳細記述が充足されていることを確認（既存の不変条件 A〜M 表を更新）

## 4. deps.yaml 更新

- [ ] 4.1 `deps.yaml` に `autopilot-pilot-wakeup-loop`（type: atomic、spawnable_by: [controller]）を追加
- [ ] 4.2 `co-autopilot.calls` に `- atomic: autopilot-pilot-wakeup-loop` を追記

## 5. ツールチェーン実行

- [ ] 5.1 `twl --check` を実行してバリデーション通過を確認
- [ ] 5.2 `twl update-readme` を実行
