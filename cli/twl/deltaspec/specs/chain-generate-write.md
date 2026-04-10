## Requirements

### Requirement: --write フラグによるプロンプトファイル書き込み

`--write` フラグ指定時、生成されたテンプレートを対応するプロンプトファイルに直接書き込まなければならない（SHALL）。

プロンプトファイルのパスは deps.yaml の各コンポーネントの `path` フィールドから取得しなければならない（MUST）。

#### Scenario: --write でチェックポイントセクション置換
- **WHEN** `twl chain generate dev-pr-cycle --write` を実行し、プロンプトファイルに `## チェックポイント` セクションが存在する
- **THEN** 既存のチェックポイントセクションが生成されたテンプレートで置換される

#### Scenario: セクション未検出時の警告
- **WHEN** `--write` 実行時にプロンプトファイルに対応するセクションマーカーが存在しない
- **THEN** 警告メッセージ "Section marker not found in {path}, skipping" が出力され、該当ファイルはスキップされる

### Requirement: セクション検出パターン

Template A は `## チェックポイント` または `## Checkpoint` セクションヘッダーをパターンマッチで検出しなければならない（SHALL）。

Template B は frontmatter の description フィールド内で `から呼び出される` パターンを検出しなければならない（SHALL）。

Template C は `## ライフサイクル` または `## Lifecycle` セクションヘッダーをパターンマッチで検出しなければならない（SHALL）。

#### Scenario: 日本語セクションヘッダー
- **WHEN** プロンプトファイルに `## チェックポイント（MUST）` が存在する
- **THEN** セクションが正しく検出され、置換対象となる

#### Scenario: 英語セクションヘッダー
- **WHEN** プロンプトファイルに `## Checkpoint` が存在する
- **THEN** セクションが正しく検出され、置換対象となる

### Requirement: path フィールド未設定時のスキップ

コンポーネントの `path` フィールドが未設定の場合、--write 時にそのコンポーネントをスキップし警告を出力しなければならない（MUST）。

#### Scenario: path なしコンポーネント
- **WHEN** chain 参加者のコンポーネントに path フィールドがない
- **THEN** 警告 "No path defined for {component}, skipping --write" が出力され、他のコンポーネントの処理は継続される
