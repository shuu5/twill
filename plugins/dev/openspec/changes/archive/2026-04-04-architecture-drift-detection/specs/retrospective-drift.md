## ADDED Requirements

### Requirement: autopilot-retrospective Step 4.5（architecture 差分チェック）

autopilot-retrospective の Step 4（doobidoo memory 保存）の直後に Step 4.5 を追加しなければならない（SHALL）。

Step 4.5 は以下を実行しなければならない（SHALL）:
- Phase で変更されたファイルのパスを収集する
- 変更ファイルと `architecture/` 内のコンテキストファイルの対応を確認する
- 乖離が疑われる候補リストを「以下の architecture 項目の更新を検討してください:」の形式で提示する
- 自動 Issue 化は行ってはならない（SHALL NOT）

architecture/ が存在しない場合、Step 4.5 全体をスキップしなければならない（SHALL）。

#### Scenario: Phase でコンポーネントが追加される
- **WHEN** autopilot Phase で `commands/new-atomic.md` が新規追加された
- **THEN** Step 4.5 が「`architecture/domain/model.md` の Component Mapping セクションの更新を検討してください」を提示する

#### Scenario: Phase で状態遷移ロジックが変更される
- **WHEN** autopilot Phase で `scripts/state-update.sh` が変更された
- **THEN** Step 4.5 が「`architecture/domain/model.md` の IssueState / SessionState 定義の更新を検討してください」を提示する

#### Scenario: architecture/ が存在しない
- **WHEN** プロジェクトに `architecture/` ディレクトリが存在しない
- **THEN** Step 4.5 をスキップし、メッセージを出力せずに完了する

#### Scenario: 変更ファイルと architecture/ の対応が不明
- **WHEN** Phase 変更ファイルがいずれの architecture/ コンテキストとも対応しない
- **THEN** 候補リストを空として「architecture 更新候補なし」と提示する
