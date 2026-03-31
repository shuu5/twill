## 1. co-autopilot SKILL.md の修正

- [x] 1.1 Step 0 の PROJECT_DIR 取得直後に `AUTOPILOT_DIR="${PROJECT_DIR}/.autopilot"` を export する行を追加

## 2. autopilot-init.md の修正

- [x] 2.1 autopilot-init.sh 呼び出しに `AUTOPILOT_DIR=$AUTOPILOT_DIR` 環境変数を前置
- [x] 2.2 session-create.sh 呼び出しに `AUTOPILOT_DIR=$AUTOPILOT_DIR` 環境変数を前置
- [x] 2.3 SESSION_STATE_FILE の定義を `$AUTOPILOT_DIR/session.json` に変更

## 3. autopilot-phase-execute.md の修正

- [x] 3.1 state-read.sh の全呼び出しに `AUTOPILOT_DIR=$AUTOPILOT_DIR` 環境変数を前置
- [x] 3.2 state-write.sh の全呼び出しに `AUTOPILOT_DIR=$AUTOPILOT_DIR` 環境変数を前置
- [x] 3.3 autopilot-should-skip.sh の呼び出しに `AUTOPILOT_DIR=$AUTOPILOT_DIR` 環境変数を前置

## 4. 検証

- [x] 4.1 co-autopilot SKILL.md の AUTOPILOT_DIR export を確認
- [x] 4.2 autopilot-init.md の全スクリプト呼び出しで AUTOPILOT_DIR 伝搬を確認
- [x] 4.3 autopilot-phase-execute.md の全スクリプト呼び出しで AUTOPILOT_DIR 伝搬を確認
