## Name
Validation

## Key Entities

- **Violation**: 検証で検出された問題。severity（ERROR/WARNING/INFO）と message を持つ
- **CheckResult**: --check の結果。ファイル存在/不在のリスト
- **AuditSection**: audit レポートの5セクション（Structure, Dependency, Content, Chain, Metrics）
- **AuditReport**: audit の総合結果。スコアと詳細 findings を含む

## Dependencies

- **Plugin Structure (upstream)**: コンポーネントグラフを入力として受け取る
- **Type System (upstream)**: 型ルールを参照して spawn 制約違反を検出
- **Chain Management (upstream)**: chain 整合性検証の結果を統合
- **Refactoring (downstream)**: rename/promote 後に検証を実行

## Constraints

- 4段階の検証レベル（check → validate → deep-validate → audit）は包含関係ではなく独立
- check はファイルシステムのみ、validate は deps.yaml + types.yaml のみ、deep-validate は実ファイル内容を参照
- audit は全体の準拠度を5セクションで評価し、数値スコアを付与

## CLI Commands

| コマンド | 説明 |
|---------|------|
| `loom --check` | ファイル存在確認 |
| `loom --validate` | 型ルール整合性検証 |
| `loom --deep-validate` | frontmatter/body の深層検証 |
| `loom --audit` | Loom 準拠度の5セクション総合監査 |
