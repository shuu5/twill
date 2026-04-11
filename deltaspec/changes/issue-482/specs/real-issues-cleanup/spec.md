## ADDED Requirements

### Requirement: real-issues クリーンアップフラグ

`test-project-reset` コマンドは `--real-issues` フラグを受け付け、`.test-target/loaded-issues.json` に記録された PR/Issue/branch を一括削除しなければならない（SHALL）。

#### Scenario: real-issues フラグで全リソース削除

- **WHEN** `--real-issues` フラグ付きで実行し、loaded-issues.json が存在する
- **THEN** 各エントリの PR close → Issue close → branch 削除が順次実行される

#### Scenario: loaded-issues.json が存在しない

- **WHEN** `--real-issues` フラグ付きで実行し、`.test-target/loaded-issues.json` が存在しない
- **THEN** エラーメッセージを出力して終了する（実操作なし）

### Requirement: older-than フィルタリング

`--older-than <duration>` オプションを指定した場合、`loaded_at` が指定期間より古いエントリのみを対象としなければならない（SHALL）。`duration` は `d`（日）、`w`（週）、`m`（月）の単位をサポートする。

#### Scenario: older-than で古いエントリのみ削除

- **WHEN** `--real-issues --older-than 30d` で実行する
- **THEN** `loaded_at` が 30 日以上前のエントリのみが削除対象となる

#### Scenario: 無効な duration 指定

- **WHEN** `--older-than 2x` のような無効な単位を指定する
- **THEN** エラーメッセージを出力して終了する（実操作なし）

### Requirement: ドライランモード

`--dry-run` フラグを指定した場合、削除予定の PR#/Issue#/branch 名のリストのみを出力し、実操作を行ってはならない（MUST NOT）。

#### Scenario: dry-run で削除予定リストのみ出力

- **WHEN** `--real-issues --dry-run` で実行する
- **THEN** 削除予定の PR#/Issue#/branch のリストが出力され、`gh` CLI による実操作は行われない

## MODIFIED Requirements

### Requirement: local モードと real-issues の相互排他

`--mode local` と `--real-issues` を同時に指定した場合、エラーを出力して終了しなければならない（SHALL）。

#### Scenario: 両フラグ同時指定時エラー

- **WHEN** `--mode local --real-issues` を同時に指定する
- **THEN** エラーメッセージを出力して終了する（いずれの操作も実行しない）

### Requirement: local モード分岐整理

既存の Step 4（ユーザー確認）と Step 5（`git reset --hard`）は `--mode local`（またはフラグなし）の場合のみ実行しなければならない（SHALL）。`--real-issues` 時には実行してはならない（MUST NOT）。

#### Scenario: local モードで既存動作を維持

- **WHEN** フラグなしまたは `--mode local` で実行する
- **THEN** Step 4（ユーザー確認）→ Step 5（git reset --hard）の既存フローが維持される
