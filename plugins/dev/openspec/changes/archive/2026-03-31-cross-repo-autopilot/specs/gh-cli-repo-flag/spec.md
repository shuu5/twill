## MODIFIED Requirements

### Requirement: autopilot-plan.sh の -R フラグ対応

autopilot-plan.sh の `gh issue view` および `gh api` 呼び出しに、外部リポジトリの場合 `-R owner/repo` フラグを付与しなければならない（SHALL）。

#### Scenario: 外部リポジトリ Issue の取得
- **WHEN** `loom#50` の Issue 情報を取得する
- **THEN** `gh issue view 50 -R shuu5/loom --json ...` が実行される

#### Scenario: デフォルトリポジトリ Issue の取得
- **WHEN** `_default#42` の Issue 情報を取得する
- **THEN** 従来通り `gh issue view 42 --json ...` が実行される（`-R` なし）

### Requirement: worktree-create.sh の -R フラグ対応

worktree-create.sh の `gh issue view` に外部リポジトリの場合 `-R owner/repo` フラグを付与し、さらに対象リポジトリの bare repo パスで worktree を作成しなければならない（SHALL）。

#### Scenario: 外部リポジトリの worktree 作成
- **WHEN** loom#50 用の worktree を作成する
- **THEN** `gh issue view 50 -R shuu5/loom` で Issue 情報を取得し、loom リポジトリの bare repo 配下に worktree を作成する

### Requirement: merge-gate-init.sh の -R フラグ対応

merge-gate-init.sh の `gh pr diff` に外部リポジトリの場合 `-R owner/repo` を付与しなければならない（SHALL）。

#### Scenario: 外部リポジトリ PR の diff 取得
- **WHEN** loom リポジトリの PR #5 の diff を取得する
- **THEN** `gh pr diff 5 -R shuu5/loom` が実行される

### Requirement: merge-gate-execute.sh の -R フラグ対応

merge-gate-execute.sh の `gh pr merge` に外部リポジトリの場合 `-R owner/repo` を付与しなければならない（SHALL）。

#### Scenario: 外部リポジトリ PR のマージ
- **WHEN** loom リポジトリの PR #5 をマージする
- **THEN** `gh pr merge 5 -R shuu5/loom --squash` が実行される

### Requirement: parse-issue-ac.sh の -R フラグ対応

parse-issue-ac.sh の `gh api "repos/{owner}/{repo}/..."` 呼び出しで、外部リポジトリの場合 owner/repo を明示的に指定しなければならない（SHALL）。

#### Scenario: 外部リポジトリ Issue の AC パース
- **WHEN** loom#50 の受け入れ基準をパースする
- **THEN** `gh api "repos/shuu5/loom/issues/50"` のように owner/repo を明示指定する
