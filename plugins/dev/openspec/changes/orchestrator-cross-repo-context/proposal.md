## Why

autopilot orchestrator の `_nudge_command_for_pattern()` と `cleanup_worker()` はクロスリポジトリ環境でリポコンテキストを無視する。`resolve_issue_repo_context()` が既に ISSUE_REPO_OWNER/ISSUE_REPO_NAME/ISSUE_REPO_PATH を設定するが、この2つの関数には伝搬されていない。

具体的な問題:
1. `_nudge_command_for_pattern()` が `gh issue view "$issue"` を `--repo` なしで実行するため、CWD リポの Issue を参照してしまう
2. `cleanup_worker()` が `git push origin --delete "$branch"` を常に CWD リポの origin に送信するため、クロスリポ環境で誤ったリモートを操作する
3. `orchestrator-nudge.bats` の test double が gh API fallback シナリオをカバーしていない

## What Changes

- `scripts/autopilot-orchestrator.sh`: `_nudge_command_for_pattern()` に entry 引数を追加し、`--repo` フラグ付きで gh 呼び出しを実行
- `scripts/autopilot-orchestrator.sh`: `cleanup_worker()` に entry 引数を追加し、entry の ISSUE_REPO_PATH を使って正しいリモートに branch 削除
- `scripts/autopilot-orchestrator.sh`: `check_and_nudge()`、`poll_single()`、`poll_phase()` の呼び出しシグネチャを entry 伝搬に対応
- `tests/bats/scripts/orchestrator-nudge.bats`: gh API fallback とクロスリポ `--repo` フラグのテストケースを追加

## Capabilities

### Modified Capabilities

- `_nudge_command_for_pattern()` がクロスリポ環境で正しいリポの `quick` ラベルを確認する
- `cleanup_worker()` がクロスリポ環境で正しいリモートに対してブランチを削除する
- `check_and_nudge()` / `poll_single()` / `poll_phase()` が entry を受け取り、下位関数に伝搬する

### New Capabilities

- orchestrator-nudge.bats に gh API fallback の test double が追加される
- クロスリポ環境での `--repo` フラグ付き gh 呼び出しが bats でテストされる

## Impact

- 影響ファイル: `scripts/autopilot-orchestrator.sh`, `tests/bats/scripts/orchestrator-nudge.bats`
- スコープ外: `resolve_issue_repo_context()` 自体の変更（変更不要）
- スコープ外: `merge-gate-execute.sh` の `git push origin --delete`（worktree 内実行のため文脈が異なる）
- 後方互換性: `ISSUE_REPO_ID == "_default"` の場合は従来通り `origin` を使用する（デフォルトリポ動作を維持）
