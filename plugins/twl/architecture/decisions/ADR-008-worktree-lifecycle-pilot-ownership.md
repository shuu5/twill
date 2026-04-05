# ADR-008: Worktree Lifecycle Pilot Ownership

## Status
Accepted

## Context

Autopilot の Worker は従来、main/ で cld セッションを起動し、chain の最初のステップで worktree を作成して cd していた。しかし Claude Code の CWD リセット挙動（セッション起動ディレクトリに戻る）により、以下の問題が繰り返し発生した:

- CWD が main/ にリセットされ、`git branch --show-current` が `main` を返す
- IS_AUTOPILOT=false と誤判定され、chain が停止する（不変条件 C 違反リスク）
- 最悪の場合、main ブランチに直接 commit & push される（PR なし）

実例:
- ap-#168: CWD リセット → IS_AUTOPILOT=false → chain 停止（nudge で復旧）
- ap-#200: CWD リセット → main で作業継続 → main に直接 commit & push

## Decision

### Worktree ライフサイクルを Pilot に完全集約する

**不変条件 B を拡張**: "Worktree 削除 Pilot 専任" → "Worktree の作成・削除は Pilot が行う。Worker は使用のみ"

| フェーズ | 実行者 | 操作 |
|----------|--------|------|
| 作成 | Pilot | worktree-create.sh（Worker 起動前） |
| Worker 起動 | Pilot | autopilot-launch.sh --worktree-dir（worktree ディレクトリで cld セッション開始） |
| 使用 | Worker | chain ステップ逐次実行（CWD = worktrees/{branch}/） |
| クリーンアップ | Pilot | tmux kill-window → worktree-delete.sh → git push --delete |

### CWD リセット耐性の確保

Worker を worktree ディレクトリで起動することで、CWD リセット時もセッション起動ディレクトリ（= worktree）に戻る。これにより `git branch --show-current` が正しいブランチ名を返し続ける。

### Defense in depth: IS_AUTOPILOT 判定の CWD 非依存化

根本解決に加え、防御的に IS_AUTOPILOT 判定を state file ベースに移行する:

1. `resolve_issue_num()`: AUTOPILOT_DIR の issue-{N}.json をスキャン（優先）
2. フォールバック: `git branch --show-current`（従来方式）

### クリーンアップの Pilot 集約

merge-gate 成功後のクリーンアップを Pilot 側で一括実行:
1. tmux kill-window（Worker セッション終了を保証）
2. worktree-delete.sh（worktree + ローカルブランチ削除）
3. git push origin --delete（リモートブランチ削除）

各ステップは独立して失敗可能（冪等性）。

## Consequences

### Positive
- CWD リセットによる不変条件 C 違反が原理的に解消される
- Worktree のライフサイクルが単一責任者（Pilot）に集約され、一貫性が向上
- Worker の chain から worktree-create ステップが不要になり、chain が簡潔になる
- クリーンアップの責務分散が解消される

### Negative
- Pilot の責務が増加する（worktree 作成 + クリーンアップ）
- Worker 起動前の worktree 作成が失敗した場合、Worker は起動されない（エラーハンドリングが必要）
- 既存の workflow-setup が worktree 作成を含んでいたため、Pilot 経由と手動実行の両方に対応が必要

## Related Issues
- #210: Worker を worktree ディレクトリで起動する
- #211: IS_AUTOPILOT 判定を CWD/git branch 非依存にする
- #212: Worker 終了後のクリーンアップを Pilot 側に集約する
