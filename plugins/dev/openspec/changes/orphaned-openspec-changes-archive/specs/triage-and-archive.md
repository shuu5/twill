## ADDED Requirements

### Requirement: トリアージリスト生成

`openspec/changes/` 配下の全 change を調査し、完了状況・ブランチ存在・最終更新日に基づいてトリアージリストを生成しなければならない（SHALL）。

#### Scenario: tasks.md が全完了の change
- **WHEN** change に `tasks.md` が存在し、全タスクが `- [x]` で完了済みである
- **THEN** その change を「アーカイブ対象」に分類する

#### Scenario: tasks.md が未完了またはブランチが残存する change
- **WHEN** change の tasks.md に未完了タスクがある、または `git branch -a` に対応するブランチが存在する
- **THEN** その change を「保留」に分類する

#### Scenario: tasks.md が存在しない change
- **WHEN** change に `tasks.md` が存在しない
- **THEN** その change を「要調査」に分類する

#### Scenario: ユーザーへのリスト提示
- **WHEN** トリアージリストが生成される
- **THEN** 各 change の分類・tasks.md 状況・関連ブランチ・最終更新日を含むリストをユーザーに提示し、承認を得る

### Requirement: 承認済み change の一括アーカイブ

ユーザーが承認したトリアージリストに基づき、アーカイブ対象 change を `openspec/changes/archive/YYYY-MM-DD-<name>/` へ移動しなければならない（SHALL）。

#### Scenario: deltaspec コマンド正常動作時
- **WHEN** `deltaspec archive <name> --yes --skip-specs` が正常に実行できる
- **THEN** そのコマンドでアーカイブを実行する

#### Scenario: deltaspec コマンドが使えない場合
- **WHEN** deltaspec に構文エラーがあり `deltaspec archive` が使えない
- **THEN** `mv openspec/changes/<name> openspec/changes/archive/<date>-<name>` で手動移動する

#### Scenario: アーカイブ日付の決定
- **WHEN** change の `.openspec.yaml` に `created` フィールドが存在する
- **THEN** その日付（YYYY-MM-DD）をプレフィックスとして使用する

#### Scenario: アーカイブ日付のフォールバック
- **WHEN** `.openspec.yaml` に `created` フィールドがない
- **THEN** `git log` で初回コミット日を取得してプレフィックスに使用する

### Requirement: 既存 archive の命名統一

`openspec/changes/archive/` 内の既存 17 件（日付プレフィックスなし）に `YYYY-MM-DD-` プレフィックスを付与し命名を統一しなければならない（SHALL）。

#### Scenario: 既存 archive の日付取得
- **WHEN** 既存 archive エントリに日付プレフィックスがない
- **THEN** `.openspec.yaml` の `created` または `git log` で初回コミット日を取得し、`mv` でリネームする

#### Scenario: 日付が取得できない場合
- **WHEN** `.openspec.yaml` にも git log にも日付情報がない
- **THEN** `1970-01-01` プレフィックスを付与し、ユーザーが識別できるようにする

### Requirement: アーカイブ後の状態確認

アーカイブ完了後、`openspec/changes/` に残る change が「保留」「要調査」に分類されたもののみであることを確認しなければならない（SHALL）。

#### Scenario: アーカイブ後の残留確認
- **WHEN** 全アーカイブ操作が完了する
- **THEN** `openspec/changes/` の残留 change リストを表示し、保留・要調査以外が存在しないことをユーザーが確認できる
