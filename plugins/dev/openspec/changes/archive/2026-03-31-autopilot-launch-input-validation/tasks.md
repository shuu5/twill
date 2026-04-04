## 1. 入力バリデーション追加（Step 4.5）

- [x] 1.1 autopilot-launch.md の Step 4 と Step 5 の間に「Step 4.5: 入力バリデーション」セクションを追加
- [x] 1.2 ISSUE_REPO_OWNER のバリデーション実装（`^[a-zA-Z0-9_-]+$`、失敗時 state-write + return 1）
- [x] 1.3 ISSUE_REPO_NAME のバリデーション実装（`^[a-zA-Z0-9_.-]+$`、失敗時 state-write + return 1）
- [x] 1.4 PILOT_AUTOPILOT_DIR のバリデーション実装（絶対パス必須 + `..` 禁止、失敗時 state-write + return 1）

## 2. クォート修正（Step 5）

- [x] 2.1 AUTOPILOT_ENV の値部分を printf '%q' でクォートするように修正
- [x] 2.2 REPO_ENV の各値部分を printf '%q' でクォートするように修正
