## MODIFIED Requirements

### Requirement: deep_validate section A ルート外パスガード

section A（Controller 行数チェック）は、ファイルアクセス前に `_is_within_root()` でパスを検証しなければならない（SHALL）。ルート外パスはスキップする。

#### Scenario: section A でルート外パスをスキップ
- **WHEN** deps.yaml の skills にパストラバーサルを含むパス（例: `../../etc/passwd`）が存在する
- **THEN** `_is_within_root()` が False を返し、`_count_body_lines()` が呼ばれずに `continue` する

#### Scenario: section A で正常パスは従来通り処理
- **WHEN** deps.yaml の skills に `plugin_root` 配下の正常なパスが存在する
- **THEN** `_is_within_root()` が True を返し、従来通り行数チェックが実行される

### Requirement: deep_validate section B ルート外パスガード

section B（Reference 配置監査）は、ファイルアクセス前に `_is_within_root()` でパスを検証しなければならない（SHALL）。ルート外パスはスキップする。

#### Scenario: section B でルート外パスをスキップ
- **WHEN** downstream コンポーネントのパスが `plugin_root` 外を指す
- **THEN** `_is_within_root()` が False を返し、`ds_path.exists()` や `read_text()` が呼ばれずに `continue` する

#### Scenario: section B で正常パスは従来通り処理
- **WHEN** downstream コンポーネントのパスが `plugin_root` 配下にある
- **THEN** 従来通り Reference 配置監査が実行される

### Requirement: deep_validate section C ルート外パスガード

section C（Frontmatter-Body ツール整合性）は、ファイルアクセス前に `_is_within_root()` でパスを検証しなければならない（SHALL）。ルート外パスはスキップする。

#### Scenario: section C でルート外パスをスキップ
- **WHEN** commands/agents のパスが `plugin_root` 外を指す
- **THEN** `_is_within_root()` が False を返し、`_parse_frontmatter_tools()` や `_scan_body_for_mcp_tools()` が呼ばれずに `continue` する

#### Scenario: section C で正常パスは従来通り処理
- **WHEN** commands/agents のパスが `plugin_root` 配下にある
- **THEN** 従来通り Frontmatter-Body ツール整合性チェックが実行される

### Requirement: section E 回帰なし

section E の既存 `_is_within_root()` チェック（L2924）は変更されてはならない（MUST NOT）。

#### Scenario: section E のチェックが維持される
- **WHEN** 修正後のコードで section E を確認する
- **THEN** `if not _is_within_root(path, plugin_root): continue` が L2924 付近にそのまま存在する
