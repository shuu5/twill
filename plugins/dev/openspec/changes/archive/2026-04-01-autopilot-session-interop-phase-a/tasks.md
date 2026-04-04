## 1. crash-detect.sh の session-state.sh 統合

- [x] 1.1 crash-detect.sh にフォールバック判定ロジック追加（SESSION_STATE_CMD 解決 + USE_SESSION_STATE フラグ）
- [x] 1.2 session-state.sh パスでの 5 状態検出ロジック実装（state コマンド呼び出し + 状態マッピング）
- [x] 1.3 フォールバックパス維持（USE_SESSION_STATE=false 時は既存 tmux list-panes ロジック）
- [x] 1.4 failure JSON に detected_state フィールド追加（session-state 経由: 状態名、フォールバック経由: pane_absent）
- [x] 1.5 session-state.sh 実行失敗時のフォールバック切替（state コマンドエラー → tmux list-panes に復帰）

## 2. autopilot-poll.md の更新

- [x] 2.1 poll_single に session-state.sh 利用パス追加（wait + state チェックサイクル）
- [x] 2.2 poll_phase に session-state.sh 利用パス追加
- [x] 2.3 session-state.sh 非存在時の既存 sleep 10 ループ維持

## 3. テスト更新

- [x] 3.1 crash-detect.bats に session-state.sh stub ヘルパー追加
- [x] 3.2 exited 状態検知テスト（session-state.sh 経由）
- [x] 3.3 error 状態検知テスト（session-state.sh 経由）
- [x] 3.4 processing/idle/input-waiting 正常テスト（session-state.sh 経由）
- [x] 3.5 フォールバックテスト（session-state.sh 非存在時）
- [x] 3.6 既存テスト互換性確認（非 running 状態、引数バリデーション）

## 4. deps.yaml・SKILL.md 更新

- [x] 4.1 deps.yaml の autopilot-poll calls セクションに session-state.sh 外部依存追加
- [x] 4.2 skills/co-autopilot/SKILL.md の crash-detect.sh 関連記述更新
- [x] 4.3 loom check PASS 確認
