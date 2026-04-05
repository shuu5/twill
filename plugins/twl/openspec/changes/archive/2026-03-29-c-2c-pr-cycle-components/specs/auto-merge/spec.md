## ADDED Requirements

### Requirement: autopilot-first squash マージ実行

merge-gate から呼び出され、squash マージ → archive → cleanup を実行しなければならない（SHALL）。

autopilot-first 前提のため、旧プラグインの `--auto-merge` フラグ分岐・環境変数チェック・マーカーファイル管理は使用しない。状態管理は issue-{N}.json + state-write.sh に一元化する。

#### Scenario: squash マージ成功
- **WHEN** merge-gate が PASS 判定を返し auto-merge が呼び出される
- **THEN** `gh pr merge --squash --delete-branch` で squash マージを実行する

#### Scenario: マージ失敗時の停止
- **WHEN** squash マージが失敗する（コンフリクト等）
- **THEN** 停止のみ行い、自動 rebase は試みない（MUST NOT）

### Requirement: archive 自動実行

マージ成功後、OpenSpec change が存在する場合は archive を実行しなければならない（SHALL）。

#### Scenario: OpenSpec change 存在時の archive
- **WHEN** マージ成功後に `openspec/changes/` にアクティブな change が存在する
- **THEN** `deltaspec archive <change-id> --yes --skip-specs` を実行する

#### Scenario: OpenSpec 未使用時のスキップ
- **WHEN** `openspec/changes/` にアクティブな change がない
- **THEN** archive ステップをスキップする

### Requirement: cleanup 実行

マージ・archive 後に worktree/ブランチの cleanup を実行しなければならない（SHALL）。

#### Scenario: worktree モードの cleanup
- **WHEN** REPO_MODE が worktree である
- **THEN** main worktree に移動し、feature worktree とブランチを削除する

#### Scenario: standard モードの cleanup
- **WHEN** REPO_MODE が standard である
- **THEN** main ブランチに切り替え、feature ブランチを削除する

### Requirement: --auto-merge 関連コード禁止

auto-merge コンポーネント内に `--auto-merge` フラグ分岐、パイロット制御ガード（マーカーファイル）、環境変数 `DEV_AUTOPILOT_SESSION` チェックを含めてはならない（MUST NOT）。

#### Scenario: フラグ分岐の不在確認
- **WHEN** auto-merge の COMMAND.md を検査する
- **THEN** `--auto-merge`, `DEV_AUTOPILOT_SESSION`, `.pilot-controlled`, `.merge-ready`, `.done`, `.fail` への参照が存在しない
