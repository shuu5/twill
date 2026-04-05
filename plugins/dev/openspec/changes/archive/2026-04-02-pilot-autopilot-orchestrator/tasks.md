## 1. autopilot-orchestrator.sh コア実装

- [x] 1.1 `scripts/autopilot-orchestrator.sh` スケルトン作成（引数パーサー: --plan, --phase, --session, --project-dir, --autopilot-dir, --summary, --repos）
- [x] 1.2 Phase Issue リスト取得（plan.yaml パース、クロスリポジトリ形式 + レガシー形式対応）
- [x] 1.3 skip/done フィルタリング（state-read.sh + autopilot-should-skip.sh 呼び出し）
- [x] 1.4 batch 分割ロジック（MAX_PARALLEL=${DEV_AUTOPILOT_MAX_PARALLEL:-4}）

## 2. Worker 起動・ポーリング統合

- [x] 2.1 Worker 起動（autopilot-launch.sh 呼び出し、クロスリポジトリ引数の透過的受け渡し）
- [x] 2.2 ポーリングループ実装（state-read.sh + crash-detect.sh、10 秒間隔、session-state.sh 対応）
- [x] 2.3 タイムアウト処理（MAX_POLL 回超過で remaining running Issue を failed に遷移）

## 3. merge-gate・window 管理

- [x] 3.1 merge-ready Issue への auto-merge.sh 呼び出し統合
- [x] 3.2 merge-gate-execute.sh 呼び出し（merge/reject/reject-final の判定透過）
- [x] 3.3 window kill の原子的実行（merge-gate-execute.sh 内で実行済みのため、追加 kill は不要を確認）

## 4. chain 遷移停止検知・nudge

- [x] 4.1 tmux capture-pane によるパターンマッチ検知ロジック実装
- [x] 4.2 nudge 送信ロジック（tmux send-keys、MAX_NUDGE 制限）
- [x] 4.3 NUDGE_TIMEOUT（デフォルト 30 秒）の実装

## 5. Phase 完了レポート・サマリー

- [x] 5.1 Phase 完了レポート JSON 出力（signal: PHASE_COMPLETE、results、changed_files）
- [x] 5.2 --summary モード実装（全 issue-{N}.json 集約、done/failed/skipped 集計）

## 6. co-autopilot SKILL.md 更新

- [x] 6.1 Step 4 を orchestrator 呼び出しに変更
- [x] 6.2 Step 5 を orchestrator --summary 呼び出しに変更
- [x] 6.3 Emergency Bypass 時の手動パス案内を追記

## 7. deps.yaml 更新・検証

- [x] 7.1 deps.yaml に autopilot-orchestrator.sh を追加
- [x] 7.2 `loom check` で整合性確認
- [x] 7.3 `loom update-readme` で README 更新
