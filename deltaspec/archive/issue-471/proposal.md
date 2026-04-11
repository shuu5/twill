## Why

bare repo 構造で新規 worktree を作成した際、`remote.origin.fetch` refspec が設定されないケースがあり、`git fetch origin` が `origin/main` を更新しない。これにより全 worktree で stale な origin/main 参照が生じ、rebase 判定・PR mergeability 判定が壊れる（Wave 4 で約 1 時間のデバッグを要した実績あり）。現在は手動修復済みだが再発防止のため恒久対策を実装する。

## What Changes

- `plugins/twl/scripts/worktree-health-check.sh` を新規追加：bare repo および全 worktree の `remote.origin.fetch` refspec を検査し、欠落時に WARN + 自動修復オプションを提供する
- `plugins/twl/scripts/autopilot-pilot-precheck.md`（または新規 atomic）に health check を統合：refspec 欠落時は WARN + 自動修復オプションを提示する
- worktree 作成フロー（`chain-runner.sh worktree-create` または手動手順ガイド）に post-create で refspec を設定する処理を追加
- bats テストシナリオ追加：「fetch refspec が欠落した worktree を検出」
- `plugins/twl/CLAUDE.md` の Bare repo 構造検証セクションに refspec 条件（4 条件目）を追加

## Capabilities

### New Capabilities

- **worktree-health-check**: `.bare/config`・main worktree・全 feat worktree の `remote.origin.fetch` refspec を一括検査。`git show-ref origin/main` と `git ls-remote origin main` の一致も検証。欠落時は `git config --add remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'` で自動修復する
- **precheck refspec guard**: autopilot セッション起動時に refspec を事前確認し、欠落が検出された場合に abort または自動修復を選択できる

### Modified Capabilities

- **worktree-create**: post-create フックで refspec を自動設定（bare repo 経由の git worktree add 後に確認・補完）
- **Bare repo 構造検証ドキュメント**: refspec チェック条件を第 4 条件として追記

## Impact

- `plugins/twl/scripts/worktree-health-check.sh`（新規）
- `plugins/twl/scripts/chain-runner.sh`（worktree-create ステップに refspec 設定追加）
- `plugins/twl/commands/autopilot-pilot-precheck.md` または新規 atomic（health check 統合）
- `test-fixtures/` または `plugins/twl/tests/`（bats テスト追加）
- `plugins/twl/CLAUDE.md`（Bare repo 構造検証セクション更新）
