## REMOVED Requirements

### Requirement: ユーザースコープスキル廃止

`~/.claude/skills/` 配下の spawn, observe, fork, fork-cd ディレクトリを削除しなければならない（SHALL）。

#### Scenario: スキルディレクトリ削除
- **WHEN** 廃止対象のスキルディレクトリ（spawn, observe, fork, fork-cd）が `~/.claude/skills/` に存在する
- **THEN** 各ディレクトリとその配下の SKILL.md を削除する

#### Scenario: 削除後の不在確認
- **WHEN** 削除完了後
- **THEN** `~/.claude/skills/` に spawn, observe, fork, fork-cd が存在しない

### Requirement: ubuntu-note-system スクリプト廃止

`ubuntu-note-system/scripts/` 配下の対象 6 スクリプトを削除しなければならない（MUST）。

対象: `cld-spawn`, `cld-observe`, `cld-fork`, `cld-fork-cd`, `session-state.sh`, `session-comm.sh`

#### Scenario: スクリプト削除
- **WHEN** 対象 6 スクリプトが `ubuntu-note-system/scripts/` に存在する
- **THEN** 各スクリプトを削除し、ubuntu-note-system リポジトリにコミットする

#### Scenario: deploy 反映
- **WHEN** スクリプト削除コミット後
- **THEN** `./scripts/deploy.sh --all` を実行し symlink 更新を反映する

## MODIFIED Requirements

### Requirement: PATH 設定更新

旧スクリプトパスを PATH から除去し、session plugin の scripts/ パスを追加しなければならない（SHALL）。

#### Scenario: 旧パス除去
- **WHEN** PATH 設定に `ubuntu-note-system/scripts/` 内の廃止スクリプトへの参照がある
- **THEN** 該当エントリを除去する

#### Scenario: session plugin パス追加
- **WHEN** session plugin の `scripts/` が PATH に含まれていない
- **THEN** `~/.claude/plugins/session/scripts/` または loom-plugin-session の scripts/ パスを PATH に追加する

## ADDED Requirements

### Requirement: 参照エラー不在検証

削除後に他プロジェクトから旧スキル・スクリプトへの参照が残っていないことを検証しなければならない（MUST）。

#### Scenario: grep 検証
- **WHEN** 全ファイル削除・PATH 更新完了後
- **THEN** `grep -r` で `~/.claude/`, `~/ubuntu-note-system/`, `~/projects/` 配下に旧パス参照（`cld-spawn`, `cld-observe`, `cld-fork`, `cld-fork-cd`, `session-state.sh`, `session-comm.sh`）が残っていないことを確認する

#### Scenario: スキル動作確認
- **WHEN** 検証完了後
- **THEN** `/spawn`, `/observe`, `/fork` が session plugin 経由で正常に解決されることを確認する
