## ADDED Requirements

### Requirement: PreCompact hook によるチェックポイント保存
`scripts/hooks/pre-compact-checkpoint.sh` を新規作成し、`hooks/hooks.json` に PreCompact hook として登録しなければならない（SHALL）。hook は compaction 前に `current_step` を issue-{N}.json に保存しなければならない（SHALL）。hook の失敗はワークフローを停止させてはならない（SHALL NOT）。

#### Scenario: PreCompact hook の正常実行
- **WHEN** Claude Code が compaction を開始する直前に PreCompact hook が発火する
- **THEN** `pre-compact-checkpoint.sh` が実行され、現在の `current_step` が issue-{N}.json に書き込まれる

#### Scenario: hook 失敗時の非停止動作
- **WHEN** `pre-compact-checkpoint.sh` がエラーで終了する（例: 書き込み権限なし）
- **THEN** compaction は継続され、ワークフロー全体は停止しない

### Requirement: compactPrompt による compaction 後コンテキスト保持
`settings.json` の `compactPrompt` フィールドを設定し、compaction サマリに chain 進行位置（current_step）・issue 番号・重要ファイルパスを保持するよう LLM に指示しなければならない（SHALL）。

#### Scenario: compactPrompt による chain コンテキスト保持
- **WHEN** compaction が完了し LLM に compaction サマリが渡される
- **THEN** サマリには現在の issue 番号・current_step・関連する state ファイルパスが含まれる

#### Scenario: compaction 後の Worker 再開
- **WHEN** Worker が compaction 後に次のアクションを決定する
- **THEN** Worker は compactPrompt サマリから issue 番号と current_step を読み取り、正しいステップから chain を継続できる
