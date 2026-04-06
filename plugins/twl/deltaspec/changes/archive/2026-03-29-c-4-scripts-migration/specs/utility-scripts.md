## ADDED Requirements

### Requirement: classify-failure スクリプト移植

classify-failure.sh を新リポジトリの `scripts/` に移植しなければならない（SHALL）。テスト失敗の分類ロジックを維持する。

#### Scenario: 失敗ログの分類
- **WHEN** テスト失敗ログが入力される
- **THEN** 失敗カテゴリ（test_failure, build_error, timeout 等）が stdout に出力される

### Requirement: parse-issue-ac スクリプト移植

parse-issue-ac.sh を新リポジトリの `scripts/` に移植しなければならない（SHALL）。Issue body からの AC 抽出ロジックを維持する。

#### Scenario: AC 抽出
- **WHEN** Issue 番号が指定される
- **THEN** Issue body から受け入れ基準（AC）セクションが抽出される

### Requirement: session-audit スクリプト移植

session-audit.sh を新リポジトリの `scripts/` に移植し、DEV_AUTOPILOT_SESSION 参照を session.json ベースの判定に置換しなければならない（MUST）。

#### Scenario: セッション事後分析
- **WHEN** `bash scripts/session-audit.sh` を実行する
- **THEN** session.json から JSONL ログを分析し、5カテゴリのワークフロー信頼性問題を検出する

### Requirement: check-db-migration スクリプト移植

check-db-migration.py を新リポジトリの `scripts/` にそのまま移植しなければならない（SHALL）。Python スクリプトであり、ロジック変更は不要。

#### Scenario: DB マイグレーションチェック
- **WHEN** `python3 scripts/check-db-migration.py` を実行する
- **THEN** マイグレーションファイルの整合性が検証される

### Requirement: ecc-monitor スクリプト移植

ecc-monitor.sh を新リポジトリの `scripts/` に移植しなければならない（SHALL）。ECC リポジトリ変更検知のロジックを維持する。

#### Scenario: ECC 変更検知
- **WHEN** `bash scripts/ecc-monitor.sh` を実行する
- **THEN** ECC リポジトリの最新変更が検出され、関連性が評価される

### Requirement: codex-review スクリプト移植

codex-review.sh を新リポジトリの `scripts/` に移植しなければならない（SHALL）。

#### Scenario: Codex レビュー実行
- **WHEN** `bash scripts/codex-review.sh` を実行する
- **THEN** Codex によるコードレビューが実行される

### Requirement: create-harness-issue スクリプト移植

create-harness-issue.sh を新リポジトリの `scripts/` に移植しなければならない（SHALL）。self-improve Issue 起票のロジックを維持する。

#### Scenario: self-improve Issue 起票
- **WHEN** 改善提案データが入力される
- **THEN** GitHub Issue が適切なラベル・テンプレートで作成される
