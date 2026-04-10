## MODIFIED Requirements

### Requirement: template-b-write 書き込み実装

`chain_generate_write()` の Template B 処理を完全実装し、`--write` 時に frontmatter description に called-by 文を追記/更新しなければならない（SHALL）。

#### Scenario: 新規 called-by 追記
- **WHEN** `--write` を実行し、対象コンポーネントの description に called-by 文が存在しない
- **THEN** description 末尾に `。{parent} Step {step} から呼び出される。` を追記する

#### Scenario: 既存 called-by 更新
- **WHEN** `--write` を実行し、対象コンポーネントの description に既存の called-by 文がある
- **THEN** 正規表現パターン `。\S+ (?:Step \d+ )?から呼び出される。` で既存文を検出し、新しい called-by 文で置換する

#### Scenario: step フィールドなしの called-by
- **WHEN** `step_in` に `step` フィールドがない（`parent` のみ）
- **THEN** `。{parent} から呼び出される。` の形式で生成する

#### Scenario: step_in を持たないコンポーネントのスキップ
- **WHEN** 対象コンポーネントが `template_b` に含まれない（`step_in` 未設定）
- **THEN** Template B の書き込み処理をスキップする

#### Scenario: 既存 description の保持
- **WHEN** description に called-by 以外のテキストがある
- **THEN** called-by 以外の部分を変更せず保持しなければならない（MUST）

#### Scenario: description 行が存在しない場合
- **WHEN** frontmatter に `description:` 行が存在しない
- **THEN** Warning を出力しスキップする（frontmatter 構造を変更してはならない）
