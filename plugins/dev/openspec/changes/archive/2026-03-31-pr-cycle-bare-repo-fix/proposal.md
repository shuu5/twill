## Why

pr-cycle チェーン（all-pass-check → merge-gate）が bare repo + worktree 構成で正しく動作しない。Worker が issue-{N}.json の status を更新できず、Pilot のポーリングが完了を検知できないため、autopilot のフィードバックループが機能停止している。

## What Changes

- all-pass-check.md / merge-gate.md の state-write.sh 呼び出しを位置引数から名前付きフラグ形式に修正
- all-pass-check.md / merge-gate.md に DCI Context セクションを追加（ISSUE_NUM 等の変数注入）
- merge-gate.md から `--delete-branch` を除去（bare repo で main checkout 不可）
- merge-gate.md の worktree-delete.sh 呼び出しをフルパスからブランチ名に修正
- worktree-create.sh で初回 push 時に upstream を自動設定
- ac-verify.md に DCI Context セクションを追加

## Capabilities

### New Capabilities

- worktree-create.sh が初回 push 時に `git push -u origin <branch>` で upstream を自動設定

### Modified Capabilities

- all-pass-check が正しい形式で state-write.sh を呼び出し、DCI 経由で ISSUE_NUM を取得
- merge-gate が正しい形式で state-write.sh を呼び出し、DCI 経由で ISSUE_NUM/PR_NUM/WORKTREE_PATH を取得
- merge-gate が bare repo 互換の merge フロー（`--delete-branch` なし、ブランチ削除は worktree-delete.sh に委譲）
- ac-verify が DCI 経由で ISSUE_NUM を取得

## Impact

- **commands/all-pass-check.md**: state-write.sh 構文修正 (2箇所) + DCI Context セクション追加
- **commands/merge-gate.md**: state-write.sh 構文修正 (6箇所) + DCI Context セクション追加 + `--delete-branch` 除去 + worktree-delete.sh にブランチ名渡し
- **scripts/worktree-create.sh**: 初回 push 時に upstream 設定
- **commands/ac-verify.md**: DCI Context セクション追加
- **依存関係**: #47（`--auto`/`--auto-merge` フラグ廃止）と補完関係。本 Issue は構文修正、#47 は判定メカニズム
