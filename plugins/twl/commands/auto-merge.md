# 自動マージ実行（autopilot-first）

merge-gate から呼び出され、squash マージ → archive → cleanup を実行する。
autopilot-first 前提で設計。4 Layer ガードで不変条件 C を機械的に担保。

## スクリプト実行（MUST）

```bash
SCRIPT_DIR="${CLAUDE_PLUGIN_ROOT}/scripts"
bash "$SCRIPT_DIR/auto-merge.sh" --issue "$ISSUE_NUM" --pr "$PR_NUMBER" --branch "$BRANCH"
```

スクリプトが以下を全て処理する:
- Layer 2: CWD ガード（worktrees/ 配下実行拒否）
- Layer 3: tmux window ガード（ap-#N パターン検出）
- Layer 1: IS_AUTOPILOT 判定（state-read.sh）
- Layer 4: フォールバック（issue-{N}.json 直接存在確認）
- autopilot 配下: merge-ready 宣言のみ（merge 禁止）
- 非 autopilot: squash merge + DeltaSpec archive + worktree 削除

## 禁止事項（MUST NOT）

- スクリプトを介さず直接 `gh pr merge` を実行してはならない
- マージ失敗時に自動 rebase を試みてはならない
