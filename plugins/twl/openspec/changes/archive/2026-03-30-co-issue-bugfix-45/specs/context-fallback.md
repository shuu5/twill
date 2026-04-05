## ADDED Requirements

### Requirement: Context フィールドのフォールバック推定

project-board-sync は ctx/* ラベルがない Issue に対して、architecture/ の context 定義と Issue 内容のキーワードマッチングで Context フィールドを推定しなければならない（SHALL）。

#### Scenario: ctx/* ラベルなしで architecture/ に context 定義がある場合
- **WHEN** Issue に ctx/* ラベルが付与されておらず、リポジトリに `architecture/domain/contexts/*.md` が存在する
- **THEN** Issue のタイトル・本文と各 context の責務を照合し、最も関連性の高い Context オプションを設定する

#### Scenario: architecture/ が存在しない場合
- **WHEN** リポジトリに `architecture/` ディレクトリが存在しない
- **THEN** Context フィールドの設定をスキップし、既存の動作（スキップ）を維持する

#### Scenario: マッチする context がない場合
- **WHEN** Issue 内容がいずれの context の責務とも一致しない
- **THEN** Context フィールドの設定をスキップし、警告メッセージ「Context を推定できませんでした」を出力する
