## MODIFIED Requirements

### Requirement: auto-merge autopilot 配下判定

auto-merge.md は autopilot 配下（issue-{N}.json の status が running）の場合、merge・archive・worktree 削除を実行せず merge-ready 宣言のみ行わなければならない（SHALL）。

#### Scenario: autopilot 配下で auto-merge 実行
- **WHEN** issue-{N}.json が存在し status=running である
- **THEN** `state-write.sh --type issue --issue "$ISSUE_NUM" --role worker --set "status=merge-ready"` を実行し、merge/archive/worktree 削除をスキップして正常終了する

#### Scenario: autopilot 非配下で auto-merge 実行
- **WHEN** issue-{N}.json が存在しない、または status が running でない
- **THEN** 既存動作を維持し、squash merge → archive → cleanup を実行する

#### Scenario: state-read 失敗時のフォールバック
- **WHEN** state-read.sh がエラーを返す（ファイル不在、jq エラー等）
- **THEN** 非 autopilot として扱い、既存の merge フローを実行する

## ADDED Requirements

### Requirement: auto-merge worktree 削除スキップ

auto-merge.md は autopilot 配下の場合、worktree 削除を実行してはならない（MUST NOT）。worktree 削除は Pilot に委譲しなければならない（SHALL）。

#### Scenario: autopilot 配下での worktree 削除スキップ
- **WHEN** autopilot 配下判定が true
- **THEN** cleanup ステップ（Step 3）を完全にスキップする
