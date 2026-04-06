# merge-gate フォローアップ Issue の project board 自動登録

status: approved

## 概要

merge-gate の CRITICAL/tech-debt findings から起票されるフォローアップ Issue が project board に自動登録されない問題を修正する。

## 背景

- `project-board-sync` は co-issue フローでは呼び出されるが、merge-gate-issues.sh からは呼び出されない
- merge-gate-issues.sh は `gh issue create` で直接 Issue を作成するため board 登録が漏れる

## MODIFIED Requirements

### Requirement: merge-gate-issues.sh に project board 登録を追加

merge-gate-issues.sh は Issue 起票後に project board へ自動登録しなければならない（SHALL）。

#### Scenario: tech-debt Issue 起票後の board 登録
- **WHEN** merge-gate-issues.sh が tech-debt Issue を `gh issue create` で起票する
- **THEN** 起票された Issue の番号を URL から抽出する
- **AND** `gh project item-add` でリポジトリにリンクされた Project に Issue を追加する
- **AND** board 登録失敗時は Warning を出力して処理を継続する（ワークフロー停止しない）

#### Scenario: self-improve Issue 起票後の board 登録
- **WHEN** merge-gate-issues.sh が self-improve Issue を `gh issue create` で起票する
- **THEN** 起票された Issue の番号を URL から抽出する
- **AND** Issue が作成されたリポジトリの Project に `gh project item-add` で追加する
- **AND** board 登録失敗時は Warning を出力して処理を継続する

#### Scenario: Project 未リンク時のスキップ
- **WHEN** リポジトリに Project V2 がリンクされていない
- **THEN** board 登録をスキップし Warning なしで正常終了する

## 実装方針

merge-gate-issues.sh 内に board 登録ヘルパー関数を追加。Issue 起票成功後に呼び出す。
Project 検出ロジックは project-board-status-update.md と同じパターン（GraphQL + user/org フォールバック）をシェル関数として実装。
