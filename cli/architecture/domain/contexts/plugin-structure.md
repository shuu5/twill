## Name
Plugin Structure

## Key Entities

- **Plugin**: deps.yaml 全体に対応するルート集約。name, version, entry_points を持つ
- **Component**: プラグインの構成単位。name, type, path, description, calls 等を持つ
- **Section**: skills, commands, agents, scripts の4セクション。Component のグルーピング
- **EntryPoint**: ユーザーがアクセスする起点ファイルパス
- **Call**: コンポーネント間の呼び出し参照（{skill:}, {command:}, {agent:}, {external:} 形式）
- **External**: 外部プラグインへの参照

## Dependencies

- **Type System (upstream)**: 型ルールを参照してコンポーネントの spawn 制約を検証
- **Chain Management (downstream)**: chain 定義のコンポーネント参照を解決
- **Validation (downstream)**: コンポーネントグラフを検証の入力として提供
- **Visualization (downstream)**: コンポーネントグラフを可視化の入力として提供
- **Refactoring (downstream)**: コンポーネントグラフを操作対象として提供

## Constraints

- deps.yaml が SSOT。コンポーネントのメタデータは全て deps.yaml から導出
- version フィールドで "1.0"/"2.0"/"3.0" を区別。バージョンによって利用可能なフィールドが異なる
- calls フィールドは SVG グラフのエッジ生成と orphan 検出の両方に使用される

## CLI Commands

| コマンド | 説明 |
|---------|------|
| `twl` (デフォルト) | Graphviz DOT 形式で依存グラフを出力 |
| `twl --check` | deps.yaml の path フィールドが参照するファイルの存在確認 |
| `twl --list` | 全コンポーネントのリスト表示 |
| `twl --orphans` | 孤立コンポーネントを検出 |
| `twl --tokens` | 各コンポーネントのトークン数を表示 |
| `twl --update-readme` | README.md に SVG 依存グラフを埋め込み更新 |
