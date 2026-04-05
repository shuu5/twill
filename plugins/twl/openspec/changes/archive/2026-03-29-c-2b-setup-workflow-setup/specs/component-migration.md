## ADDED Requirements

### Requirement: services コマンド移植

旧プラグインの services コマンドを loom-plugin-dev に移植しなければならない（SHALL）。COMMAND.md を `commands/services.md` に作成し、deps.yaml の commands セクションに atomic 型として登録する。

#### Scenario: services コマンド登録
- **WHEN** services の COMMAND.md が作成され deps.yaml に登録される
- **THEN** `loom validate` で services が認識され、spawnable_by に controller/workflow が含まれる

#### Scenario: services の機能保持
- **WHEN** 移植された services コマンドが実行される
- **THEN** 開発サービスの up/down/status/logs アクションが旧プラグインと同等に機能する

### Requirement: ui-capture コマンド移植

旧プラグインの ui-capture コマンドを loom-plugin-dev に移植しなければならない（SHALL）。COMMAND.md を `commands/ui-capture.md` に作成し、deps.yaml の commands セクションに atomic 型として登録する。

#### Scenario: ui-capture コマンド登録
- **WHEN** ui-capture の COMMAND.md が作成され deps.yaml に登録される
- **THEN** `loom validate` で ui-capture が認識され、Playwright MCP ツールへの参照が含まれる

#### Scenario: ui-capture のスクショ撮影
- **WHEN** ユーザーが UI の問題を報告し ui-capture が呼び出される
- **THEN** ブラウザのスクリーンショットが撮影され、セマンティック解析結果がコンテキストとして返される

### Requirement: e2e-plan コマンド移植

旧プラグインの e2e-plan コマンドを loom-plugin-dev に移植しなければならない（SHALL）。COMMAND.md を `commands/e2e-plan.md` に作成し、deps.yaml の commands セクションに atomic 型として登録する。

#### Scenario: e2e-plan コマンド登録
- **WHEN** e2e-plan の COMMAND.md が作成され deps.yaml に登録される
- **THEN** `loom validate` で e2e-plan が認識され、コードベース静的分析によるテスト計画生成が可能

#### Scenario: e2e-plan のテスト計画出力
- **WHEN** e2e-plan がフィーチャー名を引数に実行される
- **THEN** 4層検証（API/データ/UI/Visual）を含むテスト計画が Markdown 形式で出力される

### Requirement: test-scaffold コマンド移植

旧プラグインの test-scaffold コマンドを loom-plugin-dev に移植しなければならない（MUST）。COMMAND.md を `commands/test-scaffold.md` に作成し、deps.yaml の commands セクションに composite 型として登録する。

#### Scenario: test-scaffold コマンド登録
- **WHEN** test-scaffold の COMMAND.md が作成され deps.yaml に composite 型として登録される
- **THEN** `loom validate` で test-scaffold が認識され、can_spawn に specialist が含まれる

#### Scenario: test-scaffold の Scenario 分類
- **WHEN** test-scaffold が change-id を引数に実行される
- **THEN** openspec specs の Scenario が Unit/Integration/E2E に分類され、適切な specialist が spawn される

### Requirement: worktree-delete コマンド化

既存の `scripts/worktree-delete.sh` をラップする COMMAND.md を作成しなければならない（SHALL）。`commands/worktree-delete.md` に作成し、deps.yaml の commands セクションに atomic 型として登録する。既存の script エントリはそのまま残す。

#### Scenario: worktree-delete コマンド登録
- **WHEN** worktree-delete の COMMAND.md が作成され deps.yaml に登録される
- **THEN** `loom validate` で command 版 worktree-delete が認識され、script への calls 関係が定義される

#### Scenario: worktree-delete コマンド実行
- **WHEN** worktree-delete コマンドが引数付きで実行される
- **THEN** `scripts/worktree-delete.sh` が呼び出され、worktree とブランチが安全に削除される

## MODIFIED Requirements

### Requirement: workflow-test-ready の calls 補完

workflow-test-ready の deps.yaml 定義に calls フィールドを追加しなければならない（MUST）。test-scaffold と opsx-apply を step 番号付きで登録する。

#### Scenario: workflow-test-ready の calls 定義
- **WHEN** deps.yaml の workflow-test-ready に calls が追加される
- **THEN** test-scaffold と opsx-apply が step 番号付きで定義され、`loom validate` で呼び出し関係が検証される

#### Scenario: workflow-test-ready チェーン整合性
- **WHEN** `loom validate` が実行される
- **THEN** workflow-test-ready の calls と各コンポーネントの step_in が双方向で一致する

### Requirement: deps.yaml 全11コンポーネント整合性

Issue #15 対象の全11コンポーネントが deps.yaml v3.0 で正しく定義され、chain step と呼び出し関係が B-4 の chain 定義と一致しなければならない（MUST）。

#### Scenario: loom validate PASS
- **WHEN** 全コンポーネントの登録と prompt ファイル作成が完了する
- **THEN** `loom validate` が警告・エラーなしで PASS する

#### Scenario: 全11コンポーネント確認
- **WHEN** deps.yaml を検査する
- **THEN** init, worktree-create, crg-auto-build, services, worktree-list, worktree-delete, ui-capture, e2e-plan, test-scaffold, workflow-test-ready, opsx-apply の全11コンポーネントが定義されている
