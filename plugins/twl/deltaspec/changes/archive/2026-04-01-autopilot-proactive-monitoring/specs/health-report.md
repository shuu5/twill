## ADDED Requirements

### Requirement: health-report 出力

異常検知時に `.autopilot/health-reports/issue-{N}-{timestamp}.md` へ構造化レポートを出力しなければならない（MUST）。

#### Scenario: レポートファイル生成
- **WHEN** health-check.sh が異常を検知（exit code 1）
- **THEN** `.autopilot/health-reports/issue-{ISSUE_NUM}-{YYYYMMDD-HHMMSS}.md` にレポートを生成しなければならない（SHALL）

#### Scenario: レポート内容
- **WHEN** レポートが生成される
- **THEN** 以下のセクションを含まなければならない（MUST）:
  - 検知パターン種別（chain_stall / error_output / input_waiting）
  - 検知時刻
  - tmux capture-pane の出力（最新 50 行）
  - Issue Draft テンプレート（タイトル、概要、再現状況）

#### Scenario: Issue Draft テンプレート形式
- **WHEN** レポートに Issue Draft が含まれる
- **THEN** 以下の形式でなければならない（SHALL）:
  ```
  ## Issue Draft
  **Title**: [autopilot] Worker #N: {検知パターン}
  **Body**:
  ### 概要
  {異常の説明}
  ### 再現状況
  {tmux capture-pane の関連部分}
  ### 対応候補
  {パターンに応じた提案}
  ```

#### Scenario: ディレクトリ自動作成
- **WHEN** `.autopilot/health-reports/` が存在しない
- **THEN** `mkdir -p` で自動作成しなければならない（SHALL）

### Requirement: gh issue create の禁止

レポートは Issue Draft テンプレートの出力のみとし、`gh issue create` を実行してはならない（MUST NOT）。

#### Scenario: Issue 自動作成の防止
- **WHEN** 異常が検知される
- **THEN** レポートファイルへの出力のみ行い、GitHub API を呼び出してはならない（MUST NOT）
