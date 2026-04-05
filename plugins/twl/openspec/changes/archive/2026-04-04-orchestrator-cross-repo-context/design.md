## Context

autopilot の ADR-007 クロスリポジトリ対応は `launch_worker()` では完了済み。`resolve_issue_repo_context()` が ISSUE_REPO_OWNER / ISSUE_REPO_NAME / ISSUE_REPO_PATH を設定するが、`_nudge_command_for_pattern()` と `cleanup_worker()` には伝搬されていない。

これらの関数は `poll_single` / `poll_phase` から呼ばれるが、これらも現在は issue 番号のみを受け取る。

## Goals / Non-Goals

**Goals:**
- `_nudge_command_for_pattern()` がクロスリポ環境で `--repo` フラグ付きの gh 呼び出しを実行する
- `cleanup_worker()` がクロスリポ環境で正しいリモートに branch 削除を送信する
- orchestrator-nudge.bats が gh API fallback とクロスリポシナリオをカバーする

**Non-Goals:**
- `resolve_issue_repo_context()` 自体の変更
- `merge-gate-execute.sh` の変更（worktree 内実行のためリポコンテキストが異なる）
- _default リポへの挙動変更

## Decisions

### 1. entry を下位関数に伝搬させる（シグネチャ拡張）

poll_single / poll_phase → check_and_nudge → _nudge_command_for_pattern の呼び出しチェーンにおいて entry 文字列を伝搬させる。

poll_single: `poll_single(issue)` → `poll_single(entry)`（entry から issue を resolve_issue_repo_context で抽出）

poll_phase: `poll_phase(issues...)` → `poll_phase(entries...)`（同様に各 entry から issue を抽出）

BATCH_ISSUES ではなく BATCH（entry リスト）を poll 関数に渡すよう main loop を変更する。

### 2. gh issue view に --repo フラグを条件付きで追加

`_nudge_command_for_pattern()` 内で ISSUE_REPO_OWNER / ISSUE_REPO_NAME が空でない場合のみ `--repo "$ISSUE_REPO_OWNER/$ISSUE_REPO_NAME"` を付与する。空の場合（_default）は従来通り。

### 3. cleanup_worker の remote を entry の ISSUE_REPO_PATH から決定

entry が "_default" 以外の場合、ISSUE_REPO_PATH から正しいリモートの push URL を特定する。

```bash
# entry が _default の場合
git push origin --delete "$branch"

# entry が _default 以外（ISSUE_REPO_PATH が設定）の場合
git -C "$ISSUE_REPO_PATH" push origin --delete "$branch"
```

`git -C "$ISSUE_REPO_PATH"` により、対象リポのワーキングディレクトリで git を実行し、正しい origin を参照する。

### 4. test double の gh スタブに --repo フラグ対応を追加

orchestrator-nudge.bats の gh スタブ関数が `--repo` フラグを受け取り、適切にフィルタリングできるよう拡張する。

## Risks / Trade-offs

- **シグネチャ変更の影響範囲**: poll_single / poll_phase / check_and_nudge のシグネチャが変わるため、これらを直接呼ぶすべての箇所を更新する必要がある（現状は main loop の1箇所のみ）
- **_default ケースの後方互換性**: ISSUE_REPO_ID が "_default" の場合は従来通り origin を使用し、既存動作を維持する
- **BATCH_ISSUES の廃止**: poll 関数が entry を受け取るようになるため、BATCH_ISSUES 配列は不要になる。merge-ready チェックも BATCH から issue 番号を抽出して対応する
