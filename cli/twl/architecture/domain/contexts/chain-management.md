## Name
Chain Management

## Key Entities

- **Chain**: deps.yaml の chains セクションで定義。name と type（"A" or "B"）を持つ
- **Step**: chain 内の順序付きコンポーネント参照
- **StepIn**: step 内のサブステップ参照
- **TemplateA**: chain generate が生成するチェックポイントセクション（ステップ間の遷移を記述）
- **TemplateB**: chain generate が生成する called-by frontmatter（呼び出し元の情報を記述）

## Dependencies

- **Plugin Structure (upstream)**: コンポーネント定義を参照して chain のステップを解決
- **Type System (upstream)**: chain-type-guard で型制約を検証（chain 内の型遷移が合法か）
- **Validation (downstream)**: chain 整合性検証結果を Validation に統合

## Constraints

- v3.0 スキーマでのみ利用可能。v1.0/v2.0 では chains セクション自体が存在しない
- chain の step が参照するコンポーネントは deps.yaml に定義されている必要がある
- Template A は chain generate --write で実ファイルに書き込まれる。--check でドリフト検出

## CLI Commands

| コマンド | 説明 |
|---------|------|
| `twl chain generate <name>` | 指定 chain のテンプレートを生成（表示のみ） |
| `twl chain generate <name> --write` | テンプレートを実ファイルに書き込み |
| `twl chain generate <name> --check` | 生成済みテンプレートのドリフトを検出 |
| `twl chain generate --all` | 全 chain のテンプレートを一括生成 |
| `twl chain validate` | chain 定義の整合性を検証（5項目） |
