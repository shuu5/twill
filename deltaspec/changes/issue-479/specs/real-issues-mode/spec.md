## ADDED Requirements

### Requirement: real-issues モードフラグ

`/twl:test-project-init` は `--mode real-issues --repo <owner>/<name>` 引数を受け付けなければならない（SHALL）。`--mode` 未指定時は `local` をデフォルトとして既存動作を維持しなければならない（SHALL）。

#### Scenario: real-issues モードで引数を受け付ける
- **WHEN** `/twl:test-project-init --mode real-issues --repo owner/test-repo` を実行する
- **THEN** `real-issues` モードフローが起動し、`owner/test-repo` を対象リポとして処理する

#### Scenario: --mode 未指定時は local モードで動作
- **WHEN** `/twl:test-project-init` を引数なしで実行する
- **THEN** 既存の `local` モード動作と同一の結果になる

---

### Requirement: 既存リポの検証

`--mode real-issues` 時に指定リポが存在する場合、空リポ検証（コミット数 == 0 かつブランチ数 <= 1）と push パーミッション確認を実行しなければならない（SHALL）。検証失敗時は明確なエラーメッセージを表示して停止しなければならない（SHALL）。

#### Scenario: 既存の空リポを指定した場合
- **WHEN** 既存の空リポ（コミット数 == 0）を `--repo` で指定する
- **THEN** パーミッション確認を通過し、リポを紐付けて成功する

#### Scenario: 既存の非空リポを指定した場合
- **WHEN** コミットが存在するリポを `--repo` で指定する
- **THEN** 「リポが空ではありません」エラーを表示して停止する

#### Scenario: push パーミッションがない場合
- **WHEN** push 権限のないリポを `--repo` で指定する
- **THEN** 「push パーミッションがありません」エラーを表示して停止する

---

### Requirement: 新規リポの自動作成

`--mode real-issues` 時に指定リポが存在しない場合、gh CLI で private・空・指定 owner のリポを作成しなければならない（SHALL）。作成失敗時（rate limit / 権限不足 / 名前衝突）はエラーメッセージを表示して停止しなければならない（SHALL）。

#### Scenario: 存在しないリポを指定した場合
- **WHEN** 存在しないリポ名を `--repo` で指定する
- **THEN** gh CLI でリポが作成され、紐付けが完了する

#### Scenario: 名前衝突でリポ作成失敗
- **WHEN** 他ユーザーが同名リポを所有している場合
- **THEN** 「リポ作成に失敗しました（名前衝突）」エラーを表示して停止する

---

### Requirement: .test-target/config.json の生成

`--mode real-issues` で初期化完了後、`.test-target/config.json` を以下スキーマで生成しなければならない（SHALL）: `mode`, `repo`, `initialized_at`, `worktree_path`, `branch`。

#### Scenario: real-issues モード初期化後の config.json
- **WHEN** `--mode real-issues --repo owner/test-repo` での初期化が成功する
- **THEN** `.test-target/config.json` に `mode: "real-issues"`, `repo: "owner/test-repo"` が記録される

#### Scenario: local モード初期化後の config.json
- **WHEN** `--mode local` での初期化が成功する
- **THEN** `.test-target/config.json` に `mode: "local"`, `repo: null` が記録される

## MODIFIED Requirements

### Requirement: test-project-init.md 禁止事項の条件付き化

`test-project-init.md` の「git push してはならない」禁止事項は `--mode local` のみに適用されるよう条件付きに変更しなければならない（SHALL）。`--mode real-issues` では gh CLI 経由の remote 操作を許可しなければならない（SHALL）。

#### Scenario: local モードでの push 禁止維持
- **WHEN** `--mode local` で実行する
- **THEN** git push は禁止事項として維持され、コマンドは push を行わない

#### Scenario: real-issues モードでの remote 操作許可
- **WHEN** `--mode real-issues` で実行する
- **THEN** gh CLI 経由の remote リポ操作（clone/push）が許可される

---

### Requirement: TestProject エンティティの拡張

`observation.md` の `TestProject` エンティティに `mode: 'local' | 'real-issues'`, `repo: string | null`, `loaded_issues_file: string | null` フィールドを追加しなければならない（SHALL）。

#### Scenario: TestProject エンティティの mode フィールド
- **WHEN** observation.md の TestProject テーブル定義を参照する
- **THEN** `mode`, `repo`, `loaded_issues_file` フィールドが定義されている

---

### Requirement: 既存 bats テストへの --mode local 明示

`co-self-improve-smoke.bats` と `co-self-improve-regression.bats` の `test-project-init` 呼び出しに `--mode local` を明示しなければならない（SHALL）。

#### Scenario: bats テストが --mode local を明示して通過
- **WHEN** `co-self-improve-smoke.bats` と `co-self-improve-regression.bats` を実行する
- **THEN** 全テストが `--mode local` 引数付きで通過する
