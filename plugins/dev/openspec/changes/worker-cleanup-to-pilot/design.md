## Context

autopilot Orchestratorはmerge-gate成功後にWorkerリソースを解放する必要がある。現在のクリーンアップ処理は以下に分散している:

- `scripts/merge-gate-execute.sh` L125-145: worktree削除 + リモートブランチ削除
- `scripts/merge-gate-execute.sh` L89, L97, L152: tmux kill-window
- `commands/autopilot-phase-execute.md` L122, L177: tmux kill-window

Pilotがworktreeを作成するが削除は`merge-gate-execute.sh`任せになっており、不変条件B（Worktreeライフサイクルはのまる）に反する。

**AUTOPILOT判定方法**: `$AUTOPILOT_DIR/issues/issue-{N}.json` の存在確認（statusではなくファイル存在で判定。AUTOPILOT_DIR環境変数のデフォルト: `scripts/state-read.sh` が参照する `.autopilot/`）。

**アーキテクチャ制約**: `${AUTOPILOT_DIR:-default}` パターンを使用してオーバーライド可能にする（feedback記録より）。

## Goals / Non-Goals

**Goals:**
- autopilot時のmerge-gate-execute.shクリーンアップをスキップし、Pilot側に委譲する
- autopilot-orchestrator.shのmerge-gate成功後にcleanupシーケンスを実行する
- クリーンアップの順序保証: tmux → worktree → remote branch
- 各ステップの冪等性: 既に削除済みのリソースへの操作を正常扱い
- クロスリポジトリ対応: issue-{N}.jsonのrepo情報を使って正しいリポジトリで削除

**Non-Goals:**
- 非autopilot（手動merge）のクリーンアップフロー変更
- crash-detect.shの異常系クリーンアップ変更
- merge-gate自体のロジック変更

## Decisions

### Decision 1: IS_AUTOPILOT判定方式

**選択**: `AUTOPILOT_DIR` 環境変数 + `issue-{N}.json` ファイル存在で判定

**根拠**: statusフィールドは遷移済み（done）のため参照不可。ファイル存在はより単純で確実。`${AUTOPILOT_DIR:-.autopilot}` パターンでオーバーライド可能にする。

### Decision 2: クリーンアップ順序

**選択**: tmux kill-window → worktree-delete.sh → git push --delete の固定順序

**根拠**: Workerがworktree内で動作していない状態を保証してからworktreeを削除するため。tmuxを先に落とすことでファイルロック競合を防ぐ。

### Decision 3: エラーハンドリング方針

**選択**: 各ステップ独立実行、失敗は警告のみで次ステップ継続

**根拠**: クリーンアップの部分失敗（例: リモートブランチが既に削除済み）は致命的ではない。全ステップを最大限実行することが重要。

### Decision 4: autopilot-orchestrator.shへのcleanup追加位置

**選択**: merge-gate PASS確認直後、次のIssue処理前

**根拠**: IssueStateがdoneに遷移した後にcleanupを実行することで、cleanup前のstatus確認が不要になる（state-write.shのトランジション保証）。

### Decision 5: クロスリポジトリ対応

**選択**: issue-{N}.jsonの`repo`フィールドを参照し、リポジトリルートを解決

**根拠**: リモートブランチ削除は対象リポジトリのgit remoteに対して実行する必要がある。

## Risks / Trade-offs

- **リスク**: autopilot-orchestrator.shへのcleanup追加後、autopilot-phase-execute.mdのtmux kill-windowが二重実行される可能性 → `commands/autopilot-phase-execute.md`の重複排除で対処
- **トレードオフ**: merge-gate-execute.shにautopilot分岐を追加することで非autopilotパスのコードパスが複雑になる → コメントで明示し、非autopilotパスは変更しないことで最小化
- **制約**: `AUTOPILOT_DIR` が未設定の場合のデフォルト値を `.autopilot/` に統一する必要がある（scripts全体の一貫性）
