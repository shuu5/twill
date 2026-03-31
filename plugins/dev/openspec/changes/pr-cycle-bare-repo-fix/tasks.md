## 1. DCI Context セクション追加

- [x] 1.1 all-pass-check.md にDCI Context セクションを追加（BRANCH, ISSUE_NUM, PR_NUMBER）
- [x] 1.2 merge-gate.md にDCI Context セクションを追加（BRANCH, ISSUE_NUM, PR_NUMBER）
- [x] 1.3 ac-verify.md にDCI Context セクションを追加（ISSUE_NUM）

## 2. state-write.sh 呼び出し形式の修正

- [x] 2.1 all-pass-check.md の state-write.sh 呼び出しを名前付きフラグ形式に修正（2箇所: merge-ready, failed）
- [x] 2.2 merge-gate.md PASS パスの state-write.sh 呼び出しを修正（status=done, merged_at）— `--role pilot`
- [x] 2.3 merge-gate.md REJECT 1回目の state-write.sh 呼び出しを修正（status=failed, retry_count, fix_instructions, status=running）— `--role worker`
- [x] 2.4 merge-gate.md REJECT 2回目の state-write.sh 呼び出しを修正（status=failed）— `--role pilot`

## 3. bare repo 互換の merge フロー

- [x] 3.1 merge-gate.md の `gh pr merge` から `--delete-branch` を除去
- [x] 3.2 merge-gate.md の worktree-delete.sh 呼び出しをフルパスからブランチ名（`${BRANCH}`）に変更

## 4. worktree-create.sh の upstream 設定

- [x] 4.1 worktree-create.sh に初回 push で `git push -u origin <branch>` を追加（失敗時は警告のみ）

## 5. 検証

- [x] 5.1 `loom check` が PASS することを確認
- [x] 5.2 `loom validate` が PASS することを確認
