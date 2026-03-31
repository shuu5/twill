## ADDED Requirements

### Requirement: auto-merge autopilot 配下判定

`auto-merge.md` は issue-{N}.json の status が `running` の場合、merge/worktree 削除を実行せず merge-ready 宣言のみを行わなければならない（SHALL）。

#### Scenario: autopilot 配下で Worker が pr-cycle を完走
- **WHEN** issue-{N}.json の status が `running` である
- **THEN** `auto-merge.md` は `gh pr merge` を実行しない
- **THEN** `auto-merge.md` は worktree 削除を実行しない
- **THEN** `auto-merge.md` は `state-write.sh` で status を `merge-ready` に遷移する

#### Scenario: autopilot 非配下で Worker が pr-cycle を完走
- **WHEN** issue-{N}.json が存在しない、または status が `running` でない
- **THEN** `auto-merge.md` は従来通り merge → archive → cleanup を実行する

### Requirement: all-pass-check autopilot 配下 merge-ready 宣言

`all-pass-check.md` は autopilot 配下（issue-{N}.json status=running）時に state-write で merge-ready に遷移しなければならない（MUST）。

#### Scenario: autopilot 配下で全ステップ PASS
- **WHEN** 全ステップが PASS/WARN で、issue-{N}.json の status が `running` である
- **THEN** `all-pass-check.md` は `state-write.sh` で status を `merge-ready` に遷移する

#### Scenario: autopilot 配下で FAIL あり
- **WHEN** いずれかのステップが FAIL で、issue-{N}.json の status が `running` である
- **THEN** `all-pass-check.md` は `state-write.sh` で status を `failed` に遷移する

### Requirement: merge-gate-execute CWD ガード

`merge-gate-execute.sh` は worktrees/ 配下からの実行を拒否しなければならない（SHALL）。

#### Scenario: worktrees/ 配下から merge-gate-execute を実行
- **WHEN** CWD が `*/worktrees/*` に一致する
- **THEN** `merge-gate-execute.sh` はエラーメッセージを出力して exit 1 で終了する

#### Scenario: main/ worktree から merge-gate-execute を実行
- **WHEN** CWD が `*/worktrees/*` に一致しない
- **THEN** `merge-gate-execute.sh` は通常通り処理を実行する
