## Name
Plugin Structure

## Responsibility
deps.yaml のパース、コンポーネントグラフの構築、ファイル存在確認、依存関係の管理

## Key Entities
- Plugin, Component, Section, External, EntryPoint

## Dependencies
- Type System (upstream): 型ルールを参照してグラフエッジを検証
- Chain Management (downstream): chain 定義のコンポーネント参照を解決
