## Requirements

### Requirement: MODIFIED 操作は requirement 名マッチで置換する

`twl spec archive` の MODIFIED ブロック処理は、requirement 名でマッチして既存 requirement を置換しなければならない（SHALL）。セクション全体追記ではなく `_replace_requirements` による名前ベース置換を使用する（OpenSpec 準拠）。

#### Scenario: 既存 requirement の MODIFIED 置換
- **WHEN** MODIFIED ブロックに含まれる requirement 名が対象 spec ファイルに存在する
- **THEN** 既存 requirement が新しい内容で置換される（セクション追記ではなく）

#### Scenario: 存在しない requirement への MODIFIED は SpecIntegrationError
- **WHEN** MODIFIED ブロックに含まれる requirement 名が対象 spec ファイルに存在しない
- **THEN** `SpecIntegrationError` が発生し、archive が失敗する

### Requirement: ADDED 操作は ADDED ブロックのみを書き出す

`twl spec archive` の ADDED ブロック処理は、新規ファイル作成時に ADDED ブロックの内容のみを書き出さなければならない（SHALL）。`_extract_block` で ADDED ブロックのみ抽出して書き出す（OpenSpec 準拠）。

#### Scenario: ADDED 新規ファイルの書き出し
- **WHEN** ADDED ブロックに新規ファイルへの書き込みが指定される
- **THEN** ADDED ブロックの内容のみが書き出され、MODIFIED・REMOVED・RENAMED 等のヘッダーは含まれない

#### Scenario: ADDED 重複は SpecIntegrationError
- **WHEN** ADDED ブロックに含まれる requirement 名が対象 spec ファイルに既に存在する
- **THEN** `SpecIntegrationError` が発生し、archive が失敗する

### Requirement: 操作順序は REMOVED → MODIFIED → ADDED（OpenSpec 準拠）

`twl spec archive` の操作適用順序は REMOVED → MODIFIED → ADDED でなければならない（SHALL）。OpenSpec 原本（Fission-AI/OpenSpec TypeScript 実装）との一致を維持する。

#### Scenario: 複数操作の順序適用
- **WHEN** ADDED・MODIFIED・REMOVED が同一 change に含まれる
- **THEN** REMOVED が最初に適用され、次に MODIFIED、最後に ADDED が適用される

### Requirement: 2-pass 原子性（validate → apply）

`twl spec archive` は全 capability を validate してから apply する 2-pass 方式で原子性を確保しなければならない（SHALL）。validate フェーズで失敗した場合、apply フェーズは実行されない。

#### Scenario: validate フェーズで失敗した場合の原子性
- **WHEN** validate フェーズで `SpecIntegrationError` が発生する
- **THEN** apply フェーズは実行されず、spec ファイルへの書き込みは一切行われない

#### Scenario: validate 全通過後に apply 実行
- **WHEN** validate フェーズで全 capability が正常に検証される
- **THEN** apply フェーズが実行され、spec ファイルへの変更が一括で書き込まれる

### Requirement: scope 機構による統合先制御

`.deltaspec.yaml` の `scope` フィールドに基づき、archive 時に `deltaspec/specs/<scope>/` へ統合されなければならない（SHALL）。

#### Scenario: scope 指定 change の archive 先
- **WHEN** `.deltaspec.yaml` に `scope: plugins-twl` が設定された change が archive される
- **THEN** spec ファイルが `deltaspec/specs/plugins-twl/` に統合される

#### Scenario: scope 未指定 change のデフォルト動作
- **WHEN** `.deltaspec.yaml` に `scope` が設定されていない change が archive される
- **THEN** spec ファイルが `deltaspec/specs/` のデフォルト位置に統合される

#### Scenario: 既存スコープ一覧
- **WHEN** 現在のプロジェクトで使用される scope を確認する
- **THEN** `plugins-twl`、`plugins-session`、`cli-twl`、`test-fixtures` の 4 スコープが存在する
