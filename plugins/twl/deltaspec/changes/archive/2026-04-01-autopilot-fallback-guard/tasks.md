## 1. auto-merge.md フォールバックガード追加

- [x] 1.1 `commands/auto-merge.md` Step 0 に、`IS_AUTOPILOT=false` 判定後のフォールバックチェックブロックを追加（main worktree の `.autopilot/issue-{N}.json` 直接存在確認）
- [x] 1.2 フォールバック発動時に `state-write.sh` で `status=merge-ready` に遷移し、警告メッセージを出力して正常終了するロジックを追加
- [x] 1.3 `ISSUE_NUM` 未設定時にフォールバックチェックをスキップする条件分岐を確認

## 2. merge-gate-execute.sh Worker ロール検出ガード追加

- [x] 2.1 CWD ガードの後に、tmux window 名パターン `ap-#*` による Worker ロール検出ガードを追加
- [x] 2.2 tmux 外環境（`tmux display-message` 失敗時）のフォールバック処理を実装

## 3. OpenSpec auto-merge-guard.md 更新

- [x] 3.1 `openspec/changes/invariant-bc-runtime-guard/specs/auto-merge-guard.md` に AUTOPILOT_DIR 伝搬バグによる誤判定シナリオを追加

## 4. 検証

- [x] 4.1 `loom check` が PASS することを確認
