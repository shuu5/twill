## ADDED Requirements

### Requirement: issue-critic 調査バジェット制御

issue-critic エージェントは scope_files が 3 ファイル以上の場合、各ファイルの調査を 2-3 tool calls に制限しなければならない（SHALL）。調査は「ファイル存在確認 + 直接の呼び出し元 1 段」に留め、再帰的な依存追跡を行ってはならない（SHALL NOT）。残り turns が 3 以下になった時点で調査を打ち切り、出力生成を優先しなければならない（SHALL）。

#### Scenario: scope_files が 4 件の場合の調査制限
- **WHEN** issue-critic が scope_files: [A, B, C, D] を含む Issue をレビューする
- **THEN** 各ファイルの調査に使用する tool calls は最大 3 回に制限され、ファイル A の調査完了後に B, C, D に進む

#### Scenario: turns 残り 3 以下での出力優先
- **WHEN** issue-critic の残り turns が 3 以下になる
- **THEN** 進行中の調査を打ち切り、それまでの調査結果に基づいて構造化 findings を出力する

### Requirement: issue-feasibility 調査バジェット制御

issue-feasibility エージェントは scope_files が 3 ファイル以上の場合、各ファイルの調査を 2-3 tool calls に制限しなければならない（SHALL）。再帰的な依存追跡を行ってはならない（SHALL NOT）。残り turns が 3 以下になった時点で出力生成を優先しなければならない（SHALL）。

#### Scenario: scope_files が 4 件の場合の調査制限
- **WHEN** issue-feasibility が scope_files: [A, B, C, D] を含む Issue の実装可能性を検証する
- **THEN** 各ファイルの調査に使用する tool calls は最大 3 回に制限される

#### Scenario: turns 残り 3 以下での出力優先
- **WHEN** issue-feasibility の残り turns が 3 以下になる
- **THEN** 進行中の調査を打ち切り、構造化 findings を出力する
