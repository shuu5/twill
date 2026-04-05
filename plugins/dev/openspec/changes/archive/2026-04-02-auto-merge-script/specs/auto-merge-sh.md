## ADDED Requirements

### Requirement: auto-merge.sh 4 Layer ガード

auto-merge.sh は 4 Layer のガードを実装し、不変条件 C（Worker マージ禁止）を機械的に担保しなければならない（SHALL）。

#### Scenario: Layer 2 CWD ガード — worktrees 配下から実行
- **WHEN** auto-merge.sh が worktrees/ 配下の CWD から実行される
- **THEN** エラーメッセージを出力し exit 1 で終了する（merge を実行しない）

#### Scenario: Layer 3 tmux window ガード — autopilot Worker window から実行
- **WHEN** tmux window 名が `ap-#N` パターンに一致する
- **THEN** エラーメッセージを出力し exit 1 で終了する（merge を実行しない）

#### Scenario: Layer 1 IS_AUTOPILOT 判定 — state-read.sh で running 検出
- **WHEN** state-read.sh が issue の status を `running` と返す
- **THEN** IS_AUTOPILOT=true とし、state-write.sh で status を `merge-ready` に遷移し、merge を実行せずに exit 0 する

#### Scenario: Layer 4 フォールバック — state-read.sh は false だが issue-{N}.json が存在
- **WHEN** IS_AUTOPILOT=false かつ main worktree の `.autopilot/issue-{N}.json` が存在する
- **THEN** 誤判定と見なし、merge を禁止し merge-ready に遷移して exit 0 する

#### Scenario: Layer 4 フォールバック — ISSUE_NUM 未設定
- **WHEN** ISSUE_NUM が空文字列または未設定
- **THEN** フォールバックチェックをスキップし、通常の merge フローを実行する

### Requirement: auto-merge.sh 引数解析

auto-merge.sh は `--issue`, `--pr`, `--branch` の名前付き引数を受け取らなければならない（MUST）。

#### Scenario: 必須引数が不足
- **WHEN** --issue, --pr, --branch のいずれかが未指定
- **THEN** usage を表示し exit 1 で終了する

#### Scenario: 引数バリデーション
- **WHEN** --issue に非数値、--branch に不正文字が渡される
- **THEN** エラーメッセージを出力し exit 1 で終了する

### Requirement: auto-merge.sh 非 autopilot 時の squash merge

非 autopilot 実行時、auto-merge.sh は squash merge + worktree 削除 + OpenSpec archive を実行しなければならない（SHALL）。

#### Scenario: 非 autopilot — 正常 merge
- **WHEN** IS_AUTOPILOT=false で全ガードを通過した
- **THEN** `gh pr merge --squash` を実行し、worktree 削除、OpenSpec archive（存在時）、ブランチ削除を行う

#### Scenario: 非 autopilot — merge 失敗
- **WHEN** `gh pr merge --squash` が失敗する
- **THEN** エラーを出力し exit 1 で終了する（自動 rebase は試みない）

#### Scenario: 非 autopilot — cleanup 失敗
- **WHEN** worktree 削除またはブランチ削除が失敗する
- **THEN** 警告を出力するが処理は続行する（merge は成功済み）

## MODIFIED Requirements

### Requirement: auto-merge.md の簡素化

auto-merge.md は `bash scripts/auto-merge.sh --issue $ISSUE_NUM --pr $PR_NUMBER --branch $BRANCH` の呼び出しのみに簡素化しなければならない（MUST）。

#### Scenario: auto-merge.md から script 呼び出し
- **WHEN** auto-merge.md が実行される
- **THEN** auto-merge.sh に引数を渡して呼び出すのみで、LLM による bash 解釈実行は行わない
