## Name
Type System

## Key Entities

- **Type**: types.yaml で定義される型ルール。name, section, can_spawn, spawnable_by を持つ
- **TypeName**: 7つの型名（controller, workflow, atomic, composite, specialist, reference, script）
- **SectionName**: 型が属するセクション（skills, commands, agents, scripts）
- **TypeRule**: can_spawn と spawnable_by のペアで表現される spawn 制約

## Dependencies

- なし（他の Context から参照される最上流 Context）
- Plugin Structure, Chain Management, Validation の3 Context が Type System を参照

## Constraints

- types.yaml が唯一の型定義ソース。loom-engine.py 内のハードコードは types.yaml から起動時にロード
- can_spawn には型名のみ指定可能（コンポーネント名は不可）
- spawnable_by には型名 + 特殊値（user, launcher, all, agents.skills）を指定可能

## CLI Commands

| コマンド | 説明 |
|---------|------|
| `loom --validate` | can_spawn/spawnable_by の型ルール整合性を検証 |
| `loom --rules` | types.yaml の型ルールテーブルを表示 |
| `loom --sync-check <ref>` | types.yaml と参照ドキュメントの整合性を比較 |
