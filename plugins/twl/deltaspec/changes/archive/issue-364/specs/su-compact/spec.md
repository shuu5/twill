## ADDED Requirements

### Requirement: su-compact コマンド作成

`plugins/twl/commands/su-compact.md` を新規作成し、知識外部化 + compaction を統合する atomic コマンドを実装しなければならない（SHALL）。

#### Scenario: デフォルト実行（引数なし）
- **WHEN** ユーザーが `/su-compact` を引数なしで実行する
- **THEN** 状況を自動判定して適切な外部化モードを選択し、Memory MCP 保存 → Working Memory 退避 → /compact を順に実行する

#### Scenario: --wave オプション実行
- **WHEN** ユーザーが `/su-compact --wave` を実行する
- **THEN** Wave 完了サマリを Memory MCP に保存し、compaction を実行する

#### Scenario: --task オプション実行
- **WHEN** ユーザーが `/su-compact --task` を実行する
- **THEN** 現在のタスク状態を `.supervisor/working-memory.md` に退避し、compaction を実行する

#### Scenario: --full オプション実行
- **WHEN** ユーザーが `/su-compact --full` を実行する
- **THEN** Long-term Memory・Working Memory の全知識を外部化し、compaction を実行する

### Requirement: Memory MCP 参照による Long-term Memory 保存

`refs/memory-mcp-config.md` を参照して Memory MCP ツール名を解決し、Long-term Memory を保存しなければならない（SHALL）。

#### Scenario: Memory MCP への保存
- **WHEN** su-compact が Long-term Memory 保存ステップを実行する
- **THEN** `refs/memory-mcp-config.md` の `store_tool` を使用して記憶を保存し、成功・失敗を報告する

### Requirement: Working Memory 退避

compaction 前に作業状態を `.supervisor/working-memory.md` に書き出さなければならない（MUST）。

#### Scenario: Working Memory ファイル書出
- **WHEN** su-compact が Working Memory 退避ステップを実行する
- **THEN** `.supervisor/working-memory.md` に現在のタスク・コンテキスト情報を書き出す

### Requirement: deps.yaml エントリ追加

`plugins/twl/deps.yaml` に `su-compact` コンポーネントエントリを追加しなければならない（MUST）。

#### Scenario: deps.yaml 登録
- **WHEN** su-compact コマンドを追加する
- **THEN** deps.yaml に type/path/dependencies が正しく登録され、`twl --check` が通る
