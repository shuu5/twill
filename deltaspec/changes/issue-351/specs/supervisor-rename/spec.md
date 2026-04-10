## MODIFIED Requirements

### Requirement: Supervisor クラス定義

model.md の Observer クラスは Supervisor クラスに更新されなければならない（SHALL）。クラス名を `Observer` → `Supervisor` に変更し、`name: co-*` を `name: su-*` に変更する。

#### Scenario: クラス図の Supervisor 定義
- **WHEN** model.md のクラス図を参照する
- **THEN** `class Supervisor` が存在し、`name: su-*` と `type: observer` を持つ

#### Scenario: クラス図の関係線更新
- **WHEN** model.md のクラス図を参照する
- **THEN** `Supervisor ..> Controller : supervises` および `Supervisor *-- InterventionRecord : records` が存在する

### Requirement: InterventionRecord の supervisor フィールド

InterventionRecord クラスの `observer` フィールドは `supervisor` に更新されなければならない（SHALL）。

#### Scenario: InterventionRecord.supervisor フィールド
- **WHEN** model.md の InterventionRecord クラス定義を参照する
- **THEN** `supervisor: string` フィールドが存在し、`observer: string` は存在しない

### Requirement: Controller Spawning 関係図の su-observer 更新

関係図のノード `CO["co-observer"]` は `SO["su-observer"]` に更新されなければならない（SHALL）。

#### Scenario: Mermaid ノードの更新
- **WHEN** model.md の Controller Spawning 関係図を参照する
- **THEN** `SO["su-observer<br/>(Meta-cognitive)"]` ノードが存在し、`CO["co-observer"]` は存在しない

#### Scenario: Spawning ルール説明文の更新
- **WHEN** model.md の Spawning ルール説明文を参照する
- **THEN** `su-observer` が全 `co-observer` 参照箇所を置換している

### Requirement: intervention-{N}.json スキーマの supervisor フィールド

`intervention-{N}.json` スキーマの `observer` フィールドは `supervisor` に更新されなければならない（SHALL）。

#### Scenario: スキーマテーブルの supervisor フィールド
- **WHEN** model.md の intervention-{N}.json スキーマテーブルを参照する
- **THEN** `supervisor` 行が存在し、`observer` 行は存在しない
