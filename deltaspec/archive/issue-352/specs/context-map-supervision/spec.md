## MODIFIED Requirements

### Requirement: Context 分類テーブルの Supervision 更新

Context Map の Context 分類テーブルにおいて、Cross-cutting Context 名を `Observer` から `Supervision` に更新しなければならない（SHALL）。

#### Scenario: Context 分類の更新確認
- **WHEN** `context-map.md` の Context 分類テーブルを参照する
- **THEN** `Cross-cutting | Supervision` 行が存在し、`Observer` 行が存在しない

### Requirement: 依存関係図の Supervision ノード更新

依存関係図（Mermaid graph TD）の Cross-cutting サブグラフにおいて、`Observer` ノードを `Supervision` ノードに更新しなければならない（SHALL）。

#### Scenario: 依存関係図のノード確認
- **WHEN** Mermaid 依存関係図を確認する
- **THEN** Cross-cutting サブグラフに `Supervision` ノードが存在し、`Observer` ノードが存在しない

### Requirement: DCI フロー図の su-observer サブグラフ更新

DCI フロー図（Mermaid graph LR）のサブグラフ名を `co-observer` から `su-observer` に更新しなければならない（SHALL）。

#### Scenario: DCI フロー図のサブグラフ確認
- **WHEN** Mermaid DCI フロー図（L124-141）を確認する
- **THEN** `subgraph "su-observer"` が存在し、`subgraph "co-observer"` が存在しない

### Requirement: 関係の詳細テーブルの Supervision 更新

関係の詳細テーブルにおいて、`Observer` Upstream の全行を `Supervision` に更新しなければならない（SHALL）。

#### Scenario: 関係テーブルの更新確認
- **WHEN** 関係の詳細テーブルを参照する
- **THEN** Upstream 列に `Supervision` が存在し、`Observer` が存在しない
