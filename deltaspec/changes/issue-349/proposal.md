## Why

ADR-014 (Supervisor 再定義) の設計が完成し実装が進んだため、ステータスを Proposed から Accepted に昇格させる。同時に、ADR-014 が ADR-013 (Observer First-Class) を置き換える関係を明示するため、ADR-013 を Superseded に更新する。

## What Changes

- `plugins/twl/architecture/decisions/ADR-014-supervisor-redesign.md`: Status を `Proposed` → `Accepted` に変更
- `plugins/twl/architecture/decisions/ADR-013-observer-first-class.md`: Status を `Accepted` → `Superseded by ADR-014` に変更
- ADR-013 冒頭に Superseded 注記を追加

## Capabilities

### New Capabilities

なし（ドキュメント更新のみ）

### Modified Capabilities

- ADR ステータス管理: ADR-014 が Accepted となり、公式アーキテクチャ決定として有効化される
- ADR ステータス管理: ADR-013 が Superseded となり、ADR-014 への参照が明記される

## Impact

- 影響コード: なし（Markdown ファイルのみ）
- 影響 API: なし
- 影響依存: なし
