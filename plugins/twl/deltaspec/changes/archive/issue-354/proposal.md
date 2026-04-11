## Why

ADR-014 Decision 5 に基づき co-observer が su-observer に昇格し、OBS-* 制約は supervision.md の SU-* に統合された。しかし observation.md はまだ OBS-* を定義したまま残っており、supervision.md との整合が取れていない。この不整合を解消する。

## What Changes

- `plugins/twl/architecture/domain/contexts/observation.md`
  - OBS-* Constraints セクション（L138-146）に「Superseded by SU-* in supervision.md（ADR-014）」deprecation 注記を追加
  - Component Mapping の co-observer 行（L160）を削除（supervision.md に移動済みのため）
  - OB-3 適用範囲注記（L135）の「co-observer は介入権限を持つメタ認知レイヤー（ADR-013）のため OB-3 適用外。介入ルールは OBS-1〜OBS-5 で定義。」を SU-* 参照に更新

## Capabilities

### New Capabilities

なし（ドキュメント整合のみ）

### Modified Capabilities

- observation.md の OBS-* Constraints セクション: deprecation 注記付きで残存（削除ではなく非推奨化）
- observation.md の OB-3 注記: ADR-013 (Observer) → ADR-014 (Supervisor) の参照に更新

## Impact

- 変更ファイル: `plugins/twl/architecture/domain/contexts/observation.md`（1ファイルのみ）
- supervision.md の SU-* は変更不要（既に7件全て定義済み、整合確認のみ）
- コード変更なし（アーキテクチャドキュメントのみ）
