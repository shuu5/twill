## MODIFIED Requirements

### Requirement: workflow SKILL.md への compaction 復帰プロトコル追記
`workflow-setup/SKILL.md`、`workflow-test-ready/SKILL.md`、`workflow-pr-cycle/SKILL.md` の各ファイルに compaction 復帰プロトコルセクションを追記しなければならない（SHALL）。プロトコルは chain 再開時に `compaction-resume.sh` を呼び出して完了済みステップをスキップする手順を明示しなければならない（SHALL）。

#### Scenario: workflow-setup SKILL.md からの compaction 後再開
- **WHEN** Worker が compaction 後に workflow-setup chain を再開する
- **THEN** SKILL.md の復帰プロトコルに従い `compaction-resume.sh` で current_step を確認し、完了済みステップをスキップして正しいステップから実行を継続できる

#### Scenario: workflow-pr-cycle SKILL.md からの compaction 後再開
- **WHEN** Worker が compaction 後に workflow-pr-cycle の途中ステップを再開する
- **THEN** SKILL.md の復帰プロトコルに従い、完了済み 11 ステップのうち途中まで完了したステップをスキップし残りのステップのみ実行する

#### Scenario: 復帰プロトコルなしの場合（失敗ケース）
- **WHEN** SKILL.md に復帰プロトコルが存在しない状態で Worker が compaction 後に再開する
- **THEN** Worker は chain を最初から再実行するか中断し、二重実行や処理失敗が発生する
