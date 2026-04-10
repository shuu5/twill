## Why

`glossary.md` の Supervisor 関連 6 用語は MUST セクションに存在するが、`Three-Layer Memory` の層名称が ADR-014 Decision 3 の正式名称（Long-term Memory / Working Memory Externalization / Compressed Memory）と乖離している。また co-observer → su-observer 移行後の Observer 関連用語との整合性を最終確認する必要がある。

## What Changes

- `plugins/twl/architecture/domain/glossary.md`
  - `Three-Layer Memory` の定義を ADR-014 準拠の層名称に修正
    - 誤: `Working Memory（context）+ Externalized Memory（doobidoo/ファイル）+ Compressed Memory（compaction後）`
    - 正: `Long-term Memory（永続）+ Working Memory Externalization（一時退避）+ Compressed Memory（compaction後）`
  - Observer/Observed/Live Observation 等 Observation context 用語が SHOULD に残ることを意図的と確認（変更なし）
  - Supervisor 6 用語と他 MUST 用語間の参照整合性を確認（軽微修正のみ）

## Capabilities

### New Capabilities

なし

### Modified Capabilities

- `Three-Layer Memory` の定義が ADR-014 / supervision.md の層名称と完全一致する
- `Supervisor` 関連 6 用語すべての定義が ADR-014 最終版と整合する

## Impact

- `plugins/twl/architecture/domain/glossary.md`（MUST テーブルの Three-Layer Memory 行のみ）
