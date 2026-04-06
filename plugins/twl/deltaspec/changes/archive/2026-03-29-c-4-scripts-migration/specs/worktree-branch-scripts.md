## ADDED Requirements

### Requirement: worktree-create スクリプト移植

worktree-create.sh を新リポジトリの `scripts/` に移植しなければならない（SHALL）。Issue番号からのブランチ名生成、バリデーション、依存同期のロジックを維持する。`$HOME/.claude/plugins/dev/scripts/` への固定パス参照を排除する。

#### Scenario: Issue番号指定での worktree 作成
- **WHEN** `bash scripts/worktree-create.sh '#11'` を実行する
- **THEN** Issue タイトルとラベルから slug を生成し、`worktrees/<branch>/` に worktree が作成される

#### Scenario: ブランチ名バリデーション
- **WHEN** 不正なブランチ名（大文字、50文字超、予約語）が指定される
- **THEN** エラーメッセージと修正候補が表示される

### Requirement: branch-create スクリプト移植

branch-create.sh を新リポジトリの `scripts/` に移植しなければならない（SHALL）。通常 repo 向けブランチ作成のロジックを維持する。

#### Scenario: Issue番号指定でのブランチ作成
- **WHEN** `bash scripts/branch-create.sh '#11'` を実行する
- **THEN** Issue タイトルとラベルから slug を生成し、feature ブランチが作成される

#### Scenario: --auto --auto-merge フラグの引き継ぎ
- **WHEN** `bash scripts/branch-create.sh --auto --auto-merge '#11'` を実行する
- **THEN** ブランチ作成後、フラグ情報が stdout に出力される
