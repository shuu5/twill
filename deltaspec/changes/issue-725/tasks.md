## 1. supervisor hook 修正

- [x] 1.1 `supervisor-input-wait.sh` の AUTOPILOT_DIR ゲートを撤去し `git rev-parse --git-common-dir` ベースの EVENTS_DIR 解決に変更
- [x] 1.2 `supervisor-input-clear.sh` に同一パターンを適用
- [x] 1.3 `supervisor-heartbeat.sh` に同一パターンを適用
- [x] 1.4 `supervisor-skill-step.sh` に同一パターンを適用
- [x] 1.5 `supervisor-session-end.sh` に同一パターンを適用

## 2. テスト更新

- [x] 2.1 `_no_autopilot_dir` 群のテストケースを「AUTOPILOT_DIR 未設定 + git 内 → イベント生成」に更新
- [x] 2.2 `git rev-parse --git-common-dir` モックを使ったテストシナリオを追加（bare repo 構造 + 非 git 環境）

## 3. 動作確認

- [x] 3.1 autopilot Worker セッション（AUTOPILOT_DIR 設定済み）で EVENTS_DIR が `main/.supervisor/events` を指すことを確認
- [x] 3.2 非 autopilot セッション（AUTOPILOT_DIR 未設定）で EVENTS_DIR が `main/.supervisor/events` を指すことを確認
