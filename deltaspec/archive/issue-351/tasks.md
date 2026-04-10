## 1. クラス図の Supervisor クラス更新

- [x] 1.1 `class Observer` を `class Supervisor` に変更（name: co-* → su-*）
- [x] 1.2 `Observer ..> Controller : supervises` を `Supervisor ..> Controller : supervises` に変更
- [x] 1.3 `Observer *-- InterventionRecord : records` を `Supervisor *-- InterventionRecord : records` に変更

## 2. InterventionRecord の supervisor フィールド更新

- [x] 2.1 `InterventionRecord` クラスの `observer: string` を `supervisor: string` に変更

## 3. Controller Spawning 関係図の更新

- [x] 3.1 Mermaid ノード `CO["co-observer<br/>(Meta-cognitive)"]` を `SO["su-observer<br/>(Meta-cognitive)"]` に変更
- [x] 3.2 `CO -.->|supervises| CA` 等の全 CO 参照を SO に変更
- [x] 3.3 Spawning ルール説明文の `co-observer` を `su-observer` に変更

## 4. intervention-{N}.json スキーマの更新

- [x] 4.1 スキーマテーブルの `observer` 行を `supervisor` に変更
- [x] 4.2 アクセスルール説明文の `Observer = write` を `Supervisor = write` に変更
