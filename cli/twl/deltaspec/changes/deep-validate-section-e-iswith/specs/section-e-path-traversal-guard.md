## MODIFIED Requirements

### Requirement: section E パストラバーサル防御

`deep_validate()` section E は、specialist コンポーネントの `path` フィールドから構築したファイルパスに対して `_is_within_root()` チェックを実行しなければならない（SHALL）。チェックは `path.exists()` の前に配置し、ルート外のパスは静かにスキップする。

#### Scenario: 正常な path はスキーマ検証される
- **WHEN** specialist の `path` がプラグインルート内の既存ファイルを指す
- **THEN** `_is_within_root()` チェックを通過し、出力スキーマキーワード検証が実行される

#### Scenario: パストラバーサルを含む path は拒否される
- **WHEN** specialist の `path` が `../../etc/passwd` のようなプラグインルート外を指す値を持つ
- **THEN** `_is_within_root()` が False を返し、当該コンポーネントの検証はスキップされる（エラーや warning は出力しない）

#### Scenario: 既存テストの互換性
- **WHEN** 既存の `deep_validate()` テストスイートを実行する
- **THEN** 全テストが PASS を維持する
