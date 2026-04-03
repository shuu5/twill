## ADDED Requirements

### Requirement: Board アーカイブコマンド
`chain-runner.sh` は `board-archive <ISSUE_NUM>` サブコマンドを受け付け、指定 Issue の Project Board アイテムをアーカイブしなければならない（SHALL）。

#### Scenario: 正常アーカイブ
- **WHEN** `bash scripts/chain-runner.sh board-archive "131"` を実行し、Project が検出され、アイテムIDが取得できる
- **THEN** `gh project item-archive` が呼ばれ、`✓ board-archive: Board アイテムをアーカイブしました (#131)` を出力して終了コード 0 で返る

#### Scenario: アーカイブ後 item-list に含まれない
- **WHEN** アーカイブ成功後に `gh project item-list` を実行する
- **THEN** Issue #131 のアイテムが結果に含まれない

#### Scenario: アイテムID取得失敗
- **WHEN** `gh project item-list` の結果に対象 Issue が存在しない
- **THEN** `⚠️ board-archive: アイテムIDが取得できませんでした — スキップ` を出力して終了コード 0 で返る（マージフローをブロックしない）

#### Scenario: `gh project item-archive` 失敗
- **WHEN** `gh project item-archive` がエラーを返す
- **THEN** `⚠️ board-archive: アーカイブに失敗しました — スキップ` を出力して終了コード 0 で返る

## MODIFIED Requirements

### Requirement: merge-gate PASS 時の自動アーカイブ
`merge-gate-execute.sh` は PASS フロー（squash merge + worktree 削除）の完了後に `board-archive` を呼び出さなければならない（SHALL）。

#### Scenario: merge-gate PASS 後の自動アーカイブ
- **WHEN** merge-gate が PASS 判定し、squash merge と worktree 削除が完了する
- **THEN** `bash scripts/chain-runner.sh board-archive "$ISSUE_NUM"` が実行され、Board アイテムがアーカイブされる

#### Scenario: アーカイブ失敗でもマージ成立
- **WHEN** `board-archive` が警告を出力して return 0 で終了する
- **THEN** merge-gate の終了コードはアーカイブ結果に影響されず、マージは成立済み状態を維持する
