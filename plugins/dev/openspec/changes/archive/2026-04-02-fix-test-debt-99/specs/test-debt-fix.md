## MODIFIED Requirements

### Requirement: 廃止フラグ参照テストの修正

`--auto`/`--auto-merge` フラグおよび `DEV_AUTOPILOT_SESSION` 環境変数は #47 で廃止済み。これらの不在を検証するテストが、検索パターンや対象ディレクトリの不一致で失敗しているため修正しなければならない（SHALL）。

#### Scenario: auto フラグ不在確認テストの修正
- **WHEN** `auto-flag-removal.test.sh` および関連テストを実行する
- **THEN** `--auto`/`--auto-merge` の不在確認が PASS する（検索対象と除外パターンが現行ディレクトリ構造に適合する）

#### Scenario: DEV_AUTOPILOT_SESSION 不在確認テストの修正
- **WHEN** `DEV_AUTOPILOT_SESSION` 不在確認テストを実行する
- **THEN** openspec 以外での完全不在が確認され PASS する

### Requirement: 削除済みコンポーネントのテスト修正

#82 で削除された `check-db-migration` や、統合・廃止されたスクリプト（`autopilot-plan.sh`、`autopilot-should-skip.sh`、`project-create.sh`、`project-migrate.sh`、`classify-failure.sh`、`session-audit.sh`、`ecc-monitor.sh`、`branch-create.sh`）の存在を前提とするテストを修正しなければならない（SHALL）。

#### Scenario: 削除済みスクリプトテストの除去または修正
- **WHEN** 削除済みスクリプトの機能を検証するテストが存在する
- **THEN** テストを削除するか、現行の代替実装に対する検証に書き換える

### Requirement: deps.yaml 構造変更に伴うテスト修正

#98 の deps.yaml 構造変更（external 依存除去、コンポーネント数変更）でカウント系・構造系テストが不整合になっているため修正しなければならない（SHALL）。

#### Scenario: コンポーネント数・ファイル数テストの更新
- **WHEN** agents 数、refs 数、bats/scenario ファイル数を期待するテストを実行する
- **THEN** 現行の実際の値と一致して PASS する

#### Scenario: chain/step_in 構造テストの更新
- **WHEN** chain 定義や step_in 双方向参照のテストを実行する
- **THEN** 現行の deps.yaml 構造に基づき PASS する

### Requirement: SKILL.md 構造テストの修正

co-issue SKILL.md の行数制限テストや pr-cycle SKILL.md の構造テストが現行の SKILL.md 内容と不整合になっているため修正しなければならない（SHALL）。

#### Scenario: co-issue SKILL.md 行数テスト
- **WHEN** co-issue SKILL.md の行数を検証する
- **THEN** 現行の実際の行数に基づく閾値で PASS する

#### Scenario: pr-cycle SKILL.md 構造テスト
- **WHEN** pr-cycle SKILL.md のステップ番号ルーティング・フロー列挙を検証する
- **THEN** 現行の chain-driven 構造に基づき PASS する

### Requirement: merge-gate テストの修正

merge-gate-execute.sh の `--reject`/`--reject-final` モード、パス分岐変数、health-report スタブ参照が現行実装と不整合なため修正しなければならない（SHALL）。

#### Scenario: merge-gate モード検証テストの修正
- **WHEN** merge-gate-execute.sh のモード分岐テストを実行する
- **THEN** 現行のモード実装に基づき PASS する

### Requirement: loom deep-validate 警告テストの修正

controller-bloat 警告や全 Warning 0 件テストが現行状態と不整合なため修正しなければならない（SHALL）。

#### Scenario: deep-validate 警告テストの更新
- **WHEN** loom deep-validate の警告件数テストを実行する
- **THEN** 現行の実際の警告件数に基づき PASS する

### Requirement: Bash エラー記録テストの修正

bash-error-recording テストが現行のエラー記録スクリプト実装と不整合なため修正しなければならない（SHALL）。

#### Scenario: エラー記録テストの修正
- **WHEN** Bash エラー記録テスト（exit_code 検証、成功時非記録）を実行する
- **THEN** 現行のエラー記録ロジックに基づき PASS する

### Requirement: worktree-create テストの修正

worktree-create.sh の git worktree add 呼び出し検証テストが現行実装と不整合なため修正しなければならない（SHALL）。

#### Scenario: worktree-create 機能テストの修正
- **WHEN** worktree-create.sh の機能テストを実行する
- **THEN** 現行のスクリプト実装に基づき PASS する

### Requirement: ベースラインテストの修正

bats テスト件数・scenario テスト件数のベースライン値、specialist パーサーテストが現行状態と不整合なため修正しなければならない（SHALL）。

#### Scenario: テストファイル数ベースラインの更新
- **WHEN** テストファイル数のベースラインテストを実行する
- **THEN** 現行の実際のファイル数と一致して PASS する
