## ADDED Requirements

### Requirement: Board Issue 取得モード

`autopilot-plan.sh` に `--board` モードを追加し、Project Board の非 Done Issue を自動取得しなければならない（SHALL）。取得した Issue リストは既存の `parse_issues()` に渡して plan.yaml を生成する。

#### Scenario: Board から Todo/In Progress Issue を取得
- **WHEN** `autopilot-plan.sh --board --project-dir DIR --repo-mode MODE` を実行
- **THEN** リポジトリにリンクされた Project Board の Todo + In Progress ステータスの Issue 番号リストを取得し、`parse_issues()` に渡して plan.yaml を生成する

#### Scenario: Board に非 Done Issue がない場合
- **WHEN** `--board` モードで実行し、Board の全 Issue が Done ステータス
- **THEN** `"Board に未完了の Issue がありません"` とエラーメッセージを出力し、exit code 1 で終了する

#### Scenario: Draft issue や PR のフィルタリング
- **WHEN** Board に Draft issue や Pull Request が含まれる
- **THEN** `content.type` が `Issue` のもののみを対象とし、それ以外はスキップする（MUST）

### Requirement: 排他バリデーション

`--board` は `--explicit` および `--issues` と排他的でなければならない（MUST）。同時指定時はエラー終了する。

#### Scenario: --board と --issues の同時指定
- **WHEN** `autopilot-plan.sh --board --issues "42 43"` を実行
- **THEN** `"Error: --board は --explicit/--issues と同時に指定できません"` を出力し、exit code 1 で終了する

### Requirement: クロスリポジトリ Issue 自動解決

Board item の `content.repository` フィールドから、現在のリポジトリ以外の Issue を検出し、`--repos` JSON を自動構築しなければならない（SHALL）。

#### Scenario: 複数リポジトリの Issue が Board にある場合
- **WHEN** Board に `shuu5/loom-plugin-dev#110` と `shuu5/loom#56` がある
- **THEN** `--repos` JSON を `{"loom":{"owner":"shuu5","name":"loom","path":""}}` のように自動構築し、Issue リストを `"110 loom#56"` 形式で `parse_issues()` に渡す

#### Scenario: 単一リポジトリの Issue のみの場合
- **WHEN** Board の全 Issue が現在のリポジトリに属する
- **THEN** `--repos` JSON は構築せず、Issue 番号リストのみを `parse_issues()` に渡す

### Requirement: Project Board 自動検出

`--board` モード実行時、リポジトリにリンクされた Project Board を自動検出しなければならない（SHALL）。検出ロジックは `project-board-status-update.md` と同等。

#### Scenario: リポジトリにリンクされた Project が1つ
- **WHEN** リポジトリに1つの Project がリンクされている
- **THEN** その Project の item-list を取得する

#### Scenario: リポジトリにリンクされた Project が複数
- **WHEN** リポジトリに複数の Project がリンクされている
- **THEN** タイトルにリポジトリ名を含む Project を優先し、なければ最初のマッチを使用する

#### Scenario: リポジトリに Project がリンクされていない
- **WHEN** リポジトリにリンクされた Project がない
- **THEN** `"Error: リポジトリにリンクされた Project Board が見つかりません"` を出力し、exit code 1 で終了する

## MODIFIED Requirements

### Requirement: co-autopilot SKILL.md Step 0 引数解析テーブル更新

Step 0 引数解析テーブルに `--board` パターンを追加しなければならない（MUST）。

#### Scenario: --board パターンの解析
- **WHEN** ユーザーが `co-autopilot --board` を指定
- **THEN** MODE=board として `autopilot-plan.sh --board` を実行する

#### Scenario: --board と --auto の組み合わせ
- **WHEN** ユーザーが `co-autopilot --board --auto` を指定
- **THEN** MODE=board, AUTO=true として Board 取得→plan 生成→自動承認の流れを実行する
