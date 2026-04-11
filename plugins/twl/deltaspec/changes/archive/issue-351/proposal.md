## Why

ADR-014 Decision 1 により、Observer クラスを Supervisor クラスに改名する設計決定が下された。ドメインモデル（model.md）がこの決定を反映していないため、型定義・スキーマ・図表との乖離が生じている。

## What Changes

- `Observer` クラスを `Supervisor` クラスに改名（`name: co-*` → `name: su-*`）
- `InterventionRecord` クラスの `observer` フィールドを `supervisor` に改名
- Controller Spawning 関係図のノード `CO["co-observer"]` を `SO["su-observer"]` に更新
- クラス図の `Observer ..> Controller` 関係を `Supervisor ..> Controller` に更新
- `intervention-{N}.json` スキーマの `observer` フィールドを `supervisor` に更新
- Spawning ルール説明文の `co-observer` 参照を `su-observer` に更新

## Capabilities

### New Capabilities

なし（既存機能の改名のみ）

### Modified Capabilities

- **Supervisor（旧 Observer）**: ドメインクラスのプレフィックスが `su-*` となり、ADR-014 の su- prefix 規則に準拠
- **InterventionRecord**: `supervisor` フィールドで介入記録の記録者を識別
- **intervention-{N}.json**: `supervisor` フィールドを持つスキーマとして更新

## Impact

- `plugins/twl/architecture/domain/model.md` のみ変更
- コード実装への影響なし（ドキュメント更新のみ）
- 後続 Issue（C1）が本変更に依存
