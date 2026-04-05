## MODIFIED Requirements

### Requirement: Project 検出ロジックの統一

`project-board-status-update.md` の Step 2 は、`project-board-sync.md` と同等の TITLE_MATCH_PROJECT パターンを使用して Project を検出しなければならない（SHALL）。

#### Scenario: リポジトリ名と一致するタイトルの Project が存在する場合
- **WHEN** リポジトリ `shuu5/loom-plugin-dev` にリンクされた Project が複数あり、タイトルに `loom-plugin-dev` を含む Project (#3) が存在する
- **THEN** TITLE_MATCH_PROJECT としてその Project を優先選択し、`gh project item-add` に使用する

#### Scenario: タイトルが一致する Project がない場合
- **WHEN** リポジトリにリンクされた Project が複数あるがタイトルにリポジトリ名を含むものがない
- **THEN** MATCHED_PROJECTS の最初の Project を使用し、警告メッセージを出力する

#### Scenario: リポジトリにリンクされた Project がない場合
- **WHEN** どの Project もリポジトリにリンクされていない
- **THEN** 警告なしで正常終了する（ワークフローを停止しない）

#### Scenario: user クエリが失敗し organization にフォールバック
- **WHEN** GraphQL の `user()` クエリが null を返す
- **THEN** `organization()` クエリにフォールバックして Project 情報を取得する

## ADDED Requirements

### Requirement: バッチバックフィルスクリプト

欠落した Issue を Project Board に一括追加する `scripts/project-board-backfill.sh` を提供しなければならない（MUST）。

#### Scenario: Issue 範囲を指定して一括追加
- **WHEN** `bash scripts/project-board-backfill.sh 41 58` を実行する
- **THEN** Issue #41 から #58 の全 Issue が Project Board (#3) に追加され、各 Issue の結果が表形式で出力される

#### Scenario: 既に Board に存在する Issue の処理
- **WHEN** バッチ対象に既に Board に存在する Issue が含まれる
- **THEN** `gh project item-add` は既存アイテムの ID を返すため、エラーにならず処理を継続する

#### Scenario: 存在しない Issue 番号の処理
- **WHEN** 指定範囲に存在しない Issue 番号が含まれる
- **THEN** 該当 Issue をスキップし、警告を出力して次の Issue の処理を継続する

### Requirement: バッチ実行結果の検証

バッチスクリプト実行後の検証手順が明文化されていなければならない（SHALL）。

#### Scenario: Board 追加の検証
- **WHEN** バッチスクリプト実行後に検証コマンドを実行する
- **THEN** `gh project item-list --owner @me 3 --format json | jq '[.items[].content.number] | sort'` で対象 Issue が Board に存在することを確認できる
