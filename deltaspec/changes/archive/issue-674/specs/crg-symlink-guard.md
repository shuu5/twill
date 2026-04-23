## MODIFIED Requirements

### Requirement: crg-auto-build LLM symlink 操作禁止

LLM ステップ（crg-auto-build）は `.code-review-graph` に対して symlink 操作を実行してはならない（SHALL NOT）。`crg-auto-build.md` の禁止事項セクションに `ln` コマンド実行禁止および `.code-review-graph` の手動操作禁止を明記しなければならない（MUST）。

#### Scenario: LLM ステップで symlink 禁止ルールが明記されている
- **WHEN** `crg-auto-build.md` の `禁止事項（MUST NOT）` セクションを読む
- **THEN** `ln` コマンドの実行を禁止するルールが存在する

#### Scenario: LLM が壊れた symlink を検出した場合
- **WHEN** crg-auto-build の実行時に `.code-review-graph` が symlink である
- **THEN** 何も操作せず正常終了する（symlink の作成・削除・修正を行わない）

### Requirement: orchestrator main worktree CRG 自己参照防止チェック

orchestrator は main worktree の `.code-review-graph` が誤って symlink になっている場合、即座に削除しなければならない（MUST）。このチェックは CRG symlink 作成処理の冒頭、worktree の main 判定より前に実行されなければならない（MUST）。

#### Scenario: main worktree の .code-review-graph が symlink の場合
- **WHEN** orchestrator が worktree を処理する際、`${TWILL_REPO_ROOT}/main/.code-review-graph` が symlink である
- **THEN** 当該 symlink を削除し、警告ログを出力する

#### Scenario: main worktree の .code-review-graph が正常ディレクトリの場合
- **WHEN** orchestrator が worktree を処理する際、`${TWILL_REPO_ROOT}/main/.code-review-graph` が通常ディレクトリである
- **THEN** 何もせず既存処理を継続する

## ADDED Requirements

### Requirement: su-observer Wave 開始時 CRG ヘルスチェック

su-observer は各 Wave の開始時に `main/.code-review-graph` の symlink 状態をチェックしなければならない（MUST）。symlink が検出された場合、即座に警告を出力しなければならない（MUST）。

#### Scenario: Wave 開始時に main CRG が symlink の場合
- **WHEN** su-observer が Wave 開始処理を実行する
- **AND** `${TWILL_REPO_ROOT}/main/.code-review-graph` が symlink である
- **THEN** `⚠️ [CRG health]` プレフィックスを付けた警告メッセージを出力する

#### Scenario: Wave 開始時に main CRG が正常ディレクトリの場合
- **WHEN** su-observer が Wave 開始処理を実行する
- **AND** `${TWILL_REPO_ROOT}/main/.code-review-graph` が通常ディレクトリである
- **THEN** 何も出力しない（サイレント正常終了）
