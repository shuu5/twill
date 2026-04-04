## MODIFIED Requirements

### Requirement: Worker のリポジトリ別起動

autopilot-launch が Worker を起動する際、Issue の repo_id から repos セクションの path を解決し、正しいリポジトリの Pilot が事前作成した worktree ディレクトリで Claude Code を起動しなければならない（SHALL）。

#### Scenario: 外部リポジトリ Issue の Worker 起動
- **WHEN** loom#50 の Worker が起動される
- **THEN** `repos.loom.path` を解決し、bare repo 構造なら `{path}/worktrees/{branch}/` で、standard repo なら `{path}/{branch}/` で Pilot が作成した worktree ディレクトリにて Claude Code が起動される

#### Scenario: デフォルトリポジトリ Issue の Worker 起動
- **WHEN** lpd#42 の Worker が起動され、lpd がデフォルトリポジトリである
- **THEN** 従来通り `PROJECT_DIR/worktrees/{branch}/` で Pilot が作成した worktree ディレクトリにて起動される

### Requirement: AUTOPILOT_DIR の Pilot 固定

Worker が別リポジトリで起動される場合でも、AUTOPILOT_DIR は Pilot 側の `.autopilot/` パスに固定しなければならない（MUST）。

#### Scenario: 外部リポジトリ Worker の状態ファイルアクセス
- **WHEN** loom リポジトリで起動された Worker が状態を更新する
- **THEN** Pilot 側の `.autopilot/repos/loom/issues/issue-50.json` に書き込まれる（Worker のローカル `.autopilot/` ではない）

### Requirement: bare repo パス検証

Worker 起動前に repos[repo_id].path の存在と bare repo 構造を検証しなければならない（SHALL）。

#### Scenario: リポジトリパスが存在しない
- **WHEN** repos.loom.path が指すディレクトリが存在しない
- **THEN** エラーメッセージ「リポジトリパスが見つかりません: {path}」を出力し、該当 Issue をスキップする

#### Scenario: bare repo 構造でない
- **WHEN** repos.loom.path に `.bare/` が存在せず `.git/` ディレクトリがある
- **THEN** standard repo として `{path}` で起動する（bare repo 前提に固定しない）
