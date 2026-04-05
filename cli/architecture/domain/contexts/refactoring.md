## Name
Refactoring

## Key Entities

- **RenameOperation**: コンポーネント名の変更。deps.yaml, frontmatter, body refs を一括更新
- **PromoteOperation**: コンポーネント型の変更（例: atomic → composite）。セクション移動とファイル移動を伴う
- **OrphanNode**: どのコンポーネントの calls からも参照されない孤立ノード
- **DeadComponent**: entry_points から到達不能なコンポーネント
- **ComplexityMetric**: depth score, fan-out, type balance, duplication, cost projection の5指標

## Dependencies

- **Plugin Structure (upstream)**: コンポーネントグラフを操作対象として受け取る
- **Validation (downstream)**: rename/promote 後に検証を実行して整合性を確認

## Constraints

- rename/promote は deps.yaml + 実ファイル（frontmatter, body）を同時に更新。部分更新は不可
- --dry-run で変更内容をプレビュー可能。破壊的操作の安全ネット
- complexity は read-only 操作。メトリクスの表示のみで、自動修正は行わない

## CLI Commands

| コマンド | 説明 |
|---------|------|
| `twl --rename <old> <new>` | コンポーネント名を一括変更 |
| `twl --promote <name> <new_type>` | コンポーネント型を変更（セクション移動含む） |
| `twl --dry-run` | rename/promote の変更をプレビュー |
| `twl --orphans` | 孤立コンポーネントを検出 |
| `twl --complexity` | 複雑さメトリクスレポートを生成 |
