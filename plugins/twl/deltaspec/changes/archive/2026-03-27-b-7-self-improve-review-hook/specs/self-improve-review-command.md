## ADDED Requirements

### Requirement: self-improve-review コマンド

ユーザーが `/twl:self-improve-review` で呼び出す atomic コマンドを提供しなければならない（SHALL）。

コマンドは以下のフローを実行する:
1. `.self-improve/errors.jsonl` を読み込み
2. エラーを集計（コマンド別、exit_code 別、頻度順）
3. サマリーテーブルをユーザーに提示
4. AskUserQuestion で選択肢提示
5. 選択されたエラーについて問題を構造化
6. `.controller-issue/explore-summary.md` に書き出し

#### Scenario: エラーログなしの終了
- **WHEN** `.self-improve/errors.jsonl` が存在しないまたは空である
- **THEN** 「エラーログなし」とメッセージを表示して正常終了する

#### Scenario: エラーサマリー表示
- **WHEN** `.self-improve/errors.jsonl` に 1 件以上のエラーが記録されている
- **THEN** コマンド別・exit_code 別にグループ化したサマリーテーブルが表示される

#### Scenario: ユーザー選択による構造化
- **WHEN** ユーザーがサマリーから特定のエラーグループを選択する
- **THEN** 選択されたエラーについて会話コンテキストを参照し問題が構造化される

### Requirement: explore-summary.md 出力

self-improve-review は構造化結果を `.controller-issue/explore-summary.md` に書き出さなければならない（MUST）。このファイルは co-issue の Phase 1 出力と同形式でなければならない（SHALL）。

#### Scenario: explore-summary.md の生成
- **WHEN** ユーザーがエラーの構造化を完了する
- **THEN** `.controller-issue/explore-summary.md` が co-issue Phase 1 互換形式で生成される

#### Scenario: co-issue 続行の確認
- **WHEN** explore-summary.md の生成が完了する
- **THEN** 「co-issue を呼び出して Issue 化を続けますか？」とユーザーに確認する

### Requirement: エラーログクリアオプション

self-improve-review はエラーログのクリアオプションを提供しなければならない（SHALL）。

#### Scenario: エラーログのクリア
- **WHEN** ユーザーがクリアオプションを選択する
- **THEN** `.self-improve/errors.jsonl` が削除される

### Requirement: deps.yaml 登録

`self-improve-review` を deps.yaml の `commands` セクションに atomic コマンドとして登録しなければならない（MUST）。

#### Scenario: deps.yaml への登録
- **WHEN** self-improve-review コマンドが追加される
- **THEN** deps.yaml の commands セクションに type: atomic、path: commands/self-improve-review.md として登録される
